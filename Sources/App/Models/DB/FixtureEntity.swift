import Foundation
import Vapor
import Fluent
import SQLKit

public final class FixtureEntity: Model, Content, @unchecked Sendable {
    public static let schema = "fixtures"

    @ID(key: .id)
    public var id: UUID?

    // External API fixture identifier (unique)
    @Field(key: "api_fixture_id")
    var apiFixtureId: Int

    // League and season
    @Field(key: "league_id")
    var leagueId: Int

    @Field(key: "season")
    var season: Int

    // Fixture details
    @OptionalField(key: "referee")
    var referee: String?

    @Field(key: "timezone")
    var timezone: String

    @Field(key: "date")
    var date: Date

    @Field(key: "timestamp")
    var timestamp: Int

    // Venue
    @Field(key: "venue_id")
    var venueId: Int

    @Field(key: "venue_name")
    var venueName: String

    @OptionalField(key: "venue_city")
    var venueCity: String?

    // Status
    @Field(key: "status_long")
    var statusLong: String

    @Field(key: "status_short")
    var statusShort: String

    @OptionalField(key: "status_elapsed")
    var statusElapsed: Int?
    
    @OptionalField(key: "status_extra")
    var statusExtra: Int?

    // Home Team
    @Field(key: "home_team_id")
    var homeTeamId: Int

    @Field(key: "home_team_name")
    var homeTeamName: String

    @OptionalField(key: "home_team_logo")
    var homeTeamLogo: String?

    @OptionalField(key: "home_team_winner")
    var homeTeamWinner: Bool?

    // Away Team
    @Field(key: "away_team_id")
    var awayTeamId: Int

    @Field(key: "away_team_name")
    var awayTeamName: String

    @OptionalField(key: "away_team_logo")
    var awayTeamLogo: String?

    @OptionalField(key: "away_team_winner")
    var awayTeamWinner: Bool?

    // Goals
    @OptionalField(key: "home_goals")
    var homeGoals: Int?

    @OptionalField(key: "away_goals")
    var awayGoals: Int?

    // Score details
    @OptionalField(key: "halftime_home")
    var halftimeHome: Int?

    @OptionalField(key: "halftime_away")
    var halftimeAway: Int?

    @OptionalField(key: "fulltime_home")
    var fulltimeHome: Int?

    @OptionalField(key: "fulltime_away")
    var fulltimeAway: Int?
    
    @OptionalField(key: "extratime_home")
    var extratimeHome: Int?
    
    @OptionalField(key: "extratime_away")
    var extratimeAway: Int?
    
    @OptionalField(key: "penalty_home")
    var penaltyHome: Int?
    
    @OptionalField(key: "penalty_away")
    var penaltyAway: Int?

    // Periods
    @OptionalField(key: "period_first")
    var periodFirst: Int?

    @OptionalField(key: "period_second")
    var periodSecond: Int?

    // Metadata
    @Field(key: "competition")
    var competition: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    public init() {}

    init(
        id: UUID? = nil,
        apiFixtureId: Int,
        leagueId: Int,
        season: Int,
        referee: String?,
        timezone: String,
        date: Date,
        timestamp: Int,
        venueId: Int,
        venueName: String,
        venueCity: String?,
        statusLong: String,
        statusShort: String,
        statusElapsed: Int?,
        statusExtra: Int?,
        homeTeamId: Int,
        homeTeamName: String,
        homeTeamLogo: String?,
        homeTeamWinner: Bool?,
        awayTeamId: Int,
        awayTeamName: String,
        awayTeamLogo: String?,
        awayTeamWinner: Bool?,
        homeGoals: Int?,
        awayGoals: Int?,
        halftimeHome: Int?,
        halftimeAway: Int?,
        fulltimeHome: Int?,
        fulltimeAway: Int?,
        extratimeHome: Int?,
        extratimeAway: Int?,
        penaltyHome: Int?,
        penaltyAway: Int?,
        periodFirst: Int?,
        periodSecond: Int?,
        competition: String
    ) {
        self.id = id
        self.apiFixtureId = apiFixtureId
        self.leagueId = leagueId
        self.season = season
        self.referee = referee
        self.timezone = timezone
        self.date = date
        self.timestamp = timestamp
        self.venueId = venueId
        self.venueName = venueName
        self.venueCity = venueCity
        self.statusLong = statusLong
        self.statusShort = statusShort
        self.statusElapsed = statusElapsed
        self.statusExtra = statusExtra
        self.homeTeamId = homeTeamId
        self.homeTeamName = homeTeamName
        self.homeTeamLogo = homeTeamLogo
        self.homeTeamWinner = homeTeamWinner
        self.awayTeamId = awayTeamId
        self.awayTeamName = awayTeamName
        self.awayTeamLogo = awayTeamLogo
        self.awayTeamWinner = awayTeamWinner
        self.homeGoals = homeGoals
        self.awayGoals = awayGoals
        self.halftimeHome = halftimeHome
        self.halftimeAway = halftimeAway
        self.fulltimeHome = fulltimeHome
        self.fulltimeAway = fulltimeAway
        self.extratimeHome = extratimeHome
        self.extratimeAway = extratimeAway
        self.penaltyHome = penaltyHome
        self.penaltyAway = penaltyAway
        self.periodFirst = periodFirst
        self.periodSecond = periodSecond
        self.competition = competition
    }
}

// MARK: - Migration
struct CreateFixtureEntity: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(FixtureEntity.schema)
            .id()
            .field("api_fixture_id", .int, .required)
            .field("league_id", .int, .required)
            .field("season", .int, .required)
            .field("referee", .string)
            .field("timezone", .string, .required)
            .field("date", .datetime, .required)
            .field("timestamp", .int, .required)
            .field("venue_id", .int, .required)
            .field("venue_name", .string, .required)
            .field("venue_city", .string)
            .field("status_long", .string, .required)
            .field("status_short", .string, .required)
            .field("status_elapsed", .int)
            .field("status_extra", .int)
            .field("home_team_id", .int, .required)
            .field("home_team_name", .string, .required)
            .field("home_team_logo", .string)
            .field("home_team_winner", .bool)
            .field("away_team_id", .int, .required)
            .field("away_team_name", .string, .required)
            .field("away_team_logo", .string)
            .field("away_team_winner", .bool)
            .field("home_goals", .int)
            .field("away_goals", .int)
            .field("halftime_home", .int)
            .field("halftime_away", .int)
            .field("fulltime_home", .int)
            .field("fulltime_away", .int)
            .field("extratime_home", .int)
            .field("extratime_away", .int)
            .field("penalty_home", .int)
            .field("penalty_away", .int)
            .field("period_first", .int)
            .field("period_second", .int)
            .field("competition", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "api_fixture_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(FixtureEntity.schema).delete()
    }
}

struct AddFixtureScoreExtras: AsyncMigration {
    // No-op: columns are added by EnsureFixtureScoreExtras using IF NOT EXISTS
    func prepare(on database: any Database) async throws {}
    func revert(on database: any Database) async throws {}
}

struct EnsureFixtureScoreExtras: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let columns = ["status_extra", "extratime_home", "extratime_away", "penalty_home", "penalty_away"]
        for column in columns {
            try await (database as! any SQLDatabase)
                .raw("ALTER TABLE fixtures ADD COLUMN IF NOT EXISTS \"\(raw: column)\" BIGINT")
                .run()
        }
    }

    func revert(on database: any Database) async throws {
        try await database.schema(FixtureEntity.schema)
            .deleteField("status_extra")
            .deleteField("extratime_home")
            .deleteField("extratime_away")
            .deleteField("penalty_home")
            .deleteField("penalty_away")
            .update()
    }
}
