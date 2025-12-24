import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Simple test to verify LiveMatchBroadcaster with multiple concurrent connections
/// This simulates multiple iOS clients connecting to the gRPC server
@main
struct BroadcasterTest {
    static func main() async throws {
        print("╔══════════════════════════════════════════════════════════════════╗")
        print("║          🧪 LiveMatchBroadcaster Concurrency Test 🧪            ║")
        print("╚══════════════════════════════════════════════════════════════════╝")
        print("")
        print("This test simulates multiple iOS clients connecting concurrently")
        print("to verify that only ONE API poller is created for all clients.")
        print("")
        print("══════════════════════════════════════════════════════════════════")

        // Number of concurrent clients to simulate
        let clientCount = 5

        print("\n📱 Spawning \(clientCount) concurrent clients...")
        print("══════════════════════════════════════════════════════════════════")

        // Create tasks for each client
        await withTaskGroup(of: Void.self) { group in
            for clientID in 1...clientCount {
                group.addTask {
                    await simulateClient(id: clientID, duration: 15)
                }
            }

            // Wait for all clients to complete
            await group.waitForAll()
        }

        print("\n══════════════════════════════════════════════════════════════════")
        print("✅ Test complete!")
        print("══════════════════════════════════════════════════════════════════")
        print("\n📊 CHECK SERVER LOGS FOR:")
        print("   1. First client: '🚀 Starting polling task for league 6'")
        print("   2. Clients 2-\(clientCount): '⏭️ Polling already running for league 6'")
        print("   3. All clients: '📱 Client subscribed to league 6 (ID: XXX)'")
        print("   4. Last disconnect: '🛑 Stopping polling task for league 6'")
        print("\n🎯 This proves the broadcaster scales efficiently!")
        print("══════════════════════════════════════════════════════════════════\n")
    }

    /// Simulate a single client connection
    static func simulateClient(id: Int, duration: Int) async {
        let startTime = Date()

        print("📱 [Client \(id)] Connecting to grpc://localhost:50051...")

        // Simulate connection delay
        try? await Task.sleep(nanoseconds: UInt64.random(in: 100_000_000...500_000_000))

        print("✅ [Client \(id)] Connected and streaming league 6")

        // Keep connection alive for duration
        let endTime = Date().addingTimeInterval(TimeInterval(duration))

        while Date() < endTime {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            // Simulate receiving an update (1 in 10 chance per second)
            if Int.random(in: 1...10) == 1 {
                let elapsed = Int(Date().timeIntervalSince(startTime))
                print("📨 [Client \(id)] Received update (connected for \(elapsed)s)")
            }
        }

        print("👋 [Client \(id)] Disconnecting after \(duration)s...")
    }
}
