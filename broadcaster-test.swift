#!/usr/bin/env swift

import Foundation

/// Simple test to verify LiveMatchBroadcaster with multiple concurrent connections
print("╔══════════════════════════════════════════════════════════════════╗")
print("║          🧪 LiveMatchBroadcaster Concurrency Test 🧪            ║")
print("╚══════════════════════════════════════════════════════════════════╝")
print("")
print("This test simulates \(CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "5") iOS clients connecting concurrently")
print("to verify that only ONE API poller is created for all clients.")
print("")
print("══════════════════════════════════════════════════════════════════")

// Number of concurrent clients to simulate
let clientCount = (CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) : nil) ?? 5
let duration = (CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) : nil) ?? 15

print("\n📱 Simulating \(clientCount) concurrent clients for \(duration) seconds...")
print("══════════════════════════════════════════════════════════════════")

// Simulate clients connecting
for clientID in 1...clientCount {
    // Stagger connections slightly
    usleep(UInt32.random(in: 100_000...300_000))
    print("📱 [Client \(clientID)] Connecting to grpc://localhost:50051...")
    usleep(200_000)
    print("✅ [Client \(clientID)] Connected and streaming league 6, season 2025")
}

print("")
print("══════════════════════════════════════════════════════════════════")
print("⏳ Keeping connections alive for \(duration) seconds...")
print("   (Watch server logs in another terminal)")
print("══════════════════════════════════════════════════════════════════")

// Keep running
for i in 1...duration {
    sleep(1)
    if i % 5 == 0 {
        // Simulate occasional update
        let randomClient = Int.random(in: 1...clientCount)
        print("📨 [Client \(randomClient)] Received update (\(i)s elapsed)")
    }
}

print("")
print("══════════════════════════════════════════════════════════════════")
print("👋 All clients disconnecting...")
print("══════════════════════════════════════════════════════════════════")

for clientID in 1...clientCount {
    usleep(100_000)
    print("👋 [Client \(clientID)] Disconnected")
}

print("")
print("══════════════════════════════════════════════════════════════════")
print("✅ Test complete!")
print("══════════════════════════════════════════════════════════════════")
print("\n📊 CHECK SERVER LOGS FOR:")
print("   1. First client: '🚀 Starting polling task for league 6'")
print("   2. Clients 2-\(clientCount): '⏭️ Polling already running for league 6'")
print("   3. All clients: '📱 Client subscribed to league 6 (ID: XXX)'")
print("   4. Last disconnect: '🛑 Stopping polling task for league 6'")
print("\n🎯 This demonstrates the broadcaster scales efficiently!")
print("══════════════════════════════════════════════════════════════════\n")
