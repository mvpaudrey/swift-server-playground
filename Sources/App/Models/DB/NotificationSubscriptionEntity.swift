import Foundation
import Vapor
import Fluent

/// Notification subscription entity
/// Defines which leagues, teams, and events a device wants to receive notifications for
public final class NotificationSubscriptionEntity: Model, Content, @unchecked Sendable {
    public static let schema = "notification_subscriptions"

    @ID(key: .id)
    public var id: UUID?

    @Parent(key: "device_id")
    var device: DeviceRegistrationEntity

    @Field(key: "league_id")
    var leagueId: Int

    @Field(key: "season")
    var season: Int

    @OptionalField(key: "team_id")
    var teamId: Int?  // NULL = all teams in the league

    // Notification preferences
    @Field(key: "notify_goals")
    var notifyGoals: Bool

    @Field(key: "notify_match_start")
    var notifyMatchStart: Bool

    @Field(key: "notify_match_end")
    var notifyMatchEnd: Bool

    @Field(key: "notify_red_cards")
    var notifyRedCards: Bool

    @Field(key: "notify_lineups")
    var notifyLineups: Bool

    @Field(key: "notify_var")
    var notifyVar: Bool

    @Field(key: "match_start_minutes_before")
    var matchStartMinutesBefore: Int

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    public init() {}

    init(
        id: UUID? = nil,
        deviceId: UUID,
        leagueId: Int,
        season: Int,
        teamId: Int? = nil,
        notifyGoals: Bool = true,
        notifyMatchStart: Bool = true,
        notifyMatchEnd: Bool = true,
        notifyRedCards: Bool = true,
        notifyLineups: Bool = false,
        notifyVar: Bool = false,
        matchStartMinutesBefore: Int = 15
    ) {
        self.id = id
        self.$device.id = deviceId
        self.leagueId = leagueId
        self.season = season
        self.teamId = teamId
        self.notifyGoals = notifyGoals
        self.notifyMatchStart = notifyMatchStart
        self.notifyMatchEnd = notifyMatchEnd
        self.notifyRedCards = notifyRedCards
        self.notifyLineups = notifyLineups
        self.notifyVar = notifyVar
        self.matchStartMinutesBefore = matchStartMinutesBefore
    }
}

// MARK: - Migration

struct CreateNotificationSubscriptionEntity: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(NotificationSubscriptionEntity.schema)
            .id()
            .field("device_id", .uuid, .required, .references(DeviceRegistrationEntity.schema, "id", onDelete: .cascade))
            .field("league_id", .int, .required)
            .field("season", .int, .required)
            .field("team_id", .int)
            .field("notify_goals", .bool, .required, .sql(.default(true)))
            .field("notify_match_start", .bool, .required, .sql(.default(true)))
            .field("notify_match_end", .bool, .required, .sql(.default(true)))
            .field("notify_red_cards", .bool, .required, .sql(.default(true)))
            .field("notify_lineups", .bool, .required, .sql(.default(false)))
            .field("notify_var", .bool, .required, .sql(.default(false)))
            .field("match_start_minutes_before", .int, .required, .sql(.default(15)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "device_id", "league_id", "season", "team_id")
            .create()

    }

    func revert(on database: any Database) async throws {
        try await database.schema(NotificationSubscriptionEntity.schema).delete()
    }
}
