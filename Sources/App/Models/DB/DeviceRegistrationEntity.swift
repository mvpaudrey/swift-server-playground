import Foundation
import Vapor
import Fluent

/// Device registration entity for push notifications
/// Stores device tokens and metadata for iOS and Android devices
public final class DeviceRegistrationEntity: Model, Content, @unchecked Sendable {
    public static let schema = "device_registrations"

    @ID(key: .id)
    public var id: UUID?

    @Field(key: "user_id")
    var userId: String

    @Field(key: "device_token")
    var deviceToken: String

    @Field(key: "platform")
    var platform: String  // "ios" or "android"

    @OptionalField(key: "device_id")
    var deviceId: String?

    @OptionalField(key: "app_version")
    var appVersion: String?

    @OptionalField(key: "os_version")
    var osVersion: String?

    @Field(key: "language")
    var language: String

    @OptionalField(key: "timezone")
    var timezone: String?

    @Field(key: "is_active")
    var isActive: Bool

    @OptionalField(key: "last_active_at")
    var lastActiveAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    // Relationships
    @Children(for: \.$device)
    var subscriptions: [NotificationSubscriptionEntity]

    public init() {}

    init(
        id: UUID? = nil,
        userId: String,
        deviceToken: String,
        platform: String,
        deviceId: String? = nil,
        appVersion: String? = nil,
        osVersion: String? = nil,
        language: String = "en",
        timezone: String? = nil,
        isActive: Bool = true,
        lastActiveAt: Date? = Date()
    ) {
        self.id = id
        self.userId = userId
        self.deviceToken = deviceToken
        self.platform = platform
        self.deviceId = deviceId
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.language = language
        self.timezone = timezone
        self.isActive = isActive
        self.lastActiveAt = lastActiveAt
    }
}

// MARK: - Migration

struct CreateDeviceRegistrationEntity: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(DeviceRegistrationEntity.schema)
            .id()
            .field("user_id", .string, .required)
            .field("device_token", .string, .required)
            .field("platform", .string, .required)
            .field("device_id", .string)
            .field("app_version", .string)
            .field("os_version", .string)
            .field("language", .string, .required, .sql(.default("en")))
            .field("timezone", .string)
            .field("is_active", .bool, .required, .sql(.default(true)))
            .field("last_active_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "device_token")
            .create()

        // Note: Additional indexes can be created manually if needed for performance
    }

    func revert(on database: any Database) async throws {
        try await database.schema(DeviceRegistrationEntity.schema).delete()
    }
}
