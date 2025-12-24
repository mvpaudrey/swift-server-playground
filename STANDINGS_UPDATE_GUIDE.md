# Standings Update Service

## Overview

The `StandingsUpdateService` provides automated standings updates with intelligent scheduling based on fixture status. It implements an optimized update pattern:

- **During match days**: Updates standings every 1 hour while games are in progress
- **After last game finishes**: Makes intermediate updates at:
  - 10 minutes after last game
  - 20 minutes after last game
  - 30 minutes after last game
  - 1 hour and 5 minutes after last game (final update)
- **No games scheduled**: Automatically pauses and resumes when fixtures are scheduled

This ensures standings are updated frequently after matches conclude while minimizing API calls during active play.

## Features

- ✅ Automatic hourly updates during active match days
- ✅ Intermediate updates at 10, 20, and 30 minutes after last game finishes
- ✅ Final standings update 1h 5min after last game finishes
- ✅ Intelligent sleep scheduling when no games are scheduled
- ✅ In-memory caching with 1-hour TTL
- ✅ RESTful API endpoints for control
- ✅ Thread-safe implementation using Swift Concurrency

## API Endpoints

### 1. Start Standings Updates

```bash
POST /api/v1/league/{leagueId}/season/{season}/standings/start
```

**Example:**
```bash
curl -X POST "http://localhost:8080/api/v1/league/1/season/2024/standings/start"
```

**Response:**
```json
{
  "status": "started",
  "leagueId": "1",
  "season": "2024",
  "message": "Standings updates started. Will poll every hour during games, then at 10, 20, 30 min and 1h 5min after last game."
}
```

### 2. Stop Standings Updates

```bash
POST /api/v1/league/{leagueId}/standings/stop
```

**Example:**
```bash
curl -X POST "http://localhost:8080/api/v1/league/1/standings/stop"
```

**Response:**
```json
{
  "status": "stopped",
  "leagueId": "1",
  "message": "Standings updates stopped"
}
```

### 3. Check Status

```bash
GET /api/v1/league/{leagueId}/standings/status
```

**Example:**
```bash
curl "http://localhost:8080/api/v1/league/1/standings/status"
```

**Response:**
```json
{
  "leagueId": 1,
  "isActive": true,
  "lastUpdate": "2025-01-15T14:30:00Z"
}
```

### 4. Manual Update

```bash
POST /api/v1/league/{leagueId}/season/{season}/standings/update
```

**Example:**
```bash
curl -X POST "http://localhost:8080/api/v1/league/1/season/2024/standings/update"
```

**Response:**
```json
{
  "status": "updated",
  "leagueId": "1",
  "season": "2024",
  "message": "Standings updated successfully"
}
```

### 5. Get Standings (Cached)

```bash
GET /api/v1/league/{leagueId}/season/{season}/standings
```

**Example:**
```bash
curl "http://localhost:8080/api/v1/league/1/season/2024/standings"
```

Returns the cached standings data (or fetches fresh if cache expired).

## Update Schedule Logic

### Active Match Days

When fixtures are scheduled for today and not all have finished:

```
09:00 - Update standings (hourly)
10:00 - Update standings
11:00 - Update standings
...
20:00 - Last game finishes
20:10 - Update standings (10 min after)
20:20 - Update standings (20 min after)
20:30 - Update standings (30 min after)
21:05 - Final standings update (1h 5min after)
```

### No Games Today

```
- Check for next scheduled fixture
- Sleep until appropriate time before next fixture
- If no upcoming fixtures: sleep for 24 hours
```

### Smart Sleep Intervals

- More than 1 day away: sleep 12 hours
- 6-24 hours away: sleep 3 hours
- 1-6 hours away: sleep 30 minutes
- Less than 1 hour: active polling (every hour)

## Caching Strategy

- **Cache Key**: `standings:{leagueId}:{season}`
- **TTL**: 1 hour (3600 seconds)
- **Storage**: In-memory (CacheService)
- **Automatic**: Updates are automatically cached on fetch

## Usage Examples

### Start Updates for AFCON 2025

```bash
# Start automatic updates
curl -X POST "http://localhost:8080/api/v1/league/1387/season/2025/standings/start"

# Check status
curl "http://localhost:8080/api/v1/league/1387/standings/status"

# Get standings
curl "http://localhost:8080/api/v1/league/1387/season/2025/standings"
```

### Monitor Multiple Leagues

```bash
# Start updates for multiple leagues
curl -X POST "http://localhost:8080/api/v1/league/1387/season/2025/standings/start"
curl -X POST "http://localhost:8080/api/v1/league/2/season/2025/standings/start"
curl -X POST "http://localhost:8080/api/v1/league/39/season/2024/standings/start"

# Check all statuses
curl "http://localhost:8080/api/v1/league/1387/standings/status"
curl "http://localhost:8080/api/v1/league/2/standings/status"
curl "http://localhost:8080/api/v1/league/39/standings/status"
```

### Force Immediate Update

```bash
# Trigger manual update (doesn't affect automatic schedule)
curl -X POST "http://localhost:8080/api/v1/league/1387/season/2025/standings/update"
```

## Implementation Details

### Service Architecture

The `StandingsUpdateService` is registered as a singleton service in `configure.swift`:

```swift
app.services.use { app -> StandingsUpdateService in
    guard let db = app.db as? any Database else {
        fatalError("Database not configured")
    }
    let apiClient: APIFootballClient = app.getService()
    let cacheService: CacheService = app.getService()
    let fixtureRepository = FixtureRepository(db: db, logger: app.logger)

    return StandingsUpdateService(
        apiClient: apiClient,
        fixtureRepository: fixtureRepository,
        cacheService: cacheService,
        logger: app.logger
    )
}
```

### Update Loop Algorithm

1. **Check Today's Fixtures**
   - Query database for fixtures scheduled today
   - If none: sleep until next day

2. **Determine Status**
   - Count unfinished fixtures
   - If games in progress: update standings, sleep 1 hour
   - If all finished: calculate last game end time

3. **Post-Game Updates**
   - Wait 10 minutes after last game, update standings
   - Wait 20 minutes after last game, update standings
   - Wait 30 minutes after last game, update standings
   - Wait 1h 5min after last game, make final update
   - Sleep until next day

4. **Repeat**
   - Continue loop until service is stopped

### Thread Safety

- Uses Swift `Mutex` for thread-safe state management
- Actor-based `CacheService` for concurrent cache access
- Detached tasks for independent league polling

## Logs

The service provides detailed logging:

```
🏆 Starting standings updates for league 1387, season 2025
🔄 Standings update loop started for league 1387
⚽️ 4 unfinished fixture(s) today for league 1387
📥 Fetching standings for league 1387, season 2025
✅ Standings cached for league 1387 (1 groups)
🏁 All fixtures finished for today in league 1387
⏰ Waiting 9m 30s before 10-minute post-game standings update for league 1387
🏆 Making 10-minute post-game standings update for league 1387
⏰ Waiting 9m 59s before 20-minute post-game standings update for league 1387
🏆 Making 20-minute post-game standings update for league 1387
⏰ Waiting 9m 59s before 30-minute post-game standings update for league 1387
🏆 Making 30-minute post-game standings update for league 1387
⏰ Waiting 34m 59s before 65-minute post-game standings update for league 1387
🏆 Making final (1h 5min) standings update for league 1387
💤 Sleeping until next day for league 1387
```

## Performance Considerations

- **One task per league**: Prevents duplicate API calls
- **Efficient sleep scheduling**: Minimizes resource usage during idle periods
- **In-memory caching**: Fast reads for cached standings
- **Background tasks**: Non-blocking operation

## Testing

### Local Testing

1. **Start the server:**
   ```bash
   swift run
   ```

2. **Start standings updates:**
   ```bash
   curl -X POST "http://localhost:8080/api/v1/league/1387/season/2025/standings/start"
   ```

3. **Check logs for update cycle**

4. **Verify cached data:**
   ```bash
   curl "http://localhost:8080/api/v1/league/1387/season/2025/standings"
   ```

### Integration with iOS App

The iOS app can:
- Call the standings endpoint to get cached data (no API calls)
- Updates are automatically scheduled server-side
- No need to poll from client (more battery efficient)

## Future Enhancements

- [ ] Add gRPC streaming for real-time standings updates
- [ ] Support for multiple groups/tables in response
- [ ] Persist standings history in database
- [ ] Add metrics/monitoring for update frequency
- [ ] Support for custom update schedules per league
- [ ] Webhook notifications when standings change

## Related Files

- `Sources/App/Services/StandingsUpdateService.swift` - Main service implementation
- `Sources/App/routes.swift` - API endpoint definitions
- `Sources/App/configure.swift` - Service registration
- `Sources/App/Services/APIFootballClient.swift` - API client with getStandings()
- `Sources/App/Services/CacheService.swift` - In-memory caching
