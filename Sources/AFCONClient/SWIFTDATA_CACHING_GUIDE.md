# SwiftData Caching Strategy Guide

This guide explains how to use the AFCONClient library with SwiftData caching and JSON fallback.

## Architecture

The caching strategy follows a three-tier approach:

```
┌─────────────────────────────────────────────┐
│           Your SwiftUI App                  │
│      (Uses AFCONDataManager)                │
└──────────────────┬──────────────────────────┘
                   │
          ┌────────▼─────────┐
          │  1. SwiftData    │ ← Fast, persistent cache
          │     Cache        │
          └────────┬─────────┘
                   │ (if empty/stale)
          ┌────────▼─────────┐
          │  2. JSON         │ ← Offline fallback
          │     Fallback     │
          └────────┬─────────┘
                   │ (always fetch to update)
          ┌────────▼─────────┐
          │  3. gRPC         │ ← Fresh data from server
          │     Server       │
          └──────────────────┘
```

## How It Works

### Step 1: Check SwiftData Cache

When you request data (e.g., fixtures), the `AFCONDataManager` first checks SwiftData:

```swift
// Check if data exists in SwiftData
if let cached = try await fetchCachedFixtures() {
    // Data found! Return it immediately
    return cached
}
```

**Benefits:**
- ⚡ Instant loading (no network call)
- 📱 Works offline
- 🔋 Battery efficient

### Step 2: Load JSON Fallback

If SwiftData is empty (first app launch or cache cleared), load from bundled JSON:

```swift
// SwiftData is empty, load from JSON
if let jsonData = try await loadFixturesFromJSON() {
    // Save to SwiftData for next time
    saveToSwiftData(jsonData)
    return jsonData
}
```

**Benefits:**
- 📦 Pre-populated data (no wait on first launch)
- 🌐 Works when server is down
- 👍 Better user experience

### Step 3: Fetch from Server

Whether data was loaded from cache or JSON, always fetch fresh data in the background:

```swift
// Update cache in background
Task {
    let fresh = try await service.getFixtures()
    updateSwiftData(fresh)
}
```

**Benefits:**
- 🔄 Always stays up to date
- 🎯 Silent updates (no loading spinners)
- ✅ Ensures data accuracy

## Usage Examples

### Basic Setup

```swift
import SwiftUI
import SwiftData

@main
struct MyAFCONApp: App {
    let dataManager: AFCONDataManager

    init() {
        do {
            // Initialize with AFCON 2025
            self.dataManager = try AFCONDataManager(
                leagueId: 6,
                season: 2025
            )
        } catch {
            fatalError("Failed to initialize: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataManager)
                .modelContainer(dataManager.modelContainer)
        }
    }
}
```

### Fetching Fixtures

```swift
struct FixturesView: View {
    @EnvironmentObject var dataManager: AFCONDataManager
    @State private var fixtures: [FixtureModel] = []

    var body: some View {
        List(fixtures, id: \.id) { fixture in
            FixtureRow(fixture: fixture)
        }
        .task {
            // This will:
            // 1. Check SwiftData (instant)
            // 2. If empty, load JSON (fast)
            // 3. Fetch from server (update in background)
            do {
                fixtures = try await dataManager.getFixtures()
            } catch {
                print("Error: \(error)")
            }
        }
        .refreshable {
            // Force refresh from server
            do {
                fixtures = try await dataManager.getFixtures()
            } catch {
                print("Error: \(error)")
            }
        }
    }
}
```

### Live Fixtures (Always Fresh)

```swift
// For live matches, always fetch from server
let liveFixtures = try await dataManager.getFixtures(live: true)
```

### Filter by Team

```swift
// Get all fixtures for a specific team
let teamFixtures = try await dataManager.getFixtures(teamId: 15)
```

### Get Teams

```swift
let teams = try await dataManager.getTeams()
```

### Get Standings

```swift
let standings = try await dataManager.getStandings()
```

## Cache Configuration

### Cache Expiration

By default, cached data expires after 1 hour. You can customize this:

```swift
// Set cache expiration to 30 minutes
dataManager.cacheExpirationInterval = 1800  // seconds
```

### Clear Cache

Clear all cached data:

```swift
try dataManager.clearAllCache()
```

## JSON Fallback Files

The library looks for these JSON files in the bundle:

- `league_fallback.json` - League information
- `teams_fallback.json` - All teams
- `fixtures_fallback.json` - All fixtures
- `standings_fallback.json` - Standings

### Creating Fallback Files

#### Option 1: Export from Server

Use the included script to export current data:

```bash
cd Sources/AFCONClient/Resources
./export-fallback-data.sh
```

This fetches data from your gRPC server and saves it as JSON.

#### Option 2: Manual Creation

Create JSON files matching the SwiftData model structure:

**league_fallback.json:**
```json
{
  "id": 6,
  "name": "Africa Cup of Nations",
  "type": "Cup",
  "logoURL": "https://...",
  "countryName": "World",
  "countryCode": "WW",
  "countryFlagURL": "https://...",
  "season": 2025,
  "lastUpdated": "2025-01-01T00:00:00Z"
}
```

**teams_fallback.json:**
```json
[
  {
    "id": 1,
    "name": "Egypt",
    "code": "EGY",
    "country": "Egypt",
    "founded": 1921,
    "logoURL": "https://...",
    "venueName": "Cairo International Stadium",
    "venueCity": "Cairo",
    "venueCapacity": 75000,
    "season": 2025,
    "lastUpdated": "2025-01-01T00:00:00Z"
  }
]
```

## SwiftData Models

All models are Codable and use SwiftData:

- `LeagueModel` - League information
- `TeamModel` - Team details
- `FixtureModel` - Match fixtures
- `StandingsModel` - Group standings

You can use `@Query` in SwiftUI for reactive updates:

```swift
struct FixturesView: View {
    @Query(sort: \FixtureModel.date) var fixtures: [FixtureModel]

    var body: some View {
        List(fixtures) { fixture in
            Text(fixture.homeTeamName)
        }
    }
}
```

## Performance Tips

### 1. Use Background Refresh

The data manager automatically refreshes in the background:

```swift
// This returns cached data instantly
// and updates in background
let fixtures = try await dataManager.getFixtures()
```

### 2. Preload Data

Preload data on app launch:

```swift
.task {
    async let teams = dataManager.getTeams()
    async let fixtures = dataManager.getFixtures()
    async let standings = dataManager.getStandings()

    // Wait for all to complete
    _ = try await (teams, fixtures, standings)
}
```

### 3. Monitor Loading State

Use the `@Published` properties:

```swift
@EnvironmentObject var dataManager: AFCONDataManager

var body: some View {
    VStack {
        if dataManager.isLoading {
            ProgressView()
        }

        if let error = dataManager.lastError {
            Text("Error: \(error.localizedDescription)")
        }
    }
}
```

## Testing Without Server

You can test the app without a running server:

1. **Provide JSON fallback files** - App will load from JSON
2. **Pre-populate SwiftData** - Use the test data seeder
3. **Mock the service** - Replace `AFCONService` with a mock

## Troubleshooting

### Data Not Updating

```swift
// Force clear cache and refetch
try dataManager.clearAllCache()
let fresh = try await dataManager.getFixtures()
```

### JSON Not Loading

Ensure JSON files are:
- In `Resources` directory
- Added to target in Xcode
- Properly formatted (valid JSON)

### SwiftData Errors

```swift
// Reset model container
let container = try ModelContainer(
    for: schema,
    configurations: [.init(isStoredInMemoryOnly: true)]  // In-memory for testing
)
```

## Best Practices

1. ✅ **Always use the DataManager** - Don't call gRPC service directly
2. ✅ **Provide JSON fallbacks** - Better first-launch experience
3. ✅ **Handle errors gracefully** - Network can fail
4. ✅ **Show loading states** - But only when data is empty
5. ✅ **Use pull-to-refresh** - Let users force refresh
6. ✅ **Clear cache rarely** - Only in settings or on errors

## Migration from Direct gRPC Calls

### Before:

```swift
let service = try AFCONService()
let teams = try await service.getTeams()  // Always network call
```

### After:

```swift
let dataManager = try AFCONDataManager()
let teams = try await dataManager.getTeams()  // Smart caching
```

## Example App

See `Examples/DataManagerUsage.swift` for a complete working example with:
- Fixtures list view
- Teams list view
- Standings view
- Pull-to-refresh
- Error handling
- Loading states

## Summary

The SwiftData caching strategy provides:

- ⚡ **Fast loading** - Instant from cache
- 📱 **Offline support** - Works without network
- 🔄 **Always fresh** - Background updates
- 🎯 **Smart fallbacks** - JSON when cache is empty
- 🔋 **Battery efficient** - Minimal network calls
- 👍 **Great UX** - No loading spinners after first load

Start using it today:

```swift
let dataManager = try AFCONDataManager()
let fixtures = try await dataManager.getFixtures()
```

That's it! 🎉
