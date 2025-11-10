import Foundation
import Vapor
import GRPC
import NIO
import SwiftProtobuf

/// gRPC service provider for AFCON data
/// This class implements the AFCONServiceAsyncProvider protocol from the generated code
public final class AFCONServiceProvider: Afcon_AFCONServiceAsyncProvider {
    private let apiClient: APIFootballClient
    private let cache: CacheService
    private let fixtureRepository: FixtureRepository
    private let logger: Logger
    private var standingsRefreshTasks: [String: Task<Void, Never>] = [:]
    private let standingsTasksLock = NSLock()

    public init(apiClient: APIFootballClient, cache: CacheService, fixtureRepository: FixtureRepository, logger: Logger) {
        self.apiClient = apiClient
        self.cache = cache
        self.fixtureRepository = fixtureRepository
        self.logger = logger
    }

    deinit {
        standingsTasksLock.lock()
        let tasks = standingsRefreshTasks.values
        standingsRefreshTasks.removeAll()
        standingsTasksLock.unlock()
        for task in tasks {
            task.cancel()
        }
    }

    // MARK: - Initialization

    /// Initialize fixtures database on server startup
    /// Checks if database is empty and performs initial sync if needed
    public func initializeFixtures(leagues: [(id: Int, season: Int, name: String)] = [(2, 2024, "Champions League"), (6, 2025, "AFCON 2025")]) async {
        logger.info("🔍 Checking fixtures database initialization...")

        for league in leagues {
            do {
                let hasFixtures = try await fixtureRepository.hasFixtures(leagueId: league.id, season: league.season)

                if !hasFixtures {
                    logger.warning("⚠️  Database is empty for \(league.name) (ID: \(league.id), Season: \(league.season))")
                    logger.info("📡 Fetching fixtures from API-Football for initial sync...")

                    // Fetch fixtures from API
                    let fixturesData = try await apiClient.getFixtures(
                        leagueId: league.id,
                        season: league.season
                    )

                    logger.info("✅ Received \(fixturesData.count) fixtures from API-Football")

                    // Save to database
                    try await fixtureRepository.upsertBatch(
                        fixtures: fixturesData,
                        leagueId: league.id,
                        season: league.season,
                        competition: league.name
                    )

                    logger.info("✅ Successfully initialized database with \(fixturesData.count) fixtures for \(league.name)")
                } else {
                    let count = try await fixtureRepository.getAllFixtures(leagueId: league.id, season: league.season).count
                    logger.info("✅ Database already initialized for \(league.name) (\(count) fixtures)")
                }

                scheduleStandingsRefresh(for: league.id, season: league.season)
            } catch {
                logger.error("❌ Failed to initialize fixtures for \(league.name): \(error)")
            }
        }

        logger.info("✅ Fixtures database initialization complete")
    }

    // MARK: - gRPC Service Methods

    /// Get league information
    public func getLeague(
        request: Afcon_LeagueRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_LeagueResponse {
        logger.info("gRPC: GetLeague - id=\(request.leagueID), season=\(request.season)")

        // Fetch from API with caching
        let leagueData = try await cache.getOrFetchLeague(
            id: Int(request.leagueID),
            season: Int(request.season)
        ) {
            try await apiClient.getLeague(id: Int(request.leagueID), season: Int(request.season))
        }

        // Convert to gRPC response
        return convertToLeagueResponse(leagueData)
    }

    /// Get all teams for a league/season
    public func getTeams(
        request: Afcon_TeamsRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_TeamsResponse {
        logger.info("gRPC: GetTeams - league=\(request.leagueID), season=\(request.season)")

        let teamsData = try await cache.getOrFetchTeams(
            leagueID: Int(request.leagueID),
            season: Int(request.season)
        ) {
            try await apiClient.getTeams(leagueId: Int(request.leagueID), season: Int(request.season))
        }

        var response = Afcon_TeamsResponse()
        response.teams = teamsData.map { convertToTeamInfo($0) }
        return response
    }

    /// Get fixtures for a league/season
    public func getFixtures(
        request: Afcon_FixturesRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_FixturesResponse {
        logger.info("gRPC: GetFixtures - league=\(request.leagueID), season=\(request.season)")

        let date = request.date.isEmpty ? nil : request.date
        let teamID = request.teamID == 0 ? nil : Int(request.teamID)

        let fixturesData = try await cache.getOrFetchFixtures(
            leagueID: Int(request.leagueID),
            season: Int(request.season),
            date: date,
            teamID: teamID,
            live: request.live
        ) {
            try await apiClient.getFixtures(
                leagueId: Int(request.leagueID),
                season: Int(request.season),
                date: date,
                teamId: teamID,
                live: request.live
            )
        }

        var response = Afcon_FixturesResponse()
        response.fixtures = fixturesData.map { convertToFixture($0) }
        return response
    }

    /// Get today's upcoming fixtures (not started yet)
    public func getTodayUpcoming(
        request: Afcon_TodayUpcomingRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_FixturesResponse {
        logger.info("gRPC: GetTodayUpcoming - league=\(request.leagueID), season=\(request.season)")

        // Get today's date in YYYY-MM-DD format
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        // Fetch today's fixtures
        let allFixtures = try await cache.getOrFetchFixtures(
            leagueID: Int(request.leagueID),
            season: Int(request.season),
            date: today,
            teamID: nil,
            live: false
        ) {
            try await apiClient.getFixtures(
                leagueId: Int(request.leagueID),
                season: Int(request.season),
                date: today,
                teamId: nil,
                live: false
            )
        }

        // Filter for upcoming games only (not started, not finished)
        let upcomingFixtures = allFixtures.filter { fixture in
            let status = fixture.fixture.status.short
            // Include: NS (Not Started), TBD (To Be Defined)
            // Exclude: FT, 1H, HT, 2H, ET, BT, P, SUSP, INT, LIVE, etc.
            return status == "NS" || status == "TBD"
        }

        var response = Afcon_FixturesResponse()
        response.fixtures = upcomingFixtures.map { convertToFixture($0) }
        return response
    }

    /// Get next upcoming fixtures (all games at the earliest kickoff time)
    public func getNextUpcoming(
        request: Afcon_NextUpcomingRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_FixturesResponse {
        logger.info("gRPC: GetNextUpcoming - league=\(request.leagueID), season=\(request.season)")

        // Fetch all fixtures for the season
        let allFixtures = try await cache.getOrFetchFixtures(
            leagueID: Int(request.leagueID),
            season: Int(request.season),
            date: nil,
            teamID: nil,
            live: false
        ) {
            try await apiClient.getFixtures(
                leagueId: Int(request.leagueID),
                season: Int(request.season),
                date: nil,
                teamId: nil,
                live: false
            )
        }

        // Filter for upcoming fixtures (not started yet)
        let now = Date()
        let upcomingFixtures = allFixtures.filter { fixture in
            let fixtureDate = Date(timeIntervalSince1970: TimeInterval(fixture.fixture.timestamp))
            let status = fixture.fixture.status.short
            return (status == "NS" || status == "TBD") && fixtureDate > now
        }.sorted { $0.fixture.timestamp < $1.fixture.timestamp }

        // Get all fixtures with the earliest timestamp (happening at the exact same time)
        guard !upcomingFixtures.isEmpty else {
            logger.info("gRPC: GetNextUpcoming - No upcoming fixtures found")
            return Afcon_FixturesResponse()
        }

        let earliestTimestamp = upcomingFixtures[0].fixture.timestamp
        let nextFixtures = upcomingFixtures.filter { $0.fixture.timestamp == earliestTimestamp }

        logger.info("gRPC: GetNextUpcoming - Found \(nextFixtures.count) fixture\(nextFixtures.count == 1 ? "" : "s") at earliest kickoff time")

        var response = Afcon_FixturesResponse()
        response.fixtures = nextFixtures.map { convertToFixture($0) }
        return response
    }

    /// Get fixture by ID
    public func getFixtureById(
        request: Afcon_FixtureByIdRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_FixtureResponse {
        logger.info("gRPC: GetFixtureById - fixtureID=\(request.fixtureID)")

        let fixtureData = try await apiClient.getFixtureById(fixtureId: Int(request.fixtureID))

        var response = Afcon_FixtureResponse()
        response.fixture = convertToFixture(fixtureData)
        return response
    }

    /// Get fixture events by ID
    public func getFixtureEvents(
        request: Afcon_FixtureEventsRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_FixtureEventsResponse {
        logger.info("gRPC: GetFixtureEvents - fixtureID=\(request.fixtureID)")

        let events = try await apiClient.getFixtureEvents(fixtureId: Int(request.fixtureID))

        var response = Afcon_FixtureEventsResponse()
        response.events = events.map { convertToFixtureEvent($0) }
        return response
    }

    /// Get fixtures by date
    public func getFixturesByDate(
        request: Afcon_FixturesByDateRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_FixturesResponse {
        logger.info("gRPC: GetFixturesByDate - date=\(request.date)")

        let leagueID = request.leagueID > 0 ? Int(request.leagueID) : nil
        let season = request.season > 0 ? Int(request.season) : nil

        var response = Afcon_FixturesResponse()

        if
            let leagueID,
            let season,
            !request.date.isEmpty
        {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)

            if let targetDate = formatter.date(from: request.date) {
                let dbFixtures = try await fixtureRepository.getFixturesForDate(
                    leagueId: leagueID,
                    season: season,
                    date: targetDate
                )

                if !dbFixtures.isEmpty {
                    response.fixtures = dbFixtures.map { convertFixtureEntityToFixture($0) }
                    return response
                }
            }
        }

        let fixturesData: [FixtureData]
        if let leagueID = leagueID, let season = season {
            fixturesData = try await cache.getOrFetchFixtures(
                leagueID: leagueID,
                season: season,
                date: request.date,
                teamID: nil,
                live: false
            ) {
                try await apiClient.getFixtures(
                    leagueId: leagueID,
                    season: season,
                    date: request.date,
                    teamId: nil,
                    live: false
                )
            }
        } else {
            fixturesData = try await apiClient.getFixturesByDate(date: request.date)
        }

        response.fixtures = fixturesData.map { convertToFixture($0) }
        return response
    }

    /// Stream live match updates
    public func streamLiveMatches(
        request: Afcon_LiveMatchRequest,
        responseStream: GRPC.GRPCAsyncResponseStreamWriter<Afcon_LiveMatchUpdate>,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws {
        let isPaused = request.leagueID == 6 // Only pause AFCON (league 6)
        logger.info("gRPC: StreamLiveMatches - league=\(request.leagueID)\(isPaused ? " - PAUSED" : "")")

        var previousFixtures: [Int: FixtureData] = [:]
        var previousEvents: [Int: [FixtureEvent]] = [:] // Track events per fixture
        let activePollingInterval: UInt64 = 15_000_000_000 // 15 seconds when checking for live matches

        var lastNoLiveCheckTime: Date?
        var nextFixtureTimestamp: Int?

        while !Task.isCancelled {
            do {
                // Only pause league 6 (AFCON), allow other leagues to stream
                let liveFixtures: [FixtureData]
                if isPaused {
                    // PAUSED for league 6: No API calls
                    liveFixtures = []
                } else {
                    // Active streaming for other leagues
                    liveFixtures = try await apiClient.getLiveFixtures(leagueId: Int(request.leagueID))
                }

                // Calculate dynamic sleep interval
                var sleepInterval = activePollingInterval

                // If no live fixtures, fetch next upcoming fixture and adjust polling
                if liveFixtures.isEmpty && !isPaused {
                    let currentTime = Date()
                    // Check for next fixture info
                    if lastNoLiveCheckTime == nil || currentTime.timeIntervalSince(lastNoLiveCheckTime!) > 300 {
                        lastNoLiveCheckTime = currentTime
                        nextFixtureTimestamp = await getNextUpcomingFixtureTimestamp(leagueId: Int(request.leagueID), season: Int(request.season))
                        await logNextUpcomingFixture(leagueId: Int(request.leagueID), season: Int(request.season))
                    }

                    // Calculate time until next fixture and adjust sleep
                    if let timestamp = nextFixtureTimestamp {
                        let now = Date()
                        let nextFixtureDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
                        let timeUntilMatch = nextFixtureDate.timeIntervalSince(now)

                        let days = Int(timeUntilMatch / 86400)
                        let hours = Int(timeUntilMatch / 3600)
                        let minutes = Int(timeUntilMatch / 60)

                        if timeUntilMatch > 86400 {
                            // More than 1 day away: sleep for 12 hours
                            sleepInterval = 12 * 60 * 60 * 1_000_000_000
                            logger.info("⏸️ No live matches. Next fixture in \(days) day\(days == 1 ? "" : "s"). Pausing polling for 12 hours...")
                        } else if timeUntilMatch > 21600 {
                            // Between 6 hours and 1 day: sleep for 3 hours
                            sleepInterval = 3 * 60 * 60 * 1_000_000_000
                            logger.info("⏸️ No live matches. Next fixture in \(hours) hours. Pausing polling for 3 hours...")
                        } else if timeUntilMatch > 3600 {
                            // Between 1 hour and 6 hours: sleep for 30 minutes
                            sleepInterval = 30 * 60 * 1_000_000_000
                            logger.info("⏸️ No live matches. Next fixture in \(hours) hour\(hours == 1 ? "" : "s"). Pausing polling for 30 minutes...")
                        } else if timeUntilMatch > 600 {
                            // Between 10 minutes and 1 hour: sleep for 5 minutes
                            sleepInterval = 5 * 60 * 1_000_000_000
                            logger.info("⏸️ No live matches. Next fixture in \(minutes) minutes. Pausing polling for 5 minutes...")
                        } else if timeUntilMatch > 0 {
                            // Less than 10 minutes: start polling every 15 seconds
                            sleepInterval = activePollingInterval
                            logger.info("⏰ Next fixture starts in \(minutes) minute\(minutes == 1 ? "" : "s"). Resuming active polling...")
                        }
                    } else {
                        // No next fixture found, sleep for 24 hours
                        sleepInterval = 24 * 60 * 60 * 1_000_000_000
                        logger.info("⏸️ No upcoming fixtures found. Pausing polling for 24 hours...")
                    }
                }

                for fixture in liveFixtures {
                    let fixtureID = fixture.fixture.id

                    // Fetch current events for this fixture
                    let currentEvents = try await fetchFixtureEventsIfNeeded(fixtureId: fixtureID)

                    if let previous = previousFixtures[fixtureID] {
                        // Detect changes
                        if hasSignificantChanges(
                            previous: previous,
                            current: fixture,
                            currentEvents: currentEvents,
                            previousEvents: previousEvents[fixtureID] ?? []
                        ) {
                            var update = Afcon_LiveMatchUpdate()
                            update.fixtureID = Int32(fixtureID)
                            update.timestamp = Google_Protobuf_Timestamp(date: Date())

                            // Enhanced event detection with actual fixture events
                            let detectedEventType = detectEventTypeEnhanced(
                                previous: previous,
                                current: fixture,
                                currentEvents: currentEvents,
                                previousEvents: previousEvents[fixtureID] ?? []
                            )
                            update.eventType = detectedEventType
                            update.fixture = convertToFixture(fixture)

                            // Materialize status for easy access
                            update.status = convertToFixtureStatus(fixture.fixture.status)

                            // Include recent events (last 5 minutes)
                            let recentEvents = getRecentEvents(
                                events: currentEvents,
                                currentElapsed: fixture.fixture.status.elapsed ?? 0
                            )
                            update.recentEvents = recentEvents

                            logger.info("📊 Fixture \(fixtureID): \(currentEvents.count) total events, \(recentEvents.count) recent events")

                            // Debug: Log each event being sent
                            for (index, event) in recentEvents.enumerated() {
                                logger.info("   Event \(index + 1): \(event.time.elapsed)' \(event.type) - \(event.player.name)")
                            }

                            // Attach latest event if there is a newly detected one
                            let newlyDetectedEvents = currentEvents.filter { currentEvent in
                                !(previousEvents[fixtureID] ?? []).contains { prevEvent in
                                    eventsAreEqual(currentEvent, prevEvent)
                                }
                            }
                            if let latestEvent = newlyDetectedEvents.last {
                                update.event = convertToFixtureEvent(latestEvent)
                            }

                            // Log each newly detected event with detailed description
                            for newEvent in newlyDetectedEvents {
                                let teamName = newEvent.team?.name ?? "Unknown Team"
                                let playerName = newEvent.player?.name ?? "Unknown Player"
                                let elapsed = newEvent.time?.elapsed ?? 0
                                let eventType = newEvent.type ?? "unknown"
                                let eventDetail = newEvent.detail ?? ""

                                // Get current UTC time
                                let dateFormatter = ISO8601DateFormatter()
                                dateFormatter.timeZone = TimeZone(identifier: "UTC")
                                let utcTime = dateFormatter.string(from: Date())

                                // Build descriptive log message
                                var logMessage = "[\(utcTime)] ⚽️ NEW EVENT - Fixture \(fixtureID)"
                                logMessage += " | \(elapsed)' \(teamName)"

                                switch eventType.lowercased() {
                                case "goal":
                                    logMessage += " | ⚽️ GOAL by \(playerName)"
                                    if let assist = newEvent.assist, let assistName = assist.name, !assistName.isEmpty {
                                        logMessage += " (assist: \(assistName))"
                                    }
                                    if !eventDetail.isEmpty {
                                        logMessage += " | \(eventDetail)"
                                    }

                                    // Log the goal event first
                                    logger.info("\(logMessage)")

                                    // Fetch and log standings/rankings after a goal
                                    Task {
                                        await logStandingsForGoal(leagueId: Int(request.leagueID), teamName: teamName, utcTime: utcTime)
                                    }

                                    // Skip the normal logging at the end since we already logged
                                    continue
                                case "card":
                                    let cardEmoji = eventDetail.lowercased().contains("yellow") ? "🟨" : "🟥"
                                    logMessage += " | \(cardEmoji) \(eventDetail.uppercased()) for \(playerName)"
                                case "subst":
                                    logMessage += " | 🔄 SUBSTITUTION - OUT: \(playerName)"
                                    if let assist = newEvent.assist, let assistName = assist.name, !assistName.isEmpty {
                                        logMessage += ", IN: \(assistName)"
                                    }
                                case "var":
                                    logMessage += " | 📺 VAR - \(eventDetail)"
                                    if !playerName.isEmpty && playerName != "Unknown Player" {
                                        logMessage += " (\(playerName))"
                                    }
                                default:
                                    logMessage += " | \(eventType.uppercased()) - \(playerName) - \(eventDetail)"
                                }

                                if let comments = newEvent.comments, !comments.isEmpty {
                                    logMessage += " | Note: \(comments)"
                                }

                                logger.info("\(logMessage)")
                            }

                            try await fixtureRepository.upsert(
                                from: fixture,
                                leagueId: Int(request.leagueID),
                                season: Int(request.season),
                                competition: fixture.league.name
                            )

                            try await responseStream.send(update)
                        }
                    } else {
                        // New live match
                        var update = Afcon_LiveMatchUpdate()
                        update.fixtureID = Int32(fixtureID)
                        update.timestamp = Google_Protobuf_Timestamp(date: Date())
                        update.eventType = "match_started"
                        update.fixture = convertToFixture(fixture)

                        // Materialize status
                        update.status = convertToFixtureStatus(fixture.fixture.status)

                        // Include recent events
                        update.recentEvents = getRecentEvents(
                            events: currentEvents,
                            currentElapsed: fixture.fixture.status.elapsed ?? 0
                        )

                        // Attach latest event if available
                        if let latestEvent = currentEvents.last {
                            update.event = convertToFixtureEvent(latestEvent)
                        }

                        try await fixtureRepository.upsert(
                            from: fixture,
                            leagueId: Int(request.leagueID),
                            season: Int(request.season),
                            competition: fixture.league.name
                        )

                        try await responseStream.send(update)
                    }

                    previousFixtures[fixtureID] = fixture
                    previousEvents[fixtureID] = currentEvents
                }

                // Remove finished matches
                let currentLiveIDs = Set(liveFixtures.map { $0.fixture.id })
                for (fixtureID, fixture) in previousFixtures {
                    if !currentLiveIDs.contains(fixtureID) {
                        let finalFixture: FixtureData
                        do {
                            finalFixture = try await apiClient.getFixtureById(fixtureId: fixtureID)
                        } catch {
                            logger.warning("⚠️ Failed to fetch final fixture snapshot for \(fixtureID), using cached data: \(error)")
                            finalFixture = fixture
                        }

                        try await fixtureRepository.upsert(
                            from: finalFixture,
                            leagueId: Int(request.leagueID),
                            season: Int(request.season),
                            competition: finalFixture.league.name
                        )

                        var update = Afcon_LiveMatchUpdate()
                        update.fixtureID = Int32(fixtureID)
                        update.timestamp = Google_Protobuf_Timestamp(date: Date())
                        update.eventType = "match_finished"
                        update.fixture = convertToFixture(finalFixture)

                        // Materialize final status
                        update.status = convertToFixtureStatus(finalFixture.fixture.status)

                        try await responseStream.send(update)
                        previousFixtures.removeValue(forKey: fixtureID)
                        previousEvents.removeValue(forKey: fixtureID)
                    }
                }

                try await Task.sleep(nanoseconds: sleepInterval)
            } catch {
                logger.error("Error in live stream: \(error)")
                try await Task.sleep(nanoseconds: activePollingInterval)
            }
        }
    }

    /// Helper method to get the timestamp of the next upcoming fixture
    /// Now uses database instead of API for efficient polling
    private func getNextUpcomingFixtureTimestamp(leagueId: Int, season: Int) async -> Int? {
        do {
            // Query database for next upcoming fixture timestamp
            return try await fixtureRepository.getNextUpcomingTimestamp(leagueId: leagueId, season: season)
        } catch {
            logger.error("Failed to fetch next fixture timestamp from database: \(error)")
            return nil
        }
    }

    /// Helper method to log the next upcoming fixtures when no live games (shows all games at the earliest kickoff time)
    /// Now uses database instead of API
    private func logNextUpcomingFixture(leagueId: Int, season: Int) async {
        do {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.timeZone = TimeZone(identifier: "UTC")
            let utcTime = dateFormatter.string(from: Date())

            logger.info("[\(utcTime)] 🔍 No live matches - Fetching next upcoming fixtures from database for league \(leagueId)...")

            // Get next fixture timestamp from database
            guard let earliestTimestamp = try await fixtureRepository.getNextUpcomingTimestamp(leagueId: leagueId, season: season) else {
                logger.info("[\(utcTime)] ⚠️ No upcoming fixtures found in database for league \(leagueId)")
                return
            }

            // Get all fixtures with that timestamp from database
            let nextFixtureEntities = try await fixtureRepository.getFixturesAtTimestamp(leagueId: leagueId, season: season, timestamp: earliestTimestamp)

            guard !nextFixtureEntities.isEmpty else {
                logger.info("[\(utcTime)] ⚠️ No fixtures found at timestamp \(earliestTimestamp)")
                return
            }

            // Calculate time until the first match
            let now = Date()
            let firstFixtureDate = Date(timeIntervalSince1970: TimeInterval(earliestTimestamp))
            let timeUntilMatch = firstFixtureDate.timeIntervalSince(now)

            let hours = Int(timeUntilMatch / 3600)
            let minutes = Int((timeUntilMatch.truncatingRemainder(dividingBy: 3600)) / 60)
            let days = hours / 24

            var timeString = ""
            if days > 0 {
                timeString = "\(days)d \(hours % 24)h \(minutes)m"
            } else if hours > 0 {
                timeString = "\(hours)h \(minutes)m"
            } else {
                timeString = "\(minutes)m"
            }

            // Format the kickoff time
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            timeFormatter.timeZone = TimeZone(identifier: "UTC")
            let kickoffTime = timeFormatter.string(from: firstFixtureDate)

            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            dayFormatter.timeZone = TimeZone(identifier: "UTC")
            let matchDay = dayFormatter.string(from: firstFixtureDate)

            // Log header
            let separator = String(repeating: "─", count: 80)
            logger.info("[\(utcTime)] 📅 NEXT FIXTURES: \(matchDay) at \(kickoffTime) UTC - \(nextFixtureEntities.count) game\(nextFixtureEntities.count == 1 ? "" : "s")")
            logger.info("[\(utcTime)]    Time until kickoff: \(timeString)")
            logger.info("[\(utcTime)] \(separator)")

            // Log each fixture from database
            for (index, fixtureEntity) in nextFixtureEntities.enumerated() {
                let homeTeam = fixtureEntity.homeTeamName
                let awayTeam = fixtureEntity.awayTeamName
                let venueName = fixtureEntity.venueName

                logger.info("[\(utcTime)]    \(index + 1). \(homeTeam) vs \(awayTeam)")
                logger.info("[\(utcTime)]       Venue: \(venueName)")
                logger.info("[\(utcTime)]       Fixture ID: \(fixtureEntity.apiFixtureId)")

                if index < nextFixtureEntities.count - 1 {
                    logger.info("[\(utcTime)] ")
                }
            }

            logger.info("[\(utcTime)] \(separator)")
        } catch {
            logger.error("❌ Failed to fetch next fixtures from database: \(error)")
        }
    }

    /// Helper method to fetch and log standings/rankings after a goal
    private func logStandingsForGoal(leagueId: Int, teamName: String, utcTime: String) async {
        do {
            logger.info("[\(utcTime)] 📊 Fetching standings after goal by \(teamName)...")
            let standingsData = try await apiClient.getStandings(leagueId: leagueId, season: 2025)

            if standingsData.isEmpty {
                logger.info("[\(utcTime)] ⚠️ No standings available for league \(leagueId)")
                return
            }

            // Log standings for each group
            for standingDataItem in standingsData {
                let leagueName = standingDataItem.league.name
                logger.info("[\(utcTime)] 📊 STANDINGS - \(leagueName)")

                // standings is [[StandingInfo]] - iterate through groups
                for (groupIndex, standingGroup) in standingDataItem.league.standings.enumerated() {
                    if standingDataItem.league.standings.count > 1 {
                        logger.info("[\(utcTime)]    Group \(groupIndex + 1):")
                    }

                    for standing in standingGroup {
                        let rank = standing.rank
                        let team = standing.team.name
                        let played = standing.all.played
                        let wins = standing.all.win
                        let draws = standing.all.draw
                        let losses = standing.all.lose
                        let goalsFor = standing.all.goals.for
                        let goalsAgainst = standing.all.goals.against
                        let goalDiff = standing.goalsDiff
                        let points = standing.points
                        let form = standing.form ?? "N/A"
                        let group = standing.group.isEmpty ? "" : " (\(standing.group))"

                        logger.info("[\(utcTime)]       #\(rank) \(team)\(group) | P:\(played) W:\(wins) D:\(draws) L:\(losses) | GF:\(goalsFor) GA:\(goalsAgainst) GD:\(goalDiff) | Pts:\(points) | Form:\(form)")
                    }
                }
            }
        } catch {
            logger.error("[\(utcTime)] ❌ Failed to fetch standings for league \(leagueId): \(error)")
        }
    }

    private enum StandingsRefreshTrigger: String {
        case scheduled
    }

    private func scheduleStandingsRefresh(for leagueId: Int, season: Int) {
        let key = standingsTaskKey(for: leagueId, season: season)

        standingsTasksLock.lock()
        standingsRefreshTasks[key]?.cancel()
        standingsRefreshTasks[key] = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            await self.runStandingsRefreshLoop(leagueId: leagueId, season: season)
        }
        standingsTasksLock.unlock()

        logger.info("📊 Scheduled standings refresh loop for league \(leagueId) season \(season)")
    }

    private func standingsTaskKey(for leagueId: Int, season: Int) -> String {
        "\(leagueId)-\(season)"
    }

    private func runStandingsRefreshLoop(leagueId: Int, season: Int) async {
        logger.info("📊 Standings refresh loop started for league \(leagueId) season \(season)")
        let hour: TimeInterval = 3600

        while !Task.isCancelled {
            do {
                let now = Date()

                if let window = try await fixtureRepository.getDailyFixtureWindow(
                    leagueId: leagueId,
                    season: season,
                    containing: now
                ) {
                    let start = window.earliest
                    let end = window.latest.addingTimeInterval(3 * hour)

                    if now < start {
                        logger.debug("📊 Waiting until \(start) to begin hourly standings refresh for league \(leagueId)")
                        await sleep(seconds: start.timeIntervalSince(now))
                        continue
                    }

                    if now > end {
                        if let nextWindow = try await nextStandingsWindow(for: leagueId, season: season) {
                            let wait = nextWindow.start.timeIntervalSince(now)
                            logger.debug("📊 Standings window finished for league \(leagueId). Next window at \(nextWindow.start)")
                            await sleep(seconds: max(wait, 0))
                        } else {
                            logger.info("📊 No upcoming fixtures for league \(leagueId). Sleeping 6 hours before checking standings again.")
                            await sleep(seconds: 6 * hour)
                        }
                        continue
                    }

                    let runStart = Date()
                    await performStandingsRefresh(leagueId: leagueId, season: season, trigger: .scheduled)
                    let runEnd = Date()

                    if let nextRefresh = nextStandingsRefreshDate(after: runStart, anchor: start, end: end) {
                        let wait = nextRefresh.timeIntervalSince(runEnd)
                        if wait > 0 {
                            logger.debug("📊 Next scheduled standings refresh for league \(leagueId) at \(nextRefresh)")
                            await sleep(seconds: wait)
                        }
                    } else {
                        let remaining = end.timeIntervalSince(runEnd)
                        if remaining > 0 {
                            logger.debug("📊 Standings window closing for league \(leagueId) in \(remaining) seconds")
                            await sleep(seconds: remaining)
                        }
                    }
                } else if let nextWindow = try await nextStandingsWindow(for: leagueId, season: season) {
                    let wait = nextWindow.start.timeIntervalSince(now)
                    logger.debug("📊 No fixtures today for league \(leagueId). Waiting \(wait) seconds until next standings window at \(nextWindow.start)")
                    await sleep(seconds: max(wait, 0))
                } else {
                    logger.info("📊 No scheduled fixtures remaining for league \(leagueId). Sleeping 12 hours.")
                    await sleep(seconds: 12 * hour)
                }
            } catch {
                logger.error("❌ Standings refresh loop error for league \(leagueId) season \(season): \(error)")
                await sleep(seconds: 300)
            }
        }

        logger.info("📊 Standings refresh loop cancelled for league \(leagueId) season \(season)")
    }

    private func nextStandingsRefreshDate(after runTime: Date, anchor: Date, end: Date) -> Date? {
        let hour: TimeInterval = 3600
        if runTime < anchor {
            return anchor
        }

        let elapsed = runTime.timeIntervalSince(anchor)
        let steps = floor(elapsed / hour) + 1
        let candidate = anchor.addingTimeInterval(steps * hour)
        return candidate <= end ? candidate : nil
    }

    private func nextStandingsWindow(for leagueId: Int, season: Int) async throws -> (start: Date, end: Date)? {
        guard let nextTimestamp = try await fixtureRepository.getNextUpcomingTimestamp(leagueId: leagueId, season: season) else {
            return nil
        }

        let nextDate = Date(timeIntervalSince1970: TimeInterval(nextTimestamp))
        if let window = try await fixtureRepository.getDailyFixtureWindow(leagueId: leagueId, season: season, containing: nextDate) {
            return (start: window.earliest, end: window.latest.addingTimeInterval(3 * 3600))
        } else {
            return (start: nextDate, end: nextDate.addingTimeInterval(3 * 3600))
        }
    }

    private func performStandingsRefresh(leagueId: Int, season: Int, trigger: StandingsRefreshTrigger) async {
        do {
            let standings = try await apiClient.getStandings(leagueId: leagueId, season: season)
            let hasLiveMatches = try await fixtureRepository.hasLiveMatches(leagueId: leagueId, season: season)

            if standings.isEmpty {
                logger.warning("📊 Standings refresh (\(trigger.rawValue)) returned no data for league \(leagueId) season \(season)")
            }

            let ttl = hasLiveMatches ? CacheService.CacheTTL.standingsLive : CacheService.CacheTTL.standingsIdle
            let key = cache.standingsKey(leagueID: leagueId, season: season)
            try await cache.set(key: key, value: standings, ttl: ttl)

            let ttlHours = ttl / 3600
            logger.info("📊 Standings refreshed (\(trigger.rawValue)) for league \(leagueId) season \(season). TTL \(ttlHours)h (\(hasLiveMatches ? "live matches" : "idle")).")
        } catch {
            logger.error("❌ Failed to refresh standings (\(trigger.rawValue)) for league \(leagueId) season \(season): \(error)")
        }
    }

    private func sleep(seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let maxSeconds = Double(UInt64.max) / 1_000_000_000
        let clamped = min(seconds, maxSeconds)

        do {
            try await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
        } catch {
            if Task.isCancelled {
                return
            }
            logger.warning("⏱️ Standings scheduler sleep interrupted: \(error)")
        }
    }

    /// Get standings
    public func getStandings(
        request: Afcon_StandingsRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_StandingsResponse {
        logger.info("gRPC: GetStandings - league=\(request.leagueID), season=\(request.season)")

        // Check if there are live matches to determine cache TTL
        let hasLive = try await fixtureRepository.hasLiveMatches(
            leagueId: Int(request.leagueID),
            season: Int(request.season)
        )

        let standingsData = try await cache.getOrFetchStandings(
            leagueID: Int(request.leagueID),
            season: Int(request.season),
            hasLiveMatches: hasLive
        ) {
            try await apiClient.getStandings(leagueId: Int(request.leagueID), season: Int(request.season))
        }

        var response = Afcon_StandingsResponse()
        // Convert standings data
        // Note: Implementation depends on API structure
        return response
    }

    /// Get team details
    public func getTeamDetails(
        request: Afcon_TeamDetailsRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_TeamDetailsResponse {
        logger.info("gRPC: GetTeamDetails - team=\(request.teamID)")

        let teamData = try await apiClient.getTeamDetails(teamId: Int(request.teamID))

        var response = Afcon_TeamDetailsResponse()
        response.team = convertToTeam(teamData.team)
        response.venue = convertToVenue(teamData.venue)
        return response
    }

    /// Get fixture lineups
    public func getLineups(
        request: Afcon_LineupsRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_LineupsResponse {
        logger.info("gRPC: GetLineups - fixture=\(request.fixtureID)")

        let lineupsData = try await apiClient.getFixtureLineups(fixtureId: Int(request.fixtureID))

        var response = Afcon_LineupsResponse()
        response.lineups = lineupsData.map { convertToFixtureLineup($0) }
        return response
    }

    /// Sync fixtures from API to database
    public func syncFixtures(
        request: Afcon_SyncFixturesRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_SyncFixturesResponse {
        logger.info("gRPC: SyncFixtures - league=\(request.leagueID), season=\(request.season), competition=\(request.competition)")

        var response = Afcon_SyncFixturesResponse()

        do {
            // Fetch all fixtures from API
            let fixturesData = try await apiClient.getFixtures(
                leagueId: Int(request.leagueID),
                season: Int(request.season)
            )

            // Upsert all fixtures into database
            try await fixtureRepository.upsertBatch(
                fixtures: fixturesData,
                leagueId: Int(request.leagueID),
                season: Int(request.season),
                competition: request.competition
            )

            response.success = true
            response.fixturesSynced = Int32(fixturesData.count)
            response.message = "Successfully synced \(fixturesData.count) fixtures to database"

            logger.info("✅ Synced \(fixturesData.count) fixtures for league \(request.leagueID), season \(request.season)")
        } catch {
            response.success = false
            response.fixturesSynced = 0
            response.message = "Failed to sync fixtures: \(error.localizedDescription)"

            logger.error("❌ Failed to sync fixtures: \(error)")
        }

        return response
    }

    // MARK: - Conversion Methods

    private func convertToLeagueResponse(_ data: LeagueData) -> Afcon_LeagueResponse {
        var response = Afcon_LeagueResponse()

        var league = Afcon_League()
        league.id = Int32(data.league.id)
        league.name = data.league.name
        league.type = data.league.type
        league.logo = data.league.logo
        response.league = league

        var country = Afcon_Country()
        country.name = data.country.name
        country.code = data.country.code ?? ""
        country.flag = data.country.flag ?? ""
        response.country = country

        response.seasons = data.seasons.map { seasonInfo in
            var season = Afcon_Season()
            season.year = Int32(seasonInfo.year)
            season.start = seasonInfo.start
            season.end = seasonInfo.end
            season.current = seasonInfo.current

            var coverage = Afcon_Coverage()
            var fixtureCov = Afcon_FixtureCoverage()
            fixtureCov.events = seasonInfo.coverage.fixtures.events
            fixtureCov.lineups = seasonInfo.coverage.fixtures.lineups
            fixtureCov.statisticsFixtures = seasonInfo.coverage.fixtures.statisticsFixtures
            fixtureCov.statisticsPlayers = seasonInfo.coverage.fixtures.statisticsPlayers
            coverage.fixtures = fixtureCov
            coverage.standings = seasonInfo.coverage.standings
            coverage.players = seasonInfo.coverage.players
            coverage.topScorers = seasonInfo.coverage.topScorers
            coverage.topAssists = seasonInfo.coverage.topAssists
            coverage.topCards = seasonInfo.coverage.topCards
            coverage.injuries = seasonInfo.coverage.injuries
            coverage.predictions = seasonInfo.coverage.predictions
            coverage.odds = seasonInfo.coverage.odds

            season.coverage = coverage
            return season
        }

        return response
    }

    private func convertToTeamInfo(_ data: TeamData) -> Afcon_TeamInfo {
        var teamInfo = Afcon_TeamInfo()
        teamInfo.team = convertToTeam(data.team)
        teamInfo.venue = convertToVenue(data.venue)
        return teamInfo
    }

    private func convertToTeam(_ data: TeamInfo) -> Afcon_Team {
        var team = Afcon_Team()
        team.id = Int32(data.id)
        team.name = data.name
        team.code = data.code
        team.country = data.country
        team.founded = Int32(data.founded)
        team.national = data.national
        team.logo = data.logo
        return team
    }

    private func convertToVenue(_ data: VenueInfo) -> Afcon_Venue {
        var venue = Afcon_Venue()
        venue.id = Int32(data.id)
        venue.name = data.name
        venue.address = data.address ?? ""
        venue.city = data.city
        venue.capacity = Int32(data.capacity)
        venue.surface = data.surface
        venue.image = data.image
        return venue
    }

    private func convertToFixture(_ data: FixtureData) -> Afcon_Fixture {
        var fixture = Afcon_Fixture()
        fixture.id = Int32(data.fixture.id)
        fixture.referee = data.fixture.referee ?? ""
        fixture.timezone = data.fixture.timezone
        fixture.timestamp = Int32(data.fixture.timestamp)

        let dateFormatter = ISO8601DateFormatter()
        if let date = dateFormatter.date(from: data.fixture.date) {
            fixture.date = Google_Protobuf_Timestamp(date: date)
        }

        var periods = Afcon_FixturePeriods()
        periods.first = Int32(data.fixture.periods.first ?? 0)
        periods.second = Int32(data.fixture.periods.second ?? 0)
        fixture.periods = periods

        var fixtureVenue = Afcon_FixtureVenue()
        fixtureVenue.id = Int32(data.fixture.venue.id ?? 0)
        fixtureVenue.name = data.fixture.venue.name ?? ""
        fixtureVenue.city = data.fixture.venue.city ?? ""
        fixture.venue = fixtureVenue

        var status = Afcon_FixtureStatus()
        status.long = data.fixture.status.long
        status.short = data.fixture.status.short
        status.elapsed = Int32(data.fixture.status.elapsed ?? 0)
        fixture.status = status

        var teams = Afcon_FixtureTeams()
        var home = Afcon_FixtureTeam()
        home.id = Int32(data.teams.home.id)
        home.name = data.teams.home.name
        home.logo = data.teams.home.logo
        home.winner = data.teams.home.winner ?? false
        teams.home = home

        var away = Afcon_FixtureTeam()
        away.id = Int32(data.teams.away.id)
        away.name = data.teams.away.name
        away.logo = data.teams.away.logo
        away.winner = data.teams.away.winner ?? false
        teams.away = away
        fixture.teams = teams

        var goals = Afcon_FixtureGoals()
        goals.home = Int32(data.goals.home ?? 0)
        goals.away = Int32(data.goals.away ?? 0)
        fixture.goals = goals

        var score = Afcon_FixtureScore()
        var halftime = Afcon_ScoreDetail()
        halftime.home = Int32(data.score.halftime.home ?? 0)
        halftime.away = Int32(data.score.halftime.away ?? 0)
        score.halftime = halftime

        var fulltime = Afcon_ScoreDetail()
        fulltime.home = Int32(data.score.fulltime.home ?? 0)
        fulltime.away = Int32(data.score.fulltime.away ?? 0)
        score.fulltime = fulltime

        fixture.score = score

        return fixture
    }

    private func convertFixtureEntityToFixture(_ entity: FixtureEntity) -> Afcon_Fixture {
        var fixture = Afcon_Fixture()
        fixture.id = Int32(entity.apiFixtureId)
        fixture.referee = entity.referee ?? ""
        fixture.timezone = entity.timezone
        fixture.timestamp = Int32(entity.timestamp)
        fixture.date = Google_Protobuf_Timestamp(date: entity.date)

        var periods = Afcon_FixturePeriods()
        periods.first = Int32(entity.periodFirst ?? 0)
        periods.second = Int32(entity.periodSecond ?? 0)
        fixture.periods = periods

        var venue = Afcon_FixtureVenue()
        venue.id = Int32(entity.venueId)
        venue.name = entity.venueName
        venue.city = entity.venueCity ?? ""
        fixture.venue = venue

        var status = Afcon_FixtureStatus()
        status.long = entity.statusLong
        status.short = entity.statusShort
        status.elapsed = Int32(entity.statusElapsed ?? 0)
        fixture.status = status

        var teams = Afcon_FixtureTeams()
        var home = Afcon_FixtureTeam()
        home.id = Int32(entity.homeTeamId)
        home.name = entity.homeTeamName
        home.logo = entity.homeTeamLogo ?? ""
        home.winner = entity.homeTeamWinner ?? false
        teams.home = home

        var away = Afcon_FixtureTeam()
        away.id = Int32(entity.awayTeamId)
        away.name = entity.awayTeamName
        away.logo = entity.awayTeamLogo ?? ""
        away.winner = entity.awayTeamWinner ?? false
        teams.away = away
        fixture.teams = teams

        var goals = Afcon_FixtureGoals()
        goals.home = Int32(entity.homeGoals ?? 0)
        goals.away = Int32(entity.awayGoals ?? 0)
        fixture.goals = goals

        var score = Afcon_FixtureScore()
        var halftime = Afcon_ScoreDetail()
        halftime.home = Int32(entity.halftimeHome ?? 0)
        halftime.away = Int32(entity.halftimeAway ?? 0)
        score.halftime = halftime

        var fulltime = Afcon_ScoreDetail()
        fulltime.home = Int32(entity.fulltimeHome ?? 0)
        fulltime.away = Int32(entity.fulltimeAway ?? 0)
        score.fulltime = fulltime

        fixture.score = score

        return fixture
    }

    // MARK: - Helper Methods

    private func hasSignificantChanges(
        previous: FixtureData,
        current: FixtureData,
        currentEvents: [FixtureEvent],
        previousEvents: [FixtureEvent]
    ) -> Bool {
        // Check for new events
        let hasNewEvents = currentEvents.count != previousEvents.count ||
            currentEvents.contains { currentEvent in
                !previousEvents.contains { prevEvent in
                    eventsAreEqual(currentEvent, prevEvent)
                }
            }

        // For live matches (1H, 2H), send update every 1 minute of elapsed time
        let isLive = current.fixture.status.short == "1H" || current.fixture.status.short == "2H"
        let elapsedDifference = (current.fixture.status.elapsed ?? 0) - (previous.fixture.status.elapsed ?? 0)

        // Check for other significant changes
        return previous.goals.home != current.goals.home ||
               previous.goals.away != current.goals.away ||
               previous.fixture.status.short != current.fixture.status.short ||
               hasNewEvents ||
               (isLive && elapsedDifference >= 1) // Send update every minute for live matches
    }

    private func detectEventType(previous: FixtureData, current: FixtureData) -> String {
        if previous.goals.home != current.goals.home || previous.goals.away != current.goals.away {
            return "goal"
        }
        if previous.fixture.status.short != current.fixture.status.short {
            return "status_update"
        }
        return "time_update"
    }

    /// Enhanced event detection using actual fixture events
    private func detectEventTypeEnhanced(
        previous: FixtureData,
        current: FixtureData,
        currentEvents: [FixtureEvent],
        previousEvents: [FixtureEvent]
    ) -> String {
        // Check for new events
        let newEvents = currentEvents.filter { currentEvent in
            !previousEvents.contains { prevEvent in
                eventsAreEqual(currentEvent, prevEvent)
            }
        }

        // Prioritize event types
        if let latestEvent = newEvents.last {
            let eventType = latestEvent.type?.lowercased() ?? ""
            let eventDetail = latestEvent.detail?.lowercased() ?? ""

            // Goal events
            if eventType == "goal" {
                if eventDetail.contains("missed") {
                    return "missed_penalty"
                }
                return "goal"
            }

            // Card events
            if eventType == "card" {
                if eventDetail.contains("red") || eventDetail.contains("second yellow") {
                    return "red_card"
                }
                if eventDetail.contains("yellow") {
                    return "yellow_card"
                }
                return "card"
            }

            // Substitution
            if eventType == "subst" {
                return "substitution"
            }

            // VAR events
            if eventType == "var" {
                return "var"
            }
        }

        // Fallback to score/status changes
        if previous.goals.home != current.goals.home || previous.goals.away != current.goals.away {
            return "goal"
        }
        if previous.fixture.status.short != current.fixture.status.short {
            return "status_update"
        }

        return "time_update"
    }

    /// Fetch fixture events with error handling
    private func fetchFixtureEventsIfNeeded(fixtureId: Int) async throws -> [FixtureEvent] {
        do {
            return try await apiClient.getFixtureEvents(fixtureId: fixtureId)
        } catch {
            logger.warning("Failed to fetch events for fixture \(fixtureId): \(error)")
            return []
        }
    }

    /// Get recent events (all events from the match, sorted by time)
    private func getRecentEvents(events: [FixtureEvent], currentElapsed: Int) -> [Afcon_FixtureEvent] {
        // Return all events, sorted by time (oldest first)
        return events
            .sorted { (event1, event2) -> Bool in
                let time1 = (event1.time?.elapsed ?? 0) + (event1.time?.extra ?? 0)
                let time2 = (event2.time?.elapsed ?? 0) + (event2.time?.extra ?? 0)
                return time1 < time2
            }
            .map { convertToFixtureEvent($0) }
    }

    /// Check if two events are equal
    private func eventsAreEqual(_ event1: FixtureEvent, _ event2: FixtureEvent) -> Bool {
        return event1.time?.elapsed == event2.time?.elapsed &&
               event1.time?.extra == event2.time?.extra &&
               event1.type == event2.type &&
               event1.detail == event2.detail &&
               event1.player?.id == event2.player?.id
    }

    /// Convert fixture status to proto message
    private func convertToFixtureStatus(_ status: FixtureStatusInfo) -> Afcon_FixtureStatus {
        var protoStatus = Afcon_FixtureStatus()
        protoStatus.long = status.long
        protoStatus.short = status.short
        protoStatus.elapsed = Int32(status.elapsed ?? 0)
        return protoStatus
    }

    /// Convert fixture event to proto message (Afcon_FixtureEvent)
    private func convertToFixtureEvent(_ event: FixtureEvent) -> Afcon_FixtureEvent {
        var protoEvent = Afcon_FixtureEvent()

        if let time = event.time {
            var eventTime = Afcon_EventTime()
            eventTime.elapsed = Int32(time.elapsed ?? 0)
            eventTime.extra = Int32(time.extra ?? 0)
            protoEvent.time = eventTime
        }

        if let team = event.team {
            var eventTeam = Afcon_EventTeam()
            eventTeam.id = Int32(team.id ?? 0)
            eventTeam.name = team.name ?? ""
            eventTeam.logo = team.logo ?? ""
            protoEvent.team = eventTeam
        }

        if let player = event.player {
            var eventPlayer = Afcon_EventPlayer()
            eventPlayer.id = Int32(player.id ?? 0)
            eventPlayer.name = player.name ?? ""
            protoEvent.player = eventPlayer
        }

        if let assist = event.assist {
            var eventAssist = Afcon_EventPlayer()
            eventAssist.id = Int32(assist.id ?? 0)
            eventAssist.name = assist.name ?? ""
            protoEvent.assist = eventAssist
        }

        protoEvent.type = event.type ?? ""
        protoEvent.detail = event.detail ?? ""
        protoEvent.comments = event.comments ?? ""

        return protoEvent
    }

    /// Convert fixture lineup to proto message
    private func convertToFixtureLineup(_ lineup: FixtureLineup) -> Afcon_FixtureLineup {
        var protoLineup = Afcon_FixtureLineup()

        // Team
        var team = Afcon_LineupTeam()
        team.id = Int32(lineup.team.id)
        team.name = lineup.team.name
        team.logo = lineup.team.logo
        if let colors = lineup.team.colors {
            var teamColors = Afcon_TeamColors()
            if let player = colors.player {
                var playerColor = Afcon_ColorInfo()
                playerColor.primary = player.primary ?? ""
                playerColor.number = player.number ?? ""
                playerColor.border = player.border ?? ""
                teamColors.player = playerColor
            }
            if let goalkeeper = colors.goalkeeper {
                var goalkeeperColor = Afcon_ColorInfo()
                goalkeeperColor.primary = goalkeeper.primary ?? ""
                goalkeeperColor.number = goalkeeper.number ?? ""
                goalkeeperColor.border = goalkeeper.border ?? ""
                teamColors.goalkeeper = goalkeeperColor
            }
            team.colors = teamColors
        }
        protoLineup.team = team

        // Coach
        var coach = Afcon_LineupCoach()
        coach.id = Int32(lineup.coach.id ?? 0)
        coach.name = lineup.coach.name
        coach.photo = lineup.coach.photo ?? ""
        protoLineup.coach = coach

        // Formation
        protoLineup.formation = lineup.formation ?? ""

        // Start XI
        protoLineup.startXi = lineup.startXI.map { position in
            var playerPos = Afcon_LineupPlayerPosition()
            var player = Afcon_LineupPlayer()
            player.id = Int32(position.player.id)
            player.name = position.player.name
            player.number = Int32(position.player.number)
            player.pos = position.player.pos ?? ""
            playerPos.player = player
            playerPos.grid = "" // Grid not available in API response
            return playerPos
        }

        // Substitutes
        protoLineup.substitutes = lineup.substitutes.map { position in
            var playerPos = Afcon_LineupPlayerPosition()
            var player = Afcon_LineupPlayer()
            player.id = Int32(position.player.id)
            player.name = position.player.name
            player.number = Int32(position.player.number)
            player.pos = position.player.pos ?? ""
            playerPos.player = player
            playerPos.grid = ""
            return playerPos
        }

        return protoLineup
    }
}
