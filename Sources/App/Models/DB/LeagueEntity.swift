import Foundation
import Vapor
import Fluent

final class LeagueEntity: Model, Content {
    static let schema = "leagues"

    @ID(key: .id)
    var id: UUID?

    // External API league identifier (unique)
    @Field(key: "api_league_id")
    var apiLeagueId: Int

    @Field(key: "name")
    var name: String

    @Field(key: "type")
    var type: String

    @Field(key: "country_name")
    var countryName: String

    @OptionalField(key: "country_code")
    var countryCode: String?

    @OptionalField(key: "logo")
    var logo: String?

    @OptionalField(key: "current_season")
    var currentSeason: Int?

    @Field(key: "active")
    var active: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        apiLeagueId: Int,
        name: String,
        type: String,
        countryName: String,
        countryCode: String?,
        logo: String?,
        currentSeason: Int?,
        active: Bool
    ) {
        self.id = id
        self.apiLeagueId = apiLeagueId
        self.name = name
        self.type = type
        self.countryName = countryName
        self.countryCode = countryCode
        self.logo = logo
        self.currentSeason = currentSeason
        self.active = active
    }
}

struct CreateLeagueEntity: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(LeagueEntity.schema)
            .id()
            .field("api_league_id", .int, .required)
            .field("name", .string, .required)
            .field("type", .string, .required)
            .field("country_name", .string, .required)
            .field("country_code", .string)
            .field("logo", .string)
            .field("current_season", .int)
            .field("active", .bool, .required, .sql(.default(true)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "api_league_id")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(LeagueEntity.schema).delete()
    }
}
