import Foundation
import Vapor
import Fluent

/// Notification history entity
/// Tracks all sent notifications for debugging and analytics
public final class NotificationHistoryEntity: Model, Content, @unchecked Sendable {
    public static let schema = "notification_history"

    @ID(key: .id)
    public var id: UUID?

    @OptionalParent(key: "device_id")
    var device: DeviceRegistrationEntity?

    @Field(key: "fixture_id")
    var fixtureId: Int

    @Field(key: "notification_type")
    var notificationType: String  // 'goal', 'match_start', 'match_end', 'red_card'

    @OptionalField(key: "payload")
    var payload: String?  // JSON string

    @Field(key: "platform")
    var platform: String  // 'ios' or 'android'

    @Timestamp(key: "sent_at", on: .create)
    var sentAt: Date?

    @Field(key: "status")
    var status: String  // 'sent', 'failed', 'invalid_token'

    @OptionalField(key: "error_message")
    var errorMessage: String?

    @OptionalField(key: "response_code")
    var responseCode: Int?

    public init() {}

    init(
        id: UUID? = nil,
        deviceId: UUID?,
        fixtureId: Int,
        notificationType: String,
        payload: String? = nil,
        platform: String,
        status: String = "sent",
        errorMessage: String? = nil,
        responseCode: Int? = nil
    ) {
        self.id = id
        self.$device.id = deviceId
        self.fixtureId = fixtureId
        self.notificationType = notificationType
        self.payload = payload
        self.platform = platform
        self.status = status
        self.errorMessage = errorMessage
        self.responseCode = responseCode
    }
}

// MARK: - Migration

struct CreateNotificationHistoryEntity: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(NotificationHistoryEntity.schema)
            .id()
            .field("device_id", .uuid, .references(DeviceRegistrationEntity.schema, "id", onDelete: .setNull))
            .field("fixture_id", .int, .required)
            .field("notification_type", .string, .required)
            .field("payload", .json)
            .field("platform", .string, .required)
            .field("sent_at", .datetime)
            .field("status", .string, .required, .sql(.default("sent")))
            .field("error_message", .string)
            .field("response_code", .int)
            .create()

    }

    func revert(on database: any Database) async throws {
        try await database.schema(NotificationHistoryEntity.schema).delete()
    }
}
