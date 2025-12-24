# API-Football Events Analysis

## Available Event Types

Based on API-Football documentation, here are the available fixture events:

### 1. Goal Events
- **Type**: `"Goal"`
- **Details**:
  - `"Normal Goal"` - Regular goal scored
  - `"Own Goal"` - Own goal
  - `"Penalty"` - Goal from penalty kick

### 2. Card Events
- **Type**: `"Card"`
- **Details**:
  - `"Yellow Card"` - Yellow card issued
  - `"Red Card"` - Direct red card
  - `"Second Yellow card"` - Second yellow = red card

### 3. Substitution Events
- **Type**: `"subst"`
- **Details**:
  - Player substitution (in/out)
  - Includes both player being substituted and replacement

### 4. VAR Events (Video Assistant Referee)
- **Type**: `"Var"`
- **Details**:
  - `"Goal cancelled"` - Goal overturned by VAR
  - `"Goal confirmed"` - Goal confirmed by VAR
  - `"Penalty confirmed"` - Penalty decision confirmed by VAR
  - `"Penalty cancelled"` - Penalty decision overturned

**Note**: VAR events are only available from the 2020-2021 season onwards.

### 5. Missed Penalty
- **Type**: `"Goal"`
- **Details**:
  - `"Missed Penalty"` - Penalty kick that was missed/saved

## Event Data Structure

Each event contains:
```json
{
  "time": {
    "elapsed": 45,  // Minutes into the match
    "extra": 2      // Additional time (optional)
  },
  "team": {
    "id": 123,
    "name": "Team Name",
    "logo": "https://..."
  },
  "player": {
    "id": 456,
    "name": "Player Name"
  },
  "assist": {      // Only for goals
    "id": 789,
    "name": "Assisting Player"
  },
  "type": "Goal",   // Event type
  "detail": "Normal Goal",  // Event detail
  "comments": "Optional comments"
}
```

## Fixture Status Codes

### Match States
- **NS** - Not Started
- **TBD** - Time To Be Defined
- **1H** - First Half, Kick Off
- **HT** - Halftime
- **2H** - Second Half, Kick Off
- **ET** - Extra Time
- **BT** - Break Time (between extra time periods)
- **P** - Penalty in Progress
- **SUSP** - Match Suspended
- **INT** - Match Interrupted
- **LIVE** - In Progress (generic live state)

### Final States
- **FT** - Match Finished
- **AET** - Match Finished After Extra Time
- **PEN** - Match Finished After Penalty
- **PST** - Match Postponed
- **CANC** - Match Cancelled
- **ABD** - Match Abandoned
- **AWA** - Technical Loss
- **WO** - WalkOver

## LiveMatchUpdate Event Types

Current event types in the streaming service:
1. `"match_started"` - New live match detected
2. `"match_finished"` - Match no longer live
3. `"goal"` - Goal scored (detected by score change)
4. `"status_update"` - Match status changed
5. `"time_update"` - Time elapsed significantly

## Recommended Improvements

### 1. Materialize Status in LiveMatchUpdate
Add `status` field directly to `LiveMatchUpdate` for easy access without navigating `fixture.status`.

### 2. Enhanced Event Detection
Fetch actual events from `/fixtures/events` endpoint and include them in updates:
- Real-time goals with scorer information
- Cards with player names
- Substitutions
- VAR decisions

### 3. Event Classification Enum
Create proper enums for event types instead of strings for type safety.

### 4. Rich Event Data
Include player information, assist data, and VAR context in the stream updates.
