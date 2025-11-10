# AFCON Middleware - gRPC API for African Cup of Nations

A high-performance middleware built with **Vapor (Swift)** that fetches data from the **API-Football REST API** and exposes it via **gRPC** for real-time football match data streaming.

## 📦 What's Inside This Project?

This repository contains **two main components**:

### 1. **AFCONMiddleware** (The Server - Root Package)
The main Swift package that acts as a gRPC/HTTP server. It bridges API-Football's REST API to gRPC clients.

**Location**: Root directory (`Package.swift`)

**What it provides**:
- **AFCONClient library**: A lightweight gRPC client library (no Vapor) for iOS/macOS apps
- **App module**: The Vapor server that runs the middleware
- **Run executable**: Runs the gRPC (port 50051) and HTTP (port 8080) servers

### 2. **AFCONClient Example** (Demo Client App)
A standalone example application showing how to use the AFCONClient library.

**Location**: `Examples/AFCONClient/`

**What it demonstrates**:
- How to connect to the gRPC middleware
- How to make RPC calls (GetLeague, GetTeams, GetFixtures, etc.)
- How to stream live match updates
- Integration patterns for your own apps

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────┐
│          Your iOS/macOS/Server Applications          │
│     (Use AFCONClient library from root package)      │
└───────────────────────┬─────────────────────────────┘
                        │ gRPC
                        │ Port 50051
┌───────────────────────▼─────────────────────────────┐
│              AFCON Middleware Server                 │
│           (Root Package - "AFCONMiddleware")         │
│  ┌─────────────────────────────────────────────┐    │
│  │  HTTP Server (8080) + gRPC Server (50051)   │    │
│  └─────────────────────┬───────────────────────┘    │
│                        │                             │
│  ┌─────────────────────▼───────────────────────┐    │
│  │    PostgreSQL Database (localhost:5432)     │    │
│  │      - Fixtures cache (intelligent poll)    │    │
│  │      - Next match timestamps                │    │
│  └─────────────────────┬───────────────────────┘    │
│                        │                             │
│  ┌─────────────────────▼───────────────────────┐    │
│  │       Redis Cache (localhost:6379)          │    │
│  │      - Teams, leagues, standings cache      │    │
│  └─────────────────────┬───────────────────────┘    │
│                        │                             │
│  ┌─────────────────────▼───────────────────────┐    │
│  │       API-Football Client (HTTP/REST)       │    │
│  └─────────────────────┬───────────────────────┘    │
└────────────────────────┼───────────────────────────┘
                         │ HTTPS REST
                         ▼
                  ┌─────────────┐
                  │API-Football │
                  │     API     │
                  └─────────────┘

┌─────────────────────────────────────────────────────┐
│         AFCONClient Example (Examples/ dir)          │
│    A demo app showing how to use AFCONClient         │
└─────────────────────────────────────────────────────┘
```

### Key Features

- **gRPC API**: High-performance protocol buffers for efficient data transfer
- **Real-time Streaming**: Server-side streaming for live match updates
- **PostgreSQL Database**: Persistent storage for fixtures with intelligent polling
- **Redis Caching**: Intelligent caching for teams, leagues, and standings
- **Smart Polling**: Database-driven polling that adapts based on next fixture time
- **REST API**: Optional HTTP endpoints for debugging and testing
- **Type-Safe**: Full Swift type safety with Codable models
- **Concurrent**: Runs both HTTP and gRPC servers simultaneously

## 📋 Prerequisites

1. **Swift** 5.9 or later
2. **PostgreSQL** (for fixture storage and intelligent polling)
3. **Redis** (for caching teams, leagues, standings)
4. **Protocol Buffers Compiler** and plugins:
   ```bash
   brew install protobuf swift-protobuf
   ```
5. **gRPC Swift Plugin**:
   ```bash
   git clone https://github.com/grpc/grpc-swift.git
   cd grpc-swift
   make plugins
   sudo cp .build/release/protoc-gen-grpc-swift /usr/local/bin/
   ```

## 🚀 Quick Start

### Understanding the Workflow

**There are TWO ways to use this project:**

#### Option A: Run the Middleware Server (for production/testing)
Run the server to provide gRPC and HTTP APIs for your apps.

#### Option B: Try the Example Client (for learning)
Run the demo client to see how to integrate the AFCONClient library into your apps.

---

### Option A: Running the Middleware Server

This starts the gRPC and HTTP servers that your apps will connect to.

**Step 1: Install Dependencies**

```bash
# Install PostgreSQL
brew install postgresql
brew services start postgresql

# Install Redis
brew install redis
brew services start redis

# Install protobuf tools
brew install protobuf swift-protobuf
```

**Step 2: Generate Protocol Buffer Code**

```bash
./generate-protos.sh
```

This generates Swift code from `Protos/afcon.proto` into `Sources/App/gRPC/Generated/`

**Step 3: Configure Environment**

```bash
cp .env.example .env
# Edit .env with your API-Football API key
```

**Step 4: Build and Run the Server**

```bash
# Build the project
swift build

# Run the middleware server
swift run Run
```

The application will start:
- **gRPC Server**: `localhost:50051` (for client apps)
- **HTTP Server**: `localhost:8080` (for debugging)

**Step 5: Test the Server**

```bash
# HTTP endpoints (for quick testing)
curl http://localhost:8080/health
curl http://localhost:8080/api/v1/league/6/season/2025/teams
```

---

### Option B: Running the Example Client

This demonstrates how to use the AFCONClient library in your own apps.

**Prerequisites**: The middleware server must be running (see Option A above)

**Step 1: Navigate to Example**

```bash
cd Examples/AFCONClient/
```

**Step 2: Build and Run**

```bash
swift build
swift run AFCONClient
```

You'll see output showing:
- League information
- Team listings
- Fixtures
- Live match streaming (if matches are live)

**Step 3: Study the Code**

Open `Examples/AFCONClient/Sources/main.swift` to see:
- How to create a gRPC connection
- How to make RPC calls
- How to handle streaming responses
- Error handling patterns

## 🎯 API Endpoints

### gRPC Services

Defined in `Protos/afcon.proto`:

#### 1. GetLeague
Get league information including seasons and coverage.
```protobuf
rpc GetLeague(LeagueRequest) returns (LeagueResponse)
```

#### 2. GetTeams
Get all teams participating in a league season.
```protobuf
rpc GetTeams(TeamsRequest) returns (TeamsResponse)
```

#### 3. GetFixtures
Get fixtures/matches for a league season.
```protobuf
rpc GetFixtures(FixturesRequest) returns (FixturesResponse)
```

#### 4. StreamLiveMatches (🔴 Live Streaming)
Real-time server-side streaming of live match updates.
```protobuf
rpc StreamLiveMatches(LiveMatchRequest) returns (stream LiveMatchUpdate)
```

#### 5. GetStandings
Get league standings/tables.
```protobuf
rpc GetStandings(StandingsRequest) returns (StandingsResponse)
```

#### 6. GetTeamDetails
Get detailed information about a specific team.
```protobuf
rpc GetTeamDetails(TeamDetailsRequest) returns (TeamDetailsResponse)
```

#### 7. SyncFixtures (🔄 Database Sync)
Sync all fixtures from API-Football to the database (admin operation).
```protobuf
rpc SyncFixtures(SyncFixturesRequest) returns (SyncFixturesResponse)
```

**Important**: Call this endpoint once to populate the database with fixtures. After syncing, the server will use the database for intelligent polling instead of repeatedly hitting the API.

### HTTP REST Endpoints (Debug)

For testing and debugging:

- `GET /health` - Health check
- `GET /api/status` - API Football account status
- `GET /api/v1/league/:id/season/:season` - Get league info
- `GET /api/v1/league/:id/season/:season/teams` - Get teams
- `GET /api/v1/league/:id/season/:season/fixtures` - Get fixtures
- `GET /api/v1/league/:id/live` - Get live fixtures
- `GET /api/v1/league/:id/season/:season/standings` - Get standings
- `DELETE /api/v1/cache/league/:id/season/:season` - Clear cache

## 📊 Example Usage

### HTTP Testing (curl)

```bash
# Get AFCON 2025 league info
curl http://localhost:8080/api/v1/league/6/season/2025

# Get teams
curl http://localhost:8080/api/v1/league/6/season/2025/teams

# Get live fixtures
curl http://localhost:8080/api/v1/league/6/live

# Check health
curl http://localhost:8080/health
```

### gRPC Client (Swift)

See `Examples/AFCONClient/` for a complete Swift client example.

```swift
import GRPC
import NIO

let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
defer {
    try? group.syncShutdownGracefully()
}

let channel = try GRPCChannelPool.with(
    target: .host("localhost", port: 50051),
    transportSecurity: .plaintext,
    eventLoopGroup: group
)

let client = Afcon_AFCONServiceClient(channel: channel)

// Get league info
let request = Afcon_LeagueRequest.with {
    $0.leagueID = 6
    $0.season = 2025
}

let response = try client.getLeague(request).response.wait()
print("League: \(response.league.name)")

// Stream live matches
let liveRequest = Afcon_LiveMatchRequest.with {
    $0.leagueID = 6
    $0.season = 2025
}

let call = client.streamLiveMatches(liveRequest) { update in
    print("⚽ \(update.eventType): Fixture \(update.fixtureID)")
}

try call.status.wait()
```

## 🔌 Integrating Into Your Own App

### For iOS/macOS Applications

**Step 1: Add AFCONClient Library to Your Package.swift**

```swift
dependencies: [
    .package(path: "/path/to/APIPlayground")
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

**Step 2: Import and Use**

```swift
import AFCONClient
import GRPC
import NIO

// Create connection
let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
let channel = try GRPCChannelPool.with(
    target: .host("your-server.com", port: 50051),
    transportSecurity: .tls,
    eventLoopGroup: eventLoopGroup
)

let client = Afcon_AFCONServiceClient(channel: channel)

// Make requests
let teams = try await client.getTeams(request).response.get()
```

**Step 3: Build Your UI**

The AFCONClient library gives you:
- Type-safe protobuf models
- gRPC client stubs
- No Vapor dependency (lightweight for mobile)

You can build SwiftUI/UIKit views on top of this.

### For Server-to-Server Communication

If you have another Swift server that needs AFCON data:

```swift
// In your server's Package.swift
dependencies: [
    .package(url: "https://github.com/yourusername/APIPlayground.git", from: "1.0.0")
]

// Use the same AFCONClient library
import AFCONClient
```

## 🔧 Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `API_FOOTBALL_KEY` | Your API-Football API key | Required |
| `DATABASE_URL` | PostgreSQL connection URL | `postgresql://postgres:postgres@localhost:5432/afcon` |
| `PGHOST` | PostgreSQL host (if not using DATABASE_URL) | `127.0.0.1` |
| `PGPORT` | PostgreSQL port (if not using DATABASE_URL) | `5432` |
| `PGUSER` | PostgreSQL username (if not using DATABASE_URL) | `postgres` |
| `PGPASSWORD` | PostgreSQL password (if not using DATABASE_URL) | `postgres` |
| `PGDATABASE` | PostgreSQL database name (if not using DATABASE_URL) | `afcon` |
| `REDIS_URL` | Redis connection URL | `redis://localhost:6379` |
| `PORT` | HTTP server port | `8080` |
| `GRPC_PORT` | gRPC server port | `50051` |
| `ENVIRONMENT` | Environment (development/production) | `development` |
| `LOG_LEVEL` | Logging level | `info` |

### Cache TTL Settings

Configured in `Sources/App/Services/CacheService.swift`:

- **League Info**: 24 hours (rarely changes)
- **Teams**: 12 hours (rarely changes)
- **Fixtures**: 30 minutes (can change)
- **Live Matches**: 10 seconds (frequent updates)
- **Standings**: 1 hour (updates after matches)
- **Players**: 12 hours (rarely changes)

## 📁 Project Structure

```
APIPlayground/                       # Root directory
├── Package.swift                    # Main package: "AFCONMiddleware"
│                                    # Contains: AFCONClient library, App, Run
├── Protos/
│   └── afcon.proto                  # Protocol Buffer definitions
│
├── Sources/                         # Main middleware server code
│   ├── AFCONClient/                 # Client library (for iOS/macOS apps)
│   │   └── *.swift                  # gRPC client code (no Vapor dependency)
│   ├── App/                         # Vapor server application
│   │   ├── configure.swift          # Vapor configuration
│   │   ├── routes.swift             # HTTP debug endpoints
│   │   ├── Models/
│   │   │   ├── APIFootballModels.swift  # REST API models
│   │   │   └── DB/
│   │   │       ├── FixtureEntity.swift  # Fluent fixture model
│   │   │       └── LeagueEntity.swift   # Fluent league model
│   │   ├── Repositories/
│   │   │   └── FixtureRepository.swift  # Database operations for fixtures
│   │   ├── Services/
│   │   │   ├── APIFootballClient.swift  # HTTP client for API-Football
│   │   │   └── CacheService.swift       # Redis caching layer
│   │   └── gRPC/
│   │       ├── Server/
│   │       │   ├── AFCONServiceProvider.swift     # gRPC handlers
│   │       │   └── LiveMatchStreamProvider.swift  # Live streaming
│   │       └── Generated/           # Generated proto code
│   └── Run/
│       └── main.swift               # Server entry point (starts gRPC + HTTP)
│
├── Examples/                        # Example client applications
│   └── AFCONClient/                 # Demo client showing library usage
│       ├── Package.swift            # Standalone package
│       ├── README.md                # Client-specific docs
│       └── Sources/
│           └── main.swift           # Example RPC calls
│
├── Tests/
│   ├── AppTests/                    # Server tests
│   └── GRPCClient/                  # Test gRPC client
│
├── .env.example                     # Environment template
├── generate-protos.sh               # Proto generation script
├── Makefile                         # Build commands
└── README.md                        # This file
```

### 🎯 Package Targets Explained

**Root Package (`Package.swift`)** provides:

1. **`.library(name: "AFCONClient")`**
   - Lightweight gRPC client library
   - Import this in your iOS/macOS apps
   - No Vapor dependency

2. **`.target(name: "App")`**
   - The Vapor server application
   - Uses AFCONClient + API-Football + Redis
   - Internal use only (not exposed as library)

3. **`.executableTarget(name: "Run")`**
   - Runs the middleware server
   - Starts both gRPC (50051) and HTTP (8080) servers

4. **`.executableTarget(name: "GRPCClient")`**
   - Test client for development
   - Located in `Tests/GRPCClient/`

**Example Package (`Examples/AFCONClient/Package.swift`)** provides:

1. **`.library(name: "AFCONClient")`**
   - Demonstrates how external apps would use the library
   - Shows best practices for integration

## 🎮 African Cup of Nations 2025

This middleware is pre-configured for AFCON 2025:

- **League ID**: 6
- **Season**: 2025
- **Start Date**: December 21, 2025
- **End Date**: December 31, 2025
- **Teams**: 24 national teams

### Example Teams
- Senegal (SEN)
- Nigeria (NIG)
- Morocco (MOR)
- Egypt (EGY)
- Ivory Coast (IVO)
- Cameroon (CAM)
- Algeria (ALG)
- ...and 17 more

## 🔄 Live Match Streaming

The `StreamLiveMatches` RPC provides real-time updates:

1. **Match Started**: When a match goes live
2. **Goal**: When a goal is scored
3. **Status Update**: Match status changes (HT, FT, etc.)
4. **Time Update**: Significant time progressions
5. **Match Finished**: When a match ends

### Intelligent Polling

The server now uses **database-driven intelligent polling** instead of fixed intervals:

- **No live matches + next match >1 day away**: Sleep 12 hours
- **No live matches + next match 6 hours - 1 day**: Sleep 3 hours
- **No live matches + next match 1-6 hours**: Sleep 30 minutes
- **No live matches + next match <1 hour**: Poll every 30 seconds
- **Live matches detected**: Poll every 30 seconds

This drastically reduces unnecessary API calls. See [DATABASE_INTEGRATION.md](DATABASE_INTEGRATION.md) for details.

## 📈 Performance & Rate Limiting

- **Caching**: Redis caching minimizes API calls
- **Rate Limits**: API-Football free plan: 100 requests/day
- **Concurrent**: Non-blocking async/await throughout
- **Efficient**: gRPC binary protocol reduces bandwidth

## 🛠️ Development

### Running Tests

```bash
swift test
```

### Clearing Cache

```bash
# Via HTTP API
curl -X DELETE http://localhost:8080/api/v1/cache/league/6/season/2025

# Via Redis CLI
redis-cli
> KEYS afcon:*
> FLUSHDB
```

### Monitoring

```bash
# Check Redis
redis-cli MONITOR

# Check logs
tail -f /path/to/logs
```

## 📝 TODO / Future Enhancements

- [ ] Add authentication/authorization
- [ ] Implement player statistics endpoints
- [ ] Add predictions and odds endpoints
- [ ] WebSocket support for browsers
- [ ] Docker containerization
- [ ] Kubernetes deployment configs
- [ ] Metrics and monitoring (Prometheus)
- [ ] API rate limiting middleware
- [ ] GraphQL API option
- [ ] Unit and integration tests

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

MIT License - See LICENSE file for details

## 🙏 Acknowledgments

- [API-Football](https://www.api-football.com/) for the football data API
- [Vapor](https://vapor.codes/) Swift web framework
- [gRPC Swift](https://github.com/grpc/grpc-swift) for gRPC support
- African Cup of Nations organizers

## 📞 Support

For issues and questions:
- Open an issue on GitHub
- Check API-Football documentation: https://www.api-football.com/documentation-v3

---

Built with ❤️ and Swift
