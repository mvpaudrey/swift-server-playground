import Foundation
import Vapor

/// Client for interacting with API-Football REST API
public final class APIFootballClient {
    private let apiKey: String
    private let baseURL: String
    private let client: Client
    private let logger: Logger

    public init(apiKey: String, client: Client, logger: Logger) {
        self.apiKey = apiKey
        self.baseURL = "https://v3.football.api-sports.io"
        self.client = client
        self.logger = logger
    }

    // MARK: - Private Helper Methods

    private func makeRequest<T: Codable>(
        endpoint: String,
        parameters: [String: String] = [:]
    ) async throws -> APIFootballResponse<T> {
        var urlString = "\(baseURL)/\(endpoint)"

        // Add query parameters
        if !parameters.isEmpty {
            let queryItems = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            urlString += "?\(queryItems)"
        }

        let url = URI(string: urlString)

        logger.info("API Football Request: \(urlString)")

        let response = try await client.get(url) { req in
            req.headers.add(name: "x-apisports-key", value: self.apiKey)
        }

        guard response.status == .ok else {
            logger.error("API Football Error: \(response.status)")
            throw Abort(response.status, reason: "API Football request failed")
        }

        do {
            let apiResponse = try response.content.decode(APIFootballResponse<T>.self)

            if !apiResponse.errors.isEmpty {
                logger.error("API Football Errors: \(apiResponse.errors)")
                throw Abort(.badGateway, reason: "API returned errors: \(apiResponse.errors.joined(separator: ", "))")
            }

            logger.info("API Football Response: \(apiResponse.results) results")
            return apiResponse
        } catch {
            logger.error("Failed to decode API response: \(error)")
            throw Abort(.internalServerError, reason: "Failed to decode API response: \(error)")
        }
    }

    // MARK: - Public API Methods

    /// Get league information
    func getLeague(id: Int, season: Int) async throws -> LeagueData {
        let response: APIFootballResponse<[LeagueData]> = try await makeRequest(
            endpoint: "leagues",
            parameters: ["id": "\(id)", "season": "\(season)"]
        )

        guard let league = response.response.first else {
            throw Abort(.notFound, reason: "League not found")
        }

        return league
    }

    /// List/search leagues (optionally filter by name/current/season/country/type)
    /// API docs: GET /leagues with optional params
    func listLeagues(
        name: String? = nil,
        current: Bool? = nil,
        season: Int? = nil,
        country: String? = nil,
        type: String? = nil
    ) async throws -> [LeagueData] {
        var params: [String: String] = [:]
        if let name { params["name"] = name }
        if let current { params["current"] = current ? "true" : "false" }
        if let season { params["season"] = "\(season)" }
        if let country { params["country"] = country }
        if let type { params["type"] = type }

        let response: APIFootballResponse<[LeagueData]> = try await makeRequest(
            endpoint: "leagues",
            parameters: params
        )
        return response.response
    }

    /// Get all teams for a league and season
    func getTeams(leagueId: Int, season: Int) async throws -> [TeamData] {
        let response: APIFootballResponse<[TeamData]> = try await makeRequest(
            endpoint: "teams",
            parameters: ["league": "\(leagueId)", "season": "\(season)"]
        )

        return response.response
    }

    /// Get fixtures for a league and season
    func getFixtures(
        leagueId: Int,
        season: Int,
        date: String? = nil,
        teamId: Int? = nil,
        live: Bool = false
    ) async throws -> [FixtureData] {
        var params: [String: String] = [
            "league": "\(leagueId)",
            "season": "\(season)"
        ]

        if let date = date {
            params["date"] = date
        }

        if let teamId = teamId {
            params["team"] = "\(teamId)"
        }

        if live {
            params["live"] = "all"
        }

        let response: APIFootballResponse<[FixtureData]> = try await makeRequest(
            endpoint: "fixtures",
            parameters: params
        )

        return response.response
    }

    /// Get live fixtures for a league
    func getLiveFixtures(leagueId: Int) async throws -> [FixtureData] {
        let response: APIFootballResponse<[FixtureData]> = try await makeRequest(
            endpoint: "fixtures",
            parameters: ["league": "\(leagueId)", "live": "all"]
        )

        return response.response
    }

    /// Get fixture by ID
    func getFixtureById(fixtureId: Int) async throws -> FixtureData {
        let response: APIFootballResponse<[FixtureData]> = try await makeRequest(
            endpoint: "fixtures",
            parameters: ["id": "\(fixtureId)"]
        )

        guard let fixture = response.response.first else {
            throw Abort(.notFound, reason: "Fixture not found")
        }

        return fixture
    }

    /// Get fixture events
    func getFixtureEvents(fixtureId: Int) async throws -> [FixtureEvent] {
        let response: APIFootballResponse<[FixtureEvent]> = try await makeRequest(
            endpoint: "fixtures/events",
            parameters: ["fixture": "\(fixtureId)"]
        )

        return response.response
    }

    /// Get fixtures by date
    func getFixturesByDate(date: String) async throws -> [FixtureData] {
        let response: APIFootballResponse<[FixtureData]> = try await makeRequest(
            endpoint: "fixtures",
            parameters: ["date": date]
        )

        return response.response
    }

    /// Get standings for a league and season
    func getStandings(leagueId: Int, season: Int) async throws -> [StandingsData] {
        let response: APIFootballResponse<[StandingsData]> = try await makeRequest(
            endpoint: "standings",
            parameters: ["league": "\(leagueId)", "season": "\(season)"]
        )

        return response.response
    }

    /// Get team details
    func getTeamDetails(teamId: Int) async throws -> TeamData {
        let response: APIFootballResponse<[TeamData]> = try await makeRequest(
            endpoint: "teams",
            parameters: ["id": "\(teamId)"]
        )

        guard let team = response.response.first else {
            throw Abort(.notFound, reason: "Team not found")
        }

        return team
    }

    /// Get players for a team and season
    func getPlayers(teamId: Int, season: Int) async throws -> [PlayerData] {
        let response: APIFootballResponse<[PlayerData]> = try await makeRequest(
            endpoint: "players",
            parameters: ["team": "\(teamId)", "season": "\(season)"]
        )

        return response.response
    }

    /// Get fixture lineups
    func getFixtureLineups(fixtureId: Int) async throws -> [FixtureLineup] {
        let response: APIFootballResponse<[FixtureLineup]> = try await makeRequest(
            endpoint: "fixtures/lineups",
            parameters: ["fixture": "\(fixtureId)"]
        )

        return response.response
    }

    /// Get head to head between two teams
    func getHeadToHead(team1: Int, team2: Int, last: Int? = nil) async throws -> [HeadToHeadData] {
        var params: [String: String] = [
            "h2h": "\(team1)-\(team2)"
        ]

        if let last = last {
            params["last"] = "\(last)"
        }

        let response: APIFootballResponse<[HeadToHeadData]> = try await makeRequest(
            endpoint: "fixtures/headtohead",
            parameters: params
        )

        return response.response
    }

    /// Get fixture statistics
    func getFixtureStatistics(fixtureId: Int) async throws -> [FixtureStatistics] {
        let response: APIFootballResponse<[FixtureStatistics]> = try await makeRequest(
            endpoint: "fixtures/statistics",
            parameters: ["fixture": "\(fixtureId)"]
        )

        return response.response
    }

}
