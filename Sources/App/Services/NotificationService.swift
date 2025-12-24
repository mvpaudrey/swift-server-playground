import Foundation
import Vapor
import Fluent
import APNS

// MARK: - Live Activity Content States

/// Content state for AFCON match Live Activities
struct MatchContentState: Codable {
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int
    let awayScore: Int
    let elapsed: Int
    let status: String
    let lastEvent: String
}

/// Empty content state for dismissing Live Activities
struct EmptyContentState: Codable {}
import APNSCore

/// Actor-based notification service with APNSwift v5+ for Swift 6 compliance
/// Handles push notifications (iOS/Android) and Live Activity updates
public actor NotificationService {
    private let db: any Database
    private let logger: Logger
    private let deviceRepository: DeviceRepository

    // APNs client for iOS - lazily initialized
    private var _apnsClient: APNSClient<JSONDecoder, JSONEncoder>?
    private let apnsConfig: APNSConfiguration?

    // FCM configuration for Android
    private let fcmServerKey: String?
    private let fcmClient: any Client

    // Live Activity management
    private var activeActivities: [UUID: LiveActivityTracker] = [:]
    private var cleanupTask: Task<Void, Never>?

    struct APNSConfiguration {
        let keyData: String
        let keyId: String
        let teamId: String
        let environment: APNSEnvironment
        let topic: String
    }

    public init(db: any Database, logger: Logger, fcmClient: any Client, eventLoopGroup: any EventLoopGroup) {
        self.db = db
        self.logger = logger
        self.deviceRepository = DeviceRepository(db: db, logger: logger)
        self.fcmClient = fcmClient

        // Parse APNs configuration without initializing client yet
        if let keyId = Environment.get("APNS_KEY_ID"),
           let teamId = Environment.get("APNS_TEAM_ID"),
           let keyPath = Environment.get("APNS_KEY_PATH"),
           let topic = Environment.get("APNS_TOPIC") {

            do {
                let keyData = try String(contentsOfFile: keyPath, encoding: .utf8)
                let environment: APNSEnvironment =
                    Environment.get("APNS_ENVIRONMENT") == "production" ? .production : .development

                self.apnsConfig = APNSConfiguration(
                    keyData: keyData,
                    keyId: keyId,
                    teamId: teamId,
                    environment: environment,
                    topic: topic
                )

                logger.info("✅ APNs configuration loaded (\(environment.url))")
            } catch {
                logger.error("❌ Failed to load APNs key file: \(error)")
                self.apnsConfig = nil
            }
        } else {
            logger.warning("⚠️ APNs credentials not configured (APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_PATH, APNS_TOPIC)")
            self.apnsConfig = nil
        }

        // Get FCM server key
        self.fcmServerKey = Environment.get("FCM_SERVER_KEY")
        if fcmServerKey == nil {
            logger.warning("⚠️ FCM server key not configured")
        }

        // Initialize cleanup task (will be started after initialization)
        self.cleanupTask = nil
    }

    /// Start the cleanup task (should be called after initialization)
    public func startCleanupTask() {
        guard cleanupTask == nil else { return }
        cleanupTask = Task {
            await self.startPeriodicCleanup()
        }
    }

    deinit {
        cleanupTask?.cancel()
    }

    /// Lazily initialize APNSClient on first use
    private func getAPNSClient() throws -> APNSClient<JSONDecoder, JSONEncoder> {
        if let client = _apnsClient {
            return client
        }

        guard let config = apnsConfig else {
            throw NotificationError.apnsNotConfigured
        }

        do {
            let clientConfig = APNSClientConfiguration(
                authenticationMethod: try .jwt(
                    privateKey: .init(pemRepresentation: config.keyData),
                    keyIdentifier: config.keyId,
                    teamIdentifier: config.teamId
                ),
                environment: config.environment
            )

            let client = APNSClient(
                configuration: clientConfig,
                eventLoopGroupProvider: .shared(MultiThreadedEventLoopGroup.singleton),
                responseDecoder: JSONDecoder(),
                requestEncoder: JSONEncoder()
            )

            _apnsClient = client
            logger.info("✅ APNs client initialized")
            return client
        } catch {
            logger.error("❌ Failed to initialize APNs client: \(error)")
            throw NotificationError.apnsInitializationFailed(error)
        }
    }

    // MARK: - Goal Notifications

    public func sendGoalNotification(
        fixtureId: Int,
        homeTeam: String,
        awayTeam: String,
        homeGoals: Int,
        awayGoals: Int,
        scorer: String,
        assist: String?,
        minute: Int,
        leagueId: Int,
        season: Int
    ) async throws {
        logger.info("⚽ Sending goal notification: \(scorer) - \(homeTeam) \(homeGoals)-\(awayGoals) \(awayTeam)")

        // Find subscribed devices
        let subscriptions = try await db.query(NotificationSubscriptionEntity.self)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .filter(\.$notifyGoals == true)
            .with(\.$device)
            .all()

        logger.info("Found \(subscriptions.count) goal notification subscribers")

        // Create notification payload
        let title = "⚽ GOAL!"
        let assistText = assist.map { " (assist: \($0))" } ?? ""
        let body = "\(scorer) scores!\(assistText) \(homeTeam) \(homeGoals)-\(awayGoals) \(awayTeam) (\(minute)')"

        // Send to iOS devices
        let iosDevices = subscriptions.filter { $0.device.platform == "ios" }
        for subscription in iosDevices {
            do {
                try await sendAPNs(
                    deviceToken: subscription.device.deviceToken,
                    title: title,
                    body: body,
                    badge: 1,
                    sound: "goal.aiff",
                    data: [
                        "type": "goal",
                        "fixture_id": String(fixtureId),
                        "scorer": scorer,
                        "minute": String(minute)
                    ]
                )
            } catch {
                logger.error("Failed to send APNs to device \(subscription.device.id?.uuidString ?? "unknown"): \(error)")
            }
        }

        // Send to Android devices
        let androidDevices = subscriptions.filter { $0.device.platform == "android" }
        for subscription in androidDevices {
            do {
                try await sendFCM(
                    deviceToken: subscription.device.deviceToken,
                    title: title,
                    body: body,
                    data: [
                        "type": "goal",
                        "fixture_id": String(fixtureId),
                        "scorer": scorer,
                        "minute": String(minute)
                    ]
                )
            } catch {
                logger.error("Failed to send FCM to device \(subscription.device.id?.uuidString ?? "unknown"): \(error)")
            }
        }

        // Update Live Activities for this fixture
        await updateLiveActivitiesForFixture(
            fixtureId: fixtureId,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            homeScore: homeGoals,
            awayScore: awayGoals,
            elapsed: minute,
            status: "IN_PLAY",
            lastEvent: "⚽ \(scorer) \(minute)'"
        )
    }

    // MARK: - Red Card Notifications

    public func sendRedCardNotification(
        fixtureId: Int,
        homeTeam: String,
        awayTeam: String,
        playerName: String,
        teamName: String,
        minute: Int,
        leagueId: Int,
        season: Int
    ) async throws {
        logger.info("🟥 Sending red card notification: \(playerName) (\(teamName)) - \(minute)'")

        // Find subscribed devices
        let subscriptions = try await db.query(NotificationSubscriptionEntity.self)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .filter(\.$notifyRedCards == true)
            .with(\.$device)
            .all()

        logger.info("Found \(subscriptions.count) red card notification subscribers")

        // Create notification payload
        let title = "🟥 RED CARD!"
        let body = "\(playerName) (\(teamName)) sent off! \(homeTeam) vs \(awayTeam) (\(minute)')"

        // Send to iOS devices
        let iosDevices = subscriptions.filter { $0.device.platform == "ios" }
        for subscription in iosDevices {
            do {
                try await sendAPNs(
                    deviceToken: subscription.device.deviceToken,
                    title: title,
                    body: body,
                    badge: 1,
                    sound: "red_card.aiff",
                    data: [
                        "type": "red_card",
                        "fixture_id": String(fixtureId),
                        "player": playerName,
                        "team": teamName,
                        "minute": String(minute)
                    ]
                )
            } catch {
                logger.error("Failed to send APNs to device \(subscription.device.id?.uuidString ?? "unknown"): \(error)")
            }
        }

        // Send to Android devices
        let androidDevices = subscriptions.filter { $0.device.platform == "android" }
        for subscription in androidDevices {
            do {
                try await sendFCM(
                    deviceToken: subscription.device.deviceToken,
                    title: title,
                    body: body,
                    data: [
                        "type": "red_card",
                        "fixture_id": String(fixtureId),
                        "player": playerName,
                        "team": teamName,
                        "minute": String(minute)
                    ]
                )
            } catch {
                logger.error("Failed to send FCM to device \(subscription.device.id?.uuidString ?? "unknown"): \(error)")
            }
        }
    }

    // MARK: - Live Activity Management

    public func startLiveActivity(
        deviceUUID: UUID,
        fixtureId: Int,
        activityId: String,
        pushToken: String,
        updateFrequency: String
    ) async throws -> LiveActivityEntity {
        logger.info("🎬 Starting Live Activity: \(activityId) for fixture \(fixtureId)")

        // Find device
        guard let device = try await DeviceRegistrationEntity.find(deviceUUID, on: db) else {
            throw NotificationError.deviceNotFound
        }

        // Create Live Activity entity
        let activity = LiveActivityEntity(
            deviceId: try device.requireID(),
            fixtureId: fixtureId,
            activityId: activityId,
            pushToken: pushToken,
            updateFrequency: updateFrequency
        )

        try await activity.create(on: db)

        // Track in memory
        let tracker = LiveActivityTracker(
            activityUUID: try activity.requireID(),
            deviceUUID: deviceUUID,
            fixtureId: fixtureId,
            pushToken: pushToken,
            updateFrequency: updateFrequency
        )
        activeActivities[try activity.requireID()] = tracker

        logger.info("✅ Live Activity started: \(activityId)")
        return activity
    }

    public func endLiveActivity(
        deviceUUID: UUID,
        fixtureId: Int
    ) async throws {
        logger.info("🛑 Ending Live Activity for fixture \(fixtureId)")

        // Find and deactivate activity
        guard let device = try await DeviceRegistrationEntity.find(deviceUUID, on: db) else {
            throw NotificationError.deviceNotFound
        }

        if let activity = try await db.query(LiveActivityEntity.self)
            .filter(\.$device.$id == (try device.requireID()))
            .filter(\.$fixtureId == fixtureId)
            .filter(\.$isActive == true)
            .first() {

            // Send dismissal update
            await sendLiveActivityDismissal(
                pushToken: activity.pushToken,
                dismissalDate: Int(Date().timeIntervalSince1970)
            )

            // Update database
            activity.isActive = false
            try await activity.update(on: db)

            // Remove from memory
            if let uuid = activity.id {
                activeActivities.removeValue(forKey: uuid)
            }

            logger.info("✅ Live Activity ended")
        } else {
            logger.warning("⚠️ No active Live Activity found for fixture \(fixtureId)")
        }
    }

    /// End a Live Activity by its UUID
    public func endLiveActivity(activityUUID: UUID) async throws {
        logger.info("🛑 Ending Live Activity \(activityUUID)")

        guard let activity = try await db.query(LiveActivityEntity.self)
            .filter(\.$id == activityUUID)
            .filter(\.$isActive == true)
            .first() else {
            throw NotificationError.activityNotFound
        }

        // Send dismissal update
        await sendLiveActivityDismissal(
            pushToken: activity.pushToken,
            dismissalDate: Int(Date().timeIntervalSince1970)
        )

        // Update database
        activity.isActive = false
        try await activity.update(on: db)

        // Remove from memory
        activeActivities.removeValue(forKey: activityUUID)

        logger.info("✅ Live Activity ended")
    }

    /// Update Live Activity frequency
    public func updateLiveActivityFrequency(
        activityUUID: UUID,
        updateFrequency: String
    ) async throws {
        logger.info("🔄 Updating Live Activity frequency: \(activityUUID) -> \(updateFrequency)")

        guard let activity = try await db.query(LiveActivityEntity.self)
            .filter(\.$id == activityUUID)
            .first() else {
            throw NotificationError.activityNotFound
        }

        // Update database
        activity.updateFrequency = updateFrequency
        try await activity.update(on: db)

        // Update in memory
        if let tracker = activeActivities[activityUUID] {
            let updatedTracker = LiveActivityTracker(
                activityUUID: tracker.activityUUID,
                deviceUUID: tracker.deviceUUID,
                fixtureId: tracker.fixtureId,
                pushToken: tracker.pushToken,
                updateFrequency: updateFrequency
            )
            activeActivities[activityUUID] = updatedTracker
        }

        logger.info("✅ Live Activity frequency updated")
    }

    /// Get all active Live Activities for a device
    public func getActiveLiveActivities(deviceUUID: UUID) async throws -> [LiveActivityEntity] {
        logger.info("📋 Getting active Live Activities for device \(deviceUUID)")

        guard let device = try await DeviceRegistrationEntity.find(deviceUUID, on: db) else {
            throw NotificationError.deviceNotFound
        }

        let deviceId = try device.requireID()

        let activities = try await db.query(LiveActivityEntity.self)
            .filter(\.$device.$id == deviceId)
            .filter(\.$isActive == true)
            .all()

        logger.info("Found \(activities.count) active Live Activities")
        return activities
    }

    // MARK: - Private Methods

    /// Send Apple Push Notification
    private func sendAPNs(
        deviceToken: String,
        title: String,
        body: String,
        badge: Int? = nil,
        sound: String? = nil,
        data: [String: String] = [:]
    ) async throws {
        guard let config = apnsConfig else {
            throw NotificationError.apnsNotConfigured
        }

        let client = try getAPNSClient()

        let alert = APNSAlertNotification(
            alert: .init(
                title: .raw(title),
                subtitle: nil,
                body: .raw(body),
                launchImage: nil
            ),
            expiration: .immediately,
            priority: .immediately,
            topic: config.topic,
            payload: data
        )

        try await client.sendAlertNotification(
            alert,
            deviceToken: deviceToken
        )

        logger.debug("📱 APNs sent to \(deviceToken.prefix(10))...")
    }

    /// Send Firebase Cloud Message
    private func sendFCM(
        deviceToken: String,
        title: String,
        body: String,
        data: [String: String] = [:]
    ) async throws {
        guard let serverKey = fcmServerKey else {
            throw NotificationError.fcmNotConfigured
        }

        struct FCMPayload: Content {
            let to: String
            let notification: FCMNotification
            let data: [String: String]
        }

        struct FCMNotification: Codable {
            let title: String
            let body: String
        }

        let url = URI(string: "https://fcm.googleapis.com/fcm/send")

        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "key=\(serverKey)")
        headers.add(name: .contentType, value: "application/json")

        let payload = FCMPayload(
            to: deviceToken,
            notification: FCMNotification(title: title, body: body),
            data: data
        )

        let response = try await fcmClient.post(url, headers: headers) { req in
            try req.content.encode(payload)
        }

        if response.status == .ok {
            logger.debug("🤖 FCM sent to \(deviceToken.prefix(10))...")
        } else {
            throw NotificationError.fcmSendFailed(response.status.code)
        }
    }

    /// Update all Live Activities for a specific fixture
    private func updateLiveActivitiesForFixture(
        fixtureId: Int,
        homeTeam: String,
        awayTeam: String,
        homeScore: Int,
        awayScore: Int,
        elapsed: Int,
        status: String,
        lastEvent: String?
    ) async {
        logger.info("🔔 Live Activity update triggered:")
        logger.info("  📍 Fixture ID: \(fixtureId)")
        logger.info("  ⚽ Match: \(homeTeam) \(homeScore)-\(awayScore) \(awayTeam)")
        logger.info("  ⏱️ Time: \(elapsed)' | Status: \(status)")
        logger.info("  📢 Event: \(lastEvent ?? "None")")

        let activities = activeActivities.values.filter { $0.fixtureId == fixtureId }
        logger.info("  📲 Active trackers for this fixture: \(activities.count)")

        if activities.isEmpty {
            logger.warning("  ⚠️ No active Live Activities found for fixture \(fixtureId)")
            return
        }

        var updatesSent = 0
        var updatesSkipped = 0

        for activity in activities {
            logger.info("  🎯 Processing activity \(activity.activityUUID)")
            logger.info("    - Device: \(activity.deviceUUID)")
            logger.info("    - Frequency: \(activity.updateFrequency)")
            logger.info("    - Push Token: \(activity.pushToken.prefix(20))...")

            // Check update frequency filter
            guard shouldSendUpdate(for: activity, event: lastEvent) else {
                logger.info("    ⏭️ SKIPPED: Filtered by frequency setting '\(activity.updateFrequency)'")
                updatesSkipped += 1
                continue
            }

            logger.info("    ✅ SENDING update...")

            await sendLiveActivityUpdate(
                pushToken: activity.pushToken,
                contentState: [
                    "homeTeam": homeTeam,
                    "awayTeam": awayTeam,
                    "homeScore": String(homeScore),
                    "awayScore": String(awayScore),
                    "elapsed": String(elapsed),
                    "status": status,
                    "lastEvent": lastEvent ?? ""
                ]
            )
            updatesSent += 1
        }

        logger.info("  📊 Summary: \(updatesSent) updates sent, \(updatesSkipped) skipped")
    }

    /// Check if update should be sent based on frequency setting
    private func shouldSendUpdate(for activity: LiveActivityTracker, event: String?) -> Bool {
        switch activity.updateFrequency {
        case "every_minute":
            return true
        case "goals_only":
            return event?.contains("⚽") ?? false
        case "major_events":
            // Goals, red cards, VAR, penalties, status changes
            let majorEvents = ["⚽", "🟥", "VAR", "⚡"]
            return majorEvents.contains { event?.contains($0) ?? false }
        case "all_events":
            return true
        default:
            return true
        }
    }

    /// Send Live Activity push-to-update notification
    private func sendLiveActivityUpdate(
        pushToken: String,
        contentState: [String: String]
    ) async {
        let timestamp = Int(Date().timeIntervalSince1970)

        guard let apnsClient = _apnsClient, let config = apnsConfig else {
            logger.warning("⚠️ APNs not configured, cannot send Live Activity update")
            logger.warning("  - Push Token: \(pushToken.prefix(20))...")
            return
        }

        // Create the content state from dictionary
        let matchState = MatchContentState(
            homeTeam: contentState["homeTeam"] ?? "",
            awayTeam: contentState["awayTeam"] ?? "",
            homeScore: Int(contentState["homeScore"] ?? "0") ?? 0,
            awayScore: Int(contentState["awayScore"] ?? "0") ?? 0,
            elapsed: Int(contentState["elapsed"] ?? "0") ?? 0,
            status: contentState["status"] ?? "LIVE",
            lastEvent: contentState["lastEvent"] ?? ""
        )

        logger.info("      📤 Preparing Live Activity push notification:")
        logger.info("        - Home: \(matchState.homeTeam) (\(matchState.homeScore))")
        logger.info("        - Away: \(matchState.awayTeam) (\(matchState.awayScore))")
        logger.info("        - Time: \(matchState.elapsed)' | Status: \(matchState.status)")
        logger.info("        - Event: \(matchState.lastEvent)")
        logger.info("        - Timestamp: \(timestamp)")
        logger.info("        - Topic: \(config.topic)")

        do {
            // Create Live Activity notification using APNSwift 5.x/6.x API
            let notification = APNSLiveActivityNotification(
                expiration: .immediately,
                priority: .immediately,
                appID: config.topic,
                contentState: matchState,
                event: .update,
                timestamp: timestamp
            )

            // Send the notification
            try await apnsClient.sendLiveActivityNotification(
                notification,
                deviceToken: pushToken
            )

            logger.info("      ✅ Live Activity update sent successfully to \(pushToken.prefix(10))...")
        } catch {
            logger.error("      ❌ Failed to send Live Activity update to \(pushToken.prefix(10))...")
            logger.error("      ❌ Error: \(error)")
        }
    }

    /// Send Live Activity dismissal
    private func sendLiveActivityDismissal(
        pushToken: String,
        dismissalDate: Int
    ) async {
        guard let apnsClient = _apnsClient, let config = apnsConfig else {
            logger.warning("⚠️ APNs not configured, cannot send Live Activity dismissal")
            return
        }

        do {
            // Create empty content state for dismissal
            let emptyState = EmptyContentState()

            let notification = APNSLiveActivityNotification(
                expiration: .immediately,
                priority: .immediately,
                appID: config.topic,
                contentState: emptyState,
                event: .end,
                timestamp: dismissalDate
            )

            try await apnsClient.sendLiveActivityNotification(
                notification,
                deviceToken: pushToken
            )

            logger.info("✅ Live Activity dismissal sent successfully")
        } catch {
            logger.error("❌ Failed to send Live Activity dismissal: \(error)")
        }
    }

    /// Periodic cleanup of expired Live Activities
    private func startPeriodicCleanup() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 3_600_000_000_000) // 1 hour
                await cleanupExpiredActivities()
            } catch {
                // Task cancelled or sleep interrupted
                break
            }
        }
    }

    private func cleanupExpiredActivities() async {
        logger.info("🧹 Cleaning up expired Live Activities...")

        do {
            let expiredActivities = try await db.query(LiveActivityEntity.self)
                .filter(\.$isActive == true)
                .filter(\.$expiresAt < Date())
                .all()

            logger.info("Found \(expiredActivities.count) expired activities")

            for activity in expiredActivities {
                // Send dismissal
                await sendLiveActivityDismissal(
                    pushToken: activity.pushToken,
                    dismissalDate: Int(Date().timeIntervalSince1970)
                )

                // Deactivate in database
                activity.isActive = false
                try await activity.update(on: db)

                // Remove from memory
                if let uuid = activity.id {
                    activeActivities.removeValue(forKey: uuid)
                }
            }

            logger.info("✅ Cleanup complete")
        } catch {
            logger.error("❌ Cleanup failed: \(error)")
        }
    }
}

// MARK: - Supporting Types

struct LiveActivityTracker {
    let activityUUID: UUID
    let deviceUUID: UUID
    let fixtureId: Int
    let pushToken: String
    let updateFrequency: String
}

enum NotificationError: Error {
    case apnsNotConfigured
    case apnsInitializationFailed(any Error)
    case fcmNotConfigured
    case fcmSendFailed(UInt)
    case deviceNotFound
    case activityNotFound
    case invalidToken
}
