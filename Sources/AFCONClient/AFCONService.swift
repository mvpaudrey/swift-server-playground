import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2

/// Service to communicate with AFCON Middleware via gRPC
/// This is a lightweight client library for iOS/macOS apps (grpc-swift 2.x)
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
public final class AFCONService: Sendable {
    private let client: Afcon_AFCONService.Client<HTTP2ClientTransport.Posix>

    // Configuration
    public let host: String
    public let port: Int

    /// Initialize AFCON Service
    /// - Parameters:
    ///   - host: gRPC server host (default: localhost for development)
    ///   - port: gRPC server port (default: 50051)
    public init(host: String = "localhost", port: Int = 50051) throws {
        self.host = host
        self.port = port

        // Create transport
        let transport = try HTTP2ClientTransport.Posix(
            target: .ipv4(host: host, port: port),
            transportSecurity: .plaintext
        )

        // Create typed client
        self.client = Afcon_AFCONService.Client(wrapping: GRPCClient(transport: transport))
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

        let response: Afcon_TeamsResponse = try await client.getTeams(request)
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

        let response: Afcon_FixturesResponse = try await client.getFixtures(request)
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

        let response: Afcon_LineupsResponse = try await client.getLineups(request)
        return response.lineups
    }

    /// Stream live match updates
    public func streamLiveMatches(
        leagueId: Int32 = 6,
        season: Int32 = 2025,
        onUpdate: @Sendable @escaping (Afcon_LiveMatchUpdate) -> Void
    ) async throws {
        var request = Afcon_LiveMatchRequest()
        request.leagueID = leagueId
        request.season = season

        try await client.streamLiveMatches(request) { response in
            for try await message in response.messages {
                onUpdate(message)
            }
            return
        }
    }
}

// MARK: - Shared Instance
@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
extension AFCONService {
    /// Shared singleton instance for convenience
    public nonisolated(unsafe) static let shared: AFCONService = {
        do {
            return try AFCONService()
        } catch {
            fatalError("Failed to initialize AFCONService: \(error)")
        }
    }()
}
