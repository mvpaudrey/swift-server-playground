import Foundation

// Lightweight summary for showing standings next to teams
public struct TeamStandingSummary: Sendable {
    public let rank: Int32
    public let points: Int32
    public let goalsFor: Int32
    public let goalsAgainst: Int32
    public let goalDiff: Int32
    public let group: String

    public init(rank: Int32, points: Int32, goalsFor: Int32, goalsAgainst: Int32, goalDiff: Int32, group: String) {
        self.rank = rank
        self.points = points
        self.goalsFor = goalsFor
        self.goalsAgainst = goalsAgainst
        self.goalDiff = goalDiff
        self.group = group
    }
}

// Actor-based provider with simple in-memory caching by (league, season)
public actor StandingsProvider {
    private let service: AFCONService

    // Cache key format: "leagueId:season" -> teamId -> standing
    private var cache: [String: [Int32: TeamStandingSummary]] = [:]

    public init(service: AFCONService = .shared) {
        self.service = service
    }

    private func cacheKey(leagueId: Int32, season: Int32) -> String {
        "\(leagueId):\(season)"
    }

    // Fetch and cache standings map if needed
    private func loadStandingsIfNeeded(leagueId: Int32, season: Int32) async throws {
        let key = cacheKey(leagueId: leagueId, season: season)
        if cache[key] != nil { return }

        let response = try await service.getStandings(leagueId: leagueId, season: season)
        var mapping: [Int32: TeamStandingSummary] = [:]

        for group in response.groups {
            for s in group.standings {
                let teamId = s.team.id
                let goalsFor = s.all.goals.`for`
                let goalsAgainst = s.all.goals.against
                let summary = TeamStandingSummary(
                    rank: s.rank,
                    points: s.points,
                    goalsFor: goalsFor,
                    goalsAgainst: goalsAgainst,
                    goalDiff: s.goalsDiff,
                    group: s.group
                )
                mapping[teamId] = summary
            }
        }

        cache[key] = mapping
    }

    // Public API: get a team's standing summary
    public func standing(for teamId: Int32, leagueId: Int32, season: Int32) async throws -> TeamStandingSummary? {
        try await loadStandingsIfNeeded(leagueId: leagueId, season: season)
        return cache[cacheKey(leagueId: leagueId, season: season)]?[teamId]
    }

    // Optional: prefetch standings for a screen
    public func prefetch(leagueId: Int32, season: Int32) async throws {
        try await loadStandingsIfNeeded(leagueId: leagueId, season: season)
    }
}

