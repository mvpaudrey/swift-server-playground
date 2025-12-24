import Foundation
import Vapor

// MARK: - Base Response
struct APIFootballResponse<T: Content>: Content {
    let get: String
    let parameters: [String: String]
    let errors: [String]
    let results: Int
    let paging: Paging
    let response: T

    enum CodingKeys: String, CodingKey {
        case get, parameters, errors, results, paging, response
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        get = try container.decode(String.self, forKey: .get)
        if let parameterDict = try? container.decode([String: String].self, forKey: .parameters) {
            parameters = parameterDict
        } else {
            // API can return [] or {} when no parameters
            parameters = [:]
        }
        results = try container.decode(Int.self, forKey: .results)
        paging = try container.decode(Paging.self, forKey: .paging)
        response = try container.decode(T.self, forKey: .response)

        // Handle errors: can be either an array of strings or an empty dictionary
        if let errorArray = try? container.decode([String].self, forKey: .errors) {
            errors = errorArray
        } else {
            // If it's a dictionary (likely empty {}), treat as no errors
            errors = []
        }
    }
}

struct Paging: Content {
    let current: Int
    let total: Int
}

// MARK: - League Models
struct LeagueData: Content {
    let league: LeagueInfo
    let country: CountryInfo
    let seasons: [SeasonInfo]
}

struct LeagueInfo: Content {
    let id: Int
    let name: String
    let type: String
    let logo: String
}

struct CountryInfo: Content {
    let name: String
    let code: String?
    let flag: String?
}

struct SeasonInfo: Content {
    let year: Int
    let start: String
    let end: String
    let current: Bool
    let coverage: CoverageInfo
}

struct CoverageInfo: Content {
    let fixtures: FixtureCoverageInfo
    let standings: Bool
    let players: Bool
    let topScorers: Bool
    let topAssists: Bool
    let topCards: Bool
    let injuries: Bool
    let predictions: Bool
    let odds: Bool

    enum CodingKeys: String, CodingKey {
        case fixtures, standings, players, injuries, predictions, odds
        case topScorers = "top_scorers"
        case topAssists = "top_assists"
        case topCards = "top_cards"
    }
}

struct FixtureCoverageInfo: Content {
    let events: Bool
    let lineups: Bool
    let statisticsFixtures: Bool
    let statisticsPlayers: Bool

    enum CodingKeys: String, CodingKey {
        case events, lineups
        case statisticsFixtures = "statistics_fixtures"
        case statisticsPlayers = "statistics_players"
    }
}

// MARK: - Team Models
struct TeamData: Content {
    let team: TeamInfo
    let venue: VenueInfo
}

struct TeamInfo: Content {
    let id: Int
    let name: String
    let code: String
    let country: String
    let founded: Int
    let national: Bool
    let logo: String
}

struct VenueInfo: Content {
    let id: Int
    let name: String
    let address: String?
    let city: String
    let capacity: Int
    let surface: String
    let image: String
}

// MARK: - Fixture Models
struct FixtureData: Content {
    let fixture: FixtureDetails
    let league: FixtureLeague
    let teams: FixtureTeamsInfo
    let goals: FixtureGoalsInfo
    let score: FixtureScoreInfo
}

struct FixtureDetails: Content {
    let id: Int
    let referee: String?
    let timezone: String
    let date: String
    let timestamp: Int
    let periods: FixturePeriods
    let venue: FixtureVenueInfo
    let status: FixtureStatusInfo
}

struct FixturePeriods: Content {
    let first: Int?
    let second: Int?
}

struct FixtureVenueInfo: Content {
    let id: Int?
    let name: String?
    let city: String?
}

struct FixtureStatusInfo: Content {
    let long: String
    let short: String
    let elapsed: Int?
    let extra: Int?
}

struct FixtureLeague: Content {
    let id: Int
    let name: String
    let country: String
    let logo: String
    let flag: String?
    let season: Int
    let round: String?
}

struct FixtureTeamsInfo: Content {
    let home: FixtureTeamInfo
    let away: FixtureTeamInfo
}

struct FixtureTeamInfo: Content {
    let id: Int
    let name: String
    let logo: String
    let winner: Bool?
}

struct FixtureGoalsInfo: Content {
    let home: Int?
    let away: Int?
}

struct FixtureScoreInfo: Content {
    let halftime: ScoreDetailInfo
    let fulltime: ScoreDetailInfo
    let extratime: ScoreDetailInfo
    let penalty: ScoreDetailInfo
}

struct ScoreDetailInfo: Content {
    let home: Int?
    let away: Int?
}

// MARK: - Fixture Events
struct FixtureEvent: Content {
    let time: EventTime?
    let team: EventTeamInfo?
    let player: EventPlayerInfo?
    let assist: EventPlayerInfo?
    let type: String?
    let detail: String?
    let comments: String?
}

struct EventTime: Content {
    let elapsed: Int?
    let extra: Int?
}

struct EventTeamInfo: Content {
    let id: Int?
    let name: String?
    let logo: String?
}

struct EventPlayerInfo: Content {
    let id: Int?
    let name: String?
}

// MARK: - Fixture Lineups
struct FixtureLineup: Content {
    let team: LineupTeamInfo
    let coach: LineupCoachInfo
    let formation: String?
    let startXI: [LineupPlayerPosition]
    let substitutes: [LineupPlayerPosition]
}

struct LineupTeamInfo: Content {
    let id: Int
    let name: String
    let logo: String
    let colors: TeamColors?
}

struct TeamColors: Content {
    let player: ColorInfo?
    let goalkeeper: ColorInfo?
}

struct ColorInfo: Content {
    let primary: String?
    let number: String?
    let border: String?
}

struct LineupCoachInfo: Content {
    let id: Int?
    let name: String
    let photo: String?
}

struct LineupPlayerPosition: Content {
    let player: LineupPlayer
}

struct LineupPlayer: Content {
    let id: Int
    let name: String
    let number: Int
    let pos: String?
    let grid: String?
}

// MARK: - Head to Head
struct HeadToHeadData: Content {
    let fixture: FixtureDetails
    let league: FixtureLeague
    let teams: FixtureTeamsInfo
    let goals: FixtureGoalsInfo
    let score: FixtureScoreInfo
}

// MARK: - Fixture Statistics
struct FixtureStatistics: Content {
    let team: StatisticsTeamInfo
    let statistics: [StatisticDetail]
}

struct StatisticsTeamInfo: Content {
    let id: Int
    let name: String
    let logo: String
}

struct StatisticDetail: Content {
    let type: String
    let value: StatisticValue?
}

// Custom decoding to handle value being either Int, String, or null
struct StatisticValue: Content {
    let stringValue: String?
    let intValue: Int?

    var displayValue: String {
        if let str = stringValue {
            return str
        } else if let int = intValue {
            return "\(int)"
        }
        return "N/A"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intVal = try? container.decode(Int.self) {
            intValue = intVal
            stringValue = nil
        } else if let strVal = try? container.decode(String.self) {
            stringValue = strVal
            intValue = nil
        } else {
            intValue = nil
            stringValue = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if let intVal = intValue {
            try container.encode(intVal)
        } else if let strVal = stringValue {
            try container.encode(strVal)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - Standings Models
struct StandingsData: Content {
    let league: StandingsLeague
}

struct StandingsLeague: Content {
    let id: Int
    let name: String
    let country: String
    let logo: String
    let flag: String?
    let season: Int
    let standings: [[StandingInfo]]
}

struct StandingInfo: Content {
    let rank: Int
    let team: StandingTeamInfo
    let points: Int
    let goalsDiff: Int
    let group: String
    let form: String?
    let status: String?
    let description: String?
    let all: StandingStatsInfo
    let home: StandingStatsInfo
    let away: StandingStatsInfo
    let update: String

    enum CodingKeys: String, CodingKey {
        case rank, team, points, group, form, status, description, all, home, away, update
        case goalsDiff = "goalsDiff"
    }
}

struct StandingTeamInfo: Content {
    let id: Int
    let name: String
    let logo: String
}

struct StandingStatsInfo: Content {
    let played: Int
    let win: Int
    let draw: Int
    let lose: Int
    let goals: StandingGoalsInfo

    enum CodingKeys: String, CodingKey {
        case played, win, draw, lose, goals
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        played = try container.decodeIfPresent(Int.self, forKey: .played) ?? 0
        win = try container.decodeIfPresent(Int.self, forKey: .win) ?? 0
        draw = try container.decodeIfPresent(Int.self, forKey: .draw) ?? 0
        lose = try container.decodeIfPresent(Int.self, forKey: .lose) ?? 0
        goals = try container.decodeIfPresent(StandingGoalsInfo.self, forKey: .goals) ?? StandingGoalsInfo()
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(played, forKey: .played)
        try container.encode(win, forKey: .win)
        try container.encode(draw, forKey: .draw)
        try container.encode(lose, forKey: .lose)
        try container.encode(goals, forKey: .goals)
    }
}

struct StandingGoalsInfo: Content {
    let `for`: Int
    let against: Int

    enum CodingKeys: String, CodingKey {
        case `for` = "for"
        case against
    }

    init(`for`: Int = 0, against: Int = 0) {
        self.`for` = `for`
        self.against = against
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.`for` = try container.decodeIfPresent(Int.self, forKey: .for) ?? 0
        self.against = try container.decodeIfPresent(Int.self, forKey: .against) ?? 0
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.`for`, forKey: .for)
        try container.encode(against, forKey: .against)
    }
}

// MARK: - Player Models
struct PlayerData: Content {
    let player: PlayerInfo
    let statistics: [PlayerStatistics]
}

struct PlayerInfo: Content {
    let id: Int
    let name: String
    let firstname: String
    let lastname: String
    let age: Int
    let birth: BirthInfo
    let nationality: String
    let height: String?
    let weight: String?
    let injured: Bool
    let photo: String
}

struct BirthInfo: Content {
    let date: String
    let place: String?
    let country: String?
}

struct PlayerStatistics: Content {
    let team: TeamInfo
    let league: LeagueInfo
    let games: PlayerGames
}

struct PlayerGames: Content {
    let position: String?
    let rating: String?
}
