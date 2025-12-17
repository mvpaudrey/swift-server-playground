import Foundation
import Vapor
import Fluent

/// Repository for managing device registrations and notification subscriptions
public final class DeviceRepository {
    private let db: Database
    private let logger: Logger

    public init(db: Database, logger: Logger) {
        self.db = db
        self.logger = logger
    }

    // MARK: - Device Registration

    /// Register a new device or update existing device
    /// If device token already exists, updates the existing registration
    public func registerDevice(
        userId: String,
        deviceToken: String,
        platform: String,
        deviceId: String?,
        appVersion: String?,
        osVersion: String?,
        language: String,
        timezone: String?
    ) async throws -> DeviceRegistrationEntity {
        // Check if device already exists
        if let existing = try await DeviceRegistrationEntity.query(on: db)
            .filter(\.$deviceToken == deviceToken)
            .first() {

            logger.info("📱 Updating existing device registration: \(existing.id?.uuidString ?? "unknown")")

            // Update existing device
            existing.userId = userId
            existing.platform = platform
            existing.deviceId = deviceId
            existing.appVersion = appVersion
            existing.osVersion = osVersion
            existing.language = language
            existing.timezone = timezone
            existing.isActive = true
            existing.lastActiveAt = Date()

            try await existing.save(on: db)
            return existing
        }

        // Create new device
        logger.info("📱 Creating new device registration for user: \(userId)")

        let device = DeviceRegistrationEntity(
            userId: userId,
            deviceToken: deviceToken,
            platform: platform,
            deviceId: deviceId,
            appVersion: appVersion,
            osVersion: osVersion,
            language: language,
            timezone: timezone
        )

        try await device.save(on: db)
        return device
    }

    /// Update device token when it changes (e.g., after app reinstall)
    public func updateDeviceToken(deviceUUID: UUID, newToken: String) async throws {
        guard let device = try await DeviceRegistrationEntity.find(deviceUUID, on: db) else {
            throw Abort(.notFound, reason: "Device not found")
        }

        logger.info("📱 Updating device token for device: \(deviceUUID.uuidString)")

        device.deviceToken = newToken
        device.lastActiveAt = Date()
        try await device.save(on: db)
    }

    /// Unregister device (mark as inactive)
    public func unregisterDevice(deviceUUID: UUID) async throws {
        guard let device = try await DeviceRegistrationEntity.find(deviceUUID, on: db) else {
            throw Abort(.notFound, reason: "Device not found")
        }

        logger.info("📱 Unregistering device: \(deviceUUID.uuidString)")

        device.isActive = false
        try await device.save(on: db)
    }

    /// Get device by UUID
    public func getDevice(deviceUUID: UUID) async throws -> DeviceRegistrationEntity? {
        return try await DeviceRegistrationEntity.find(deviceUUID, on: db)
    }

    /// Get all devices for a user
    public func getDevices(userId: String) async throws -> [DeviceRegistrationEntity] {
        return try await DeviceRegistrationEntity.query(on: db)
            .filter(\.$userId == userId)
            .filter(\.$isActive == true)
            .all()
    }

    // MARK: - Subscription Management

    /// Update subscriptions for a device (replaces all existing subscriptions)
    public func updateSubscriptions(
        deviceUUID: UUID,
        subscriptions: [(
            leagueId: Int,
            season: Int,
            teamId: Int?,
            preferences: (
                notifyGoals: Bool,
                notifyMatchStart: Bool,
                notifyMatchEnd: Bool,
                notifyRedCards: Bool,
                notifyLineups: Bool,
                notifyVar: Bool,
                matchStartMinutesBefore: Int
            )
        )]
    ) async throws {
        // Verify device exists
        guard let device = try await DeviceRegistrationEntity.find(deviceUUID, on: db) else {
            throw Abort(.notFound, reason: "Device not found")
        }

        logger.info("📱 Updating subscriptions for device: \(deviceUUID.uuidString) (\(subscriptions.count) subscriptions)")

        // Delete existing subscriptions
        try await NotificationSubscriptionEntity.query(on: db)
            .filter(\.$device.$id == deviceUUID)
            .delete()

        // Create new subscriptions
        for sub in subscriptions {
            let subscription = NotificationSubscriptionEntity(
                deviceId: deviceUUID,
                leagueId: sub.leagueId,
                season: sub.season,
                teamId: sub.teamId,
                notifyGoals: sub.preferences.notifyGoals,
                notifyMatchStart: sub.preferences.notifyMatchStart,
                notifyMatchEnd: sub.preferences.notifyMatchEnd,
                notifyRedCards: sub.preferences.notifyRedCards,
                notifyLineups: sub.preferences.notifyLineups,
                notifyVar: sub.preferences.notifyVar,
                matchStartMinutesBefore: sub.preferences.matchStartMinutesBefore
            )

            try await subscription.save(on: db)
        }

        logger.info("✅ Successfully updated subscriptions for device: \(deviceUUID.uuidString)")
    }

    /// Get all subscriptions for a device
    public func getSubscriptions(deviceUUID: UUID) async throws -> [NotificationSubscriptionEntity] {
        return try await NotificationSubscriptionEntity.query(on: db)
            .filter(\.$device.$id == deviceUUID)
            .all()
    }

    /// Get all devices subscribed to a specific league/season
    public func getSubscribedDevices(leagueId: Int, season: Int) async throws -> [DeviceRegistrationEntity] {
        let subscriptions = try await NotificationSubscriptionEntity.query(on: db)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .with(\.$device)
            .all()

        return subscriptions.compactMap { $0.$device.value }
    }

    /// Get all devices subscribed to a specific team
    public func getSubscribedDevices(teamId: Int, leagueId: Int, season: Int) async throws -> [DeviceRegistrationEntity] {
        let subscriptions = try await NotificationSubscriptionEntity.query(on: db)
            .filter(\.$leagueId == leagueId)
            .filter(\.$season == season)
            .filter(\.$teamId == teamId)
            .with(\.$device)
            .all()

        return subscriptions.compactMap { $0.$device.value }
    }

    // MARK: - Cleanup

    /// Remove inactive devices (not active for > 90 days)
    public func cleanupInactiveDevices() async throws {
        let cutoffDate = Date().addingTimeInterval(-90 * 24 * 60 * 60)  // 90 days ago

        let inactiveDevices = try await DeviceRegistrationEntity.query(on: db)
            .group(.or) { group in
                group.filter(\.$isActive == false)
                group.filter(\.$lastActiveAt < cutoffDate)
            }
            .all()

        logger.info("🧹 Cleaning up \(inactiveDevices.count) inactive devices")

        for device in inactiveDevices {
            try await device.delete(on: db)
        }
    }

    /// Remove old notification history (older than 30 days)
    public func cleanupNotificationHistory() async throws {
        let cutoffDate = Date().addingTimeInterval(-30 * 24 * 60 * 60)  // 30 days ago

        let oldHistory = try await NotificationHistoryEntity.query(on: db)
            .filter(\.$sentAt < cutoffDate)
            .all()

        logger.info("🧹 Cleaning up \(oldHistory.count) old notification history records")

        for record in oldHistory {
            try await record.delete(on: db)
        }
    }

    // MARK: - Analytics

    /// Get notification statistics for a device
    public func getNotificationStats(deviceUUID: UUID, days: Int = 7) async throws -> [String: Int] {
        let cutoffDate = Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60))

        let history = try await NotificationHistoryEntity.query(on: db)
            .filter(\.$device.$id == deviceUUID)
            .filter(\.$sentAt >= cutoffDate)
            .all()

        var stats: [String: Int] = [
            "total": history.count,
            "sent": history.filter { $0.status == "sent" }.count,
            "failed": history.filter { $0.status == "failed" }.count
        ]

        // Count by notification type
        for type in ["goal", "red_card", "match_start", "match_end"] {
            stats[type] = history.filter { $0.notificationType == type }.count
        }

        return stats
    }
}
