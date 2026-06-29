# Tournament Switch — Server Deployment Design

**Date:** 2026-06-26  
**Status:** Approved

## Goal

Switch the existing AWS-deployed gRPC server from AFCON 2025 to FIFA World Cup 2026 with zero infrastructure changes and minimal downtime, by updating a single environment variable and triggering a rolling ECS deploy. The same server, same endpoint URL, same RDS instance — just a different tournament.

---

## Context

The server (`swift-server-playground`) is a Vapor/Swift gRPC server deployed on AWS via CloudFormation. It is fully tournament-agnostic: all gRPC endpoints accept `leagueId` and `season` as parameters, and the `INIT_LEAGUES` environment variable controls which fixtures are pre-loaded at startup.

**Current value:** `INIT_LEAGUES=6:2025:AFCON 2025`  
**Target value:** `INIT_LEAGUES=1:2026:FIFA World Cup 2026`

No source code changes are required.

---

## AWS Resources (from CloudFormation stack `afcon-${ENV}`)

| Resource | Name |
|---|---|
| ECS Cluster | `${ENV}-afcon-cluster` |
| ECS Service | `afcon-service` |
| Task Definition family | derived from current ECS service |
| Database | RDS PostgreSQL — `afcon` database |
| Region | `eu-north-1` (from AWS config) |

---

## What Changes

**One env var** in the ECS task definition:
```
INIT_LEAGUES: "6:2025:AFCON 2025"  →  "1:2026:FIFA World Cup 2026"
```

Nothing else changes: same Docker image, same RDS instance, same Redis, same ALB endpoint. Old AFCON rows in RDS are harmless — the FWC2026 iOS app only queries `leagueId=1`.

---

## Files to Create

### `infrastructure/switch-tournament.sh`

Interactive script that:
1. Validates AWS credentials and resolves the ECS cluster/service names from the CloudFormation stack outputs
2. Fetches the current active task definition
3. Patches `INIT_LEAGUES` to the new value
4. Registers a new task definition revision
5. Updates the ECS service to use the new revision
6. Waits for the rolling deploy to stabilise (all tasks running the new revision)
7. Prints the server endpoint for verification

**Interface:**
```bash
./infrastructure/switch-tournament.sh \
  --league-id 1 \
  --season 2026 \
  --name "FIFA World Cup 2026" \
  --environment production   # default: production
```

**Flags:**
- `--league-id` — API-Football league ID (required)
- `--season` — tournament season year (required)
- `--name` — human-readable tournament name (required)
- `--environment` — CloudFormation stack env prefix (`production` / `staging`), default `production`

### `infrastructure/verify-tournament.sh`

Sanity-check script that calls the server's REST health endpoint and prints which league/season it is currently serving.

**Interface:**
```bash
./infrastructure/verify-tournament.sh --environment production
```

Exits 0 if the server responds and the active league matches expectations, 1 otherwise.

---

## Rollout Sequence

```
1. Run switch-tournament.sh
   → registers new ECS task definition revision
   → ECS starts new task(s) with INIT_LEAGUES=1:2026:FIFA World Cup 2026
   → new task connects to RDS, runs migrations (no-op — schema unchanged)
   → FIXTURE_SYNC_ON_STARTUP=true triggers WC fixture sync from API-Football
   → ECS health checks pass → old AFCON task(s) are drained and stopped

2. Run verify-tournament.sh
   → confirms server responds and is serving league 1 / 2026

3. Submit FWC2026 iOS app archive to App Store
   → app points to the same gRPC endpoint (unchanged URL)
   → FWC2026 iOS app requests leagueId=1 → gets World Cup data
```

**Estimated downtime:** 0 (rolling deploy — at least one task is always healthy during the transition)  
**Estimated total time:** ~5 minutes

---

## Reverting to AFCON

To roll back at any time:
```bash
./infrastructure/switch-tournament.sh \
  --league-id 6 \
  --season 2025 \
  --name "AFCON 2025" \
  --environment production
```

---

## Future Tournaments

For any future tournament (AFCON 2027, WC 2030, etc.):
```bash
./infrastructure/switch-tournament.sh \
  --league-id <id> \
  --season <year> \
  --name "<Name>" \
  --environment production
```

No code changes, no new infrastructure. Just the right `--league-id` from API-Football.
