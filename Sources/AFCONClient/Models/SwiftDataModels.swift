import Foundation

// MARK: - Client Models (Codable structs for Swift Package Manager compatibility)

/// Model for League information
public struct LeagueModel: Codable, Identifiable, Hashable {
    public var id: Int
    public var name: String
    public var type: String
    public var logoURL: String
    public var countryName: String
    public var countryCode: String
    public var countryFlagURL: String
    public var season: Int
    public var lastUpdated: Date

    public init(
        id: Int,
        name: String,
        type: String,
        logoURL: String,
        countryName: String,
        countryCode: String,
        countryFlagURL: String,
        season: Int,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.logoURL = logoURL
        self.countryName = countryName
        self.countryCode = countryCode
        self.countryFlagURL = countryFlagURL
        self.season = season
        self.lastUpdated = lastUpdated
    }
}

/// Model for Team
public struct TeamModel: Codable, Identifiable, Hashable {
    public var id: Int
    public var name: String
    public var code: String
    public var country: String
    public var founded: Int
    public var logoURL: String
    public var venueName: String
    public var venueCity: String
    public var venueCapacity: Int
    public var season: Int
    public var lastUpdated: Date

    public init(
        id: Int,
        name: String,
        code: String,
        country: String,
        founded: Int,
        logoURL: String,
        venueName: String,
        venueCity: String,
        venueCapacity: Int,
        season: Int,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.country = country
        self.founded = founded
        self.logoURL = logoURL
        self.venueName = venueName
        self.venueCity = venueCity
        self.venueCapacity = venueCapacity
        self.season = season
        self.lastUpdated = lastUpdated
    }
}

/// Model for Fixture
public struct FixtureModel: Codable, Identifiable, Hashable {
    public var id: Int
    public var referee: String
    public var timezone: String
    public var date: Date
    public var timestamp: Int64
    public var venueName: String
    public var venueCity: String

    // Teams
    public var homeTeamId: Int
    public var homeTeamName: String
    public var homeTeamLogoURL: String
    public var awayTeamId: Int
    public var awayTeamName: String
    public var awayTeamLogoURL: String

    // Goals
    public var homeGoals: Int
    public var awayGoals: Int

    // Status
    public var statusLong: String
    public var statusShort: String
    public var statusElapsed: Int

    // League
    public var leagueId: Int
    public var leagueName: String
    public var leagueSeason: Int
    public var leagueRound: String

    public var lastUpdated: Date

    public init(
        id: Int,
        referee: String,
        timezone: String,
        date: Date,
        timestamp: Int64,
        venueName: String,
        venueCity: String,
        homeTeamId: Int,
        homeTeamName: String,
        homeTeamLogoURL: String,
        awayTeamId: Int,
        awayTeamName: String,
        awayTeamLogoURL: String,
        homeGoals: Int,
        awayGoals: Int,
        statusLong: String,
        statusShort: String,
        statusElapsed: Int,
        leagueId: Int,
        leagueName: String,
        leagueSeason: Int,
        leagueRound: String,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.referee = referee
        self.timezone = timezone
        self.date = date
        self.timestamp = timestamp
        self.venueName = venueName
        self.venueCity = venueCity
        self.homeTeamId = homeTeamId
        self.homeTeamName = homeTeamName
        self.homeTeamLogoURL = homeTeamLogoURL
        self.awayTeamId = awayTeamId
        self.awayTeamName = awayTeamName
        self.awayTeamLogoURL = awayTeamLogoURL
        self.homeGoals = homeGoals
        self.awayGoals = awayGoals
        self.statusLong = statusLong
        self.statusShort = statusShort
        self.statusElapsed = statusElapsed
        self.leagueId = leagueId
        self.leagueName = leagueName
        self.leagueSeason = leagueSeason
        self.leagueRound = leagueRound
        self.lastUpdated = lastUpdated
    }
}

/// Model for Standings
public struct StandingsModel: Codable, Identifiable, Hashable {
    public var id: String  // "{leagueId}_{season}_{teamId}"
    public var leagueId: Int
    public var season: Int
    public var groupName: String

    // Team info
    public var teamId: Int
    public var teamName: String
    public var teamLogoURL: String

    // Stats
    public var rank: Int
    public var points: Int
    public var played: Int
    public var win: Int
    public var draw: Int
    public var lose: Int
    public var goalsFor: Int
    public var goalsAgainst: Int
    public var goalsDiff: Int

    public var form: String
    public var lastUpdated: Date

    public init(
        id: String,
        leagueId: Int,
        season: Int,
        groupName: String,
        teamId: Int,
        teamName: String,
        teamLogoURL: String,
        rank: Int,
        points: Int,
        played: Int,
        win: Int,
        draw: Int,
        lose: Int,
        goalsFor: Int,
        goalsAgainst: Int,
        goalsDiff: Int,
        form: String,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.leagueId = leagueId
        self.season = season
        self.groupName = groupName
        self.teamId = teamId
        self.teamName = teamName
        self.teamLogoURL = teamLogoURL
        self.rank = rank
        self.points = points
        self.played = played
        self.win = win
        self.draw = draw
        self.lose = lose
        self.goalsFor = goalsFor
        self.goalsAgainst = goalsAgainst
        self.goalsDiff = goalsDiff
        self.form = form
        self.lastUpdated = lastUpdated
    }
}
