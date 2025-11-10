import Foundation
import GRPC
import NIO

/// Example gRPC client for AFCON Middleware
/// This demonstrates how to connect to the gRPC server and fetch data

// MARK: - Main Entry Point
@main
struct AFCONClient {

    // MARK: - Configuration
    static let serverHost = "localhost"
    static let serverPort = 50051
    static let afconLeagueId: Int32 = 6
    static let season: Int32 = 2025

    static func main() async throws {
        print("🏆 AFCON 2025 gRPC Client")
        print("Connecting to \(serverHost):\(serverPort)...")

        // Create event loop group
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer {
            try? group.syncShutdownGracefully()
        }

        // Create gRPC channel
        let channel = try GRPCChannelPool.with(
            target: .host(serverHost, port: serverPort),
            transportSecurity: .plaintext,
            eventLoopGroup: group
        )
        defer {
            try? channel.close().wait()
        }

        print("✅ Connected to gRPC server\n")

        // Note: After running ./generate-protos.sh in the main project,
        // you'll need to copy the generated files here and uncomment the client code below

        // Demonstrate different RPC calls
        try await demonstrateLeagueInfo(channel: channel)
        try await demonstrateTeams(channel: channel)
        try await demonstrateFixtures(channel: channel)
        try await demonstrateLiveMatches(channel: channel)

        print("\n✅ All examples completed successfully!")
    }

    // MARK: - Example Functions

    static func demonstrateLeagueInfo(channel: GRPCChannel) async throws {
        print("📋 Fetching League Information...")
        print("────────────────────────────────")

        /*
        // Uncomment after proto generation:

        let client = Afcon_AFCONServiceClient(channel: channel)

        var request = Afcon_LeagueRequest()
        request.leagueID = afconLeagueId
        request.season = season

        let response = try await client.getLeague(request).response.get()

        print("League: \(response.league.name)")
        print("Type: \(response.league.type)")
        print("Country: \(response.country.name)")
        print("\nSeasons:")
        for season in response.seasons {
            let indicator = season.current ? "→" : " "
            print("\(indicator) \(season.year): \(season.start) to \(season.end)")
        }
        */

        print("⚠️  Run ./generate-protos.sh first to generate client code")
        print()
    }

    static func demonstrateTeams(channel: GRPCChannel) async throws {
        print("⚽ Fetching Teams...")
        print("────────────────────────────────")

        /*
        // Uncomment after proto generation:

        let client = Afcon_AFCONServiceClient(channel: channel)

        var request = Afcon_TeamsRequest()
        request.leagueID = afconLeagueId
        request.season = season

        let response = try await client.getTeams(request).response.get()

        print("Total Teams: \(response.teams.count)\n")

        for teamInfo in response.teams.prefix(10) {
            let team = teamInfo.team
            let venue = teamInfo.venue
            print("[\(team.code)] \(team.name)")
            print("  Founded: \(team.founded)")
            print("  Venue: \(venue.name), \(venue.city)")
            print("  Capacity: \(venue.capacity)")
            print()
        }

        if response.teams.count > 10 {
            print("... and \(response.teams.count - 10) more teams")
        }
        */

        print("⚠️  Run ./generate-protos.sh first to generate client code")
        print()
    }

    static func demonstrateFixtures(channel: GRPCChannel) async throws {
        print("📅 Fetching Fixtures...")
        print("────────────────────────────────")

        /*
        // Uncomment after proto generation:

        let client = Afcon_AFCONServiceClient(channel: channel)

        var request = Afcon_FixturesRequest()
        request.leagueID = afconLeagueId
        request.season = season

        let response = try await client.getFixtures(request).response.get()

        print("Total Fixtures: \(response.fixtures.count)\n")

        for fixture in response.fixtures.prefix(5) {
            let homeTeam = fixture.teams.home.name
            let awayTeam = fixture.teams.away.name
            let homeGoals = fixture.goals.home
            let awayGoals = fixture.goals.away
            let status = fixture.status.short

            print("[\(status)] \(homeTeam) \(homeGoals) - \(awayGoals) \(awayTeam)")
            print("  Venue: \(fixture.venue.name), \(fixture.venue.city)")
            print("  Status: \(fixture.status.long)")
            print()
        }

        if response.fixtures.count > 5 {
            print("... and \(response.fixtures.count - 5) more fixtures")
        }
        */

        print("⚠️  Run ./generate-protos.sh first to generate client code")
        print()
    }

    static func demonstrateLiveMatches(channel: GRPCChannel) async throws {
        print("🔴 Streaming Live Matches (60 seconds)...")
        print("────────────────────────────────")

        /*
        // Uncomment after proto generation:

        let client = Afcon_AFCONServiceClient(channel: channel)

        var request = Afcon_LiveMatchRequest()
        request.leagueID = afconLeagueId
        request.season = season

        print("Waiting for live match updates...")
        print("(Press Ctrl+C to stop)\n")

        let call = client.streamLiveMatches(request) { update in
            let timestamp = formatTimestamp(update.timestamp)
            let eventType = update.eventType

            switch eventType {
            case "match_started":
                print("⚽ [\(timestamp)] Match Started: \(update.fixture.teams.home.name) vs \(update.fixture.teams.away.name)")
            case "goal":
                print("🎯 [\(timestamp)] GOAL! \(update.fixture.teams.home.name) \(update.fixture.goals.home) - \(update.fixture.goals.away) \(update.fixture.teams.away.name)")
            case "status_update":
                print("📊 [\(timestamp)] Status: \(update.fixture.status.long)")
            case "time_update":
                print("⏱️  [\(timestamp)] Time: \(update.fixture.status.elapsed)'")
            case "match_finished":
                print("🏁 [\(timestamp)] Match Finished: \(update.fixture.teams.home.name) \(update.fixture.goals.home) - \(update.fixture.goals.away) \(update.fixture.teams.away.name)")
            default:
                print("ℹ️  [\(timestamp)] \(eventType)")
            }
        }

        // Listen for 60 seconds
        try await Task.sleep(nanoseconds: 60_000_000_000)

        // Cancel the stream
        call.cancel(promise: nil)
        */

        print("⚠️  Run ./generate-protos.sh first to generate client code")
        print("⚠️  Live streaming will work when matches are in progress")
        print()
    }

    // MARK: - Helper Functions

    static func formatTimestamp(_ timestamp: Google_Protobuf_Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp.seconds))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Placeholder Types
// These will be replaced by generated code

struct Google_Protobuf_Timestamp {
    var seconds: Int64 = 0
    var nanos: Int32 = 0
}
