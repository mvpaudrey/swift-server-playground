# Quick Start Guide - AFCON Middleware

Get up and running with real-time football data in 5 minutes!

## What You'll Get

- ⚡ **gRPC streaming** - Real-time match updates
- 📱 **Live Activities** - Lock Screen & Dynamic Island updates
- 🎯 **Production ready** - Fully configured server

## Prerequisites

Already installed:
- ✅ Swift 6.0+
- ✅ PostgreSQL (running)
- ✅ Redis (running)
- ✅ APNs credentials configured

## 1. Start the Server (30 seconds)

```bash
cd /Users/audrey/Documents/Projects/Cheulah/CAN2025/swift-server-playground

# Start with Live Activities enabled
./start-server-with-apns.sh
```

**Server Status:**
- gRPC: `0.0.0.0:50051` ✅
- HTTP: `0.0.0.0:8080` ✅
- APNs: Sandbox environment ✅

**Wait for:**
```
[ INFO ] ✅ APNs configuration loaded (https://api.development.push.apple.com)
[ INFO ] gRPC server starting on 0.0.0.0:50051
```

## 2. Test the Server (1 minute)

### Option A: HTTP Test (Quick)

```bash
# Health check
curl http://localhost:8080/health

# Get AFCON 2025 fixtures
curl http://localhost:8080/api/v1/league/6/season/2025/fixtures
```

### Option B: gRPC Test (Using grpcurl)

```bash
# Install grpcurl if needed
brew install grpcurl

# List available services
grpcurl -plaintext localhost:50051 list

# Get fixtures
grpcurl -plaintext -d '{"league_id": 6, "season": 2025}' \
  localhost:50051 afcon.AFCONService/GetFixtures
```

## 3. Build Your iOS App (3 minutes)

### Step 1: Create a New iOS App

```bash
# In Xcode: File > New > Project > iOS App
# Name: AFCONLive
# Interface: SwiftUI
# Language: Swift
```

### Step 2: Add Package Dependency

1. In Xcode: **File > Add Package Dependencies**
2. Enter path: `/Users/audrey/Documents/Projects/Cheulah/CAN2025/swift-server-playground`
3. Add package
4. Select **AFCONClient** library

### Step 3: Add Minimal Code

**ContentView.swift:**

```swift
import SwiftUI
import AFCONClient

struct ContentView: View {
    @StateObject private var viewModel = LiveMatchViewModel()

    var body: some View {
        NavigationView {
            List(viewModel.liveMatches) { match in
                VStack(alignment: .leading) {
                    Text("\(match.homeTeam) \(match.homeScore) - \(match.awayScore) \(match.awayTeam)")
                        .font(.headline)
                    Text("\(match.status) - \(match.elapsed)'")
                        .font(.caption)
                }
            }
            .navigationTitle("Live Matches")
        }
        .onAppear {
            viewModel.startStreaming()
        }
    }
}

@MainActor
class LiveMatchViewModel: ObservableObject {
    @Published var liveMatches: [LiveMatchData] = []
    private let grpcClient: AFCONService

    init() {
        // For Simulator: use "localhost"
        // For Device: use your Mac's IP (e.g., "192.168.1.100")
        grpcClient = try! AFCONService(
            host: "localhost",
            port: 50051,
            useTLS: false
        )
    }

    func startStreaming() {
        Task {
            do {
                var request = Afcon_LiveMatchRequest()
                request.leagueID = 6  // AFCON
                request.season = 2025

                let stream = try await grpcClient.streamLiveMatches(request: request)

                for try await update in stream {
                    let match = LiveMatchData(from: update.fixture, lastEvent: update.eventType)

                    if let index = liveMatches.firstIndex(where: { $0.id == match.id }) {
                        liveMatches[index] = match
                    } else {
                        liveMatches.append(match)
                    }
                }
            } catch {
                print("Stream error: \(error)")
            }
        }
    }
}

struct LiveMatchData: Identifiable {
    let id: Int
    let homeTeam: String
    let awayTeam: String
    let homeScore: Int
    let awayScore: Int
    let status: String
    let elapsed: Int
    let lastEvent: String?

    init(from fixture: Afcon_Fixture, lastEvent: String?) {
        self.id = Int(fixture.id)
        self.homeTeam = fixture.teams.home.name
        self.awayTeam = fixture.teams.away.name
        self.homeScore = Int(fixture.goals.home)
        self.awayScore = Int(fixture.goals.away)
        self.status = fixture.status.short
        self.elapsed = Int(fixture.status.elapsed)
        self.lastEvent = lastEvent
    }
}
```

### Step 4: Run the App

1. Select iOS Simulator (iPhone 15 Pro)
2. Press **⌘R** to run
3. You'll see live match updates streaming in!

## 4. Add Live Activities (Optional - 10 minutes)

**Requirements:**
- iOS 16.2+ on **physical device** (doesn't work in Simulator)
- APNs device token

### Quick Setup

1. **Enable Live Activities** in `Info.plist`:
```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

2. **Create Widget Extension**:
   - File > New > Target > Widget Extension
   - Name: `AFCONMatchWidget`
   - Include Live Activity: ✅

3. **Copy example code** from:
   - `Sources/AFCONClient/Examples/LiveActivityExample.swift`

4. **Run on physical device** and start a Live Activity for a match

**Full guide**: See `Sources/AFCONClient/Examples/INTEGRATION_GUIDE.md`

## What's Next?

### Explore the Examples

All in `Sources/AFCONClient/Examples/`:

1. **`LiveMatchStreamingExample.swift`**
   - Complete SwiftUI examples
   - Advanced patterns
   - Error handling

2. **`LiveActivityExample.swift`**
   - Full Live Activity implementation
   - Lock Screen & Dynamic Island UI
   - Device registration

3. **`INTEGRATION_GUIDE.md`**
   - Complete documentation
   - APNs setup
   - Troubleshooting

### Customize Your App

**Get more data:**
```swift
// Get teams
let teams = try await grpcClient.getTeams(
    request: Afcon_TeamsRequest.with {
        $0.leagueID = 6
        $0.season = 2025
    }
)

// Get standings
let standings = try await grpcClient.getStandings(
    request: Afcon_StandingsRequest.with {
        $0.leagueID = 6
        $0.season = 2025
    }
)

// Get specific fixture
let fixture = try await grpcClient.getFixtureById(
    request: Afcon_FixtureByIdRequest.with {
        $0.fixtureID = 12345
    }
)
```

## Troubleshooting

### Can't connect to server

**Simulator:**
```swift
// Use "localhost"
grpcClient = try AFCONService(host: "localhost", port: 50051, useTLS: false)
```

**Physical device:**
```swift
// Use your Mac's IP address
grpcClient = try AFCONService(host: "192.168.1.100", port: 50051, useTLS: false)
```

Find your Mac's IP:
```bash
ifconfig | grep "inet " | grep -v 127.0.0.1
```

### Server not responding

```bash
# Check if server is running
ps aux | grep "Run serve"

# Restart server
./start-server-with-apns.sh

# Check logs
tail -f /tmp/claude/-Users-audrey-Documents-Projects-Cheulah-CAN2025-swift-server-playground/tasks/*.output
```

### No live matches

The server is streaming, but AFCON 2025 matches may not be live right now. The stream will automatically start sending updates when matches go live.

To test with mock data, you can modify the server or wait for actual live matches.

### Live Activities not working

Common issues:
- ❌ Using Simulator → Must use physical device
- ❌ iOS < 16.2 → Update iOS
- ❌ APNs not configured → Check server logs for "✅ APNs configuration loaded"
- ❌ Wrong bundle ID → Must match `APNS_TOPIC` environment variable

## Server Configuration

Current configuration in `start-server-with-apns.sh`:

```bash
APNS_KEY_ID="K6V97L2X47"
APNS_TEAM_ID="486Q5MQF2F"
APNS_TOPIC="com.cheulah.AFCON2025"
APNS_ENVIRONMENT="sandbox"
```

**To change:**
1. Edit `start-server-with-apns.sh`
2. Restart server

## Performance Tips

### Reduce Polling During Development

```bash
# In start-server-with-apns.sh, add:
export PAUSE_AFCON_LIVE_MATCHES="true"
```

This pauses AFCON live match polling to save API quota during development.

### Monitor Server

```bash
# Watch logs in real-time
tail -f /tmp/claude/-Users-audrey-Documents-Projects-Cheulah-CAN2025-swift-server-playground/tasks/*.output

# Filter for specific events
tail -f *.output | grep "INFO"
tail -f *.output | grep "ERROR"
tail -f *.output | grep "Live"
```

## Production Deployment

Ready to deploy? See:
- `README.md` - Full documentation
- `IMPLEMENTATION_SUMMARY.md` - Feature overview
- Environment variables for production configuration

## Need Help?

- **Examples**: `Sources/AFCONClient/Examples/`
- **Integration Guide**: `Sources/AFCONClient/Examples/INTEGRATION_GUIDE.md`
- **Implementation Summary**: `IMPLEMENTATION_SUMMARY.md`
- **Full Docs**: `README.md`

---

**You're all set! 🚀**

Server is running with:
- ✅ gRPC streaming on port 50051
- ✅ Live Activities with APNs
- ✅ 36 AFCON 2025 fixtures loaded
- ✅ Real-time updates ready

Build something amazing! ⚽
