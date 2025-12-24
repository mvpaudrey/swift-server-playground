# AFCON Client Integration Guide

Complete guide for integrating live match updates in your iOS app using gRPC streaming and Live Activities.

## Table of Contents

1. [gRPC Streaming Setup](#grpc-streaming-setup)
2. [Live Activities Setup](#live-activities-setup)
3. [APNs Configuration](#apns-configuration)
4. [Complete Example](#complete-example)

---

## gRPC Streaming Setup

### Step 1: Add AFCONClient to Your iOS Project

In your iOS app's `Package.swift`:

```swift
dependencies: [
    .package(path: "../swift-server-playground") // Path to this project
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "AFCONClient", package: "swift-server-playground")
        ]
    )
]
```

### Step 2: Initialize gRPC Client

```swift
import AFCONClient

let grpcService = try AFCONService(
    host: "your-server.com",  // or "localhost" for testing
    port: 50051,
    useTLS: true  // Use true for production, false for local testing
)
```

### Step 3: Stream Live Matches

See `LiveMatchStreamingExample.swift` for complete code. Basic usage:

```swift
import AFCONClient

@MainActor
class LiveMatchViewModel: ObservableObject {
    @Published var liveMatches: [LiveMatchData] = []
    private let grpcClient: AFCONService

    func startStreaming() {
        Task {
            var request = Afcon_LiveMatchRequest()
            request.leagueID = 6  // AFCON
            request.season = 2025

            let stream = try await grpcClient.streamLiveMatches(request: request)

            for try await update in stream {
                // Process live updates
                handleUpdate(update)
            }
        }
    }

    private func handleUpdate(_ update: Afcon_LiveMatchUpdate) {
        // Update your UI
        print("Live: \(update.fixture.teams.home.name) \(update.fixture.goals.home) - \(update.fixture.goals.away) \(update.fixture.teams.away.name)")
    }
}
```

### How It Works

1. **Server polls API-Football every 15 seconds** for live match data
2. **Server detects changes** in scores, events, status
3. **Server pushes updates** to all connected clients via gRPC stream
4. **Your app receives updates** in real-time without polling

**Benefits:**
- ✅ No polling needed in your app
- ✅ Real-time updates (15s latency max)
- ✅ Efficient battery usage
- ✅ Works while app is in foreground

---

## Live Activities Setup

Live Activities appear on the Lock Screen and Dynamic Island (iPhone 14 Pro+) with real-time score updates.

### Step 1: Enable Live Activities

In your `Info.plist`:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

### Step 2: Create Widget Extension

```bash
File > New > Target > Widget Extension
Name: AFCONMatchWidget
```

### Step 3: Implement Live Activity Widget

Copy `LiveActivityExample.swift` to your widget target and customize the UI.

Key components:

```swift
// 1. Define attributes
struct AFCONMatchAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var homeTeam: String
        var awayTeam: String
        var homeScore: Int
        var awayScore: Int
        var status: String
        var elapsed: Int
        var lastEvent: String?
    }

    var fixtureId: Int
    var homeTeamLogo: String
    var awayTeamLogo: String
}

// 2. Create widget configuration
struct AFCONMatchLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AFCONMatchAttributes.self) { context in
            // Lock Screen UI
        } dynamicIsland: { context in
            // Dynamic Island UI
        }
    }
}
```

### Step 4: Start Live Activity in Your App

```swift
import ActivityKit

// 1. Register device with server
let manager = AFCONLiveActivityManager(grpcClient: grpcService)
try await manager.registerDevice(apnsToken: deviceToken)

// 2. Start Live Activity for a match
let activity = try await manager.startLiveActivity(
    fixtureId: 12345,
    homeTeam: "Senegal",
    awayTeam: "Egypt",
    homeTeamLogo: "https://...",
    awayTeamLogo: "https://...",
    initialScore: (0, 0)
)
```

### Step 5: Server Pushes Updates

The server automatically sends push updates when:
- ⚽ Goals scored
- 🟥 Red cards
- ⚡ Major events (VAR, penalties)
- ⏱️ Status changes (Half-time, Full-time)

Updates appear on:
- 🔒 Lock Screen
- 🏝️ Dynamic Island (iPhone 14 Pro+)
- 📱 Standby Mode

**No app code needed** - updates are pushed from server!

---

## APNs Configuration

### Server-Side Configuration

Set these environment variables on your server:

```bash
export APNS_KEY_ID="ABC123XYZ"
export APNS_TEAM_ID="TEAM123456"
export APNS_KEY_PATH="/path/to/AuthKey_ABC123XYZ.p8"
export APNS_TOPIC="com.yourcompany.yourapp"
export APNS_ENVIRONMENT="production"  # or "sandbox" for testing
```

### Get APNs Credentials

1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/authkeys/list)
2. Create new key with **Apple Push Notifications service (APNs)** enabled
3. Download `.p8` file
4. Note your Key ID and Team ID

### iOS App Configuration

1. **Enable Push Notifications capability** in Xcode
2. **Request permission:**

```swift
import UserNotifications

let center = UNUserNotificationCenter.current()
let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])

if granted {
    await UIApplication.shared.registerForRemoteNotifications()
}
```

3. **Handle device token:**

```swift
func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
    let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()

    Task {
        let manager = AFCONLiveActivityManager(grpcClient: grpcService)
        try await manager.registerDevice(apnsToken: tokenString)
    }
}
```

---

## Complete Example

### In Your iOS App

```swift
import SwiftUI
import AFCONClient
import ActivityKit

@main
struct AFCONApp: App {
    @StateObject private var liveMatchVM = LiveMatchViewModel()
    @StateObject private var activityManager: AFCONLiveActivityManager

    init() {
        let grpcClient = try! AFCONService(
            host: "your-server.com",
            port: 50051,
            useTLS: true
        )

        _activityManager = StateObject(
            wrappedValue: AFCONLiveActivityManager(grpcClient: grpcClient)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(liveMatchVM)
                .environmentObject(activityManager)
                .onAppear {
                    // Start streaming live matches
                    liveMatchVM.startStreaming()
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var liveMatchVM: LiveMatchViewModel
    @EnvironmentObject var activityManager: AFCONLiveActivityManager

    var body: some View {
        NavigationView {
            List(liveMatchVM.liveMatches) { match in
                VStack(alignment: .leading) {
                    HStack {
                        Text("\(match.homeTeam) \(match.homeScore)")
                        Text("-")
                        Text("\(match.awayScore) \(match.awayTeam)")
                    }
                    .font(.headline)

                    Text("\(match.status) - \(match.elapsed)'")
                        .font(.caption)

                    Button("Start Live Activity") {
                        Task {
                            try await activityManager.startLiveActivity(
                                fixtureId: match.id,
                                homeTeam: match.homeTeam,
                                awayTeam: match.awayTeam,
                                homeTeamLogo: "...",
                                awayTeamLogo: "...",
                                initialScore: (match.homeScore, match.awayScore)
                            )
                        }
                    }
                }
            }
            .navigationTitle("Live Matches")
        }
    }
}
```

---

## Architecture Overview

```
┌─────────────────┐     15s polling      ┌──────────────────┐
│   API-Football  │ <------------------- │  Your Server     │
│   (External)    │                      │  (Middleware)    │
└─────────────────┘                      └──────────────────┘
                                                 │
                                                 │ gRPC Stream
                                                 │ (Real-time)
                                                 ▼
                                         ┌──────────────────┐
                                         │   iOS App        │
                                         │   - Foreground   │
                                         │   - gRPC Stream  │
                                         └──────────────────┘
                                                 │
                                                 │ APNs Push
                                                 │ (Background)
                                                 ▼
                                         ┌──────────────────┐
                                         │  Live Activity   │
                                         │  - Lock Screen   │
                                         │  - Dynamic Island│
                                         └──────────────────┘
```

## Update Frequencies

| Update Type | Frequency | Method |
|------------|-----------|--------|
| Server polls API | Every 15 seconds | HTTP to API-Football |
| gRPC stream updates | Immediate (when data changes) | Server → App (foreground) |
| Live Activity updates | Major events only | APNs Push (background) |

### Live Activity Update Modes

Configure when updates are sent:

```swift
// When starting Live Activity:
request.updateFrequency = "major_events"  // Default: goals, cards, VAR
// Options:
// - "every_minute"   : Every time data changes (~15s)
// - "goals_only"     : Only goals
// - "major_events"   : Goals, red cards, VAR, penalties (recommended)
// - "all_events"     : All events including yellow cards, subs
```

---

## Testing

### Local Testing (No APNs)

1. Run server: `.build/debug/Run serve`
2. Set `PAUSE_AFCON_LIVE_MATCHES=true` to pause AFCON polling during development
3. Connect iOS Simulator to `localhost:50051`
4. Test gRPC streaming (Live Activities require physical device)

### Testing with APNs (Physical Device)

1. Use sandbox APNs credentials
2. Deploy server with valid SSL certificate
3. Install app on physical iPhone
4. Start Live Activity
5. Lock phone and watch updates on Lock Screen

---

## Troubleshooting

### gRPC Connection Issues

```
❌ Error: Connection refused
```

**Solution:** Check server is running and port 50051 is accessible. For iOS Simulator, use `localhost`. For physical device, use your computer's IP address or deploy to a server.

### Live Activities Not Updating

```
⚠️ APNs not configured
```

**Solution:** Set APNs environment variables on server and restart.

### No Updates Appearing

**Check:**
1. Server logs show "✅ Live Activity update sent"
2. APNs credentials are valid
3. Device token is correct
4. Activity hasn't expired (8 hour limit)

---

## Production Checklist

- [ ] APNs production credentials configured
- [ ] Server deployed with HTTPS
- [ ] gRPC server uses TLS
- [ ] Database backups configured
- [ ] Error monitoring setup
- [ ] Rate limiting configured
- [ ] API-Football quota monitored

---

## Need Help?

See example files:
- `LiveMatchStreamingExample.swift` - gRPC streaming examples
- `LiveActivityExample.swift` - Live Activity implementation
- Server code: `Sources/App/gRPC/Server/AFCONServiceProvider.swift`

For more info on the gRPC API, see: `Protos/afcon.proto`
