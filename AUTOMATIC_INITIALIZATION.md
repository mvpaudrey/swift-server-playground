# Automatic Fixtures Initialization on Server Startup

**Date**: October 22, 2025
**Feature**: Auto-sync fixtures from API when database is empty

## Problem Statement

**Before**: The server would start with an empty database and only query the database for fixture information. If no fixtures existed, it would simply return empty results without ever fetching from the API-Football API. This created a "cold start" problem:

```
Server Startup → Check Database (empty) → Query Database (returns empty) → No fixtures available
```

**User would see**: "No live matches - Fetching next upcoming fixtures from database for league 2" but database was empty, so no fixtures would ever be loaded.

## Solution

Implemented automatic initialization that:
1. Checks if the database has fixtures for configured leagues on server startup
2. If empty, automatically fetches from API-Football
3. Populates the database with the latest fixtures
4. Logs the entire process for visibility

## Implementation

### 1. Added Initialization Method

**File**: `Sources/App/gRPC/Server/AFCONServiceProvider.swift:22-64`

```swift
/// Initialize fixtures database on server startup
/// Checks if database is empty and performs initial sync if needed
public func initializeFixtures(leagues: [(id: Int, season: Int, name: String)] = [(2, 2024, "Champions League"), (6, 2025, "AFCON 2025")]) async {
    logger.info("🔍 Checking fixtures database initialization...")

    for league in leagues {
        do {
            let hasFixtures = try await fixtureRepository.hasFixtures(leagueId: league.id, season: league.season)

            if !hasFixtures {
                logger.warning("⚠️  Database is empty for \(league.name) (ID: \(league.id), Season: \(league.season))")
                logger.info("📡 Fetching fixtures from API-Football for initial sync...")

                // Fetch fixtures from API
                let fixturesData = try await apiClient.getFixtures(
                    leagueId: league.id,
                    season: league.season
                )

                logger.info("✅ Received \(fixturesData.count) fixtures from API-Football")

                // Save to database
                try await fixtureRepository.upsertBatch(
                    fixtures: fixturesData,
                    leagueId: league.id,
                    season: league.season,
                    competition: league.name
                )

                logger.info("✅ Successfully initialized database with \(fixturesData.count) fixtures for \(league.name)")
            } else {
                let count = try await fixtureRepository.getAllFixtures(leagueId: league.id, season: league.season).count
                logger.info("✅ Database already initialized for \(league.name) (\(count) fixtures)")
            }
        } catch {
            logger.error("❌ Failed to initialize fixtures for \(league.name): \(error)")
        }
    }

    logger.info("✅ Fixtures database initialization complete")
}
```

### 2. Updated Server Startup

**File**: `Sources/Run/main.swift:79-80`

```swift
// Create gRPC service provider
let serviceProvider = AFCONServiceProvider(
    apiClient: apiClient,
    cache: cache,
    fixtureRepository: fixtureRepository,
    logger: app.logger
)

// Initialize fixtures database (fetch from API if empty)
await serviceProvider.initializeFixtures()

// Configure gRPC server
let server = try await GRPC.Server.insecure(group: eventLoopGroup)
    .withServiceProviders([serviceProvider])
    .bind(host: "0.0.0.0", port: port)
    .get()
```

## Startup Flow

### Scenario 1: Empty Database (First Run)

```
1. Server starts
   ↓
2. Service provider created
   ↓
3. initializeFixtures() called
   ↓
4. Check database for Champions League fixtures
   ├─→ Database empty!
   ├─→ Log: "⚠️  Database is empty for Champions League (ID: 2, Season: 2024)"
   ├─→ Log: "📡 Fetching fixtures from API-Football for initial sync..."
   ├─→ API call: GET /fixtures?league=2&season=2024
   ├─→ Log: "✅ Received 125 fixtures from API-Football"
   ├─→ Upsert 125 fixtures to PostgreSQL
   └─→ Log: "✅ Successfully initialized database with 125 fixtures for Champions League"
   ↓
5. Check database for AFCON fixtures
   ├─→ Database empty!
   ├─→ Fetch from API
   ├─→ Upsert 52 fixtures to PostgreSQL
   └─→ Log: "✅ Successfully initialized database with 52 fixtures for AFCON 2025"
   ↓
6. Log: "✅ Fixtures database initialization complete"
   ↓
7. gRPC server starts
   ↓
8. Server ready to serve requests with populated database
```

### Scenario 2: Database Already Populated

```
1. Server starts
   ↓
2. Service provider created
   ↓
3. initializeFixtures() called
   ↓
4. Check database for Champions League fixtures
   ├─→ Database has fixtures!
   ├─→ Count: 125 fixtures
   └─→ Log: "✅ Database already initialized for Champions League (125 fixtures)"
   ↓
5. Check database for AFCON fixtures
   ├─→ Database has fixtures!
   ├─→ Count: 52 fixtures
   └─→ Log: "✅ Database already initialized for AFCON 2025 (52 fixtures)"
   ↓
6. Log: "✅ Fixtures database initialization complete"
   ↓
7. gRPC server starts (no API calls made)
   ↓
8. Server ready to serve requests
```

## Default Leagues

The initialization method checks these leagues by default:

1. **UEFA Champions League**
   - League ID: `2`
   - Season: `2024`
   - Name: `"Champions League"`

2. **Africa Cup of Nations**
   - League ID: `6`
   - Season: `2025`
   - Name: `"AFCON 2025"`

You can customize the leagues by passing a different array:

```swift
await serviceProvider.initializeFixtures(leagues: [
    (id: 39, season: 2024, name: "Premier League"),
    (id: 140, season: 2024, name: "La Liga"),
    (id: 61, season: 2024, name: "Ligue 1")
])
```

## Expected Log Output

### First Run (Empty Database)

```
🚀 Starting AFCON Middleware
📡 HTTP Server will run on port 8080
📡 gRPC Server will run on port 50051
🔍 Checking fixtures database initialization...
⚠️  Database is empty for Champions League (ID: 2, Season: 2024)
📡 Fetching fixtures from API-Football for initial sync...
✅ Received 125 fixtures from API-Football
Upserted 125 fixtures for league 2, season 2024
✅ Successfully initialized database with 125 fixtures for Champions League
⚠️  Database is empty for AFCON 2025 (ID: 6, Season: 2025)
📡 Fetching fixtures from API-Football for initial sync...
✅ Received 52 fixtures from API-Football
Upserted 52 fixtures for league 6, season 2025
✅ Successfully initialized database with 52 fixtures for AFCON 2025
✅ Fixtures database initialization complete
✅ gRPC Server started on port 50051
```

### Subsequent Runs (Database Populated)

```
🚀 Starting AFCON Middleware
📡 HTTP Server will run on port 8080
📡 gRPC Server will run on port 50051
🔍 Checking fixtures database initialization...
✅ Database already initialized for Champions League (125 fixtures)
✅ Database already initialized for AFCON 2025 (52 fixtures)
✅ Fixtures database initialization complete
✅ gRPC Server started on port 50051
```

## Benefits

### Before

❌ **Cold Start Problem**
- Server starts with empty database
- No automatic sync
- Users see "No fixtures" messages
- Manual intervention required (call SyncFixtures RPC from iOS)

❌ **Poor Developer Experience**
- Confusing logs: "Fetching from database" but database is empty
- Required manual API call or iOS app sync
- Not truly "plug and play"

### After

✅ **Automatic Initialization**
- Server starts → Checks database → Auto-syncs if empty
- No manual intervention required
- Ready to serve data immediately

✅ **Smart Behavior**
- Only fetches from API if database is empty
- Skips sync if fixtures already exist
- Saves API quota

✅ **Better Developer Experience**
- Clear logs showing what's happening
- Works out of the box
- No manual setup required

## API Quota Impact

### First Run

- **Champions League**: 1 API call (~125 fixtures)
- **AFCON 2025**: 1 API call (~52 fixtures)
- **Total**: 2 API calls on first server startup

### Subsequent Runs

- **Total**: 0 API calls (database already populated)

### Ongoing Operation

After initialization, the server uses intelligent polling:
- Queries database for next fixture time
- Only polls API when matches are imminent or live
- ~10-50 API calls per match day (as designed)

## Testing

### Test 1: Empty Database

1. **Clear the database**:
   ```bash
   docker exec afcon-postgres psql -U postgres -d afcon -c 'DELETE FROM fixtures;'
   ```

2. **Start server**:
   ```bash
   swift run Run
   ```

3. **Expected output**:
   ```
   🔍 Checking fixtures database initialization...
   ⚠️  Database is empty for Champions League (ID: 2, Season: 2024)
   📡 Fetching fixtures from API-Football for initial sync...
   ✅ Received 125 fixtures from API-Football
   ✅ Successfully initialized database with 125 fixtures for Champions League
   ...
   ✅ Fixtures database initialization complete
   ```

4. **Verify database**:
   ```bash
   docker exec afcon-postgres psql -U postgres -d afcon -c 'SELECT COUNT(*) FROM fixtures;'
   # Should show 177 (125 + 52)
   ```

### Test 2: Database Already Populated

1. **Start server** (database has fixtures from Test 1):
   ```bash
   swift run Run
   ```

2. **Expected output**:
   ```
   🔍 Checking fixtures database initialization...
   ✅ Database already initialized for Champions League (125 fixtures)
   ✅ Database already initialized for AFCON 2025 (52 fixtures)
   ✅ Fixtures database initialization complete
   ```

3. **Verify no API calls made** (check server logs - no "Fetching from API" messages)

## Fallback Behavior

If initialization fails for any reason:
- **Error is logged** but server continues starting
- **Server remains operational** for other leagues/functions
- **Specific league will be empty** until manual sync

Example error log:
```
❌ Failed to initialize fixtures for Champions League: timeout
✅ Database already initialized for AFCON 2025 (52 fixtures)
✅ Fixtures database initialization complete
```

## Manual Override

You can still manually sync fixtures using:

### iOS App
```swift
await viewModel.syncFixturesToServer()
```

### gRPC Call
```swift
let request = Afcon_SyncFixturesRequest.with {
    $0.leagueID = 2
    $0.season = 2024
    $0.competition = "Champions League"
}
let response = try await client.syncFixtures(request)
```

### HTTP API (Debug Endpoint)
```bash
curl -X POST http://localhost:8080/api/sync-fixtures \
  -H "Content-Type: application/json" \
  -d '{"league_id": 2, "season": 2024, "competition": "Champions League"}'
```

## Related Files

- **Implementation**: `Sources/App/gRPC/Server/AFCONServiceProvider.swift:22-64`
- **Startup**: `Sources/Run/main.swift:79-80`
- **Repository**: `Sources/App/Repositories/FixtureRepository.swift`
- **Database Model**: `Sources/App/Models/DB/FixtureEntity.swift`

## Future Enhancements

Potential improvements:

- [ ] Environment variable to control which leagues to initialize
- [ ] Schedule periodic re-sync (e.g., daily at 3 AM)
- [ ] Admin endpoint to trigger manual initialization
- [ ] Health check endpoint showing database status
- [ ] Metrics for initialization success/failure

---

**Automatic initialization complete!** 🎉

The server now intelligently initializes its database on startup, ensuring the latest fixture information is always available without manual intervention.
