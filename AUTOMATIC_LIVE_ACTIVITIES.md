# Automatic Live Activities System

## ✨ What Was Built

Your AFCON server now includes a complete **automatic Live Activity system** that creates Live Activities for users based on their favorite team stored in SwiftData.

## 🏗️ Architecture

### Client-Side (iOS App)
1. **SwiftData** - Source of truth for favorite team
2. **FavoriteTeamSyncService** - Syncs team to server when changed
3. **APNs Device Token** - Registered on app launch
4. **AFCONServiceWrapper** - gRPC client with subscription methods

### Server-Side (Swift Vapor)
1. **LiveActivityAutoService** - Runs every 5 minutes, checks for matches starting in next 30 minutes
2. **Notification Subscriptions** - Database table linking devices to teams
3. **Automatic Creation** - Creates Live Activities for subscribed users 30 min before kickoff
4. **Push Notifications** - Sends real-time updates via APNs

## 🔄 Complete Flow

### 1. First Launch
```
iOS App
   ├─> Request notification permissions
   ├─> Get APNs device token
   ├─> Call registerDevice()
   └─> Store device_uuid locally
```

### 2. User Selects Favorite Team
```
iOS App (SwiftData)
   ├─> User selects "Cameroon" (ID: 1530)
   ├─> Save to SwiftData
   └─> Call updateFavoriteTeam(teamId: 1530)
          ↓
Server (Database)
   ├─> Create/update subscription record
   ├─> Link: device_uuid → team_id (1530)
   └─> Set notification preferences
```

### 3. Automatic Live Activity Creation (Server)
```
Every 5 minutes:
   ├─> Find fixtures starting in next 30 minutes
   ├─> For each fixture:
   │      ├─> Check if Cameroon is playing
   │      ├─> Find all devices subscribed to Cameroon
   │      └─> Create Live Activity for each device
   └─> Mark fixture as processed
```

### 4. Match Day Experience
```
30 min before kickoff:
   ├─> Server auto-creates Live Activity
   └─> Sends push notification

Match starts:
   ├─> Server detects match started
   └─> Sends Live Activity update

During match (every 15 seconds):
   ├─> Server polls API for changes
   ├─> Detects goals, cards, status changes
   └─> Sends push-to-update

Match ends:
   ├─> Server sends final score
   └─> Live Activity shows final result
```

## 📁 Files Created/Modified

### iOS Client
1. **Services/FavoriteTeamSyncService.swift** - NEW
   - Handles device registration
   - Syncs favorite team changes

2. **Services/AFCONService.swift** - MODIFIED
   - Added `registerDevice()`
   - Added `updateFavoriteTeam()`
   - Added `startLiveActivity()`
   - Added `endLiveActivity()`
   - Added `getSubscriptions()`

3. **Examples/FavoriteTeamIntegrationExample.swift** - NEW
   - Example SwiftUI views
   - Integration patterns
   - AppDelegate setup

### Server
1. **Services/LiveActivityAutoService.swift** - NEW
   - Core automatic creation logic
   - Scheduler running every 5 minutes
   - Checks 30-minute window for upcoming matches

2. **configure.swift** - MODIFIED
   - Registered LiveActivityAutoService

3. **Run/main.swift** - MODIFIED
   - Starts automatic service on server boot

## 🗄️ Database Schema

### notification_subscriptions
```sql
- id: UUID
- device_id: UUID (FK to device_registrations)
- league_id: INT (6 for AFCON)
- season: INT (2025)
- team_id: INT (1530 for Cameroon, etc.)
- notify_goals: BOOLEAN (default: true)
- notify_match_start: BOOLEAN (default: true)
- notify_match_end: BOOLEAN (default: true)
- notify_red_cards: BOOLEAN (default: true)
- match_start_minutes_before: INT (default: 15)
```

### live_activities
```sql
- id: UUID
- device_id: UUID (FK to device_registrations)
- fixture_id: INT
- activity_id: STRING
- push_token: STRING
- update_frequency: STRING (all_events, major_events, goals_only)
- is_active: BOOLEAN
- started_at: TIMESTAMP
- expires_at: TIMESTAMP
```

## 🚀 Deployment Status

- ✅ Code written and compiled
- ✅ Docker image building (linux/amd64)
- ⏳ Pending: Push to ECR
- ⏳ Pending: Deploy to ECS

## 📊 Team IDs Reference

| Team | ID | Team | ID |
|------|-----|------|-----|
| Algeria | 1532 | Mali | 1500 |
| Angola | 1529 | Morocco | 31 |
| Benin | 1516 | Mozambique | 1512 |
| Botswana | 1520 | Nigeria | 19 |
| Burkina Faso | 1502 | Senegal | 13 |
| Cameroon | 1530 | South Africa | 1531 |
| Comoros | 1524 | Sudan | 1510 |
| Congo DR | 1508 | Tanzania | 1489 |
| Egypt | 32 | Tunisia | 28 |
| Equatorial Guinea | 1521 | Uganda | 1519 |
| Gabon | 1503 | Zambia | 1507 |
| Ivory Coast | 1501 | Zimbabwe | 1522 |

## 🎯 Benefits

1. **Zero Manual Work** - Live Activities created automatically
2. **User Preference** - Based on favorite team in SwiftData
3. **Scalable** - Server handles all subscribed devices
4. **Real-time** - Updates every 15 seconds during matches
5. **Battery Efficient** - Server-side polling, not client-side

## 🧪 Testing Instructions

1. Register your device (already done):
   ```
   Device UUID: a5f1d7c8-ed65-400a-bdaf-150a0803a9eb
   ```

2. Set favorite team in iOS app:
   ```swift
   try await FavoriteTeamSyncService.shared.updateFavoriteTeam(
       teamId: 1530,  // Cameroon
       teamName: "Cameroon"
   )
   ```

3. Wait for next match (or test with SQL):
   ```sql
   -- Simulate upcoming match
   UPDATE fixtures
   SET date = NOW() + INTERVAL '25 minutes',
       status_short = 'NS'
   WHERE api_fixture_id = 1347274; -- Mozambique vs Cameroon
   ```

4. Check server logs:
   ```bash
   aws logs tail /ecs/staging-afcon-server --region eu-north-1 --since 10m | grep "Live Activity"
   ```

## 📝 Next Steps

1. Test device registration in your iOS app
2. Implement favorite team selection UI
3. Call `updateFavoriteTeam()` when user changes their team
4. Test with upcoming matches
5. Monitor Live Activity creation in server logs

## 🎉 Result

Users can now:
- Select their favorite team in your app
- Automatically receive Live Activities for ALL their team's matches
- Get real-time score updates on their lock screen
- Never miss a goal or match event

All fully automatic! 🚀
