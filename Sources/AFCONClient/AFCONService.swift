import Foundation
import GRPC
import NIO

/// Service to communicate with AFCON Middleware via gRPC
/// This is a lightweight client library for iOS/macOS apps
public class AFCONService {
    private let client: Afcon_AFCONServiceAsyncClient
    private let group: EventLoopGroup
    private let channel: GRPCChannel

    // Configuration
    public let host: String
    public let port: Int

    /// Initialize AFCON Service
    /// - Parameters:
    ///   - host: gRPC server host (default: localhost for development)
    ///   - port: gRPC server port (default: 50051)
    public init(host: String = "localhost", port: Int = 50051) {
        self.host = host
        self.port = port

        // Create event loop group
        self.group = PlatformSupport.makeEventLoopGroup(loopCount: 1)

        // Create gRPC channel
        self.channel = try! GRPCChannelPool.with(
            target: .host(host, port: port),
            transportSecurity: .plaintext,
            eventLoopGroup: group
        )

        // Create client
        self.client = Afcon_AFCONServiceAsyncClient(channel: channel)
    }

    deinit {
        try? channel.close().wait()
        try? group.syncShutdownGracefully()
    }

    // MARK: - API Methods

    /// Get league information for AFCON
    public func getLeague(leagueId: Int32 = 6, season: Int32 = 2025) async throws -> Afcon_LeagueResponse {
        var request = Afcon_LeagueRequest()
        request.leagueID = leagueId
        request.season = season

        return try await client.getLeague(request)
    }

    /// Get all teams for AFCON
    public func getTeams(leagueId: Int32 = 6, season: Int32 = 2025) async throws -> [Afcon_TeamInfo] {
        var request = Afcon_TeamsRequest()
        request.leagueID = leagueId
        request.season = season

        let response = try await client.getTeams(request)
        return response.teams
    }

    /// Get fixtures for AFCON
    public func getFixtures(
        leagueId: Int32 = 6,
        season: Int32 = 2025,
        date: String? = nil,
        teamId: Int32? = nil,
        live: Bool = false
    ) async throws -> [Afcon_Fixture] {
        var request = Afcon_FixturesRequest()
        request.leagueID = leagueId
        request.season = season
        request.live = live

        if let date = date {
            request.date = date
        }

        if let teamId = teamId {
            request.teamID = teamId
        }

        let response = try await client.getFixtures(request)
        return response.fixtures
    }

    /// Get live fixtures
    public func getLiveFixtures(leagueId: Int32 = 6) async throws -> [Afcon_Fixture] {
        return try await getFixtures(leagueId: leagueId, season: 2025, live: true)
    }

    /// Get team details
    public func getTeamDetails(teamId: Int32) async throws -> Afcon_TeamDetailsResponse {
        var request = Afcon_TeamDetailsRequest()
        request.teamID = teamId

        return try await client.getTeamDetails(request)
    }

    /// Get standings
    public func getStandings(leagueId: Int32 = 6, season: Int32 = 2025) async throws -> Afcon_StandingsResponse {
        var request = Afcon_StandingsRequest()
        request.leagueID = leagueId
        request.season = season

        return try await client.getStandings(request)
    }

    /// Get fixture lineups
    public func getLineups(fixtureId: Int32) async throws -> [Afcon_FixtureLineup] {
        var request = Afcon_LineupsRequest()
        request.fixtureID = fixtureId

        let response = try await client.getLineups(request)
        return response.lineups
    }

    /// Stream live match updates
    public func streamLiveMatches(
        leagueId: Int32 = 6,
        onUpdate: @escaping (Afcon_LiveMatchUpdate) -> Void
    ) async throws {
        var request = Afcon_LiveMatchRequest()
        request.leagueID = leagueId

        let stream = client.streamLiveMatches(request)

        for try await update in stream {
            onUpdate(update)
        }
    }
}

// MARK: - Shared Instance
extension AFCONService {
    /// Shared singleton instance for convenience
    public static let shared = AFCONService()
}
