# Architecture Guide

This document explains the architecture of the AFCON Middleware project in simple terms.

## 🎯 What Problem Does This Solve?

**Problem**: You want to build iOS/macOS apps that display African Cup of Nations (AFCON) football data, but:
- API-Football only provides a REST API (slower, less efficient)
- You want real-time streaming of live match updates
- You need to minimize API calls to respect rate limits
- You want efficient binary protocol (gRPC) instead of JSON
- You don't want to waste API quota checking for matches weeks in the future

**Solution**: This middleware acts as a bridge with intelligent caching:
```
Your Apps → [gRPC] → AFCONMiddleware → [PostgreSQL + Redis + REST] → API-Football
```

Key features:
- **PostgreSQL**: Stores fixtures permanently for intelligent polling
- **Redis**: Caches teams, leagues, standings for fast access
- **Smart Polling**: Queries database to know when next match is (no repeated API calls)
- **gRPC Streaming**: Real-time updates when matches are live

## 📦 The Two Main Components

### 1. AFCONMiddleware (The Server)

**What it is**: A Vapor-based Swift server that runs 24/7

**Location**: Root directory (`Package.swift` in the root)

**What it does**:
- Fetches data from API-Football REST API
- Stores fixtures in PostgreSQL for intelligent polling
- Caches teams/leagues/standings in Redis
- Exposes data via gRPC for efficient streaming
- Provides HTTP debug endpoints for testing
- Adapts polling intervals based on next match time (12 hours → 30 seconds)

**Who runs it**: You (on your server, cloud, or locally during development)

**Targets provided**:
- **AFCONClient library**: Import this in your apps (lightweight, no server code)
- **App module**: The actual server code (Vapor + gRPC handlers)
- **Run executable**: Starts the server

**Ports**:
- gRPC: `50051` (for your apps to connect)
- HTTP: `8080` (for debugging with curl/Postman)

---

### 2. AFCONClient Example (Demo App)

**What it is**: A simple Swift command-line app that demonstrates usage

**Location**: `Examples/AFCONClient/`

**What it does**:
- Shows how to import the AFCONClient library
- Demonstrates making gRPC calls
- Shows how to handle streaming responses
- Serves as a template for your own apps

**Who runs it**: Developers learning how to integrate

**Purpose**: Educational reference for building your own iOS/macOS apps

---

## 🏗️ Complete Data Flow

### Scenario 1: Getting Team Data

```
┌─────────────────────────────────────────────────────────────────┐
│  Step 1: Your iOS App                                            │
│  ───────────────────────────────────────────────────────────    │
│  import AFCONClient                                              │
│  let client = Afcon_AFCONServiceClient(channel: channel)         │
│  let teams = try await client.getTeams(request)                  │
└──────────────────────────────┬──────────────────────────────────┘
                               │ gRPC Request (binary, fast)
                               │ Port 50051
┌──────────────────────────────▼──────────────────────────────────┐
│  Step 2: AFCONMiddleware Server                                  │
│  ───────────────────────────────────────────────────────────    │
│  Receives gRPC request → Checks Redis cache                      │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │                     │
            Cache HIT ✅            Cache MISS ❌
                    │                     │
                    │         ┌───────────▼──────────────┐
                    │         │ Step 3: Fetch from API   │
                    │         │ API-Football REST call   │
                    │         │ (JSON over HTTPS)        │
                    │         └───────────┬──────────────┘
                    │                     │
                    │         ┌───────────▼──────────────┐
                    │         │ Step 4: Cache in Redis   │
                    │         │ TTL: 12 hours for teams  │
                    │         └───────────┬──────────────┘
                    │                     │
                    └──────────┬──────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│  Step 5: Return to Your App                                      │
│  ───────────────────────────────────────────────────────────    │
│  Convert to gRPC response → Stream back to client                │
│  Response time: ~5-10ms (cached) or ~200-500ms (uncached)        │
└──────────────────────────────┬──────────────────────────────────┘
                               │ gRPC Response
                               ▼
                         Your App Receives Data
```

### Scenario 2: Streaming Live Matches

```
┌─────────────────────────────────────────────────────────────────┐
│  Your iOS App                                                    │
│  ───────────────────────────────────────────────────────────    │
│  let call = client.streamLiveMatches(request) { update in        │
│      print("Goal! \(update.homeTeam) scored!")                   │
│  }                                                               │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Opens gRPC stream
                               │ (connection stays open)
┌──────────────────────────────▼──────────────────────────────────┐
│  AFCONMiddleware Server                                          │
│  ───────────────────────────────────────────────────────────    │
│  1. Starts background polling loop (every 10 seconds)            │
│  2. Fetches live match data from API-Football                    │
│  3. Detects changes (goals, status updates, time)                │
│  4. Streams updates to your app in real-time                     │
│  5. Continues until your app disconnects                         │
└──────────────────────────────┬──────────────────────────────────┘
                               │ Continuous stream of updates
                               ▼
                         Your App Updates UI Live
```

---

## 🎯 Package Structure

### Root Package (AFCONMiddleware)

```swift
// Package.swift in root directory
let package = Package(
    name: "AFCONMiddleware",
    products: [
        // ✅ This is what your apps import
        .library(name: "AFCONClient", targets: ["AFCONClient"]),
    ],
    targets: [
        // Lightweight client library (no Vapor)
        .target(name: "AFCONClient", dependencies: ["GRPC", "SwiftProtobuf"]),

        // Server application (uses Vapor)
        .target(name: "App", dependencies: ["AFCONClient", "Vapor", "GRPC"]),

        // Runs the server
        .executableTarget(name: "Run", dependencies: ["App"]),
    ]
)
```

**Key Point**: `AFCONClient` target has NO Vapor dependency, making it lightweight for mobile apps.

### Example Package

```swift
// Examples/AFCONClient/Package.swift
let package = Package(
    name: "AFCONClient",
    products: [
        // This is just a demo executable
        .library(name: "AFCONClient", targets: ["AFCONClient"]),
    ],
    targets: [
        // Demo client showing usage
        .target(name: "AFCONClient", dependencies: ["GRPC", "SwiftProtobuf"])
    ]
)
```

---

## 🔄 Typical Development Workflow

### Phase 1: Setup (One-time)

1. Install dependencies (Redis, protobuf tools)
2. Generate protocol buffer code
3. Configure environment variables

### Phase 2: Run the Server

```bash
# Terminal 1: Start Redis
brew services start redis

# Terminal 2: Start AFCONMiddleware
swift run Run
```

Server is now running and ready to accept connections.

### Phase 3: Test with Example Client

```bash
# Terminal 3: Run example client
cd Examples/AFCONClient
swift run AFCONClient
```

You'll see output showing teams, fixtures, etc.

### Phase 4: Build Your Own App

Create your iOS/macOS app:

```swift
// YourApp/Package.swift
dependencies: [
    .package(path: "../APIPlayground")  // Points to AFCONMiddleware
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "AFCONClient", package: "APIPlayground")
        ]
    )
]
```

```swift
// YourApp/ContentView.swift
import SwiftUI
import AFCONClient
import GRPC

struct ContentView: View {
    @State private var teams: [Team] = []

    func loadTeams() async {
        let client = Afcon_AFCONServiceClient(channel: channel)
        let response = try await client.getTeams(request).response.get()
        teams = response.teams
    }

    var body: some View {
        List(teams) { team in
            Text(team.name)
        }
        .task { await loadTeams() }
    }
}
```

---

## 🚀 Deployment

### Development
- Run server locally on `localhost:50051`
- Apps connect to `localhost:50051`

### Production
- Deploy AFCONMiddleware to cloud (AWS, GCP, etc.)
- Apps connect to `your-server.com:50051`
- Enable TLS for secure gRPC

---

## ❓ Common Questions

### Q: Do I need to run the server to use AFCONClient?
**A**: Yes! AFCONClient is just a library. It connects to the AFCONMiddleware server, which does the actual data fetching.

### Q: Can I use AFCONClient without the server?
**A**: No. AFCONClient needs to connect to a running AFCONMiddleware server via gRPC.

### Q: What's the difference between root AFCONClient and Examples/AFCONClient?
**A**:
- **Root AFCONClient** (`Sources/AFCONClient/`): The actual library code that your apps import
- **Examples/AFCONClient**: A demo app showing how to use the library

### Q: Why are there two Package.swift files?
**A**:
- **Root Package.swift**: Defines the server + AFCONClient library
- **Examples/AFCONClient/Package.swift**: Standalone demo package for learning

### Q: Do I need Vapor in my iOS app?
**A**: No! The AFCONClient library has no Vapor dependency. Vapor only runs on the server.

### Q: Can I modify AFCONClient for my needs?
**A**: Yes! You can fork the repo and customize the protocol buffers, add new RPC methods, etc.

---

## 📝 Summary

**AFCONMiddleware** = Server (runs 24/7, fetches data, provides gRPC API)

**AFCONClient Library** = Client code (import in your apps to connect to server)

**Examples/AFCONClient** = Demo app (shows how to use the library)

**Your iOS/macOS App** = Imports AFCONClient library → Connects to AFCONMiddleware server → Gets data

---

Need more help? Check:
- `README.md` - Full documentation
- `QUICKSTART.md` - 5-minute setup guide
- `Examples/AFCONClient/README.md` - Client-specific guide
