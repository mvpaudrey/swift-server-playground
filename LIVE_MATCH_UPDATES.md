# Live Match Updates - Implementation Summary

## Overview
Enhanced the `LiveMatchUpdate` streaming service to include materialized fixture status and real-time event detection using actual fixture events from the API.

## Changes Made

### 1. Proto Definition Updates (`Protos/afcon.proto:266-274`)

Added two new fields to `LiveMatchUpdate`:
```protobuf
message LiveMatchUpdate {
  int32 fixture_id = 1;
  google.protobuf.Timestamp timestamp = 2;
  string event_type = 3; // Enhanced with "var", "yellow_card", "red_card", etc.
  Fixture fixture = 4;
  MatchEvent event = 5;
  FixtureStatus status = 6; // ✨ NEW: Materialized status for easy access
  repeated FixtureEvent recent_events = 7; // ✨ NEW: Recent events (last 5 minutes)
}
```

**Benefits:**
- **Direct Status Access**: No need to navigate `update.fixture.status` - access via `update.status` directly
- **Recent Events**: Get last 5 minutes of match events (goals, cards, substitutions, VAR) with each update

### 2. Enhanced Event Detection (`AFCONServiceProvider.swift`)

#### New Event Types Detected:
- `"goal"` - Normal goals, own goals, penalties
- `"yellow_card"` - Yellow card issued
- `"red_card"` - Red card or second yellow
- `"substitution"` - Player substitutions
- `"var"` - VAR decisions (Goal cancelled/confirmed, Penalty decisions)
- `"missed_penalty"` - Penalty kicks that were saved/missed
- `"status_update"` - Match status changes (HT, FT, ET, etc.)
- `"time_update"` - Significant time elapsed
- `"match_started"` - New live match detected
- `"match_finished"` - Match completed

#### Key Methods Added:

**`detectEventTypeEnhanced()`** (lines 434-491)
- Analyzes actual fixture events from API
- Compares current vs previous events to detect new occurrences
- Prioritizes event types (goals > cards > subs > VAR)
- Falls back to score/status changes if event fetch fails

**`fetchFixtureEventsIfNeeded()`** (lines 494-501)
- Fetches events from `/fixtures/events` endpoint
- Graceful error handling - returns empty array on failure
- Prevents stream interruption if event fetching fails

**`getRecentEvents()`** (lines 504-513)
- Filters events from last 5 minutes of match time
- Converts to proto `FixtureEvent` messages
- Includes full event details (player, team, time, type, detail)

**`convertToFixtureStatus()`** (lines 525-531)
- Materializes `FixtureStatusInfo` to `Afcon_FixtureStatus`
- Direct conversion for easy access

**`convertToFixtureEvent()`** (lines 534-571)
- Converts API `FixtureEvent` to proto `Afcon_FixtureEvent`
- Preserves all event data: time, team, player, assist, type, detail

### 3. Stream Implementation Updates

The `streamLiveMatches()` method now:
1. **Tracks Events**: Maintains `previousEvents` dictionary per fixture
2. **Fetches Events**: Calls API for each live fixture's events
3. **Enhanced Detection**: Uses actual events to determine update type
4. **Materializes Status**: Populates `update.status` on every update
5. **Includes Recent Events**: Adds last 5 minutes of events to each update

## API Event Structure

### From API-Football
```json
{
  "time": {"elapsed": 45, "extra": 2},
  "team": {"id": 123, "name": "Team", "logo": "..."},
  "player": {"id": 456, "name": "Player Name"},
  "assist": {"id": 789, "name": "Assist Player"},
  "type": "Goal",
  "detail": "Normal Goal",
  "comments": ""
}
```

### Event Type Mapping

| API Type | API Detail | Stream Event Type |
|----------|-----------|------------------|
| "Goal" | "Normal Goal" | "goal" |
| "Goal" | "Own Goal" | "goal" |
| "Goal" | "Penalty" | "goal" |
| "Goal" | "Missed Penalty" | "missed_penalty" |
| "Card" | "Yellow Card" | "yellow_card" |
| "Card" | "Red Card" | "red_card" |
| "Card" | "Second Yellow card" | "red_card" |
| "subst" | (any) | "substitution" |
| "Var" | (any) | "var" |

## Usage Example

### Before (Nested Access):
```swift
let status = update.fixture.status  // Nested navigation
let shortStatus = update.fixture.status.short
let elapsed = update.fixture.status.elapsed
```

### After (Direct Access):
```swift
let status = update.status  // Direct access!
let shortStatus = update.status.short
let elapsed = update.status.elapsed

// Plus recent events
for event in update.recentEvents {
    print("\(event.time.elapsed)' \(event.type): \(event.player.name)")
}
```

### Client Example:
```swift
for try await update in stream {
    switch update.eventType {
    case "goal":
        print("⚽ Goal! \(update.status.short) - \(update.status.elapsed)'")
        if let scorer = update.recentEvents.last?.player.name {
            print("   Scored by: \(scorer)")
        }
    case "yellow_card":
        print("🟨 Yellow card at \(update.status.elapsed)'")
    case "red_card":
        print("🟥 Red card at \(update.status.elapsed)'")
    case "var":
        print("📺 VAR decision at \(update.status.elapsed)'")
    case "substitution":
        print("🔄 Substitution at \(update.status.elapsed)'")
    default:
        print("Status: \(update.status.long)")
    }
}
```

## Performance Considerations

1. **Additional API Calls**: Each live fixture now makes an extra call to `/fixtures/events`
   - Mitigated by error handling - stream continues even if events fail
   - Only called for active live matches (typically 1-2 per league)

2. **Memory**: Stores event history per fixture
   - Automatically cleaned when matches finish
   - Minimal impact (events are small objects)

3. **Polling Interval**: Unchanged at 10 seconds
   - Good balance between real-time and API rate limits

## Error Handling

- Event fetching failures don't interrupt the stream
- Falls back to score-based detection if events unavailable
- Logs warnings for debugging without crashing

## Testing

After building, test with:
```bash
swift run GRPCClient
```

Watch for enhanced event types in the stream output!

## Files Modified

1. `Protos/afcon.proto` - Added status and recent_events fields
2. `Sources/App/gRPC/Server/AFCONServiceProvider.swift` - Enhanced event detection
3. Generated files will be updated automatically on build

## Next Steps

Once proto files are regenerated:
1. Test with live matches
2. Monitor API call volume
3. Fine-tune recent events time window if needed (currently 5 minutes)
4. Add event filtering options if desired
