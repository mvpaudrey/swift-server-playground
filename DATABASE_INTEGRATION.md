# Database Integration Guide

## Overview

The AFCON Middleware now uses **PostgreSQL** for persistent storage of fixtures, enabling intelligent polling and eliminating repeated API calls for fixtures that may be weeks or months away.

## Why Database Storage?

### The Problem
Previously, the server would repeatedly call the API-Football API to check for upcoming fixtures, even if the next match was weeks away. This was inefficient and consumed API quota unnecessarily.

### The Solution
- **Store fixtures in PostgreSQL** once after fetching from API
- **Query database** for next fixture timestamp (no API calls)
- **Intelligent polling** that adapts based on when the next match actually starts
- **Efficient updates** during live matches (upsert pattern)

## Architecture

```
┌──────────────────────────────────────────────────────┐
│  Workflow: Initial Fixture Sync                      │
├──────────────────────────────────────────────────────┤
│  1. Client calls SyncFixtures RPC                    │
│  2. Server fetches all fixtures from API-Football    │
│  3. Server batch upserts to PostgreSQL               │
│  4. Database now contains all fixtures               │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│  Workflow: Intelligent Polling (Live Streaming)      │
├──────────────────────────────────────────────────────┤
│  1. Server queries DB for next upcoming timestamp    │
│  2. Calculates time until next match                 │
│  3. Adjusts polling interval:                        │
│     - >1 day away: sleep 12 hours                    │
│     - 6 hours - 1 day: sleep 3 hours                 │
│     - 1-6 hours: sleep 30 minutes                    │
│     - <1 hour: poll every 30 seconds                 │
│  4. When match starts: fetch live data from API      │
│  5. Update database with live scores                 │
└──────────────────────────────────────────────────────┘
```

## Database Schema

### FixtureEntity Table

The `fixtures` table stores comprehensive fixture data:

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `api_fixture_id` | INT | Unique fixture ID from API-Football |
| `league_id` | INT | League identifier |
| `season` | INT | Season year (e.g., 2025) |
| `timestamp` | INT | Unix timestamp of match kickoff |
| `date` | DATETIME | Match date and time |
| `status_short` | STRING | Match status (NS, LIVE, FT, etc.) |
| `status_long` | STRING | Full status description |
| `status_elapsed` | INT | Elapsed minutes |
| `home_team_id` | INT | Home team ID |
| `home_team_name` | STRING | Home team name |
| `home_goals` | INT | Home team goals |
| `away_team_id` | INT | Away team ID |
| `away_team_name` | STRING | Away team name |
| `away_goals` | INT | Away team goals |
| `venue_id` | INT | Venue ID |
| `venue_name` | STRING | Venue name |
| `venue_city` | STRING | Venue city |
| `referee` | STRING | Referee name |
| `competition` | STRING | Competition name (e.g., "AFCON 2025") |
| ... | ... | 33 total fields |

**Indexes**:
- Primary key on `id`
- Unique constraint on `api_fixture_id`

## Key Components

### 1. FixtureEntity (`Sources/App/Models/DB/FixtureEntity.swift`)

Fluent model representing fixtures in PostgreSQL:

```swift
final class FixtureEntity: Model, Content {
    static let schema = "fixtures"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "api_fixture_id")
    var apiFixtureId: Int  // Unique

    @Field(key: "timestamp")
    var timestamp: Int

    @Field(key: "status_short")
    var statusShort: String

    // ... 30+ more fields
}
```

### 2. FixtureRepository (`Sources/App/Repositories/FixtureRepository.swift`)

Database operations for fixtures:

```swift
final class FixtureRepository {
    // Get next upcoming fixture timestamp (NO API CALL!)
    func getNextUpcomingTimestamp(leagueId: Int, season: Int) async throws -> Int?

    // Get all fixtures at a specific timestamp
    func getFixturesAtTimestamp(leagueId: Int, season: Int, timestamp: Int) async throws -> [FixtureEntity]

    // Upsert single fixture
    func upsert(from fixtureData: FixtureData, leagueId: Int, season: Int, competition: String) async throws

    // Batch upsert fixtures
    func upsertBatch(fixtures: [FixtureData], leagueId: Int, season: Int, competition: String) async throws

    // Get all upcoming fixtures
    func getUpcomingFixtures(leagueId: Int, season: Int) async throws -> [FixtureEntity]

    // Check if fixtures exist
    func hasFixtures(leagueId: Int, season: Int) async throws -> Bool
}
```

### 3. Migration (`CreateFixtureEntity`)

Automatically creates the database table on server startup:

```swift
struct CreateFixtureEntity: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(FixtureEntity.schema)
            .id()
            .field("api_fixture_id", .int, .required)
            .field("league_id", .int, .required)
            .field("season", .int, .required)
            .field("timestamp", .int, .required)
            // ... all fields
            .unique(on: "api_fixture_id")  // Prevent duplicates
            .create()
    }
}
```

## gRPC Endpoints

### SyncFixtures

Syncs all fixtures from API-Football to the database.

**Request**:
```protobuf
message SyncFixturesRequest {
  int32 league_id = 1;      // e.g., 6 for AFCON
  int32 season = 2;         // e.g., 2025
  string competition = 3;   // e.g., "AFCON 2025"
}
```

**Response**:
```protobuf
message SyncFixturesResponse {
  bool success = 1;           // true if successful
  int32 fixtures_synced = 2;  // number of fixtures synced
  string message = 3;         // success/error message
}
```

**Usage Example** (Swift):
```swift
let request = Afcon_SyncFixturesRequest.with {
    $0.leagueID = 6
    $0.season = 2025
    $0.competition = "AFCON 2025"
}

let response = try await client.syncFixtures(request).response.get()
print("Synced \(response.fixturesSynced) fixtures")
```

## Setup Instructions

### 1. Install PostgreSQL

```bash
# macOS
brew install postgresql
brew services start postgresql

# Create database
createdb afcon
```

### 2. Configure Environment

```bash
# Option A: Use DATABASE_URL
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/afcon"

# Option B: Use individual variables
export PGHOST="127.0.0.1"
export PGPORT="5432"
export PGUSER="postgres"
export PGPASSWORD="postgres"
export PGDATABASE="afcon"
```

### 3. Start Server

The server will automatically:
1. Connect to PostgreSQL
2. Run migrations (create tables)
3. Start accepting connections

```bash
swift run Run
```

Output:
```
✅ Application configured successfully
📡 HTTP Server will run on port 8080
📡 gRPC Server will run on port 50051
✅ gRPC Server started on port 50051
```

### 4. Sync Fixtures (First Time)

Call the `SyncFixtures` RPC to populate the database:

```swift
// From your iOS app or test client
let syncRequest = Afcon_SyncFixturesRequest.with {
    $0.leagueID = 6
    $0.season = 2025
    $0.competition = "AFCON 2025"
}

let syncResponse = try await client.syncFixtures(syncRequest).response.get()
if syncResponse.success {
    print("✅ Synced \(syncResponse.fixturesSynced) fixtures")
} else {
    print("❌ Sync failed: \(syncResponse.message)")
}
```

### 5. Verify Database

```bash
# Connect to PostgreSQL
psql -d afcon

# Check fixtures
SELECT COUNT(*) FROM fixtures;
SELECT home_team_name, away_team_name, timestamp FROM fixtures ORDER BY timestamp LIMIT 5;
```

## Intelligent Polling Logic

The live match streaming now uses the database to determine polling intervals:

```swift
// AFCONServiceProvider.swift
func streamLiveMatches(...) async throws {
    while !Task.isCancelled {
        // Get live fixtures from API
        let liveFixtures = try await apiClient.getLiveFixtures(...)

        if liveFixtures.isEmpty {
            // No live matches - query database for next fixture
            let nextTimestamp = try await fixtureRepository.getNextUpcomingTimestamp(
                leagueId: leagueId,
                season: season
            )

            // Calculate time until next match
            let timeUntilMatch = nextFixtureDate.timeIntervalSince(now)

            // Adjust polling interval
            if timeUntilMatch > 86400 {
                sleepInterval = 12 * 60 * 60  // 12 hours
            } else if timeUntilMatch > 21600 {
                sleepInterval = 3 * 60 * 60   // 3 hours
            } else if timeUntilMatch > 3600 {
                sleepInterval = 30 * 60       // 30 minutes
            } else {
                sleepInterval = 30            // 30 seconds
            }
        }

        try await Task.sleep(nanoseconds: sleepInterval * 1_000_000_000)
    }
}
```

## Benefits

### Before (API-Only)
- ❌ Repeated API calls even when no matches for weeks
- ❌ Wasted API quota
- ❌ Fixed 30-second polling regardless of schedule
- ❌ No persistent storage

### After (Database-Backed)
- ✅ Single API call to populate database
- ✅ Query database (no API calls) for next match time
- ✅ Adaptive polling intervals (12 hours → 30 seconds)
- ✅ Persistent fixture storage
- ✅ Efficient live match updates (upsert pattern)
- ✅ Foundation for iOS app SwiftData sync

## Database Queries

### Get Next Upcoming Fixture

```swift
// Swift (via Repository)
let timestamp = try await fixtureRepository.getNextUpcomingTimestamp(
    leagueId: 6,
    season: 2025
)

// SQL equivalent
SELECT timestamp FROM fixtures
WHERE league_id = 6
  AND season = 2025
  AND date > NOW()
  AND (status_short = 'NS' OR status_short = 'TBD')
ORDER BY timestamp ASC
LIMIT 1;
```

### Get All Fixtures at a Time

```swift
// Swift (via Repository)
let fixtures = try await fixtureRepository.getFixturesAtTimestamp(
    leagueId: 6,
    season: 2025,
    timestamp: 1735689600
)

// SQL equivalent
SELECT * FROM fixtures
WHERE league_id = 6
  AND season = 2025
  AND timestamp = 1735689600;
```

### Upsert Fixture (Insert or Update)

```swift
// Swift (via Repository)
try await fixtureRepository.upsert(
    from: fixtureData,
    leagueId: 6,
    season: 2025,
    competition: "AFCON 2025"
)

// SQL equivalent
INSERT INTO fixtures (api_fixture_id, league_id, season, ...)
VALUES (1234, 6, 2025, ...)
ON CONFLICT (api_fixture_id) DO UPDATE SET
  status_short = EXCLUDED.status_short,
  home_goals = EXCLUDED.home_goals,
  away_goals = EXCLUDED.away_goals,
  ...;
```

## Troubleshooting

### Database Connection Issues

```bash
# Check PostgreSQL is running
brew services list | grep postgresql

# Test connection
psql -d afcon -c "SELECT 1;"

# Check logs
tail -f $(brew --prefix)/var/log/postgres.log
```

### Migration Issues

```bash
# Drop and recreate database (CAUTION: deletes all data)
dropdb afcon
createdb afcon

# Restart server to re-run migrations
swift run Run
```

### Verify Fixtures Were Synced

```bash
psql -d afcon

# Count fixtures
SELECT COUNT(*) FROM fixtures;

# View sample fixtures
SELECT
  api_fixture_id,
  home_team_name,
  away_team_name,
  TO_TIMESTAMP(timestamp) as match_time,
  status_short
FROM fixtures
ORDER BY timestamp
LIMIT 10;
```

## Future Enhancements

- [ ] Add database indexes for faster queries
- [ ] Implement fixture cleanup (delete old finished matches)
- [ ] Add database backups and restore functionality
- [ ] Support for multiple leagues/competitions
- [ ] Real-time database triggers for match updates
- [ ] GraphQL API for flexible fixture queries
- [ ] Analytics and statistics storage

## Related Files

- `Sources/App/Models/DB/FixtureEntity.swift` - Database model
- `Sources/App/Repositories/FixtureRepository.swift` - Database operations
- `Sources/App/gRPC/Server/AFCONServiceProvider.swift` - Intelligent polling logic
- `Sources/App/configure.swift` - Database configuration
- `Protos/afcon.proto` - SyncFixtures RPC definition

---

**Database integration complete!** 🎉 The server now intelligently manages fixtures without wasting API calls.
