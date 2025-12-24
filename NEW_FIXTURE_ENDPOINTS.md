# New Fixture Endpoints Guide

## Overview

New endpoints have been added to get fixtures by ID, by date, and to retrieve match events.

## HTTP REST Endpoints

### 1. Get Fixture by ID

**URL:** `GET /api/v1/fixture/:id`

**Description:** Get a single fixture with all its details

**Parameters:**
- `id` (path) - Fixture ID

**Example:**
```bash
curl http://localhost:8080/api/v1/fixture/12345
```

**Response:** Single `FixtureData` object with complete fixture information

---

### 2. Get Fixture Events

**URL:** `GET /api/v1/fixture/:id/events`

**Description:** Get all events (goals, cards, substitutions) for a specific fixture

**Parameters:**
- `id` (path) - Fixture ID

**Example:**
```bash
curl http://localhost:8080/api/v1/fixture/12345/events
```

**Response:** Array of `FixtureEvent` objects

**Event Types:**
- `Goal` - Goals scored
- `Card` - Yellow/Red cards
- `subst` - Player substitutions
- `Var` - VAR decisions

**Example Response:**
```json
[
  {
    "time": {
      "elapsed": 23,
      "extra": null
    },
    "team": {
      "id": 33,
      "name": "Manchester United",
      "logo": "https://..."
    },
    "player": {
      "id": 2935,
      "name": "Bruno Fernandes"
    },
    "assist": {
      "id": 882,
      "name": "Marcus Rashford"
    },
    "type": "Goal",
    "detail": "Normal Goal",
    "comments": null
  },
  {
    "time": {
      "elapsed": 45,
      "extra": 2
    },
    "team": {
      "id": 50,
      "name": "Manchester City",
      "logo": "https://..."
    },
    "player": {
      "id": 635,
      "name": "Kevin De Bruyne"
    },
    "assist": null,
    "type": "Card",
    "detail": "Yellow Card",
    "comments": "Foul"
  }
]
```

---

### 3. Get Fixtures by Date

**URL:** `GET /api/v1/fixtures/date/:date`

**Description:** Get all fixtures for a specific date, optionally filtered by league

**Parameters:**
- `date` (path) - Date in YYYY-MM-DD format
- `league` (query, optional) - League ID to filter
- `season` (query, optional) - Season (required if league is specified)

**Examples:**
```bash
# All fixtures on a specific date
curl http://localhost:8080/api/v1/fixtures/date/2025-01-15

# Fixtures for a specific league and date
curl "http://localhost:8080/api/v1/fixtures/date/2025-01-15?league=39&season=2024"

# Premier League fixtures on January 15, 2025
curl "http://localhost:8080/api/v1/fixtures/date/2025-01-15?league=39&season=2024"
```

**Response:** Array of `FixtureData` objects

---

### 4. Get Today's Upcoming Fixtures (Already Added)

**URL:** `GET /api/v1/league/:id/season/:season/today`

**Description:** Get upcoming fixtures scheduled for today that haven't started yet

**Example:**
```bash
curl http://localhost:8080/api/v1/league/39/season/2024/today
```

---

## gRPC Methods

### 1. GetFixtureById

**Service:** `AFCONService`

**Request:**
```protobuf
message FixtureByIdRequest {
  int32 fixture_id = 1;
}
```

**Response:**
```protobuf
message FixtureResponse {
  Fixture fixture = 1;
}
```

**Swift Example:**
```swift
let request = Afcon_FixtureByIdRequest.with {
    $0.fixtureID = 12345
}

let response = try await client.getFixtureById(request).response.get()
let fixture = response.fixture
print("Match: \(fixture.teams.home.name) vs \(fixture.teams.away.name)")
```

---

### 2. GetFixtureEvents

**Request:**
```protobuf
message FixtureEventsRequest {
  int32 fixture_id = 1;
}
```

**Response:**
```protobuf
message FixtureEventsResponse {
  repeated FixtureEvent events = 1;
}
```

**Swift Example:**
```swift
let request = Afcon_FixtureEventsRequest.with {
    $0.fixtureID = 12345
}

let response = try await client.getFixtureEvents(request).response.get()
for event in response.events {
    print("\(event.time.elapsed)' - \(event.type): \(event.detail)")
    print("Player: \(event.player.name)")
}
```

---

### 3. GetFixturesByDate

**Request:**
```protobuf
message FixturesByDateRequest {
  string date = 1;        // YYYY-MM-DD format
  int32 league_id = 2;    // Optional
  int32 season = 3;       // Optional (required if league_id is set)
}
```

**Response:**
```protobuf
message FixturesResponse {
  repeated Fixture fixtures = 1;
}
```

**Swift Example:**
```swift
// All fixtures for a date
let request = Afcon_FixturesByDateRequest.with {
    $0.date = "2025-01-15"
}

// Fixtures for specific league and date
let request = Afcon_FixturesByDateRequest.with {
    $0.date = "2025-01-15"
    $0.leagueID = 39
    $0.season = 2024
}

let response = try await client.getFixturesByDate(request).response.get()
for fixture in response.fixtures {
    print("\(fixture.teams.home.name) vs \(fixture.teams.away.name)")
}
```

---

## Complete API Reference

### All Available Endpoints

```bash
# Health & Status
GET  /health                                      # Health check
GET  /api/status                                  # API account status

# League & Teams
GET  /api/v1/league/:id/season/:season            # League info
GET  /api/v1/league/:id/season/:season/teams      # Teams
GET  /api/v1/team/:id                             # Team details

# Fixtures
GET  /api/v1/league/:id/season/:season/fixtures   # All fixtures
GET  /api/v1/league/:id/season/:season/today      # Today's upcoming
GET  /api/v1/league/:id/live                      # Live fixtures
GET  /api/v1/fixture/:id                          # ⭐ NEW: Fixture by ID
GET  /api/v1/fixture/:id/events                   # ⭐ NEW: Fixture events
GET  /api/v1/fixtures/date/:date                  # ⭐ NEW: Fixtures by date

# Standings
GET  /api/v1/league/:id/season/:season/standings  # Standings

# Cache
DELETE /api/v1/cache/league/:id/season/:season    # Clear cache
```

---

## Usage Examples

### Get Match Details with Events

```bash
# 1. Get fixture ID from a list
curl http://localhost:8080/api/v1/league/39/season/2024/today

# 2. Get full fixture details
curl http://localhost:8080/api/v1/fixture/12345

# 3. Get match events (goals, cards, etc.)
curl http://localhost:8080/api/v1/fixture/12345/events
```

### Get All Matches for Today

```bash
# Get today's date
TODAY=$(date +%Y-%m-%d)

# Get all fixtures for today
curl "http://localhost:8080/api/v1/fixtures/date/$TODAY"

# Get Premier League fixtures for today
curl "http://localhost:8080/api/v1/fixtures/date/$TODAY?league=39&season=2024"
```

### Track a Specific Match

```swift
import AFCONClient

class MatchDetailViewModel: ObservableObject {
    @Published var fixture: Afcon_Fixture?
    @Published var events: [Afcon_FixtureEvent] = []

    func loadMatch(id: Int32) async {
        do {
            // Get fixture details
            let fixtureRequest = Afcon_FixtureByIdRequest.with {
                $0.fixtureID = id
            }
            let fixtureResponse = try await client.getFixtureById(fixtureRequest).response.get()
            self.fixture = fixtureResponse.fixture

            // Get match events
            let eventsRequest = Afcon_FixtureEventsRequest.with {
                $0.fixtureID = id
            }
            let eventsResponse = try await client.getFixtureEvents(eventsRequest).response.get()
            self.events = eventsResponse.events
        } catch {
            print("Error loading match: \(error)")
        }
    }
}
```

---

## Enabling the gRPC Methods

The proto file has been updated. To enable these methods:

### Step 1: Regenerate Protocol Buffers
```bash
cd /Users/audrey/Documents/Projects/Cheulah/CAN2025/APIPlayground.nosync
./generate-protos.sh
```

### Step 2: Implement gRPC Handlers

Add to `Sources/App/gRPC/Server/AFCONServiceProvider.swift`:

```swift
/// Get fixture by ID
public func getFixtureById(
    request: Afcon_FixtureByIdRequest,
    context: GRPC.GRPCAsyncServerCallContext
) async throws -> Afcon_FixtureResponse {
    logger.info("gRPC: GetFixtureById - id=\(request.fixtureID)")

    let fixture = try await apiClient.getFixtureById(fixtureId: Int(request.fixtureID))

    var response = Afcon_FixtureResponse()
    response.fixture = convertToFixture(fixture)
    return response
}

/// Get fixture events
public func getFixtureEvents(
    request: Afcon_FixtureEventsRequest,
    context: GRPC.GRPCAsyncServerCallContext
) async throws -> Afcon_FixtureEventsResponse {
    logger.info("gRPC: GetFixtureEvents - id=\(request.fixtureID)")

    let events = try await apiClient.getFixtureEvents(fixtureId: Int(request.fixtureID))

    var response = Afcon_FixtureEventsResponse()
    response.events = events.map { convertToEvent($0) }
    return response
}

/// Get fixtures by date
public func getFixturesByDate(
    request: Afcon_FixturesByDateRequest,
    context: GRPC.GRPCAsyncServerCallContext
) async throws -> Afcon_FixturesResponse {
    logger.info("gRPC: GetFixturesByDate - date=\(request.date)")

    let fixturesData: [FixtureData]

    if request.leagueID > 0 && request.season > 0 {
        // Get for specific league
        fixturesData = try await cache.getOrFetchFixtures(
            leagueID: Int(request.leagueID),
            season: Int(request.season),
            date: request.date,
            teamID: nil,
            live: false
        ) {
            try await apiClient.getFixtures(
                leagueId: Int(request.leagueID),
                season: Int(request.season),
                date: request.date,
                teamId: nil,
                live: false
            )
        }
    } else {
        // Get all fixtures for date
        fixturesData = try await apiClient.getFixtures(
            leagueId: 0,
            season: 0,
            date: request.date,
            teamId: nil,
            live: false
        )
    }

    var response = Afcon_FixturesResponse()
    response.fixtures = fixturesData.map { convertToFixture($0) }
    return response
}

// Helper to convert FixtureEvent
private func convertToEvent(_ event: FixtureEvent) -> Afcon_FixtureEvent {
    var proto = Afcon_FixtureEvent()
    proto.time.elapsed = Int32(event.time.elapsed)
    if let extra = event.time.extra {
        proto.time.extra = Int32(extra)
    }
    proto.team.id = Int32(event.team.id)
    proto.team.name = event.team.name
    proto.team.logo = event.team.logo
    proto.player.id = Int32(event.player.id)
    proto.player.name = event.player.name
    if let assist = event.assist {
        proto.assist.id = Int32(assist.id)
        proto.assist.name = assist.name
    }
    proto.type = event.type
    proto.detail = event.detail
    proto.comments = event.comments ?? ""
    return proto
}
```

### Step 3: Rebuild
```bash
swift build
swift run Run
```

---

## Testing

### Test Fixture by ID
```bash
# Find a fixture ID first
curl http://localhost:8080/api/v1/league/39/season/2024/fixtures | jq '.[0].fixture.id'

# Get that fixture
curl http://localhost:8080/api/v1/fixture/FIXTURE_ID
```

### Test Fixture Events
```bash
curl http://localhost:8080/api/v1/fixture/FIXTURE_ID/events | jq
```

### Test Fixtures by Date
```bash
# Today's date
curl http://localhost:8080/api/v1/fixtures/date/$(date +%Y-%m-%d)

# Specific date
curl http://localhost:8080/api/v1/fixtures/date/2025-01-15

# With league filter
curl "http://localhost:8080/api/v1/fixtures/date/2025-01-15?league=39&season=2024"
```

---

## Summary

✅ **3 new HTTP endpoints** added:
1. Get fixture by ID
2. Get fixture events
3. Get fixtures by date

✅ **3 new gRPC methods** defined:
1. GetFixtureById
2. GetFixtureEvents
3. GetFixturesByDate

✅ **HTTP endpoints work now** - No rebuild needed
✅ **gRPC methods need proto regeneration** - Run `./generate-protos.sh`

All endpoints support caching and follow the same patterns as existing endpoints!
