import Vapor
import Fluent
import Foundation

/// Service that automatically creates Live Activities for subscribed users
/// when their favorite team's matches are about to start
public final class LiveActivityAutoService: Sendable {
    private let logger: Logger
    private let db: any Database
    private let notificationService: NotificationService

    // Track which fixtures have had Live Activities auto-created
    private let createdActivities = AsyncLockedValueBox<Set<Int>>(Set())

    // Scheduler task
    private nonisolated(unsafe) var schedulerTask: Task<Void, any Error>?

    public init(
        db: any Database,
        notificationService: NotificationService,
        logger: Logger
    ) {
        self.db = db
        self.notificationService = notificationService
        self.logger = logger
    }

    /// Start the automatic Live Activity creation service
    public func start() {
        logger.info("🎬 Starting automatic Live Activity service (checks every 5 minutes)")

        schedulerTask = Task {
            // Run first check immediately
            await performCheck()

            while !Task.isCancelled {
                do {
                    // Check every 5 minutes
                    try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)

                    await performCheck()
                } catch is CancellationError {
                    logger.info("🛑 Auto Live Activity service cancelled")
                    break
                } catch {
                    logger.error("❌ Error in auto Live Activity service: \(error)")
                    // Wait a bit before retrying on error
                    try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                }
            }
        }
    }

    /// Perform a single check cycle
    private func performCheck() async {
        logger.info("🔄 Auto Live Activity check running...")

        do {
            try await checkUpcomingMatches()
            logger.info("✅ Auto Live Activity check completed")
        } catch {
            logger.error("❌ Auto Live Activity check failed: \(error)")
        }
    }

    /// Stop the service
    public func stop() {
        logger.info("🛑 Stopping automatic Live Activity service")
        schedulerTask?.cancel()
    }

    /// Check for upcoming matches and create Live Activities for subscribed users
    private func checkUpcomingMatches() async throws {
        let now = Date()
        let upcoming = Date(timeIntervalSinceNow: 30 * 60) // Next 30 minutes

        // Find fixtures starting in the next 30 minutes
        let upcomingFixtures = try await FixtureEntity.query(on: db)
            .filter(\.$date >= now)
            .filter(\.$date <= upcoming)
            .filter(\.$statusShort == "NS") // Not Started
            .all()

        if upcomingFixtures.isEmpty {
            logger.info("   No upcoming fixtures in next 30 minutes")
            return
        }

        logger.info("   📅 Found \(upcomingFixtures.count) upcoming fixture(s) in next 30 minutes")

        for fixture in upcomingFixtures {
            try await createLiveActivitiesForFixture(fixture)
        }
    }

    /// Create Live Activities for all subscribed users of teams in this fixture
    private func createLiveActivitiesForFixture(_ fixture: FixtureEntity) async throws {
        let fixtureId = fixture.apiFixtureId

        // Check if we've already created activities for this fixture
        let alreadyCreated = await createdActivities.withLockedValue { set in
            set.contains(fixtureId)
        }

        if alreadyCreated {
            return
        }

        logger.info("   🔍 Checking subscriptions for fixture \(fixtureId): \(fixture.homeTeamName) vs \(fixture.awayTeamName)")

        // Find all subscriptions for either team in this fixture
        let homeTeamId = fixture.homeTeamId
        let awayTeamId = fixture.awayTeamId
        let leagueId = fixture.leagueId
        let season = fixture.season

        let subscriptions = try await NotificationSubscriptionEntity.query(on: db)
            .with(\.$device)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .group(.or) { group in
                group.filter(\.$teamId == homeTeamId)
                group.filter(\.$teamId == awayTeamId)
            }
            .all()

        guard !subscriptions.isEmpty else {
            logger.info("      No subscriptions found for this fixture")
            return
        }

        logger.info("      Found \(subscriptions.count) subscription(s) for this fixture")

        // Send trigger notification to each subscribed device so the app can
        // start the Live Activity itself (only the app can get the ActivityKit push token)
        for subscription in subscriptions {
            do {
                // Skip if device already has an active Live Activity for this fixture
                let existingActivity = try await LiveActivityEntity.query(on: db)
                    .filter(\.$device.$id == subscription.device.id!)
                    .filter(\.$fixtureId == fixtureId)
                    .filter(\.$isActive == true)
                    .first()

                if existingActivity != nil {
                    logger.info("      ⏭️  Device \(subscription.device.id!.uuidString) already has Live Activity for fixture \(fixtureId)")
                    continue
                }

                guard subscription.device.platform == "ios" else {
                    logger.debug("      ⏭️  Skipping non-iOS device for Live Activity trigger")
                    continue
                }

                try await notificationService.sendLiveActivityTriggerNotification(
                    deviceToken: subscription.device.deviceToken,
                    fixtureId: fixtureId,
                    homeTeam: fixture.homeTeamName,
                    awayTeam: fixture.awayTeamName,
                    kickoffTimestamp: fixture.timestamp
                )

                logger.info("      ✅ Live Activity trigger sent to device \(subscription.device.id!.uuidString) - \(fixture.homeTeamName) vs \(fixture.awayTeamName)")

            } catch {
                logger.error("      ❌ Failed to send Live Activity trigger to device \(subscription.device.id?.uuidString ?? "unknown"): \(error)")
            }
        }

        // Mark this fixture as processed
        await createdActivities.withLockedValue { set in
            set.insert(fixtureId)
        }
    }
}

// Thread-safe box for storing created activities
private actor AsyncLockedValueBox<T> {
    private var value: T

    init(_ initialValue: T) {
        self.value = initialValue
    }

    func withLockedValue<Result>(_ body: (inout T) throws -> Result) rethrows -> Result {
        try body(&value)
    }
}
