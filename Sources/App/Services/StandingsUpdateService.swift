import Foundation
import Vapor
import Synchronization

/// Service that manages standings updates with smart scheduling
/// - Polls every hour while games are in progress
/// - Makes a final update 1h 5min after the last game of the day finishes
public final class StandingsUpdateService: Sendable {
    private let apiClient: APIFootballClient
    private let fixtureRepository: FixtureRepository
    private let cacheService: CacheService
    private let logger: Logger

    // Track active polling tasks per league
    private let pollingTasksLock = Mutex<[Int: Task<Void, Never>]>([:])

    // Track last standings update time
    private let lastUpdateLock = Mutex<[Int: Date]>([:])

    public init(
        apiClient: APIFootballClient,
        fixtureRepository: FixtureRepository,
        cacheService: CacheService,
        logger: Logger
    ) {
        self.apiClient = apiClient
        self.fixtureRepository = fixtureRepository
        self.cacheService = cacheService
        self.logger = logger
    }

    // MARK: - Public API

    /// Start standings updates for a league and season
    /// This will automatically manage the update schedule based on fixture status
    public func startUpdates(leagueID: Int, season: Int) {
        pollingTasksLock.withLock { tasks in
            guard tasks[leagueID] == nil else {
                logger.debug("⏭️ Standings updates already running for league \(leagueID)")
                return
            }

            logger.info("🏆 Starting standings updates for league \(leagueID), season \(season)")

            let task: Task<Void, Never> = Task.detached(priority: .medium) { [weak self] in
                await self?.updateLoop(leagueID: leagueID, season: season)
                return ()
            }

            tasks[leagueID] = task
        }
    }

    /// Stop standings updates for a league
    public func stopUpdates(leagueID: Int) {
        pollingTasksLock.withLock { tasks in
            if let task = tasks[leagueID] {
                logger.info("🛑 Stopping standings updates for league \(leagueID)")
                task.cancel()
                tasks.removeValue(forKey: leagueID)
            }
        }

        lastUpdateLock.withLock { updates in
            updates.removeValue(forKey: leagueID)
        }
    }

    /// Manually trigger a standings update
    public func updateStandingsNow(leagueID: Int, season: Int) async throws {
        try await fetchAndCacheStandings(leagueID: leagueID, season: season)
    }

    // MARK: - Private Implementation

    /// Main update loop
    private func updateLoop(leagueID: Int, season: Int) async {
        logger.info("🔄 Standings update loop started for league \(leagueID)")

        let hourlyInterval: UInt64 = 60 * 60 * 1_000_000_000 // 1 hour
        let finalUpdateDelay: UInt64 = 65 * 60 * 1_000_000_000 // 1h 5min

        while !Task.isCancelled {
            do {
                // Check if there are games today
                let todayFixtures = try await fixtureRepository.getFixturesForDate(
                    leagueId: leagueID,
                    season: season,
                    date: Date()
                )

                if todayFixtures.isEmpty {
                    // No games today, check tomorrow
                    logger.info("📅 No fixtures today for league \(leagueID), checking next day...")

                    // Sleep until next day
                    let now = Date()
                    let tomorrow = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
                    let sleepDuration = UInt64(tomorrow.timeIntervalSince(now) * 1_000_000_000)

                    try await Task.sleep(nanoseconds: sleepDuration)
                    continue
                }

                // Determine game status
                let finishedStatuses: Set<String> = ["FT", "AET", "PEN", "ABD", "AWD", "WO", "CANC"]
                let unfinishedFixtures = todayFixtures.filter { !finishedStatuses.contains($0.statusShort) }

                if !unfinishedFixtures.isEmpty {
                    // Games are in progress or upcoming
                    logger.info("⚽️ \(unfinishedFixtures.count) unfinished fixture(s) today for league \(leagueID)")

                    // Update standings every hour while games are in progress
                    try await fetchAndCacheStandings(leagueID: leagueID, season: season)

                    // Sleep for 1 hour
                    try await Task.sleep(nanoseconds: hourlyInterval)
                } else {
                    // All games finished today
                    logger.info("🏁 All fixtures finished for today in league \(leagueID)")

                    // Get the timestamp of the last finished game
                    if let lastGameTimestamp = getLastGameEndTime(fixtures: todayFixtures) {
                        let now = Date()

                        // Define update times after last game: 10min, 20min, 30min, 1h 5min
                        let updateIntervals: [Int] = [10, 20, 30, 65] // in minutes

                        for interval in updateIntervals {
                            let updateTime = lastGameTimestamp.addingTimeInterval(TimeInterval(interval * 60))

                            if now < updateTime {
                                // Wait until this update time
                                let waitTime = updateTime.timeIntervalSince(now)
                                let waitNanos = UInt64(waitTime * 1_000_000_000)

                                let minutes = Int(waitTime / 60)
                                let seconds = Int(waitTime.truncatingRemainder(dividingBy: 60))
                                logger.info("⏰ Waiting \(minutes)m \(seconds)s before \(interval)-minute post-game standings update for league \(leagueID)")

                                try await Task.sleep(nanoseconds: waitNanos)
                            }

                            // Make standings update
                            let updateLabel = interval == 65 ? "final (1h 5min)" : "\(interval)-minute post-game"
                            logger.info("🏆 Making \(updateLabel) standings update for league \(leagueID)")
                            try await fetchAndCacheStandings(leagueID: leagueID, season: season)
                        }
                    }

                    // Sleep until next day
                    let now = Date()
                    let tomorrow = Calendar.current.startOfDay(for: now.addingTimeInterval(86400))
                    let sleepDuration = UInt64(tomorrow.timeIntervalSince(now) * 1_000_000_000)

                    logger.info("💤 Sleeping until next day for league \(leagueID)")
                    try await Task.sleep(nanoseconds: sleepDuration)
                }

            } catch is CancellationError {
                logger.info("🛑 Standings update loop cancelled for league \(leagueID)")
                break
            } catch {
                logger.error("❌ Error in standings update loop for league \(leagueID): \(error)")
                // On error, wait 1 hour before retrying
                try? await Task.sleep(nanoseconds: hourlyInterval)
            }
        }

        logger.info("✅ Standings update loop ended for league \(leagueID)")
    }

    /// Fetch standings from API and cache them
    private func fetchAndCacheStandings(leagueID: Int, season: Int) async throws {
        logger.info("📥 Fetching standings for league \(leagueID), season \(season)")

        let standings = try await apiClient.getStandings(leagueId: leagueID, season: season)

        // Cache the standings (TTL: 1 hour = 3600 seconds)
        let cacheKey = "standings:\(leagueID):\(season)"
        try await cacheService.set(key: cacheKey, value: standings, ttl: 3600)

        // Update last update time
        lastUpdateLock.withLock { updates in
            updates[leagueID] = Date()
        }

        logger.info("✅ Standings cached for league \(leagueID) (\(standings.count) groups)")
    }

    /// Get the estimated end time of the last game of the day
    /// Estimates match end as timestamp + 2 hours (typical match duration)
    private func getLastGameEndTime(fixtures: [FixtureEntity]) -> Date? {
        let finishedStatuses: Set<String> = ["FT", "AET", "PEN"]

        let finishedFixtures = fixtures.filter { finishedStatuses.contains($0.statusShort) }

        guard !finishedFixtures.isEmpty else { return nil }

        // Find the fixture with the latest timestamp
        let lastFixture = finishedFixtures.max(by: { $0.timestamp < $1.timestamp })

        guard let lastFixture = lastFixture else { return nil }

        // Estimate match end time: start time + 2 hours (typical match duration)
        let matchStart = Date(timeIntervalSince1970: TimeInterval(lastFixture.timestamp))
        let estimatedEnd = matchStart.addingTimeInterval(2 * 60 * 60) // +2 hours

        return estimatedEnd
    }

    /// Get last standings update time for a league
    public func getLastUpdateTime(leagueID: Int) -> Date? {
        lastUpdateLock.withLock { updates in
            updates[leagueID]
        }
    }

    /// Check if standings updates are active for a league
    public func isActive(leagueID: Int) -> Bool {
        pollingTasksLock.withLock { tasks in
            tasks[leagueID] != nil
        }
    }
}
