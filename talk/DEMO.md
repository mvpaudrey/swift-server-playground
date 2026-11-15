# Live Demo Runbook — U-20 Women's World Cup 2026 (league 920)

End-to-end Swift demo: local Vapor/gRPC server → real API-Football data for **league 920**
(FIFA U-20 Women's World Cup, season **2026**) → iOS app over the real gRPC stream.

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

## 3. iOS app → local server  — already wired to the **FWC2026** scheme

For the talk the FWC2026 scheme has been repurposed to the U-20 WWC demo. Just pick the
**FWC2026** scheme in Xcode and Run on the simulator — fixtures / standings / live scores
come from `localhost:50051` for league 920.

What was changed (all revert together after the talk — grep `DEMO`):
- **new** `AFCONApp/AFCONiOSApp/FWC2026/Config/U20WWCTournamentConfig.swift` (leagueId 920,
  season 2026). Auto-included in the FWC2026 target (filesystem-synchronized group).
  Its `teamFlagMap` covers **all 24** nations (U-20 API team ids → FIFA codes).
- **new flag SVGs** in `FWC2026/Assets.xcassets/Teams/`: `TAN` `BEN` `NGA` copied from the
  AFCON2025 catalog; `POL` `CHN` `CRC` `ITA` `PRK` `NCL` hand-authored (flag-icons style,
  640×480). NCL is the Kanaky/FLNKS flag.
- `FWC2026/FWC2026App.swift` — 3 refs swapped `FWCTournamentConfig()` → `U20WWCTournamentConfig()`.
- `AFCON2025.xcodeproj/.../FWC2026.xcscheme` — `LaunchAction` now sets
  `AFCON_API_HOST=localhost` / `AFCON_API_PORT=50051`.
- `AFCONClient` / `TournamentServiceWrapper` — `getLiveFixtures` takes a `season` (was
  hardcoded 2025).

> Not touched: the `AFCON2025` target, `FWCTournamentConfig.swift`, `AFCON2025.xcscheme`.

### To restore FIFA World Cup 2026
Revert the 3 lines in `FWC2026App.swift`, delete the two `<EnvironmentVariable>` entries
in `FWC2026.xcscheme` (or untick them in Edit Scheme), optionally delete
`U20WWCTournamentConfig.swift`.

---

## 4. Rehearsal order

1. `docker compose up -d postgres` → `swift run Run`, wait for the 4 startup lines.
2. `curl localhost:8080/health` and the `grpcurl GetFixtures` check.
3. Launch the app (FWC2026 scheme, env vars set). Confirm the U-20 WWC schedule loads.
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
