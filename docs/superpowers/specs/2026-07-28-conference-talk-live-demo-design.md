# Conference Talk: Animated Deck + Live Demo Server — Design

## Context

The user is preparing a conference talk about this project ("100% Swift sports streaming platform: CAN 2025 → FIFA World Cup 2026 → soon CAN Women 2026"). A content outline already exists (shared separately as a talk outline). This spec covers two integrated deliverables requested for the talk itself:

1. An animated HTML slide deck.
2. A live demo, triggerable from within the deck, that simulates match events (goal, card, substitution, VAR/penalty) in real time against both the real iOS app and a dashboard embedded in the deck.

Both must run fully offline on the presenter's laptop (no reliance on conference wifi, no calls to production infrastructure, no calls to API-Football or Apple's push servers).

## Goals

- One click in the deck triggers a simulated match event that is visible, live, in:
  - the dashboard embedded in the deck (score, event feed, animation), and
  - the real iOS app running in Simulator (via the actual gRPC stream), including a Dynamic Island Live Activity update.
- The demo reuses the project's real `.proto` contract — no duplicated/drifted schema.
- Zero risk to production: the demo never touches Postgres, AWS, API-Football, or real APNs.
- The deck itself is a coherent, animated, keyboard-navigable HTML presentation covering the content in the existing talk outline.

## Non-goals

- No scripted/automatic event sequence — event triggering is manual, on-demand (presenter clicks a button whenever suits their pacing).
- No grpc-web / browser-native gRPC. The browser dashboard talks to the demo server over plain WebSocket + HTTP, not gRPC.
- No changes to the production `App` target, its Postgres-backed services, or the deployed server.
- No attempt to make the demo server production-ready, load-tested, or reusable beyond the talk.

## Architecture

```
                 ┌─────────────────────────────────────────────┐
                 │              DemoServer (Vapor)              │
                 │                                               │
  HTML deck ───► │  POST /demo/trigger/{goal|card|sub|var}      │
  (browser)      │        │                                      │
                 │        ▼                                      │
                 │  In-memory match state (score, minute,        │
                 │  event log) for one synthetic fixture          │
                 │        │                                      │
                 │        ├──► gRPC StreamLiveMatches ──────────►│──► iOS app (Simulator)
                 │        │    (AFCONClient-generated types)      │
                 │        │                                      │
                 │        ├──► WebSocket /demo/ws (JSON) ────────►│──► Dashboard in deck
                 │        │                                      │
                 │        └──► `xcrun simctl push` (goal only) ──►│──► Dynamic Island / Live Activity
                 └─────────────────────────────────────────────┘
```

Single Swift process (`DemoServer`) serves three surfaces from one triggered event: real gRPC stream, plain WebSocket for the browser, and a local simulated push for ActivityKit.

## Components

### 1. `DemoServer` (new Package.swift target)

- New executable target, added to the existing `Package.swift` in this repo.
- Depends on **`AFCONClient`** (already has the generated protobuf/gRPC types and the grpc-swift 2.x libraries, with no Fluent/Postgres dependency) plus **Vapor** (for the HTTP trigger routes and WebSocket route only — no Fluent).
- Implements the gRPC service provider for `StreamLiveMatches` (required for the demo) and stubs the remaining RPCs the iOS app calls on launch/navigation (leagues, fixtures, standings, team details, lineups) with canned in-memory data for one synthetic league/fixture — enough for the real app's screens to render without crashing.
- Holds a single in-memory `DemoMatchState` (actor): score, minute, match status, rolling event log. Mutated only by the `/demo/trigger/*` routes.
- Runs HTTP (Vapor, incl. WebSocket) and the gRPC server concurrently, following the same `withThrowingTaskGroup` pattern already used in `Sources/Run/main.swift`.
- Default ports: HTTP `8090`, gRPC `50151` — deliberately different from the production defaults (`PORT=8080`, `GRPC_PORT=50051`) so both can run side by side locally without collision, e.g. while comparing demo vs. real data during rehearsal.
- Routes:
  - `POST /demo/trigger/goal` — bumps score, appends a goal event, broadcasts on gRPC + WebSocket, shells out to `xcrun simctl push` with a canned goal-update payload targeting the booted Simulator.
  - `POST /demo/trigger/card`, `POST /demo/trigger/substitution`, `POST /demo/trigger/var` — same broadcast path (gRPC + WebSocket), no `simctl push` (Live Activity demo is goal-only per user decision).
  - `POST /demo/reset` — resets match state to kickoff (0-0, minute 0, empty event log), for rehearsal and for resetting between practice runs.
  - `WS /demo/ws` — pushes each triggered event as JSON (`event_type`, `minute`, `team`, `player`, `score_home`, `score_away`) to connected browser dashboards.

### 2. iOS app: local/demo endpoint

- The app needs a way to point its gRPC client at `localhost:<port>` instead of the production host for the duration of the demo.
- Implementation: a separate Xcode scheme (or a debug-only toggle already available in the app, if one exists — to be confirmed during implementation) that overrides the gRPC target host. This does not touch the production scheme/config.
- No other app changes anticipated — the app should work against `DemoServer` unmodified as long as `DemoServer` implements the RPCs the app actually calls at launch.

### 3. `talk/` deck (new top-level folder in this repo)

- Hand-written HTML/CSS/JS, no build step, opened directly in a browser.
- Slide navigation via arrow keys; matches the structure of the previously-approved talk outline.
- One slide type is the "live demo" slide: embeds the dashboard widget (WebSocket client to `DemoServer`, animated score/event feed, 4 trigger buttons: But / Carton / Remplacement / VAR-Penalty) plus a "Reset" control.
- Not part of the Swift Package build; it's a static asset folder, served by opening the HTML file directly or via a trivial local file server if needed for WebSocket CORS reasons (to be resolved during implementation).

## Data flow (goal example)

1. Presenter clicks "But" in the deck's live-demo slide.
2. Browser sends `POST /demo/trigger/goal` to `DemoServer` (`http://localhost:<port>`).
3. `DemoServer` updates `DemoMatchState` (score, event log).
4. `DemoServer` broadcasts the update on the existing `StreamLiveMatches` gRPC stream — any connected iOS app (Simulator) receives it exactly as it would a real live update.
5. `DemoServer` pushes the same event as JSON over `/demo/ws` — the deck's dashboard widget animates (score pulse, event added to feed, confetti).
6. `DemoServer` shells out to `xcrun simctl push <device> <bundle-id> <payload>` with a goal payload — the booted Simulator's Dynamic Island/Live Activity updates, fully offline.

One click updates all three surfaces; the presenter can switch focus between the deck's dashboard and the Simulator window without re-triggering anything.

## Error handling

- If no iOS Simulator is booted / `simctl push` fails: log a warning server-side and continue (gRPC + WebSocket broadcasts still succeed independently) — a missing Simulator must never block the dashboard/gRPC demo from working.
- If the browser dashboard's WebSocket disconnects (e.g. laptop sleep, browser reload): dashboard should auto-reconnect and re-render from a `GET /demo/state` snapshot endpoint, not just from future WebSocket messages, so a mid-talk browser refresh doesn't leave a blank dashboard.
- `DemoServer` never talks to Postgres, AWS, API-Football, or real APNs — no code path in this target should reference those.

## Testing / rehearsal support

- `POST /demo/reset` lets the presenter rehearse the full sequence repeatedly without restarting the server.
- A short `talk/README.md` (or similar) documenting: how to start `DemoServer`, how to point the iOS app at it, and the order of operations to rehearse before going on stage.

## Out of scope (explicitly deferred)

- grpc-web / Envoy proxy.
- Scripted/automatic event sequences.
- Any production code changes (Postgres schema, AWS infra, real push notifications).
- Polish beyond what's needed for a reliable live demo (e.g., no persistence of demo state across server restarts).

## Open items to resolve during implementation planning

- Exact mechanism for the iOS app's local/demo server toggle (new scheme vs. existing debug setting) — needs a quick look at the app's current server-host configuration.
- Exact `xcrun simctl push` payload shape needed to trigger the app's existing Live Activity start/update flow (based on `LiveActivityAutoService`'s real push payload).
- Local file serving for the deck if the browser's WebSocket/CORS behavior requires it (vs. opening the HTML file directly via `file://`).
