---
name: swift-realtime-backend
description: Scaffolds a real-time Swift backend (Vapor + grpc-swift 2.x) built around four production-proven patterns — a shared Protocol Buffers contract used by both server and Swift clients, adaptive polling that scales its interval based on how close a resource is to an active/"hot" state, an actor-isolated in-memory TTL cache, and an AsyncStream-based pub/sub broadcaster for fanning out live updates to streaming gRPC clients. Use this whenever someone wants to build a new live/real-time Swift server — live scores, live order tracking, live sensor/IoT dashboards, live delivery tracking, a streaming API for any frequently-changing resource — or wants to add gRPC streaming, adaptive/smart polling, or a WebSocket-style push mechanism to an existing Vapor app, even if they don't say "Vapor," "gRPC," or "Protocol Buffers" by name. Also trigger when someone asks how to poll an API efficiently without hammering it, how to broadcast updates to multiple connected clients in Swift, or how to keep a server and its Swift client in sync on data models.
---

# Swift Real-Time Backend

Scaffolds a new Swift Package containing a working, tested starting point
for a real-time backend: an adaptive poller, an actor-based cache, an
`AsyncStream` broadcaster, and a `.proto` contract meant to be shared with
Swift clients. The four pieces come from a production sports-streaming
platform, generalized so they apply to any "poll an upstream, cache the
result, push live updates to many clients" problem — order tracking,
delivery tracking, IoT telemetry, live scores, anything with a "hot" state
that matters more than its idle state.

## When to reach for this

Someone wants a server that pushes live updates to clients as something
changes, especially when:
- there's an upstream to poll (a REST API, a database, a sensor feed) that
  shouldn't be hammered at a constant rate around the clock,
- multiple clients need the same live feed,
- the server and its client(s) are both Swift (or the client could be),
  so a shared `.proto` contract is worth the setup cost.

If the ask is a one-off script, a batch job, or a server that doesn't need
to push anything (plain request/response is enough), this skill is
overkill — say so and skip straight to a normal Vapor route.

## Workflow

1. **Get two things from the user**: a project name (e.g. `LiveOrdersServer`)
   and a singular entity name for the thing being tracked (e.g. `Order`,
   `Shipment`, `Sensor`, `Match`). If they haven't said what they're
   tracking, ask — it's the one piece of domain info the scaffold actually
   needs, and guessing wrong means renaming files after the fact.

2. **Run the scaffold script**:
   ```bash
   python3 scripts/scaffold.py --project <ProjectName> --entity <Entity> --out <output-dir>
   ```
   This generates a complete Swift Package: `Package.swift`, a `.proto`
   file, `CacheService.swift`, `<Entity>Broadcaster.swift`,
   `AdaptivePoller.swift`, `configure.swift`, `main.swift` (HTTP + gRPC as
   sibling structured tasks), a test target, and a `README.md` with next
   steps. It builds and runs immediately (`swift build && swift run Run`,
   `GET /health` → `ok`) — the gRPC server task is a documented stub until
   codegen is wired up (step 4 below), everything else is real, working,
   tested Swift.

3. **Walk the user through what got generated**, pointing at the four
   files in `Sources/App/Services/` and explaining each briefly — don't
   just dump the file tree and stop. If they want the *why* behind any of
   the four patterns (not just the *what*), read `references/patterns.md`
   and explain the relevant section — it covers the tradeoffs and the
   point at which each pattern stops being the right tool (e.g. when to
   graduate from the in-memory cache to Redis).

4. **Point them at the `README.md`'s "Next steps"** for wiring up real
   gRPC codegen (needs `protoc` + the grpc-swift plugin, which this skill
   deliberately does not attempt to install or run — environments vary too
   much to assume it'll work, and the scaffold is designed to build fine
   without it). Offer to help with that step interactively if they want to
   continue past the scaffold, rather than doing it silently — codegen
   tooling changes over time and is worth confirming against grpc-swift's
   current docs rather than assuming.

5. **Customize from there** as a normal editing session: fill in the
   `.proto`'s domain fields, replace `Example<Entity>Source` with a real
   upstream client, tune `AdaptivePoller.Intervals` to the domain's actual
   cadence (how fast is "hot," how far out does "scheduled" start
   mattering).

## What NOT to do

- Don't hand-write the four service files from scratch when the scaffold
  script exists — run it, then customize. Reinventing them inline is
  slower and more error-prone than editing generated output.
- Don't try to make the scaffold generate real gRPC stub code by shelling
  out to `protoc` — assume it may not be installed, and a build failure in
  the middle of scaffolding is a worse experience than a clearly-documented
  manual next step.
- Don't apply this to something that isn't actually a "poll + cache +
  broadcast" problem. A CRUD API with no live-update requirement doesn't
  need an adaptive poller or a broadcaster — just use plain Vapor routes.
