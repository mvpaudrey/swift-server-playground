# iOS App Fixes for LiveMatchBroadcaster

## 🐛 Issues Identified

When testing with a single iOS simulator, you're seeing:
```
gRPC: StreamLiveMatches - league=6, season=0 [Client 5 connecting]
📱 Client subscribed to league 6 (ID: 864D82AC-...). Total subscribers: 5
```

This indicates:
1. **Season = 0** (should be 2025)
2. **5 connections from 1 simulator** (should be 1)

---

## ✅ Fix 1: Add Missing Season Parameter

**File:** `/Users/audrey/Documents/Projects/Cheulah/CAN2025/AFCONApp/AFCONiOSApp/AFCON2025/Services/AFCONService.swift`

**Line 83-88:**

```swift
// BEFORE (BROKEN):
/// Stream live match updates
func streamLiveMatches(
    leagueId: Int32 = 6,
    onUpdate: @escaping @Sendable (Afcon_LiveMatchUpdate) -> Void
) async throws {
    try await service.streamLiveMatches(leagueId: leagueId, onUpdate: onUpdate)
}

// AFTER (FIXED):
/// Stream live match updates
func streamLiveMatches(
    leagueId: Int32 = 6,
    season: Int32 = 2025,  // ← ADD THIS PARAMETER
    onUpdate: @escaping @Sendable (Afcon_LiveMatchUpdate) -> Void
) async throws {
    try await service.streamLiveMatches(
        leagueId: leagueId,
        season: season,  // ← PASS IT TO SERVICE
        onUpdate: onUpdate
    )
}
```

---

## ✅ Fix 2: Prevent Connection Leaks

**File:** `/Users/audrey/Documents/Projects/Cheulah/CAN2025/AFCONApp/AFCONiOSApp/AFCON2025/ViewModels/LiveScoresViewModel.swift`

### Problem
The `startLiveUpdates()` function (line 107) creates a new Task every time but never cancels previous ones.

### Solution
Add task tracking and cancellation:

```swift
@Observable
class LiveScoresViewModel {
    private let service = AFCONServiceWrapper.shared

    var liveMatches: [Game] = []
    var upcomingMatches: [Game] = []
    var finishedMatches: [Game] = []
    var fixtureEvents: [Int: [Afcon_FixtureEvent]] = [:]
    var isLoading = false
    var errorMessage: String?

    // ADD THIS: Track streaming task
    private var streamingTask: Task<Void, Never>?

    // ADD THIS: Track if streaming is active
    var isStreaming: Bool {
        streamingTask != nil && !(streamingTask?.isCancelled ?? true)
    }

    // ... rest of existing code ...

    // MARK: - Start Live Updates Stream
    func startLiveUpdates() {
        // PREVENT MULTIPLE STREAMS
        guard !isStreaming else {
            print("⏭️ Streaming already active, skipping...")
            return
        }

        print("🚀 Starting live updates stream...")

        streamingTask = Task {
            do {
                try await service.streamLiveMatches { [weak self] update in
                    Task { @MainActor in
                        // Handle live update
                        print("Live update for fixture \(update.fixtureID): \(update.eventType)")

                        // ... rest of existing update handling code ...
                        let updatedGame = update.fixture.toGame()
                        let fixtureId = Int(update.fixtureID)

                        // Check if it's in live matches
                        if let index = self?.liveMatches.firstIndex(where: { $0.id == fixtureId }) {
                            self?.liveMatches[index] = updatedGame

                            // Update events for this live match
                            Task {
                                await self?.fetchEventsForSingleMatch(fixtureId: fixtureId)
                            }
                        } else if updatedGame.status == .live {
                            // New live match started - remove from upcoming if present
                            self?.upcomingMatches.removeAll { $0.id == fixtureId }
                            self?.liveMatches.insert(updatedGame, at: 0)

                            // Fetch events for newly live match
                            Task {
                                await self?.fetchEventsForSingleMatch(fixtureId: fixtureId)
                            }
                        } else if updatedGame.status == .upcoming {
                            // Update in upcoming list
                            if let index = self?.upcomingMatches.firstIndex(where: { $0.id == fixtureId }) {
                                self?.upcomingMatches[index] = updatedGame
                            }
                        } else if updatedGame.status == .finished {
                            // Match finished - remove from live, add to finished
                            self?.liveMatches.removeAll { $0.id == fixtureId }

                            // Add to finished if it's from today
                            let calendar = Calendar.current
                            let today = calendar.startOfDay(for: Date())
                            let gameDay = calendar.startOfDay(for: updatedGame.date)

                            if calendar.isDate(gameDay, inSameDayAs: today) {
                                self?.finishedMatches.insert(updatedGame, at: 0)

                                // Fetch final events
                                Task {
                                    await self?.fetchEventsForSingleMatch(fixtureId: fixtureId)
                                }
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Live updates stream error: \(error.localizedDescription)"
                    self?.streamingTask = nil
                }
                print("❌ Stream ended with error: \(error)")
            }
        }
    }

    // ADD THIS: Method to stop streaming
    func stopLiveUpdates() {
        print("🛑 Stopping live updates stream...")
        streamingTask?.cancel()
        streamingTask = nil
    }

    // ADD THIS: Cleanup in deinit
    deinit {
        stopLiveUpdates()
    }

    // ... rest of existing code ...
}
```

---

## ✅ Fix 3: Proper Lifecycle Management in View

Ensure the view properly manages streaming lifecycle:

```swift
struct LiveScoresView: View {
    @State private var viewModel = LiveScoresViewModel()

    var body: some View {
        // Your view code...
    }
    .onAppear {
        Task {
            await viewModel.fetchLiveMatches()
        }
        viewModel.startLiveUpdates()  // Start streaming
    }
    .onDisappear {
        viewModel.stopLiveUpdates()  // Stop streaming when view disappears
    }
}
```

---

## 🧪 Testing After Fixes

After applying these fixes, you should see:

```
// From iOS app (single simulator):
🚀 Starting live updates stream...

// In server logs:
[ INFO ] gRPC: StreamLiveMatches - league=6, season=2025 [Client 1 connecting]  ← season=2025!
[ INFO ] 📱 Client subscribed to league 6 (ID: XXX). Total subscribers: 1  ← Only 1!
[ INFO ] 🚀 Starting polling task for league 6, season 2025

// If you try to navigate away and back:
⏭️ Streaming already active, skipping...  ← Prevents duplicate!
```

---

## 📊 Expected Behavior After Fixes

| Scenario | Before | After |
|----------|--------|-------|
| **Single simulator** | 5 connections, season=0 | 1 connection, season=2025 ✅ |
| **Navigate away and back** | New connection each time | Reuses existing connection ✅ |
| **App backgrounded** | Connection stays open | Connection stays open ✅ |
| **App terminated** | Connections leak | Properly cleaned up ✅ |

---

## 🚀 Quick Fix Commands

```bash
# 1. Edit the iOS app files with the fixes above

# 2. Clean and rebuild
cd /Users/audrey/Documents/Projects/Cheulah/CAN2025/AFCONApp/AFCONiOSApp
xcodebuild clean
xcodebuild build

# 3. Restart server
cd /Users/audrey/Documents/Projects/Cheulah/CAN2025/swift-server-playground
swift run Run

# 4. Run app and monitor logs
tail -f /tmp/claude/.../tasks/XXX.output | grep -E '(Client|subscriber|Polling|season)'
```

---

## 🎯 Summary

**Root Causes:**
1. Missing `season` parameter in wrapper call → defaults to 0
2. No task cancellation in ViewModel → creates multiple streams
3. No streaming state tracking → allows duplicate calls

**After Fixes:**
- ✅ Season will be 2025
- ✅ Only 1 connection per app instance
- ✅ Proper cleanup when view disappears
- ✅ Prevents duplicate streaming attempts

Apply these fixes and the broadcaster will work perfectly with your iOS app! 🚀
