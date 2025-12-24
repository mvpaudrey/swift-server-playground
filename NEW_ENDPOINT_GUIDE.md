# New Endpoint: Today's Upcoming Games

## What Was Added

A new endpoint to fetch upcoming games scheduled for today that haven't started yet.

## HTTP REST Endpoint

### Get Today's Upcoming Fixtures

**URL:** `GET /api/v1/league/:id/season/:season/today`

**Description:** Returns all fixtures scheduled for today that haven't started yet (status: NS or TBD)

**Example:**
```bash
curl http://localhost:8080/api/v1/league/6/season/2025/today
```

**Response:** Array of `FixtureData` objects with only upcoming (not started) matches

**Filter Logic:**
- ✅ Includes: `NS` (Not Started), `TBD` (To Be Defined)
- ❌ Excludes: `FT` (Finished), `1H`, `HT`, `2H` (In Progress), `LIVE`, `CANC` (Cancelled), etc.

## gRPC Method

### GetTodayUpcoming

**Service:** `AFCONService`

**Method:** `GetTodayUpcoming`

**Request:** `TodayUpcomingRequest`
```protobuf
message TodayUpcomingRequest {
  int32 league_id = 1;
  int32 season = 2;
}
```

**Response:** `FixturesResponse`
```protobuf
message FixturesResponse {
  repeated Fixture fixtures = 1;
}
```

**Example (Swift):**
```swift
import AFCONClient
import GRPC

let request = Afcon_TodayUpcomingRequest.with {
    $0.leagueID = 6      // AFCON
    $0.season = 2025
}

let response = try await client.getTodayUpcoming(request).response.get()
for fixture in response.fixtures {
    print("Upcoming: \\(fixture.teams.home.name) vs \\(fixture.teams.away.name)")
    print("Time: \\(fixture.fixture.date)")
}
```

## How to Use

### 1. Rebuild the Server

The proto file has been updated, so you need to regenerate the protocol buffers and rebuild:

```bash
cd /Users/audrey/Documents/Projects/Cheulah/CAN2025/APIPlayground.nosync

# Regenerate proto files
./generate-protos.sh

# Rebuild the server
swift build

# Restart the server
swift run Run
```

### 2. Test the HTTP Endpoint

Once the server is running:

```bash
# Get today's upcoming AFCON 2025 matches
curl http://localhost:8080/api/v1/league/6/season/2025/today

# Pretty print with jq (if installed)
curl http://localhost:8080/api/v1/league/6/season/2025/today | jq
```

### 3. Use in Your DesignPlayground App

Update your Swift code to call the new gRPC method:

```swift
// In your ViewModel or Service
func fetchTodayUpcomingMatches() async throws -> [Fixture] {
    let request = Afcon_TodayUpcomingRequest.with {
        $0.leagueID = 6
        $0.season = 2025
    }

    let response = try await grpcClient.getTodayUpcoming(request).response.get()
    return response.fixtures.map { convertToAppModel($0) }
}
```

## Match Status Codes Reference

The endpoint filters by status. Here are common status codes:

| Code | Meaning | Included? |
|------|---------|-----------|
| `NS` | Not Started | ✅ Yes |
| `TBD` | To Be Defined | ✅ Yes |
| `FT` | Full Time (Finished) | ❌ No |
| `1H` | First Half (In Progress) | ❌ No |
| `HT` | Half Time (In Progress) | ❌ No |
| `2H` | Second Half (In Progress) | ❌ No |
| `ET` | Extra Time (In Progress) | ❌ No |
| `P` | Penalty (In Progress) | ❌ No |
| `LIVE` | In Play (In Progress) | ❌ No |
| `CANC` | Cancelled | ❌ No |
| `PST` | Postponed | ❌ No |
| `ABD` | Abandoned | ❌ No |

## Example Response

```json
[
  {
    "fixture": {
      "id": 12345,
      "referee": "John Doe",
      "timezone": "UTC",
      "date": "2025-10-19T14:00:00+00:00",
      "timestamp": 1729346400,
      "venue": {
        "id": 1,
        "name": "Stadium Name",
        "city": "City"
      },
      "status": {
        "long": "Not Started",
        "short": "NS",
        "elapsed": null
      }
    },
    "league": {
      "id": 6,
      "name": "Africa Cup of Nations",
      "country": "World",
      "logo": "...",
      "flag": "...",
      "season": 2025,
      "round": "Group Stage - 1"
    },
    "teams": {
      "home": {
        "id": 1,
        "name": "Senegal",
        "logo": "...",
        "winner": null
      },
      "away": {
        "id": 2,
        "name": "Nigeria",
        "logo": "...",
        "winner": null
      }
    },
    "goals": {
      "home": null,
      "away": null
    },
    "score": {
      "halftime": { "home": null, "away": null },
      "fulltime": { "home": null, "away": null },
      "extratime": { "home": null, "away": null },
      "penalty": { "home": null, "away": null }
    }
  }
]
```

## All Available Endpoints

For reference, here are all the HTTP endpoints:

```bash
# Health check
GET /health

# API status
GET /api/status

# League info
GET /api/v1/league/:id/season/:season

# Teams
GET /api/v1/league/:id/season/:season/teams

# All fixtures
GET /api/v1/league/:id/season/:season/fixtures

# Today's upcoming fixtures ⭐ NEW
GET /api/v1/league/:id/season/:season/today

# Live fixtures
GET /api/v1/league/:id/live

# Standings
GET /api/v1/league/:id/season/:season/standings

# Team details
GET /api/v1/team/:id

# Clear cache
DELETE /api/v1/cache/league/:id/season/:season
```

## Notes

- The endpoint uses today's date automatically (no date parameter needed)
- Cached for 30 minutes (same as regular fixtures)
- Timezone is handled server-side based on system time
- Empty array `[]` is returned if no upcoming matches today

## Troubleshooting

**Empty response `[]`?**
- Check if there are actually games scheduled for today
- Try the all fixtures endpoint to see all today's matches: `/api/v1/league/6/season/2025/fixtures?date=2025-10-19`

**Server won't rebuild?**
- Make sure you ran `./generate-protos.sh` first
- Clean build: `swift package clean && swift build`

**gRPC error in app?**
- Make sure you regenerated the proto files
- Rebuild DesignPlayground app
- Restart the server

Enjoy the new endpoint! 🎉
