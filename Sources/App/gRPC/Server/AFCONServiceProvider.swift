import Foundation
import Vapor
import GRPCCore
import GRPCProtobuf
import SwiftProtobuf

/// gRPC service provider for AFCON data
/// This class implements the AFCON service protocol from the generated code (grpc-swift 2.x)
public final class AFCONServiceProvider: Afcon_AFCONService.ServiceProtocol, @unchecked Sendable {
    private let apiClient: APIFootballClient
    private let cache: CacheService
    private let fixtureRepository: FixtureRepository
    private let notificationService: NotificationService?
    private let deviceRepository: DeviceRepository
    private let broadcaster: LiveMatchBroadcaster
    private let logger: Logger
    private var standingsRefreshTasks: [String: Task<Void, Never>] = [:]
    private let standingsTasksLock = NSLock()

    public init(
        apiClient: APIFootballClient,
        cache: CacheService,
        fixtureRepository: FixtureRepository,
        notificationService: NotificationService?,
        deviceRepository: DeviceRepository,
        broadcaster: LiveMatchBroadcaster,
        logger: Logger
    ) {
        self.apiClient = apiClient
        self.cache = cache
        self.fixtureRepository = fixtureRepository
        self.notificationService = notificationService
        self.deviceRepository = deviceRepository
        self.broadcaster = broadcaster
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
        request: ServerRequest<Afcon_LeagueRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_LeagueResponse> {
        let req = request.message
        logger.info("gRPC: GetLeague - id=\(req.leagueID), season=\(req.season)")

        // Fetch from API with caching
        let leagueData = try await cache.getOrFetchLeague(
            id: Int(req.leagueID),
            season: Int(req.season)
        ) {
            try await apiClient.getLeague(id: Int(req.leagueID), season: Int(req.season))
        }

        // Convert to gRPC response
        let response = convertToLeagueResponse(leagueData)
        return ServerResponse(message: response)
    }

    /// Get all teams for a league/season
    public func getTeams(
        request: ServerRequest<Afcon_TeamsRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_TeamsResponse> {
        let req = request.message
        logger.info("gRPC: GetTeams - league=\(req.leagueID), season=\(req.season)")

        let teamsData = try await cache.getOrFetchTeams(
            leagueID: Int(req.leagueID),
            season: Int(req.season)
        ) {
            try await apiClient.getTeams(leagueId: Int(req.leagueID), season: Int(req.season))
        }

        var response = Afcon_TeamsResponse()
        response.teams = teamsData.map { convertToTeamInfo($0) }
        return ServerResponse(message: response)
    }

    /// Get fixtures for a league/season
    public func getFixtures(
        request: ServerRequest<Afcon_FixturesRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_FixturesResponse> {
        let req = request.message
        logger.info("gRPC: GetFixtures - league=\(req.leagueID), season=\(req.season)")

        let date = req.date.isEmpty ? nil : req.date
        let teamID = req.teamID == 0 ? nil : Int(req.teamID)

        let fixturesData = try await cache.getOrFetchFixtures(
            leagueID: Int(req.leagueID),
            season: Int(req.season),
            date: date,
            teamID: teamID,
            live: req.live
        ) {
            try await apiClient.getFixtures(
                leagueId: Int(req.leagueID),
                season: Int(req.season),
                date: date,
                teamId: teamID,
                live: req.live
            )
        }

        var response = Afcon_FixturesResponse()
        response.fixtures = fixturesData.map { convertToFixture($0) }
        return ServerResponse(message: response)
    }

    /// Get today's upcoming fixtures (not started yet)
    public func getTodayUpcoming(
        request: ServerRequest<Afcon_TodayUpcomingRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_FixturesResponse> {
        let req = request.message
        logger.info("gRPC: GetTodayUpcoming - league=\(req.leagueID), season=\(req.season)")

        // Get today's date in YYYY-MM-DD format
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        // Fetch today's fixtures
        let allFixtures = try await cache.getOrFetchFixtures(
            leagueID: Int(req.leagueID),
            season: Int(req.season),
            date: today,
            teamID: nil,
            live: false
        ) {
            try await apiClient.getFixtures(
                leagueId: Int(req.leagueID),
                season: Int(req.season),
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
        return ServerResponse(message: response)
    }

    /// Get next upcoming fixtures (all games at the earliest kickoff time)
    public func getNextUpcoming(
        request: ServerRequest<Afcon_NextUpcomingRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_FixturesResponse> {
        let req = request.message
        logger.info("gRPC: GetNextUpcoming - league=\(req.leagueID), season=\(req.season)")

        // Fetch all fixtures for the season
        let allFixtures = try await cache.getOrFetchFixtures(
            leagueID: Int(req.leagueID),
            season: Int(req.season),
            date: nil,
            teamID: nil,
            live: false
        ) {
            try await apiClient.getFixtures(
                leagueId: Int(req.leagueID),
                season: Int(req.season),
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
            return ServerResponse(message: Afcon_FixturesResponse())
        }

        let earliestTimestamp = upcomingFixtures[0].fixture.timestamp
        let nextFixtures = upcomingFixtures.filter { $0.fixture.timestamp == earliestTimestamp }

        logger.info("gRPC: GetNextUpcoming - Found \(nextFixtures.count) fixture\(nextFixtures.count == 1 ? "" : "s") at earliest kickoff time")

        var response = Afcon_FixturesResponse()
        response.fixtures = nextFixtures.map { convertToFixture($0) }
        return ServerResponse(message: response)
    }

    /// Get fixture by ID
    public func getFixtureById(
        request: ServerRequest<Afcon_FixtureByIdRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_FixtureResponse> {
        let req = request.message
        logger.info("gRPC: GetFixtureById - fixtureID=\(req.fixtureID)")

        let fixtureData = try await apiClient.getFixtureById(fixtureId: Int(req.fixtureID))

        var response = Afcon_FixtureResponse()
        response.fixture = convertToFixture(fixtureData)
        return ServerResponse(message: response)
    }

    /// Get fixture events by ID
    public func getFixtureEvents(
        request: ServerRequest<Afcon_FixtureEventsRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_FixtureEventsResponse> {
        let req = request.message
        logger.info("gRPC: GetFixtureEvents - fixtureID=\(req.fixtureID)")

        let events = try await apiClient.getFixtureEvents(fixtureId: Int(req.fixtureID))

        var response = Afcon_FixtureEventsResponse()
        response.events = events.map { convertToFixtureEvent($0) }
        return ServerResponse(message: response)
    }

    /// Get fixtures by date
    public func getFixturesByDate(
        request: ServerRequest<Afcon_FixturesByDateRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_FixturesResponse> {
        let req = request.message
        logger.info("gRPC: GetFixturesByDate - date=\(req.date)")

        let leagueID = req.leagueID > 0 ? Int(req.leagueID) : nil
        let season = req.season > 0 ? Int(req.season) : nil

        var response = Afcon_FixturesResponse()

        var requestedDate: Date?
        var isToday = false

        if !req.date.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            requestedDate = formatter.date(from: req.date)

            if
                let requestedDate,
                let gmt = TimeZone(secondsFromGMT: 0)
            {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = gmt
                isToday = calendar.isDate(requestedDate, inSameDayAs: Date())
            }
        }

        var lastError: (any Error)?

        if let leagueID = leagueID, let season = season {
            do {
                let fixturesData = try await cache.getOrFetchFixtures(
                    leagueID: leagueID,
                    season: season,
                    date: req.date,
                    teamID: nil,
                    live: isToday
                ) {
                    try await apiClient.getFixtures(
                        leagueId: leagueID,
                        season: season,
                        date: req.date,
                        teamId: nil,
                        live: isToday
                    )
                }

                if !fixturesData.isEmpty {
                    let competitionName = fixturesData.first?.league.name ?? "League \(leagueID)"
                    try await fixtureRepository.upsertBatch(
                        fixtures: fixturesData,
                        leagueId: leagueID,
                        season: season,
                        competition: competitionName
                    )
                }

                response.fixtures = fixturesData.map { convertToFixture($0) }
                return ServerResponse(message: response)
            } catch {
                lastError = error
                logger.warning("gRPC: GetFixturesByDate - failed to fetch from API/cache for league \(leagueID), season \(season); falling back to DB: \(error)")
            }

            if let requestedDate {
                let dbFixtures = try await fixtureRepository.getFixturesForDate(
                    leagueId: leagueID,
                    season: season,
                    date: requestedDate
                )

                if !dbFixtures.isEmpty {
                    logger.info("gRPC: GetFixturesByDate - served from DB fallback for \(req.date) (\(dbFixtures.count) fixtures)")
                    response.fixtures = dbFixtures.map { convertFixtureEntityToFixture($0) }
                    return ServerResponse(message: response)
                }
            }

            if let error = lastError {
                throw error
            }

            return ServerResponse(message: response)
        }

        let fixturesData = try await apiClient.getFixturesByDate(date: req.date)

        response.fixtures = fixturesData.map { convertToFixture($0) }
        return ServerResponse(message: response)
    }

    /// Stream live match updates using centralized broadcaster
    /// This method now subscribes to the LiveMatchBroadcaster instead of polling directly
    /// Scales to 10k+ concurrent clients by sharing a single poller
    public func streamLiveMatches(
        request: ServerRequest<Afcon_LiveMatchRequest>,
        context: ServerContext
    ) async throws -> StreamingServerResponse<Afcon_LiveMatchUpdate> {
        let req = request.message
        let subscriberCount = broadcaster.getSubscriberCount(for: Int(req.leagueID))

        logger.info("📱 gRPC: StreamLiveMatches - league=\(req.leagueID), season=\(req.season) [Client \(subscriberCount + 1) connecting]")

        return StreamingServerResponse { writer in
            // Subscribe to the centralized broadcaster
            // This returns an AsyncStream that receives updates when the broadcaster detects changes
            let updateStream = self.broadcaster.subscribe(
                leagueID: Int(req.leagueID),
                season: Int(req.season)
            )

            // Simply relay updates from broadcaster to this client
            for await update in updateStream {
                do {
                    try await writer.write(update)
                } catch {
                    self.logger.error("Failed to write update to client: \(error)")
                    break
                }
            }

            self.logger.info("📱 Client disconnected from league \(req.leagueID)")
            return [:] // Return empty metadata
        }
    }

    // Legacy method - kept for reference but no longer used
    // The broadcaster handles all the logic below
    private func streamLiveMatchesLegacy_UNUSED(
        request: ServerRequest<Afcon_LiveMatchRequest>,
        context: ServerContext
    ) async throws -> StreamingServerResponse<Afcon_LiveMatchUpdate> {
        let req = request.message
        let pauseAfconEnv = Environment.get("PAUSE_AFCON_LIVE_MATCHES")?.lowercased()
        let shouldPauseAfcon = pauseAfconEnv == "1" || pauseAfconEnv == "true" || pauseAfconEnv == "yes"
        let isPaused = shouldPauseAfcon && req.leagueID == 6
        self.logger.info("gRPC: StreamLiveMatches - league=\(req.leagueID)\(isPaused ? " - PAUSED" : "")")

        return StreamingServerResponse { writer in

        var previousFixtures: [Int: FixtureData] = [:]
        var previousEvents: [Int: [FixtureEvent]] = [:]
        let activePollingInterval: UInt64 = 15_000_000_000

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
                    liveFixtures = try await self.apiClient.getLiveFixtures(leagueId: Int(req.leagueID))
                }

                // Calculate dynamic sleep interval
                var sleepInterval = activePollingInterval

                // If no live fixtures, fetch next upcoming fixture and adjust polling
                if liveFixtures.isEmpty && !isPaused {
                    let currentTime = Date()
                    // Check for next fixture info
                    if lastNoLiveCheckTime == nil || currentTime.timeIntervalSince(lastNoLiveCheckTime!) > 300 {
                        lastNoLiveCheckTime = currentTime
                        nextFixtureTimestamp = await self.getNextUpcomingFixtureTimestamp(leagueId: Int(req.leagueID), season: Int(req.season))
                        await self.logNextUpcomingFixture(leagueId: Int(req.leagueID), season: Int(req.season))
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
                            self.logger.info("⏸️ No live matches. Next fixture in \(days) day\(days == 1 ? "" : "s"). Pausing polling for 12 hours...")
                        } else if timeUntilMatch > 21600 {
                            // Between 6 hours and 1 day: sleep for 3 hours
                            sleepInterval = 3 * 60 * 60 * 1_000_000_000
                            self.logger.info("⏸️ No live matches. Next fixture in \(hours) hours. Pausing polling for 3 hours...")
                        } else if timeUntilMatch > 3600 {
                            // Between 1 hour and 6 hours: sleep for 30 minutes
                            sleepInterval = 30 * 60 * 1_000_000_000
                            self.logger.info("⏸️ No live matches. Next fixture in \(hours) hour\(hours == 1 ? "" : "s"). Pausing polling for 30 minutes...")
                        } else if timeUntilMatch > 600 {
                            // Between 10 minutes and 1 hour: sleep for 5 minutes
                            sleepInterval = 5 * 60 * 1_000_000_000
                            self.logger.info("⏸️ No live matches. Next fixture in \(minutes) minutes. Pausing polling for 5 minutes...")
                        } else if timeUntilMatch > 0 {
                            // Less than 10 minutes: start polling every 15 seconds
                            sleepInterval = activePollingInterval
                            self.logger.info("⏰ Next fixture starts in \(minutes) minute\(minutes == 1 ? "" : "s"). Resuming active polling...")
                        }
                    } else {
                        // No next fixture found, sleep for 24 hours
                        sleepInterval = 24 * 60 * 60 * 1_000_000_000
                        self.logger.info("⏸️ No upcoming fixtures found. Pausing polling for 24 hours...")
                    }
                }

                for fixture in liveFixtures {
                    let fixtureID = fixture.fixture.id

                    // Fetch current events for this fixture
                    let currentEvents = try await self.fetchFixtureEventsIfNeeded(fixtureId: fixtureID)

                    if let previous = previousFixtures[fixtureID] {
                        // Detect changes
                        if self.hasSignificantChanges(
                            previous: previous,
                            current: fixture,
                            currentEvents: currentEvents,
                            previousEvents: previousEvents[fixtureID] ?? []
                        ) {
                            var update = Afcon_LiveMatchUpdate()
                            update.fixtureID = Int32(fixtureID)
                            update.timestamp = Google_Protobuf_Timestamp(date: Date())

                            // Enhanced event detection with actual fixture events
                            let detectedEventType = self.detectEventTypeEnhanced(
                                previous: previous,
                                current: fixture,
                                currentEvents: currentEvents,
                                previousEvents: previousEvents[fixtureID] ?? []
                            )
                            update.eventType = detectedEventType
                            update.fixture = self.convertToFixture(fixture)

                            // Materialize status for easy access
                            update.status = self.convertToFixtureStatus(fixture.fixture.status)

                            // Include recent events (last 5 minutes)
                            let recentEvents = self.getRecentEvents(
                                events: currentEvents,
                                currentElapsed: fixture.fixture.status.elapsed ?? 0
                            )
                            update.recentEvents = recentEvents

                            self.logger.info("📊 Fixture \(fixtureID): \(currentEvents.count) total events, \(recentEvents.count) recent events")

                            // Debug: Log each event being sent
                            for (index, event) in recentEvents.enumerated() {
                                self.logger.info("   Event \(index + 1): \(event.time.elapsed)' \(event.type) - \(event.player.name)")
                            }

                            // Attach latest event if there is a newly detected one
                            let newlyDetectedEvents = currentEvents.filter { currentEvent in
                                !(previousEvents[fixtureID] ?? []).contains { prevEvent in
                                    self.eventsAreEqual(currentEvent, prevEvent)
                                }
                            }
                            if let latestEvent = newlyDetectedEvents.last {
                                update.event = self.convertToFixtureEvent(latestEvent)
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
                                    self.logger.info("\(logMessage)")

                                    // Send goal notification
                                    Task {
                                        do {
                                            try await self.notificationService?.sendGoalNotification(
                                                fixtureId: fixtureID,
                                                homeTeam: fixture.teams.home.name,
                                                awayTeam: fixture.teams.away.name,
                                                homeGoals: fixture.goals.home ?? 0,
                                                awayGoals: fixture.goals.away ?? 0,
                                                scorer: playerName,
                                                assist: newEvent.assist?.name,
                                                minute: elapsed,
                                                leagueId: Int(req.leagueID),
                                                season: Int(req.season)
                                            )
                                        } catch {
                                            self.logger.error("Failed to send goal notification: \(error)")
                                        }
                                    }

                                    // Fetch and log standings/rankings after a goal
                                    Task {
                                        await self.logStandingsForGoal(leagueId: Int(req.leagueID), teamName: teamName, utcTime: utcTime)
                                    }

                                    // Skip the normal logging at the end since we already logged
                                    continue
                                case "card":
                                    let cardEmoji = eventDetail.lowercased().contains("yellow") ? "🟨" : "🟥"
                                    logMessage += " | \(cardEmoji) \(eventDetail.uppercased()) for \(playerName)"

                                    // Send red card notification
                                    if eventDetail.lowercased().contains("red") {
                                        Task {
                                            do {
                                                try await self.notificationService?.sendRedCardNotification(
                                                    fixtureId: fixtureID,
                                                    homeTeam: fixture.teams.home.name,
                                                    awayTeam: fixture.teams.away.name,
                                                    playerName: playerName,
                                                    teamName: teamName,
                                                    minute: elapsed,
                                                    leagueId: Int(req.leagueID),
                                                    season: Int(req.season)
                                                )
                                            } catch {
                                                self.logger.error("Failed to send red card notification: \(error)")
                                            }
                                        }
                                    }
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

                                self.logger.info("\(logMessage)")
                            }

                            try await self.fixtureRepository.upsert(
                                from: fixture,
                                leagueId: Int(req.leagueID),
                                season: Int(req.season),
                                competition: fixture.league.name
                            )

                            try await writer.write(update)
                        }
                    } else {
                        // New live match
                        var update = Afcon_LiveMatchUpdate()
                        update.fixtureID = Int32(fixtureID)
                        update.timestamp = Google_Protobuf_Timestamp(date: Date())
                        update.eventType = "match_started"
                        update.fixture = self.convertToFixture(fixture)

                        // Materialize status
                        update.status = self.convertToFixtureStatus(fixture.fixture.status)

                        // Include recent events
                        update.recentEvents = self.getRecentEvents(
                            events: currentEvents,
                            currentElapsed: fixture.fixture.status.elapsed ?? 0
                        )

                        if !currentEvents.isEmpty {
                            self.logger.info("📌 Fixture \(fixtureID): \(currentEvents.count) existing events on first detection")
                            for (index, event) in currentEvents.enumerated() {
                                let elapsed = event.time?.elapsed ?? 0
                                let eventType = event.type ?? "unknown"
                                let eventDetail = event.detail ?? ""
                                let playerName = event.player?.name ?? "Unknown Player"
                                self.logger.info("   Existing Event \(index + 1): \(elapsed)' \(eventType) - \(playerName) \(eventDetail)")
                            }
                        }

                        // Attach latest event if available
                        if let latestEvent = currentEvents.last {
                            update.event = self.convertToFixtureEvent(latestEvent)
                        }

                        try await self.fixtureRepository.upsert(
                            from: fixture,
                            leagueId: Int(req.leagueID),
                            season: Int(req.season),
                            competition: fixture.league.name
                        )

                        try await writer.write(update)
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
                            finalFixture = try await self.apiClient.getFixtureById(fixtureId: fixtureID)
                        } catch {
                            self.logger.warning("⚠️ Failed to fetch final fixture snapshot for \(fixtureID), using cached data: \(error)")
                            finalFixture = fixture
                        }

                        try await self.fixtureRepository.upsert(
                            from: finalFixture,
                            leagueId: Int(req.leagueID),
                            season: Int(req.season),
                            competition: finalFixture.league.name
                        )

                        var update = Afcon_LiveMatchUpdate()
                        update.fixtureID = Int32(fixtureID)
                        update.timestamp = Google_Protobuf_Timestamp(date: Date())
                        update.eventType = "match_finished"
                        update.fixture = self.convertToFixture(finalFixture)

                        // Materialize final status
                        update.status = self.convertToFixtureStatus(finalFixture.fixture.status)

                        // Send match finished notification
                        Task {
                            do {
//                                 try await self.notificationService?.sendMatchEndNotification(
//                                     fixtureId: fixtureID,
//                                     homeTeam: finalFixture.teams.home.name,
//                                     awayTeam: finalFixture.teams.away.name,
//                                     homeGoals: finalFixture.goals.home ?? 0,
//                                     awayGoals: finalFixture.goals.away ?? 0,
//                                     leagueId: Int(req.leagueID),
//                                     season: Int(req.season)
//                                 )
                            } catch {
                                self.logger.error("Failed to send match end notification: \(error)")
                            }
                        }

                        try await writer.write(update)
                        previousFixtures.removeValue(forKey: fixtureID)
                        previousEvents.removeValue(forKey: fixtureID)
                    }
                }

                // Check for halftime status and adjust polling interval
                let halftimeFixtures = liveFixtures.filter { $0.fixture.status.short == "HT" }
                if !halftimeFixtures.isEmpty && !isPaused {
                    // Find the fixture with the longest elapsed time (most likely to resume first)
                    if let halftimeFixture = halftimeFixtures.max(by: { ($0.fixture.status.elapsed ?? 0) < ($1.fixture.status.elapsed ?? 0) }) {
                        let elapsed = halftimeFixture.fixture.status.elapsed ?? 45
                        let extraTime = halftimeFixture.fixture.periods.first ?? 45

                        // Calculate expected second half start time
                        // elapsed time + 14 minutes halftime break
                        let expectedSecondHalfMinutes = elapsed + 14
                        let timeUntilSecondHalf = (expectedSecondHalfMinutes - elapsed) * 60 // Convert to seconds

                        if timeUntilSecondHalf > 60 {
                            // More than 1 minute until second half, pause polling
                            let pauseSeconds = max(0, timeUntilSecondHalf - 30) // Resume 30 seconds before expected start
                            sleepInterval = UInt64(pauseSeconds) * 1_000_000_000

                            let minutes = pauseSeconds / 60
                            let seconds = pauseSeconds % 60

                            self.logger.info("⏸️ HALFTIME detected for fixture \(halftimeFixture.fixture.id)")
                            self.logger.info("  ⚽ Match: \(halftimeFixture.teams.home.name) \(halftimeFixture.goals.home ?? 0)-\(halftimeFixture.goals.away ?? 0) \(halftimeFixture.teams.away.name)")
                            self.logger.info("  ⏱️ Elapsed: \(elapsed)' | Extra time: \(extraTime - 45)'")
                            self.logger.info("  🕐 Expected 2nd half start: ~\(expectedSecondHalfMinutes)' mark")
                            self.logger.info("  💤 Pausing polling for \(minutes)m \(seconds)s (will resume 30s before expected start)")
                        } else if timeUntilSecondHalf > 0 {
                            // Less than 1 minute, keep active polling but log
                            sleepInterval = activePollingInterval
                            self.logger.info("⏰ HALFTIME ending soon for fixture \(halftimeFixture.fixture.id) - keeping active polling")
                        } else {
                            // Second half should have started, switch to active polling
                            sleepInterval = activePollingInterval
                            self.logger.info("🔄 Expected 2nd half time reached for fixture \(halftimeFixture.fixture.id) - resuming active polling")
                        }
                    }
                }

                try await Task.sleep(nanoseconds: sleepInterval)
            } catch {
                self.logger.error("Error in live stream: \(error)")
                try await Task.sleep(nanoseconds: activePollingInterval)
            }
        }
        return [:] // Return empty metadata for stream
        }
    }

    /// Helper method to get the timestamp of the next upcoming fixture
    /// Now uses database instead of API for efficient polling
    private func getNextUpcomingFixtureTimestamp(leagueId: Int, season: Int) async -> Int? {
        do {
            // Query database for next upcoming fixture timestamp
            logger.info("🔍 Querying for next fixture: leagueId=\(leagueId), season=\(season)")
            let timestamp = try await fixtureRepository.getNextUpcomingTimestamp(leagueId: leagueId, season: season)
            if let timestamp = timestamp {
                logger.info("✅ Found next fixture at timestamp: \(timestamp)")
            } else {
                logger.warning("⚠️ No upcoming fixture found for leagueId=\(leagueId), season=\(season)")
            }
            return timestamp
        } catch {
            logger.error("❌ Failed to fetch next fixture timestamp from database: \(error)")
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
        request: ServerRequest<Afcon_StandingsRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_StandingsResponse> {
        let req = request.message
        logger.info("gRPC: GetStandings - league=\(req.leagueID), season=\(req.season)")

        // Check if there are live matches to determine cache TTL
        let hasLive = try await fixtureRepository.hasLiveMatches(
            leagueId: Int(req.leagueID),
            season: Int(req.season)
        )

        let standingsData = try await cache.getOrFetchStandings(
            leagueID: Int(req.leagueID),
            season: Int(req.season),
            hasLiveMatches: hasLive
        ) {
            try await apiClient.getStandings(leagueId: Int(req.leagueID), season: Int(req.season))
        }

        var response = Afcon_StandingsResponse()
        // Convert standings data
        // Note: Implementation depends on API structure
        return ServerResponse(message: response)
    }

    /// Get team details
    public func getTeamDetails(
        request: ServerRequest<Afcon_TeamDetailsRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_TeamDetailsResponse> {
        let req = request.message
        logger.info("gRPC: GetTeamDetails - team=\(req.teamID)")

        let teamData = try await apiClient.getTeamDetails(teamId: Int(req.teamID))

        var response = Afcon_TeamDetailsResponse()
        response.team = convertToTeam(teamData.team)
        response.venue = convertToVenue(teamData.venue)
        return ServerResponse(message: response)
    }

    /// Get fixture lineups
    public func getLineups(
        request: ServerRequest<Afcon_LineupsRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_LineupsResponse> {
        let req = request.message
        logger.info("gRPC: GetLineups - fixture=\(req.fixtureID)")

        let lineupsData = try await apiClient.getFixtureLineups(fixtureId: Int(req.fixtureID))

        var response = Afcon_LineupsResponse()
        response.lineups = lineupsData.map { convertToFixtureLineup($0) }
        return ServerResponse(message: response)
    }

    /// Sync fixtures from API to database
    public func syncFixtures(
        request: ServerRequest<Afcon_SyncFixturesRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_SyncFixturesResponse> {
        let req = request.message
        logger.info("gRPC: SyncFixtures - league=\(req.leagueID), season=\(req.season), competition=\(req.competition)")

        var response = Afcon_SyncFixturesResponse()

        do {
            // Fetch all fixtures from API
            let fixturesData = try await apiClient.getFixtures(
                leagueId: Int(req.leagueID),
                season: Int(req.season)
            )

            // Upsert all fixtures into database
            try await fixtureRepository.upsertBatch(
                fixtures: fixturesData,
                leagueId: Int(req.leagueID),
                season: Int(req.season),
                competition: req.competition
            )

            response.success = true
            response.fixturesSynced = Int32(fixturesData.count)
            response.message = "Successfully synced \(fixturesData.count) fixtures to database"

            logger.info("✅ Synced \(fixturesData.count) fixtures for league \(req.leagueID), season \(req.season)")
        } catch {
            response.success = false
            response.fixturesSynced = 0
            response.message = "Failed to sync fixtures: \(error.localizedDescription)"

            logger.error("❌ Failed to sync fixtures: \(error)")
        }

        return ServerResponse(message: response)
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
        protoStatus.extra = Int32(status.extra ?? 0)
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

    // MARK: - Push Notification Management

    /// Register a device for push notifications
    public func registerDevice(
        request: ServerRequest<Afcon_RegisterDeviceRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_RegisterDeviceResponse> {
        let req = request.message
        logger.info("gRPC: RegisterDevice - user=\(req.userID), platform=\(req.platform)")

        let device = try await deviceRepository.registerDevice(
            userId: req.userID,
            deviceToken: req.deviceToken,
            platform: req.platform,
            deviceId: req.deviceID.isEmpty ? nil : req.deviceID,
            appVersion: req.appVersion.isEmpty ? nil : req.appVersion,
            osVersion: req.osVersion.isEmpty ? nil : req.osVersion,
            language: req.language.isEmpty ? "en" : req.language,
            timezone: req.timezone.isEmpty ? nil : req.timezone
        )

        var response = Afcon_RegisterDeviceResponse()
        response.success = true
        response.deviceUuid = device.id?.uuidString ?? ""
        response.message = "Device registered successfully"

        return ServerResponse(message: response)
    }

    /// Update device token (for token refresh)
    public func updateDeviceToken(
        request: ServerRequest<Afcon_UpdateDeviceTokenRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_UpdateDeviceTokenResponse> {
        let req = request.message
        logger.info("gRPC: UpdateDeviceToken - device=\(req.deviceUuid)")

        guard let deviceUUID = UUID(uuidString: req.deviceUuid) else {
            throw Abort(.badRequest, reason: "Invalid device UUID")
        }

        try await deviceRepository.updateDeviceToken(
            deviceUUID: deviceUUID,
            newToken: req.newDeviceToken
        )

        var response = Afcon_UpdateDeviceTokenResponse()
        response.success = true
        response.message = "Device token updated successfully"

        return ServerResponse(message: response)
    }

    /// Update notification subscriptions for a device
    public func updateSubscriptions(
        request: ServerRequest<Afcon_UpdateSubscriptionsRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_UpdateSubscriptionsResponse> {
        let req = request.message
        logger.info("gRPC: UpdateSubscriptions - device=\(req.deviceUuid), subscriptions=\(req.subscriptions.count)")

        guard let deviceUUID = UUID(uuidString: req.deviceUuid) else {
            throw Abort(.badRequest, reason: "Invalid device UUID")
        }

        // Convert proto subscriptions to repository format
        let subscriptions = req.subscriptions.map { sub -> (leagueId: Int, season: Int, teamId: Int?, preferences: (notifyGoals: Bool, notifyMatchStart: Bool, notifyMatchEnd: Bool, notifyRedCards: Bool, notifyLineups: Bool, notifyVar: Bool, matchStartMinutesBefore: Int)) in
            let leagueId = Int(sub.leagueID)
            let season = Int(sub.season)
            let teamId = sub.teamID == 0 ? nil : Int(sub.teamID)
            let prefs = (
                notifyGoals: sub.preferences.notifyGoals,
                notifyMatchStart: sub.preferences.notifyMatchStart,
                notifyMatchEnd: sub.preferences.notifyMatchEnd,
                notifyRedCards: sub.preferences.notifyRedCards,
                notifyLineups: sub.preferences.notifyLineups,
                notifyVar: sub.preferences.notifyVar,
                matchStartMinutesBefore: Int(sub.preferences.matchStartMinutesBefore)
            )
            return (leagueId: leagueId, season: season, teamId: teamId, preferences: prefs)
        }

        try await deviceRepository.updateSubscriptions(
            deviceUUID: deviceUUID,
            subscriptions: subscriptions
        )

        var response = Afcon_UpdateSubscriptionsResponse()
        response.success = true
        response.subscriptionsUpdated = Int32(subscriptions.count)
        response.message = "Subscriptions updated successfully"

        return ServerResponse(message: response)
    }

    /// Get notification subscriptions for a device
    public func getSubscriptions(
        request: ServerRequest<Afcon_GetSubscriptionsRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_GetSubscriptionsResponse> {
        let req = request.message
        logger.info("gRPC: GetSubscriptions - device=\(req.deviceUuid)")

        guard let deviceUUID = UUID(uuidString: req.deviceUuid) else {
            throw Abort(.badRequest, reason: "Invalid device UUID")
        }

        let subscriptions = try await deviceRepository.getSubscriptions(deviceUUID: deviceUUID)

        var response = Afcon_GetSubscriptionsResponse()
        response.subscriptions = subscriptions.map { sub in
            var protoSub = Afcon_Subscription()
            protoSub.leagueID = Int32(sub.leagueId)
            protoSub.season = Int32(sub.season)
            protoSub.teamID = Int32(sub.teamId ?? 0)

            var prefs = Afcon_NotificationPreferences()
            prefs.notifyGoals = sub.notifyGoals
            prefs.notifyMatchStart = sub.notifyMatchStart
            prefs.notifyMatchEnd = sub.notifyMatchEnd
            prefs.notifyRedCards = sub.notifyRedCards
            prefs.notifyLineups = sub.notifyLineups
            prefs.notifyVar = sub.notifyVar
            prefs.matchStartMinutesBefore = Int32(sub.matchStartMinutesBefore)

            protoSub.preferences = prefs
            return protoSub
        }

        return ServerResponse(message: response)
    }

    /// Unregister a device (mark as inactive)
    public func unregisterDevice(
        request: ServerRequest<Afcon_UnregisterDeviceRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_UnregisterDeviceResponse> {
        let req = request.message
        logger.info("gRPC: UnregisterDevice - device=\(req.deviceUuid)")

        guard let deviceUUID = UUID(uuidString: req.deviceUuid) else {
            throw Abort(.badRequest, reason: "Invalid device UUID")
        }

        try await deviceRepository.unregisterDevice(deviceUUID: deviceUUID)

        var response = Afcon_UnregisterDeviceResponse()
        response.success = true
        response.message = "Device unregistered successfully"

        return ServerResponse(message: response)
    }

    // MARK: - Live Activity Management

    /// Start a Live Activity for a fixture
    public func startLiveActivity(
        request: ServerRequest<Afcon_StartLiveActivityRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_StartLiveActivityResponse> {
        let req = request.message
        logger.info("gRPC: StartLiveActivity - fixture=\(req.fixtureID), device=\(req.deviceUuid)")

        guard let deviceUUID = UUID(uuidString: req.deviceUuid) else {
            var response = Afcon_StartLiveActivityResponse()
            response.success = false
            response.message = "Invalid device UUID"
            return ServerResponse(message: response)
        }

        guard let notificationService = notificationService else {
            var response = Afcon_StartLiveActivityResponse()
            response.success = false
            response.message = "Notification service not available"
            return ServerResponse(message: response)
        }

        do {
            let activity = try await notificationService.startLiveActivity(
                deviceUUID: deviceUUID,
                fixtureId: Int(req.fixtureID),
                activityId: req.activityID,
                pushToken: req.pushToken,
                updateFrequency: req.updateFrequency
            )

            var response = Afcon_StartLiveActivityResponse()
            response.success = true
            response.message = "Live Activity started successfully"
            response.activityUuid = activity.id?.uuidString ?? ""

            return ServerResponse(message: response)
        } catch {
            logger.error("Failed to start Live Activity: \(error)")

            var response = Afcon_StartLiveActivityResponse()
            response.success = false
            response.message = "Failed to start Live Activity: \(error.localizedDescription)"
            return ServerResponse(message: response)
        }
    }

    /// Update Live Activity preferences
    public func updateLiveActivity(
        request: ServerRequest<Afcon_UpdateLiveActivityRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_UpdateLiveActivityResponse> {
        let req = request.message
        logger.info("gRPC: UpdateLiveActivity - activity=\(req.activityUuid)")

        guard let activityUUID = UUID(uuidString: req.activityUuid) else {
            var response = Afcon_UpdateLiveActivityResponse()
            response.success = false
            response.message = "Invalid activity UUID"
            return ServerResponse(message: response)
        }

        guard let notificationService = notificationService else {
            var response = Afcon_UpdateLiveActivityResponse()
            response.success = false
            response.message = "Notification service not available"
            return ServerResponse(message: response)
        }

        do {
            try await notificationService.updateLiveActivityFrequency(
                activityUUID: activityUUID,
                updateFrequency: req.updateFrequency
            )

            var response = Afcon_UpdateLiveActivityResponse()
            response.success = true
            response.message = "Live Activity updated successfully"

            return ServerResponse(message: response)
        } catch {
            logger.error("Failed to update Live Activity: \(error)")

            var response = Afcon_UpdateLiveActivityResponse()
            response.success = false
            response.message = "Failed to update Live Activity: \(error.localizedDescription)"
            return ServerResponse(message: response)
        }
    }

    /// End a Live Activity
    public func endLiveActivity(
        request: ServerRequest<Afcon_EndLiveActivityRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_EndLiveActivityResponse> {
        let req = request.message
        logger.info("gRPC: EndLiveActivity - activity=\(req.activityUuid)")

        guard let activityUUID = UUID(uuidString: req.activityUuid) else {
            var response = Afcon_EndLiveActivityResponse()
            response.success = false
            response.message = "Invalid activity UUID"
            return ServerResponse(message: response)
        }

        guard let notificationService = notificationService else {
            var response = Afcon_EndLiveActivityResponse()
            response.success = false
            response.message = "Notification service not available"
            return ServerResponse(message: response)
        }

        do {
            try await notificationService.endLiveActivity(activityUUID: activityUUID)

            var response = Afcon_EndLiveActivityResponse()
            response.success = true
            response.message = "Live Activity ended successfully"

            return ServerResponse(message: response)
        } catch {
            logger.error("Failed to end Live Activity: \(error)")

            var response = Afcon_EndLiveActivityResponse()
            response.success = false
            response.message = "Failed to end Live Activity: \(error.localizedDescription)"
            return ServerResponse(message: response)
        }
    }

    /// Get active Live Activities for a device
    public func getActiveLiveActivities(
        request: ServerRequest<Afcon_GetActiveLiveActivitiesRequest>,
        context: ServerContext
    ) async throws -> ServerResponse<Afcon_GetActiveLiveActivitiesResponse> {
        let req = request.message
        logger.info("gRPC: GetActiveLiveActivities - device=\(req.deviceUuid)")

        guard let deviceUUID = UUID(uuidString: req.deviceUuid) else {
            var response = Afcon_GetActiveLiveActivitiesResponse()
            return ServerResponse(message: response)
        }

        guard let notificationService = notificationService else {
            var response = Afcon_GetActiveLiveActivitiesResponse()
            return ServerResponse(message: response)
        }

        do {
            let activities = try await notificationService.getActiveLiveActivities(deviceUUID: deviceUUID)

            var response = Afcon_GetActiveLiveActivitiesResponse()
            response.activities = activities.map { activity in
                var info = Afcon_LiveActivityInfo()
                info.activityUuid = activity.id?.uuidString ?? ""
                info.fixtureID = Int32(activity.fixtureId)
                info.activityID = activity.activityId
                info.updateFrequency = activity.updateFrequency
                info.startedAt = Google_Protobuf_Timestamp(date: activity.startedAt)
                if let expiresAt = activity.expiresAt {
                    info.expiresAt = Google_Protobuf_Timestamp(date: expiresAt)
                }

                return info
            }

            return ServerResponse(message: response)
        } catch {
            logger.error("Failed to get active Live Activities: \(error)")

            var response = Afcon_GetActiveLiveActivitiesResponse()
            return ServerResponse(message: response)
        }
    }
}
