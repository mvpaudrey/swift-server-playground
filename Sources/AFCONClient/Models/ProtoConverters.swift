import Foundation
#if canImport(SwiftData)
import SwiftData

// MARK: - Proto to SwiftData Converters

@available(macOS 15.0, iOS 18.0, *)
extension LeagueModel {
    /// Convert from gRPC LeagueResponse to SwiftData LeagueModel
    static func from(proto: Afcon_LeagueResponse, season: Int) -> LeagueModel {
        return LeagueModel(
            id: Int(proto.league.id),
            name: proto.league.name,
            type: proto.league.type,
            logoURL: proto.league.logo,
            countryName: proto.country.name,
            countryCode: proto.country.code,
            countryFlagURL: proto.country.flag,
            season: season
        )
    }
}

@available(macOS 15.0, iOS 18.0, *)
extension TeamModel {
    /// Convert from gRPC TeamInfo to SwiftData TeamModel
    static func from(proto: Afcon_TeamInfo, season: Int) -> TeamModel {
        return TeamModel(
            id: Int(proto.team.id),
            name: proto.team.name,
            code: proto.team.code,
            country: proto.team.country,
            founded: Int(proto.team.founded),
            logoURL: proto.team.logo,
            venueName: proto.venue.name,
            venueCity: proto.venue.city,
            venueCapacity: Int(proto.venue.capacity),
            season: season
        )
    }
}

@available(macOS 15.0, iOS 18.0, *)
extension FixtureModel {
    /// Convert from gRPC Fixture to SwiftData FixtureModel
    static func from(proto: Afcon_Fixture) -> FixtureModel {
        return FixtureModel(
            id: Int(proto.id),
            referee: proto.referee,
            timezone: proto.timezone,
            date: Date(timeIntervalSince1970: TimeInterval(proto.timestamp)),
            timestamp: Int64(proto.timestamp),
            venueName: proto.venue.name,
            venueCity: proto.venue.city,
            homeTeamId: Int(proto.teams.home.id),
            homeTeamName: proto.teams.home.name,
            homeTeamLogoURL: proto.teams.home.logo,
            awayTeamId: Int(proto.teams.away.id),
            awayTeamName: proto.teams.away.name,
            awayTeamLogoURL: proto.teams.away.logo,
            homeGoals: Int(proto.goals.home),
            awayGoals: Int(proto.goals.away),
            statusLong: proto.status.long,
            statusShort: proto.status.short,
            statusElapsed: Int(proto.status.elapsed),
            leagueId: Int(proto.league.id),
            leagueName: proto.league.name,
            leagueSeason: Int(proto.league.season),
            leagueRound: proto.league.round
        )
    }
}

@available(macOS 15.0, iOS 18.0, *)
extension StandingsModel {
    /// Convert from gRPC Standing to SwiftData StandingsModel
    static func from(proto: Afcon_Standing, leagueId: Int, season: Int, groupName: String) -> StandingsModel {
        let id = "\(leagueId)_\(season)_\(proto.team.id)"

        return StandingsModel(
            id: id,
            leagueId: leagueId,
            season: season,
            groupName: groupName,
            teamId: Int(proto.team.id),
            teamName: proto.team.name,
            teamLogoURL: proto.team.logo,
            rank: Int(proto.rank),
            points: Int(proto.points),
            played: Int(proto.all.played),
            win: Int(proto.all.win),
            draw: Int(proto.all.draw),
            lose: Int(proto.all.lose),
            goalsFor: Int(proto.all.goals.for),
            goalsAgainst: Int(proto.all.goals.against),
            goalsDiff: Int(proto.goalsDiff),
            form: proto.form
        )
    }
}

// MARK: - SwiftData to Proto Converters (for reverse mapping if needed)

@available(macOS 15.0, iOS 18.0, *)
extension Afcon_Fixture {
    /// Convert from SwiftData FixtureModel back to proto (useful for display)
    static func from(model: FixtureModel) -> Afcon_Fixture {
        var fixture = Afcon_Fixture()

        // Fixture info
        fixture.id = Int32(model.id)
        fixture.referee = model.referee
        fixture.timezone = model.timezone
        fixture.timestamp = Int32(model.timestamp)
        fixture.venue.name = model.venueName
        fixture.venue.city = model.venueCity

        // Teams
        fixture.teams.home.id = Int32(model.homeTeamId)
        fixture.teams.home.name = model.homeTeamName
        fixture.teams.home.logo = model.homeTeamLogoURL
        fixture.teams.away.id = Int32(model.awayTeamId)
        fixture.teams.away.name = model.awayTeamName
        fixture.teams.away.logo = model.awayTeamLogoURL

        // Goals
        fixture.goals.home = Int32(model.homeGoals)
        fixture.goals.away = Int32(model.awayGoals)

        // Status
        fixture.status.long = model.statusLong
        fixture.status.short = model.statusShort
        fixture.status.elapsed = Int32(model.statusElapsed)

        // League
        fixture.league.id = Int32(model.leagueId)
        fixture.league.name = model.leagueName
        fixture.league.season = Int32(model.leagueSeason)
        fixture.league.round = model.leagueRound

        return fixture
    }
}
#endif
