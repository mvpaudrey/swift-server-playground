import AFCONClient
import Foundation

/// Example gRPC client for AFCON Middleware using grpc-swift 2.x
/// This demonstrates how to connect to the gRPC server and stream live matches

@main
struct AFCONClientExample {
    static let serverHost = "localhost"
    static let serverPort = 50051
    static let afconLeagueId: Int32 = 6
    static let season: Int32 = 2025

    static func main() async throws {
        print("🏆 AFCON 2025 gRPC Client")
        print("Connecting to \(serverHost):\(serverPort)...")

        guard #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) else {
            print("❌ This example requires macOS 15.0+ (or equivalent OS versions).")
            return
        }

        let service = try AFCONService(host: serverHost, port: serverPort)
        print("✅ Connected to gRPC server\n")

        try await streamLiveMatches(service: service, durationSeconds: 60)
        print("\n✅ Streaming demo completed!")
    }

    static func streamLiveMatches(service: AFCONService, durationSeconds: UInt64) async throws {
        print("🔴 Streaming Live Matches (\(durationSeconds) seconds)...")
        print("────────────────────────────────")
        print("Waiting for live match updates...")
        print("(Press Ctrl+C to stop)\n")

        let streamTask = Task {
            try await service.streamLiveMatches(leagueId: afconLeagueId, season: season) { update in
                let timestamp = formatTimestamp(update.timestamp)
                let eventType = update.eventType

                switch eventType {
                case "match_started":
                    print("⚽ [\(timestamp)] Match Started: \(update.fixture.teams.home.name) vs \(update.fixture.teams.away.name)")
                case "goal":
                    print("🎯 [\(timestamp)] GOAL! \(update.fixture.teams.home.name) \(update.fixture.goals.home) - \(update.fixture.goals.away) \(update.fixture.teams.away.name)")
                case "status_update":
                    print("📊 [\(timestamp)] Status: \(update.status.long)")
                case "time_update":
                    print("⏱️  [\(timestamp)] Time: \(update.status.elapsed)'")
                case "match_finished":
                    print("🏁 [\(timestamp)] Match Finished: \(update.fixture.teams.home.name) \(update.fixture.goals.home) - \(update.fixture.goals.away) \(update.fixture.teams.away.name)")
                default:
                    print("ℹ️  [\(timestamp)] \(eventType)")
                }
            }
        }

        try await Task.sleep(nanoseconds: durationSeconds * 1_000_000_000)
        streamTask.cancel()
        _ = await streamTask.result
    }

    static func formatTimestamp(_ timestamp: Google_Protobuf_Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp.seconds))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
