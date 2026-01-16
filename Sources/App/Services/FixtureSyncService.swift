import Foundation
import Vapor
import Synchronization

/// Service that automatically syncs fixtures from the API to keep database up-to-date
/// - Runs on a configurable schedule (default: every 30 minutes)
/// - Updates fixtures for all configured leagues
/// - Clears cache after sync to ensure fresh data is served
public final class FixtureSyncService: Sendable {
    private let apiClient: APIFootballClient
    private let fixtureRepository: FixtureRepository
    private let cacheService: CacheService
    private let logger: Logger
    private let syncInterval: TimeInterval

    // Track active sync task
    private let syncTaskLock = Mutex<Task<Void, Never>?>(nil)
    private let dailySyncTaskLock = Mutex<Task<Void, Never>?>(nil)

    public init(
        apiClient: APIFootballClient,
        fixtureRepository: FixtureRepository,
        cacheService: CacheService,
        logger: Logger,
        syncInterval: TimeInterval = 1800 // 30 minutes default
    ) {
        self.apiClient = apiClient
        self.fixtureRepository = fixtureRepository
        self.cacheService = cacheService
        self.logger = logger
        self.syncInterval = syncInterval
    }

    // MARK: - Public API

    /// Start automatic fixture syncing for configured leagues
    /// This runs in a background task and syncs fixtures periodically
    public func startAutoSync(leagues: [(id: Int, season: Int, name: String)]) {
        syncTaskLock.withLock { task in
            guard task == nil else {
                logger.debug("⏭️ Fixture auto-sync already running")
                return
            }

            logger.info("🔄 Starting automatic fixture sync (interval: \(Int(syncInterval/60)) minutes)")

            let syncTask: Task<Void, Never> = Task.detached(priority: .medium) { [weak self] in
                await self?.syncLoop(leagues: leagues)
                return ()
            }

            task = syncTask
        }
    }

    /// Start daily fixture sync at local midnight
    public func startDailyMidnightSync(leagues: [(id: Int, season: Int, name: String)]) {
        dailySyncTaskLock.withLock { task in
            guard task == nil else {
                logger.debug("⏭️ Fixture daily sync already running")
                return
            }

            logger.info("🗓️ Starting daily fixture sync at midnight")

            let dailyTask: Task<Void, Never> = Task.detached(priority: .background) { [weak self] in
                await self?.dailySyncLoop(leagues: leagues)
                return ()
            }

            task = dailyTask
        }
    }

    /// Stop automatic fixture syncing
    public func stopAutoSync() {
        syncTaskLock.withLock { task in
            if let task = task {
                logger.info("🛑 Stopping automatic fixture sync")
                task.cancel()
            }
        }
    }

    /// Stop daily fixture syncing
    public func stopDailyMidnightSync() {
        dailySyncTaskLock.withLock { task in
            if let task = task {
                logger.info("🛑 Stopping daily fixture sync")
                task.cancel()
            }
        }
    }

    /// Manually trigger a fixture sync for specific league
    public func syncNow(leagueID: Int, season: Int, competition: String) async throws {
        try await syncFixtures(leagueID: leagueID, season: season, competition: competition)
    }

    /// Trigger a one-off sync for all leagues
    public func syncAll(leagues: [(id: Int, season: Int, name: String)]) async {
        for league in leagues {
            if Task.isCancelled { break }
            do {
                try await syncFixtures(
                    leagueID: league.id,
                    season: league.season,
                    competition: league.name
                )
            } catch {
                logger.error("❌ Failed to sync fixtures for \(league.name): \(error)")
            }
        }
    }

    // MARK: - Private Implementation

    /// Main sync loop - runs continuously until cancelled
    private func syncLoop(leagues: [(id: Int, season: Int, name: String)]) async {
        logger.info("🔄 Fixture sync loop started for \(leagues.count) league(s)")

        let intervalNanoseconds = UInt64(syncInterval * 1_000_000_000)

        while !Task.isCancelled {
            do {
                // Sync all configured leagues
                for league in leagues {
                    if Task.isCancelled { break }

                    do {
                        try await syncFixtures(
                            leagueID: league.id,
                            season: league.season,
                            competition: league.name
                        )
                    } catch {
                        logger.error("❌ Failed to sync fixtures for \(league.name): \(error)")
                        // Continue with next league even if one fails
                    }
                }

                // Wait for next sync interval
                logger.info("⏰ Next fixture sync in \(Int(syncInterval/60)) minutes")
                try await Task.sleep(nanoseconds: intervalNanoseconds)

            } catch {
                if Task.isCancelled {
                    logger.info("🛑 Fixture sync loop cancelled")
                    break
                }
                logger.error("❌ Error in fixture sync loop: \(error)")

                // Wait a bit before retrying on error
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 1 minute
            }
        }

        logger.info("✅ Fixture sync loop stopped")
    }

    private func dailySyncLoop(leagues: [(id: Int, season: Int, name: String)]) async {
        logger.info("🗓️ Fixture daily sync loop started for \(leagues.count) league(s)")
        let calendar = Calendar.current

        while !Task.isCancelled {
            guard let nextMidnight = calendar.nextDate(
                after: Date(),
                matching: DateComponents(hour: 0, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) else {
                logger.error("❌ Failed to compute next midnight; retrying in 1 hour")
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
                continue
            }

            let waitSeconds = max(0, nextMidnight.timeIntervalSinceNow)
            logger.info("⏰ Next daily fixture sync at \(nextMidnight)")

            do {
                try await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
            } catch {
                if Task.isCancelled { break }
            }

            if Task.isCancelled { break }

            for league in leagues {
                if Task.isCancelled { break }
                do {
                    try await syncFixtures(
                        leagueID: league.id,
                        season: league.season,
                        competition: league.name
                    )
                } catch {
                    logger.error("❌ Failed daily sync for \(league.name): \(error)")
                }
            }
        }

        logger.info("✅ Fixture daily sync loop stopped")
    }

    /// Sync fixtures for a specific league from API to database
    private func syncFixtures(leagueID: Int, season: Int, competition: String) async throws {
        logger.info("🔄 Syncing fixtures for \(competition) (ID: \(leagueID), Season: \(season))")

        // Fetch all fixtures from API
        let fixturesData = try await apiClient.getFixtures(
            leagueId: leagueID,
            season: season
        )

        logger.info("📥 Fetched \(fixturesData.count) fixtures from API")

        // Upsert all fixtures into database
        try await fixtureRepository.upsertBatch(
            fixtures: fixturesData,
            leagueId: leagueID,
            season: season,
            competition: competition
        )

        // Clear cache to force fresh data on next request
        try await cacheService.invalidateLeagueSeason(leagueID: leagueID, season: season)

        logger.info("✅ Successfully synced \(fixturesData.count) fixtures for \(competition)")
    }
}
