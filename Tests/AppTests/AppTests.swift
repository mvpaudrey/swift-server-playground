import XCTest
import XCTVapor
@testable import App

final class AppTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = Application(.testing)
        try await configure(app)
    }

    override func tearDown() async throws {
        app.shutdown()
    }

    // MARK: - Health Check Tests

    func testHealthEndpoint() async throws {
        try await app.test(.GET, "health") { res in
            XCTAssertEqual(res.status, .ok)
            let response = try res.content.decode([String: String].self)
            XCTAssertEqual(response["status"], "healthy")
            XCTAssertEqual(response["service"], "AFCON Middleware")
        }
    }

    // MARK: - API Football Client Tests

    func testAPIFootballClientLeague() async throws {
        let client: APIFootballClient = app.getService()

        do {
            let league = try await client.getLeague(id: 6, season: 2025)

            XCTAssertEqual(league.league.id, 6)
            XCTAssertEqual(league.league.name, "Africa Cup of Nations")
            XCTAssertEqual(league.league.type, "Cup")
            XCTAssertFalse(league.seasons.isEmpty)
        } catch {
            XCTFail("Failed to fetch league: \(error)")
        }
    }

    func testAPIFootballClientTeams() async throws {
        let client: APIFootballClient = app.getService()

        do {
            let teams = try await client.getTeams(leagueId: 6, season: 2025)

            XCTAssertFalse(teams.isEmpty)
            XCTAssertEqual(teams.count, 24) // AFCON has 24 teams

            // Verify team structure
            let firstTeam = teams[0]
            XCTAssertFalse(firstTeam.team.name.isEmpty)
            XCTAssertFalse(firstTeam.team.code.isEmpty)
            XCTAssertTrue(firstTeam.team.national)
        } catch {
            XCTFail("Failed to fetch teams: \(error)")
        }
    }

    // MARK: - Cache Service Tests

    func testCacheServiceSetAndGet() async throws {
        let cache: CacheService = app.getService()

        struct TestData: Codable, Equatable {
            let id: Int
            let name: String
        }

        let testData = TestData(id: 1, name: "Test")
        let key = "test:key:1"

        // Set cache
        try await cache.set(key: key, value: testData, ttl: 60)

        // Get cache
        let retrieved: TestData? = try await cache.get(key: key)

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved, testData)

        // Clean up
        try await cache.delete(key: key)
    }

    func testCacheServiceExpiration() async throws {
        let cache: CacheService = app.getService()

        let testData = ["test": "data"]
        let key = "test:expiration"

        // Set cache with 1 second TTL
        try await cache.set(key: key, value: testData, ttl: 1)

        // Should exist immediately
        let immediate: [String: String]? = try await cache.get(key: key)
        XCTAssertNotNil(immediate)

        // Wait for expiration
        try await Task.sleep(nanoseconds: 2_000_000_000)

        // Should be expired
        let expired: [String: String]? = try await cache.get(key: key)
        XCTAssertNil(expired)
    }

    // MARK: - HTTP Route Tests

    func testLeagueEndpoint() async throws {
        try await app.test(.GET, "api/v1/league/6/season/2025") { res in
            XCTAssertEqual(res.status, .ok)

            let league = try res.content.decode(LeagueData.self)
            XCTAssertEqual(league.league.id, 6)
            XCTAssertEqual(league.league.name, "Africa Cup of Nations")
        }
    }

    func testTeamsEndpoint() async throws {
        try await app.test(.GET, "api/v1/league/6/season/2025/teams") { res in
            XCTAssertEqual(res.status, .ok)

            let teams = try res.content.decode([TeamData].self)
            XCTAssertFalse(teams.isEmpty)
            XCTAssertEqual(teams.count, 24)
        }
    }

    func testInvalidLeagueEndpoint() async throws {
        try await app.test(.GET, "api/v1/league/99999/season/2025") { res in
            // Should return an error status
            XCTAssertNotEqual(res.status, .ok)
        }
    }

    // MARK: - Service Provider Tests

    func testServiceProviderLeagueConversion() {
        let apiClient: APIFootballClient = app.getService()
        let cache: CacheService = app.getService()

        let provider = AFCONServiceProvider(
            apiClient: apiClient,
            cache: cache,
            logger: app.logger
        )

        // Create sample data
        let leagueData = LeagueData(
            league: LeagueInfo(id: 6, name: "AFCON", type: "Cup", logo: "logo.png"),
            country: CountryInfo(name: "World", code: nil, flag: nil),
            seasons: [
                SeasonInfo(
                    year: 2025,
                    start: "2025-12-21",
                    end: "2025-12-31",
                    current: true,
                    coverage: CoverageInfo(
                        fixtures: FixtureCoverageInfo(
                            events: true,
                            lineups: true,
                            statisticsFixtures: true,
                            statisticsPlayers: true
                        ),
                        standings: true,
                        players: true,
                        topScorers: true,
                        topAssists: true,
                        topCards: true,
                        injuries: false,
                        predictions: true,
                        odds: false
                    )
                )
            ]
        )

        // Test conversion
        let grpcResponse = provider.convertLeagueResponse(leagueData)

        XCTAssertEqual(grpcResponse.league.id, 6)
        XCTAssertEqual(grpcResponse.league.name, "AFCON")
        XCTAssertEqual(grpcResponse.league.type, "Cup")
        XCTAssertEqual(grpcResponse.country.name, "World")
        XCTAssertEqual(grpcResponse.seasons.count, 1)
        XCTAssertEqual(grpcResponse.seasons[0].year, 2025)
        XCTAssertTrue(grpcResponse.seasons[0].current)
    }

    // MARK: - Performance Tests

    func testCachePerformance() async throws {
        let cache: CacheService = app.getService()

        measure {
            Task {
                for i in 0..<100 {
                    let key = "perf:test:\(i)"
                    let data = ["index": "\(i)"]
                    try? await cache.set(key: key, value: data, ttl: 60)
                    let _: [String: String]? = try? await cache.get(key: key)
                }
            }
        }
    }

    // MARK: - Integration Tests

    func testFullLeagueDataFlow() async throws {
        // This test verifies the full flow: API -> Cache -> Response

        let client: APIFootballClient = app.getService()
        let cache: CacheService = app.getService()

        // First request - should hit API
        let league1 = try await cache.getOrFetchLeague(id: 6, season: 2025) {
            try await client.getLeague(id: 6, season: 2025)
        }

        XCTAssertEqual(league1.league.id, 6)

        // Second request - should hit cache
        let league2 = try await cache.getOrFetchLeague(id: 6, season: 2025) {
            XCTFail("Should not fetch from API - should use cache")
            return league1
        }

        XCTAssertEqual(league2.league.id, league1.league.id)
    }
}
