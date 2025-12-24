import Foundation
import Vapor
import Fluent

/// Tracks active Live Activities and their push tokens
/// Live Activities expire after 8 hours, this entity manages their lifecycle
public final class LiveActivityEntity: Model, Content, @unchecked Sendable {
    public static let schema = "live_activities"

    @ID(key: .id)
    public var id: UUID?

    @Parent(key: "device_id")
    var device: DeviceRegistrationEntity

    @Field(key: "fixture_id")
    var fixtureId: Int

    @Field(key: "activity_id")
    var activityId: String  // iOS ActivityKit ID

    @Field(key: "push_token")
    var pushToken: String  // Push-to-update token from ActivityKit

    @Field(key: "update_frequency")
    var updateFrequency: String  // "every_minute", "goals_only", "major_events", "all_events"

    @Field(key: "is_active")
    var isActive: Bool

    @OptionalField(key: "last_update_at")
    var lastUpdateAt: Date?

    @Field(key: "started_at")
    var startedAt: Date

    @OptionalField(key: "expires_at")
    var expiresAt: Date?  // 8 hours from started_at

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    public init() {}

    init(
        deviceId: UUID,
        fixtureId: Int,
        activityId: String,
        pushToken: String,
        updateFrequency: String = "major_events",
        startedAt: Date = Date()
    ) {
        self.$device.id = deviceId
        self.fixtureId = fixtureId
        self.activityId = activityId
        self.pushToken = pushToken
        self.updateFrequency = updateFrequency
        self.isActive = true
        self.startedAt = startedAt
        self.expiresAt = startedAt.addingTimeInterval(8 * 60 * 60) // 8 hours
    }
}

// MARK: - Migration

public struct CreateLiveActivityEntity: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(LiveActivityEntity.schema)
            .id()
            .field("device_id", .uuid, .required, .references(DeviceRegistrationEntity.schema, "id", onDelete: .cascade))
            .field("fixture_id", .int, .required)
            .field("activity_id", .string, .required)
            .field("push_token", .string, .required)
            .field("update_frequency", .string, .required, .sql(.default("major_events")))
            .field("is_active", .bool, .required, .sql(.default(true)))
            .field("last_update_at", .datetime)
            .field("started_at", .datetime, .required)
            .field("expires_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "device_id", "fixture_id", "activity_id")
            .create()
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(LiveActivityEntity.schema).delete()
    }
}
