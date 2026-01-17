import Foundation
import Vapor
import Synchronization
import SwiftProtobuf

/// Centralized live match broadcaster that polls once and fans out to all subscribers
/// Scales to 10k+ concurrent clients by avoiding N*API calls
public final class LiveMatchBroadcaster: Sendable {
    private let apiClient: APIFootballClient
    private let fixtureRepository: FixtureRepository
    private let notificationService: NotificationService?
    private let logger: Logger

    // Thread-safe subscriber storage
    private let subscribersLock = Mutex<[Int: [UUID: SubscriberInfo]]>([:])

    // Single polling task per league
    private let pollingTasksLock = Mutex<[Int: Task<Void, Never>]>([:])

    // Track previous state for change detection
    private let fixtureStateLock = Mutex<[Int: [Int: FixtureState]]>([:])

    public init(
        apiClient: APIFootballClient,
        fixtureRepository: FixtureRepository,
        notificationService: NotificationService?,
        logger: Logger
    ) {
        self.apiClient = apiClient
        self.fixtureRepository = fixtureRepository
        self.notificationService = notificationService
        self.logger = logger
    }

    // MARK: - Public API

    /// Subscribe to live match updates for a specific league
    /// Returns an AsyncStream that will receive updates
    public func subscribe(leagueID: Int, season: Int) -> AsyncStream<Afcon_LiveMatchUpdate> {
        let subscriberID = UUID()

        return AsyncStream { continuation in
            let subscriber = SubscriberInfo(
                id: subscriberID,
                leagueID: leagueID,
                season: season,
                continuation: continuation
            )

            // Add subscriber
            subscribersLock.withLock { subs in
                subs[leagueID, default: [:]][subscriberID] = subscriber
            }

            logger.info("📱 Client subscribed to league \(leagueID) (ID: \(subscriberID)). Total subscribers: \(getSubscriberCount())")

            // Start polling for this league if not already running
            startPollingIfNeeded(leagueID: leagueID, season: season)

            // Send initial state to newly connected client
            Task { [weak self] in
                await self?.sendInitialState(to: continuation, leagueID: leagueID, season: season)
            }

            // Handle client disconnect
            continuation.onTermination = { [weak self] _ in
                self?.unsubscribe(subscriberID: subscriberID, leagueID: leagueID)
            }
        }
    }

    /// Get total number of active subscribers across all leagues
    public func getSubscriberCount() -> Int {
        subscribersLock.withLock { subs in
            subs.values.reduce(0) { $0 + $1.count }
        }
    }

    /// Get subscriber count for a specific league
    public func getSubscriberCount(for leagueID: Int) -> Int {
        subscribersLock.withLock { subs in
            subs[leagueID]?.count ?? 0
        }
    }

    /// Start polling even without active gRPC subscribers (for notification delivery).
    public func startNotificationPolling(leagueID: Int, season: Int) {
        startPollingIfNeeded(leagueID: leagueID, season: season)
    }

    // MARK: - Private Implementation

    private func unsubscribe(subscriberID: UUID, leagueID: Int) {
        subscribersLock.withLock { subs in
            subs[leagueID]?.removeValue(forKey: subscriberID)

            // Clean up empty league entries
            if subs[leagueID]?.isEmpty == true {
                subs.removeValue(forKey: leagueID)
            }
        }

        let remaining = getSubscriberCount(for: leagueID)
        logger.info("📱 Client unsubscribed from league \(leagueID) (ID: \(subscriberID)). Remaining: \(remaining)")

        // Stop polling if no more subscribers
        if remaining == 0 {
            stopPolling(leagueID: leagueID)
        }
    }

    /// Send initial state to a newly connected client
    /// This ensures clients receive current game state when reconnecting
    private func sendInitialState(
        to continuation: AsyncStream<Afcon_LiveMatchUpdate>.Continuation,
        leagueID: Int,
        season: Int
    ) async {
        do {
            // Fetch today's fixtures from database
            let todayFixtures = try await fixtureRepository.getFixturesForDate(
                leagueId: leagueID,
                season: season,
                date: Date()
            )

            guard !todayFixtures.isEmpty else {
                logger.debug("📭 No fixtures today for league \(leagueID) - no initial state to send")
                return
            }

            logger.info("📤 Sending initial state: \(todayFixtures.count) fixture(s) for league \(leagueID)")

            // Send each fixture as an update
            for fixtureEntity in todayFixtures {
                // Determine event type based on status
                let eventType: String
                let statusShort = fixtureEntity.statusShort

                if statusShort == "FT" || statusShort == "AET" || statusShort == "PEN" {
                    eventType = "match_finished"
                } else if statusShort == "1H" || statusShort == "2H" || statusShort == "HT" ||
                          statusShort == "ET" || statusShort == "BT" || statusShort == "P" {
                    eventType = "match_live"
                } else if statusShort == "NS" || statusShort == "TBD" {
                    eventType = "match_scheduled"
                } else {
                    eventType = "status_update"
                }

                // Convert entity to update
                var update = Afcon_LiveMatchUpdate()
                update.fixtureID = Int32(fixtureEntity.apiFixtureId)
                update.timestamp = Google_Protobuf_Timestamp(date: Date())
                update.eventType = eventType

                // Convert fixture entity to proto fixture
                update.fixture = convertFixtureEntityToFixture(fixtureEntity)

                // Add status
                var status = Afcon_FixtureStatus()
                status.long = fixtureEntity.statusLong
                status.short = fixtureEntity.statusShort
                status.elapsed = Int32(fixtureEntity.statusElapsed ?? 0)
                update.status = status

                // Try to fetch and include events for live/finished matches
                if statusShort != "NS" && statusShort != "TBD" {
                    do {
                        let events = try await apiClient.getFixtureEvents(fixtureId: fixtureEntity.apiFixtureId)
                        update.recentEvents = events
                            .sorted { (event1, event2) -> Bool in
                                let time1 = (event1.time?.elapsed ?? 0) + (event1.time?.extra ?? 0)
                                let time2 = (event2.time?.elapsed ?? 0) + (event2.time?.extra ?? 0)
                                return time1 < time2
                            }
                            .map { convertToFixtureEvent($0) }

                        if let latestEvent = events.last {
                            update.event = convertToFixtureEvent(latestEvent)
                        }
                    } catch {
                        logger.debug("⚠️ Could not fetch events for fixture \(fixtureEntity.apiFixtureId): \(error)")
                    }
                }

                // Send to client
                continuation.yield(update)

                logger.debug("  ✓ Sent \(eventType): \(fixtureEntity.homeTeamName) vs \(fixtureEntity.awayTeamName) (\(statusShort))")
            }

            logger.info("✅ Initial state sent to client for league \(leagueID)")

        } catch {
            logger.error("❌ Failed to send initial state for league \(leagueID): \(error)")
        }
    }

    private func startPollingIfNeeded(leagueID: Int, season: Int) {
        pollingTasksLock.withLock { tasks in
            guard tasks[leagueID] == nil else {
                logger.debug("⏭️ Polling already running for league \(leagueID)")
                return
            }

            logger.info("🚀 Starting polling task for league \(leagueID), season \(season)")

            let task: Task<Void, Never> = Task.detached(priority: .high) { [weak self] in
                await self?.pollLoop(leagueID: leagueID, season: season)
                return ()
            }

            tasks[leagueID] = task
        }
    }

    private func stopPolling(leagueID: Int) {
        pollingTasksLock.withLock { tasks in
            if let task = tasks[leagueID] {
                logger.info("🛑 Stopping polling task for league \(leagueID)")
                task.cancel()
                tasks.removeValue(forKey: leagueID)
            }
        }

        // Clean up state
        _ = fixtureStateLock.withLock { state in
            state.removeValue(forKey: leagueID)
        }
    }

    /// Main polling loop - runs once per league
    private func pollLoop(leagueID: Int, season: Int) async {
        logger.info("🔄 Poll loop started for league \(leagueID)")

        let activePollingInterval: UInt64 = 15_000_000_000 // 15 seconds
        var lastNoLiveCheckTime: Date?
        var nextFixtureTimestamp: Int?

        while !Task.isCancelled {
            do {
                // Check if we still have subscribers
                let subscriberCount = getSubscriberCount(for: leagueID)
                if subscriberCount == 0 {
                    let hasNotificationSubscribers: Bool
                    if let notificationService = notificationService {
                        hasNotificationSubscribers = (try? await notificationService.hasNotificationSubscribers(
                            leagueId: leagueID,
                            season: season
                        )) ?? false
                    } else {
                        hasNotificationSubscribers = false
                    }

                    guard hasNotificationSubscribers else {
                        logger.info("⏹️ No subscribers left for league \(leagueID), stopping poll loop")
                        break
                    }

                    logger.debug("🔔 Polling league \(leagueID) for notification subscribers (no gRPC clients)")
                }

                let hasUnfinishedToday = await hasUnfinishedFixturesToday(
                    leagueId: leagueID,
                    season: season
                )

                if hasUnfinishedToday {
                    // SINGLE API call for ALL subscribers
                    let liveFixtures = try await apiClient.getLiveFixtures(leagueId: leagueID)

                    logger.info("📊 Polled league \(leagueID): \(liveFixtures.count) live fixture(s), \(subscriberCount) subscriber(s)")

                    // Process fixtures and broadcast to all subscribers
                    await processAndBroadcast(
                        fixtures: liveFixtures,
                        leagueID: leagueID,
                        season: season
                    )

                    try await Task.sleep(nanoseconds: activePollingInterval)
                    continue
                }

                // No unfinished fixtures today; clear state to avoid stale updates
                fixtureStateLock.withLock { state in
                    state.removeValue(forKey: leagueID)
                }

                let currentTime = Date()

                // Check for next fixture every 5 minutes
                if lastNoLiveCheckTime == nil || currentTime.timeIntervalSince(lastNoLiveCheckTime!) > 300 {
                    lastNoLiveCheckTime = currentTime
                    nextFixtureTimestamp = await getNextUpcomingFixtureTimestamp(
                        leagueId: leagueID,
                        season: season
                    )
                }

                // Adjust sleep based on time until next fixture
                let sleepInterval: UInt64
                if let timestamp = nextFixtureTimestamp {
                    sleepInterval = calculateSleepInterval(
                        nextTimestamp: timestamp,
                        activeInterval: activePollingInterval
                    )
                } else {
                    // No upcoming fixtures, sleep for 24 hours
                    sleepInterval = 24 * 60 * 60 * 1_000_000_000
                    logger.info("⏸️ No upcoming fixtures for league \(leagueID). Pausing for 24 hours...")
                }

                try await Task.sleep(nanoseconds: sleepInterval)

            } catch is CancellationError {
                logger.info("🛑 Poll loop cancelled for league \(leagueID)")
                break
            } catch {
                logger.error("❌ Polling error for league \(leagueID): \(error)")
                try? await Task.sleep(nanoseconds: activePollingInterval)
            }
        }

        logger.info("✅ Poll loop ended for league \(leagueID)")
    }

    /// Process fixtures and broadcast updates to all subscribers
    private func processAndBroadcast(
        fixtures: [FixtureData],
        leagueID: Int,
        season: Int
    ) async {
        // Get previous state
        let previousState = fixtureStateLock.withLock { state in
            state[leagueID] ?? [:]
        }

        var newState: [Int: FixtureState] = [:]
        var updates: [Afcon_LiveMatchUpdate] = []

        // Process each live fixture
        for fixture in fixtures {
            let fixtureID = fixture.fixture.id

            // Fetch current events
            let currentEvents = (try? await apiClient.getFixtureEvents(fixtureId: fixtureID)) ?? []

            // Create current state
            let currentState = FixtureState(
                fixture: fixture,
                events: currentEvents
            )
            newState[fixtureID] = currentState

            // Check for changes
            if let previous = previousState[fixtureID] {
                if hasSignificantChanges(previous: previous, current: currentState) {
                    let update = createUpdate(
                        fixtureID: fixtureID,
                        current: currentState,
                        previous: previous,
                        eventType: detectEventType(previous: previous, current: currentState)
                    )
                    updates.append(update)

                    // Log significant events
                    logSignificantEvents(
                        previous: previous,
                        current: currentState,
                        leagueID: leagueID,
                        season: season
                    )
                }
            } else {
                // New live match
                let update = createUpdate(
                    fixtureID: fixtureID,
                    current: currentState,
                    previous: nil,
                    eventType: "match_started"
                )
                updates.append(update)

                logger.info("🆕 New live match: \(fixture.teams.home.name) vs \(fixture.teams.away.name)")

                // Send match start notification
                Task {
                    let kickoffDate = ISO8601DateFormatter().date(from: fixture.fixture.date) ?? Date()
                    try? await notificationService?.sendMatchStartNotification(
                        fixtureId: fixture.fixture.id,
                        homeTeam: fixture.teams.home.name,
                        awayTeam: fixture.teams.away.name,
                        kickoffTime: kickoffDate,
                        leagueId: leagueID,
                        season: season
                    )
                }
            }

            // Save to database
            try? await fixtureRepository.upsert(
                from: fixture,
                leagueId: leagueID,
                season: season,
                competition: fixture.league.name
            )
        }

        // Check for finished matches
        let currentLiveIDs = Set(fixtures.map { $0.fixture.id })
        for (fixtureID, previousFixtureState) in previousState {
            if !currentLiveIDs.contains(fixtureID) {
                // Match finished
                let finalFixture = (try? await apiClient.getFixtureById(fixtureId: fixtureID)) ?? previousFixtureState.fixture

                let finalState = FixtureState(
                    fixture: finalFixture,
                    events: previousFixtureState.events
                )

                let update = createUpdate(
                    fixtureID: fixtureID,
                    current: finalState,
                    previous: previousFixtureState,
                    eventType: "match_finished"
                )
                updates.append(update)

                logger.info("🏁 Match finished: \(finalFixture.teams.home.name) \(finalFixture.goals.home ?? 0)-\(finalFixture.goals.away ?? 0) \(finalFixture.teams.away.name)")

                // Send match end notification
                Task {
                    try? await notificationService?.sendMatchEndNotification(
                        fixtureId: fixtureID,
                        homeTeam: finalFixture.teams.home.name,
                        awayTeam: finalFixture.teams.away.name,
                        homeScore: finalFixture.goals.home ?? 0,
                        awayScore: finalFixture.goals.away ?? 0,
                        leagueId: leagueID,
                        season: season
                    )
                }

                // Save final state
                try? await fixtureRepository.upsert(
                    from: finalFixture,
                    leagueId: leagueID,
                    season: season,
                    competition: finalFixture.league.name
                )
            }
        }

        // Update state
        fixtureStateLock.withLock { state in
            state[leagueID] = newState
        }

        // Broadcast to all subscribers
        if !updates.isEmpty {
            await broadcast(updates: updates, to: leagueID)
        }
    }

    /// Broadcast updates to all subscribers for a league
    private func broadcast(updates: [Afcon_LiveMatchUpdate], to leagueID: Int) async {
        let subscribers = subscribersLock.withLock { subs in
            Array(subs[leagueID]?.values ?? [:].values)
        }

        guard !subscribers.isEmpty else { return }

        logger.info("📢 Broadcasting \(updates.count) update(s) to \(subscribers.count) subscriber(s)")

        for update in updates {
            for subscriber in subscribers {
                subscriber.continuation.yield(update)
            }
        }
    }

    /// Create a LiveMatchUpdate message
    private func createUpdate(
        fixtureID: Int,
        current: FixtureState,
        previous: FixtureState?,
        eventType: String
    ) -> Afcon_LiveMatchUpdate {
        var update = Afcon_LiveMatchUpdate()
        update.fixtureID = Int32(fixtureID)
        update.timestamp = Google_Protobuf_Timestamp(date: Date())
        update.eventType = eventType
        update.fixture = convertToFixture(current.fixture)
        update.status = convertToFixtureStatus(current.fixture.fixture.status)

        // Add recent events
        update.recentEvents = getRecentEvents(
            events: current.events,
            currentElapsed: current.fixture.fixture.status.elapsed ?? 0
        )

        // Attach latest new event if any
        if let previous = previous {
            let newEvents = current.events.filter { currentEvent in
                !previous.events.contains { prevEvent in
                    eventsAreEqual(currentEvent, prevEvent)
                }
            }
            if let latestEvent = newEvents.last {
                update.event = convertToFixtureEvent(latestEvent)
            }
        }

        return update
    }

    // MARK: - Helper Methods

    private func hasSignificantChanges(previous: FixtureState, current: FixtureState) -> Bool {
        let hasNewEvents = current.events.count != previous.events.count ||
            current.events.contains { currentEvent in
                !previous.events.contains { prevEvent in
                    eventsAreEqual(currentEvent, prevEvent)
                }
            }

        let isLive = current.fixture.fixture.status.short == "1H" ||
                     current.fixture.fixture.status.short == "2H"
        let elapsedDifference = (current.fixture.fixture.status.elapsed ?? 0) -
                                (previous.fixture.fixture.status.elapsed ?? 0)

        return previous.fixture.goals.home != current.fixture.goals.home ||
               previous.fixture.goals.away != current.fixture.goals.away ||
               previous.fixture.fixture.status.short != current.fixture.fixture.status.short ||
               hasNewEvents ||
               (isLive && elapsedDifference >= 1)
    }

    private func detectEventType(previous: FixtureState, current: FixtureState) -> String {
        let newEvents = current.events.filter { currentEvent in
            !previous.events.contains { prevEvent in
                eventsAreEqual(currentEvent, prevEvent)
            }
        }

        if let latestEvent = newEvents.last {
            let eventType = latestEvent.type?.lowercased() ?? ""
            let eventDetail = latestEvent.detail?.lowercased() ?? ""

            if eventType == "goal" {
                return eventDetail.contains("missed") ? "missed_penalty" : "goal"
            }
            if eventType == "card" {
                if eventDetail.contains("red") || eventDetail.contains("second yellow") {
                    return "red_card"
                }
                if eventDetail.contains("yellow") {
                    return "yellow_card"
                }
                return "card"
            }
            if eventType == "subst" { return "substitution" }
            if eventType == "var" { return "var" }
        }

        if previous.fixture.goals.home != current.fixture.goals.home ||
           previous.fixture.goals.away != current.fixture.goals.away {
            return "goal"
        }
        if previous.fixture.fixture.status.short != current.fixture.fixture.status.short {
            return "status_update"
        }

        return "time_update"
    }

    private func logSignificantEvents(
        previous: FixtureState,
        current: FixtureState,
        leagueID: Int,
        season: Int
    ) {
        let newEvents = current.events.filter { currentEvent in
            !previous.events.contains { prevEvent in
                eventsAreEqual(currentEvent, prevEvent)
            }
        }

        // Check for status changes (second half, overtime, penalties)
        let previousStatus = previous.fixture.fixture.status.short
        let currentStatus = current.fixture.fixture.status.short

        if previousStatus != currentStatus {
            // Second half start
            if previousStatus == "HT" && currentStatus == "2H" {
                logger.info("⚽ SECOND HALF - \(current.fixture.teams.home.name) vs \(current.fixture.teams.away.name)")
                Task {
                    try? await notificationService?.sendSecondHalfStartNotification(
                        fixtureId: current.fixture.fixture.id,
                        homeTeam: current.fixture.teams.home.name,
                        awayTeam: current.fixture.teams.away.name,
                        homeScore: current.fixture.goals.home ?? 0,
                        awayScore: current.fixture.goals.away ?? 0,
                        leagueId: leagueID,
                        season: season
                    )
                }
            }

            // Extra time/overtime start
            if currentStatus == "ET" {
                logger.info("⏱️ EXTRA TIME - \(current.fixture.teams.home.name) vs \(current.fixture.teams.away.name)")
                Task {
                    try? await notificationService?.sendOvertimeStartNotification(
                        fixtureId: current.fixture.fixture.id,
                        homeTeam: current.fixture.teams.home.name,
                        awayTeam: current.fixture.teams.away.name,
                        homeScore: current.fixture.goals.home ?? 0,
                        awayScore: current.fixture.goals.away ?? 0,
                        leagueId: leagueID,
                        season: season
                    )
                }
            }

            // Penalty shootout start
            if currentStatus == "P" {
                logger.info("🎯 PENALTIES - \(current.fixture.teams.home.name) vs \(current.fixture.teams.away.name)")
                Task {
                    try? await notificationService?.sendPenaltiesStartNotification(
                        fixtureId: current.fixture.fixture.id,
                        homeTeam: current.fixture.teams.home.name,
                        awayTeam: current.fixture.teams.away.name,
                        homeScore: current.fixture.goals.home ?? 0,
                        awayScore: current.fixture.goals.away ?? 0,
                        leagueId: leagueID,
                        season: season
                    )
                }
            }
        }

        for newEvent in newEvents {
            let eventType = newEvent.type?.lowercased() ?? "unknown"
            let elapsed = newEvent.time?.elapsed ?? 0
            let playerName = newEvent.player?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let teamName = newEvent.team?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = newEvent.detail?.lowercased() ?? ""

            if eventType == "goal" {
                guard let playerName, !playerName.isEmpty, playerName.lowercased() != "unknown",
                      let teamName, !teamName.isEmpty, teamName.lowercased() != "unknown" else {
                    logger.debug("⏭️ Skipping goal notification with incomplete data (fixture \(current.fixture.fixture.id))")
                    continue
                }

                let isMissedPenalty = detail.contains("miss") && detail.contains("pen")
                if isMissedPenalty {
                    logger.info("❌ MISSED PENALTY - \(teamName) | \(elapsed)' \(playerName) | League \(leagueID)")

                    Task {
                        try? await notificationService?.sendMissedPenaltyNotification(
                            fixtureId: current.fixture.fixture.id,
                            homeTeam: current.fixture.teams.home.name,
                            awayTeam: current.fixture.teams.away.name,
                            homeGoals: current.fixture.goals.home ?? 0,
                            awayGoals: current.fixture.goals.away ?? 0,
                            playerName: playerName,
                            minute: elapsed,
                            leagueId: leagueID,
                            season: season
                        )
                    }
                    continue
                }

                logger.info("⚽️ GOAL - \(teamName) | \(elapsed)' \(playerName) | League \(leagueID)")

                // Send notification
                Task {
                    try? await notificationService?.sendGoalNotification(
                        fixtureId: current.fixture.fixture.id,
                        homeTeam: current.fixture.teams.home.name,
                        awayTeam: current.fixture.teams.away.name,
                        homeGoals: current.fixture.goals.home ?? 0,
                        awayGoals: current.fixture.goals.away ?? 0,
                        scorer: playerName,
                        assist: newEvent.assist?.name,
                        minute: elapsed,
                        leagueId: leagueID,
                        season: season
                    )
                }
            } else if eventType == "card" {
                let cardEmoji = detail.contains("red") ? "🟥" : "🟨"
                if let teamName, !teamName.isEmpty, teamName.lowercased() != "unknown",
                   let playerName, !playerName.isEmpty, playerName.lowercased() != "unknown" {
                    logger.info("\(cardEmoji) CARD - \(teamName) | \(elapsed)' \(playerName)")
                } else {
                    logger.debug("⏭️ Skipping card notification with incomplete data (fixture \(current.fixture.fixture.id))")
                }

                if detail.contains("red") {
                    Task {
                        if let teamName, !teamName.isEmpty, teamName.lowercased() != "unknown",
                           let playerName, !playerName.isEmpty, playerName.lowercased() != "unknown" {
                            try? await notificationService?.sendRedCardNotification(
                                fixtureId: current.fixture.fixture.id,
                                homeTeam: current.fixture.teams.home.name,
                                awayTeam: current.fixture.teams.away.name,
                                playerName: playerName,
                                teamName: teamName,
                                minute: elapsed,
                                leagueId: leagueID,
                                season: season
                            )
                        }
                    }
                }
            }
        }
    }

    private func getNextUpcomingFixtureTimestamp(leagueId: Int, season: Int) async -> Int? {
        do {
            logger.info("🔍 Querying for next fixture: leagueId=\(leagueId), season=\(season)")
            let timestamp = try await fixtureRepository.getNextUpcomingTimestamp(leagueId: leagueId, season: season)
            if let timestamp = timestamp {
                logger.info("✅ Found next fixture at timestamp: \(timestamp)")
            } else {
                logger.warning("⚠️ No upcoming fixture found for leagueId=\(leagueId), season=\(season)")
            }
            return timestamp
        } catch {
            logger.error("❌ Failed to fetch next fixture timestamp: \(error)")
            return nil
        }
    }

    private func hasUnfinishedFixturesToday(leagueId: Int, season: Int) async -> Bool {
        do {
            let todayFixtures = try await fixtureRepository.getFixturesForDate(
                leagueId: leagueId,
                season: season,
                date: Date()
            )

            if todayFixtures.isEmpty {
                logger.info("📅 No fixtures today for league \(leagueId)")
                return false
            }

            let finishedStatuses: Set<String> = ["FT", "AET", "PEN", "ABD", "AWD", "WO", "CANC"]
            let unfinishedCount = todayFixtures.filter { !finishedStatuses.contains($0.statusShort) }.count
            logger.info("📅 Today's fixtures for league \(leagueId): \(todayFixtures.count) total, \(unfinishedCount) unfinished")
            return unfinishedCount > 0
        } catch {
            logger.error("❌ Failed to check today's fixtures for league \(leagueId): \(error)")
            return false
        }
    }

    private func calculateSleepInterval(nextTimestamp: Int, activeInterval: UInt64) -> UInt64 {
        let now = Date()
        let nextFixtureDate = Date(timeIntervalSince1970: TimeInterval(nextTimestamp))
        let timeUntilMatch = nextFixtureDate.timeIntervalSince(now)

        let days = Int(timeUntilMatch / 86400)
        let hours = Int(timeUntilMatch / 3600)
        let minutes = Int(timeUntilMatch / 60)

        if timeUntilMatch > 86400 {
            // More than 1 day away
            logger.info("⏸️ Next fixture in \(days) day(s). Pausing for 12 hours...")
            return 12 * 60 * 60 * 1_000_000_000
        } else if timeUntilMatch > 21600 {
            // 6-24 hours away
            logger.info("⏸️ Next fixture in \(hours) hours. Pausing for 3 hours...")
            return 3 * 60 * 60 * 1_000_000_000
        } else if timeUntilMatch > 3600 {
            // 1-6 hours away
            logger.info("⏸️ Next fixture in \(hours) hour(s). Pausing for 30 minutes...")
            return 30 * 60 * 1_000_000_000
        } else if timeUntilMatch > 600 {
            // 10 minutes - 1 hour
            logger.info("⏸️ Next fixture in \(minutes) minutes. Pausing for 5 minutes...")
            return 5 * 60 * 1_000_000_000
        } else if timeUntilMatch > 0 {
            // Less than 10 minutes
            logger.info("⏰ Next fixture in \(minutes) minute(s). Active polling...")
            return activeInterval
        }

        return activeInterval
    }

    private func eventsAreEqual(_ event1: FixtureEvent, _ event2: FixtureEvent) -> Bool {
        return event1.time?.elapsed == event2.time?.elapsed &&
               event1.time?.extra == event2.time?.extra &&
               event1.type == event2.type &&
               event1.detail == event2.detail &&
               event1.player?.id == event2.player?.id
    }

    private func getRecentEvents(events: [FixtureEvent], currentElapsed: Int) -> [Afcon_FixtureEvent] {
        return events
            .sorted { (event1, event2) -> Bool in
                let time1 = (event1.time?.elapsed ?? 0) + (event1.time?.extra ?? 0)
                let time2 = (event2.time?.elapsed ?? 0) + (event2.time?.extra ?? 0)
                return time1 < time2
            }
            .map { convertToFixtureEvent($0) }
    }

    // MARK: - Conversion Methods (copied from AFCONServiceProvider)

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
        status.extra = Int32(data.fixture.status.extra ?? 0)
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

        var extratime = Afcon_ScoreDetail()
        extratime.home = Int32(data.score.extratime.home ?? 0)
        extratime.away = Int32(data.score.extratime.away ?? 0)
        score.extratime = extratime

        var penalty = Afcon_ScoreDetail()
        penalty.home = Int32(data.score.penalty.home ?? 0)
        penalty.away = Int32(data.score.penalty.away ?? 0)
        score.penalty = penalty

        fixture.score = score

        return fixture
    }

    private func convertToFixtureStatus(_ status: FixtureStatusInfo) -> Afcon_FixtureStatus {
        var protoStatus = Afcon_FixtureStatus()
        protoStatus.long = status.long
        protoStatus.short = status.short
        protoStatus.elapsed = Int32(status.elapsed ?? 0)
        protoStatus.extra = Int32(status.extra ?? 0)
        return protoStatus
    }

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

    /// Convert FixtureEntity (database) to Afcon_Fixture (protobuf)
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
        status.extra = Int32(entity.statusExtra ?? 0)
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

        var extratime = Afcon_ScoreDetail()
        extratime.home = Int32(entity.extratimeHome ?? 0)
        extratime.away = Int32(entity.extratimeAway ?? 0)
        score.extratime = extratime

        var penalty = Afcon_ScoreDetail()
        penalty.home = Int32(entity.penaltyHome ?? 0)
        penalty.away = Int32(entity.penaltyAway ?? 0)
        score.penalty = penalty

        fixture.score = score

        return fixture
    }
}

// MARK: - Supporting Types

/// Information about a subscriber
private struct SubscriberInfo: Sendable {
    let id: UUID
    let leagueID: Int
    let season: Int
    let continuation: AsyncStream<Afcon_LiveMatchUpdate>.Continuation
}

/// State snapshot of a fixture at a point in time
private struct FixtureState: Sendable {
    let fixture: FixtureData
    let events: [FixtureEvent]
}
