#!/usr/bin/env swift

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2

// This test simulates multiple clients connecting to verify broadcaster scalability
@main
struct BroadcasterTest {
    static func main() async throws {
        print("🧪 Testing LiveMatchBroadcaster with multiple clients...")
        print("=" * 60)

        // Create 5 simulated clients
        let clientCount = 5
        var tasks: [Task<Void, Error>] = []

        for clientID in 1...clientCount {
            let task = Task {
                try await connectClient(id: clientID)
            }
            tasks.append(task)
        }

        print("✅ Spawned \(clientCount) concurrent clients")
        print("📊 Watch server logs to verify only ONE poller starts")
        print("=" * 60)

        // Let them run for 30 seconds
        try await Task.sleep(for: .seconds(30))

        print("\n🛑 Stopping clients...")
        for task in tasks {
            task.cancel()
        }

        // Wait for cleanup
        try await Task.sleep(for: .seconds(2))

        print("✅ Test complete!")
        print("📊 Check server logs - poller should have stopped after last client disconnected")
    }

    static func connectClient(id: Int) async throws {
        print("📱 Client \(id) connecting...")

        let client = try GRPCClient(
            transport: try .http2NIOPosix(
                target: .ipv4(host: "127.0.0.1", port: 50051),
                transportSecurity: .plaintext
            )
        )

        defer {
            Task {
                try? await client.close()
            }
        }

        // Subscribe to live match stream
        var request = Afcon_LiveMatchRequest()
        request.leagueID = 6
        request.season = 2025

        let stream = try client.streamLiveMatches(request: request)

        print("✅ Client \(id) connected and streaming")

        var updateCount = 0
        for try await update in stream {
            updateCount += 1
            print("📨 Client \(id) received update #\(updateCount): Fixture \(update.fixtureID)")

            // Cancel after receiving first update (if any)
            if updateCount >= 1 {
                break
            }
        }

        print("👋 Client \(id) disconnecting...")
    }
}

// Helper extension
extension String {
    static func * (left: String, right: Int) -> String {
        String(repeating: left, count: right)
    }
}
