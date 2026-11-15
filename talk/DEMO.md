# Live Demo Runbook — U-20 Women's World Cup 2026 (league 920)

End-to-end Swift demo: local Vapor/gRPC server → real API-Football data for **league 920**
(FIFA U-20 Women's World Cup, season **2026**) → iOS app over the real gRPC stream.

> **Another league?** The examples use league 920 (talk of 2026-09-08). To reuse this runbook,
> change the league in three places: the server `.env` (`INIT_LEAGUES`, `DEMO_LEAGUE_ID`,
> `DEMO_SEASON`), the iOS `Demo/DemoTournamentConfig.swift` (`leagueId`, `season`,
> `competitionName`), and the ids in the `curl` / `grpcurl` commands. The fixture table below
> is specific to the 2026-09-08 talk.

- Season 2026 window: **2026-09-05 → 2026-09-13** (events + lineups covered).
- Talk day **2026-09-08** fixtures (UTC):
  | kickoff | fixture id | match |
  |---|---|---|
  | 13:00 | `1637283` | Benin U20 W vs Argentina U20 W |
  | 13:00 | `1637284` | Brazil U20 W vs Canada U20 W |
  | 16:00 | `1637285` | England U20 W vs Tanzania U20 W |
  | 16:00 | `1637286` | Poland U20 W vs Mexico U20 W |

If the talk is ~16:00 UTC, the 16:00 matches are live during it. The synthetic trigger
(below) is the guaranteed "goal → app updates" moment if the real match is quiet.

---

## 1. Server (this repo)

Already configured in `.env`:
```
INIT_LEAGUES="920:2026:U20 Women World Cup"
DEMO_LEAGUE_ID=920
DEMO_SEASON=2026
```

Start it:
```bash
cd swift-server-playground
open -a Docker                       # if Docker Desktop isn't running
docker compose up -d postgres        # Redis not required (in-memory cache)
swift run Run                        # Vapor auto-loads .env
```

Healthy startup logs:
```
✅ Configured league: U20 Women World Cup (ID: 920, Season: 2026)
✅ Successfully initialized database with 36 fixtures for U20 Women World Cup
Server started on http://127.0.0.1:8080
gRPC server starting on 0.0.0.0:50051
```

Ports: HTTP `8080`, gRPC `50051` (production defaults — matches what the app expects).

### First run only — reset the local DB if you see `PSQLError`
The old local `afcon` DB has stale AFCON schema. Wipe it once:
```bash
docker exec afcon-postgres psql -U postgres -d afcon -c \
  'DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO postgres;'
```
then restart the server (migrations recreate everything).

### Sanity checks
```bash
curl -s localhost:8080/health
curl -s localhost:8080/api/v1/league/920/season/2026/fixtures | jq length      # -> 36
grpcurl -plaintext -import-path Protos -proto afcon.proto \
  -d '{"league_id":920,"season":2026}' localhost:50051 afcon.AFCONService/GetFixtures | jq '.fixtures | length'
```

---

## 2. Synthetic event trigger (safety net)

In-memory only. Never calls API-Football / AWS / real APNs; never writes to Postgres.
Broadcasts a normal `Afcon_LiveMatchUpdate` on the real `StreamLiveMatches` gRPC stream —
the iOS client can't tell it from a real event.

```bash
# Goal for the home team (auto-advances the clock, picks today's / next fixture)
curl -XPOST localhost:8080/demo/trigger/goal

# Target a specific match + control the details
curl -XPOST localhost:8080/demo/trigger/goal -H 'content-type: application/json' \
  -d '{"fixtureId":1637285,"team":"away","minute":63,"player":"A. Scott"}'

curl -XPOST localhost:8080/demo/trigger/card         -d '{"team":"home"}' -H 'content-type: application/json'
curl -XPOST localhost:8080/demo/trigger/red          -d '{"team":"away"}' -H 'content-type: application/json'
curl -XPOST localhost:8080/demo/trigger/substitution -d '{"team":"home"}' -H 'content-type: application/json'
curl -XPOST localhost:8080/demo/trigger/var          -d '{"team":"home"}' -H 'content-type: application/json'

# Back to 0-0, empty event log (between rehearsals)
curl -XPOST localhost:8080/demo/reset
```

`kind` accepts: `goal` · `card`/`yellow` · `red` · `substitution`/`sub` · `var`
(French aliases `but`/`carton`/`remplacement` also work).

Response echoes the running score:
```json
{"fixtureID":1637285,"homeTeam":"England U20 W","awayTeam":"Tanzania U20 W",
 "homeScore":1,"awayScore":0,"minute":23,"eventType":"goal","detail":"Normal Goal",
 "subscribersNotified":1}
```
`subscribersNotified: 0` → no gRPC client is connected yet (open the app / a `grpcurl`
stream first).

**Watch it stream** in another terminal:
```bash
grpcurl -plaintext -import-path Protos -proto afcon.proto \
  -d '{"league_id":920,"season":2026}' localhost:50051 afcon.AFCONService/StreamLiveMatches
```

---

## 3. iOS app → local server — the **Demo** target

The demo runs in its own app target, **`Demo`** (iOS repo `AFCONApp/AFCONiOSApp`, branch
`feat/demo-target`): separate bundle ID (`com.cheulah.halftimefootball.Demo`), no widget, no push,
in-memory SwiftData store. The `FWC2026` and `AFCON2025` targets are not touched for a demo, so
there is nothing to revert afterwards.

### One-time setup
- *Demo ▸ Signing & Capabilities*: add the App Group `group.com.cheulah.demo` (the config uses it).
- Set the league in `Demo/DemoTournamentConfig.swift` (`leagueId`, `season`, `competitionName`).
  It must match the league the local server was started with.
- Flags: `teamFlagMap` is empty by default. Fill it (API team id → FIFA code) and add the flag
  assets to `Demo/Assets.xcassets` if you want them on screen.

### Run
Pick the **Demo** scheme and Run on the simulator. Fixtures / standings / live scores come from
`localhost:50051`.

### Why it can't reach production
- At launch `DemoApp` calls `TournamentServiceWrapper.useServer(host:port:)` (`localhost:50051`).
  It is the first stored property of the app, so it runs before any other service is created.
- It does **not** depend on scheme environment variables: relaunching the app from the simulator
  home screen still talks to the local server.
- `precondition` — the app crashes at launch if the host contains `amazonaws.com`.
- `AFCON_API_HOST` / `AFCON_API_PORT` are still honoured, to reach the Mac from a physical device
  (use its LAN address; iOS will ask for local-network permission).

> **History.** A U-20 build once reached the production server and left a league-920 notification
> subscription there (removed in Nov 2026). Most likely the app was relaunched from the home
> screen, without the scheme's `AFCON_API_HOST=localhost`. The dedicated target removes that
> failure mode.

The `/demo/*` endpoints exist only on the `demo/can2025-talk` branch of this repo — never deploy
that branch.

---

## 4. Rehearsal order

1. `docker compose up -d postgres` → `swift run Run`, wait for the 4 startup lines.
2. `curl localhost:8080/health` and the `grpcurl GetFixtures` check.
3. Launch the app (**Demo** scheme). Confirm the schedule of the demo league loads.
4. Open a live match → keep the `grpcurl StreamLiveMatches` terminal visible.
5. `curl -XPOST localhost:8080/demo/reset`, then fire `goal` / `card` / `var` and watch
   the app + stream update together.
6. `curl -XPOST localhost:8080/demo/reset` before going on stage.

## Notes / limits

- API-Football plan: **Pro**, 7500 req/day — no quota risk. Live polling is one call / 15s
  per league while a match is in play.
- Dynamic Island / Live Activity via push is **not** wired for local (needs APNs or
  `xcrun simctl push`). The in-app live match view updates from the gRPC stream regardless.
- Demo state is in-memory: restarting the server resets synthetic scores to 0-0.
- `logStandingsForGoal` in `AFCONServiceProvider` still has a `season: 2025` literal — it's
  in the unused legacy streaming method, dead code, ignore.
