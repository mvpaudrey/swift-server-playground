# Why these four patterns

Background for when you (or the person you scaffolded this for) want to
understand the reasoning, not just copy the code. Each section stands
alone — read whichever's relevant.

## 1. One shared `.proto` contract for server and client

The alternative is hand-written DTOs on each side that drift the moment
someone adds a field on the server and forgets the client (or vice versa).
A single `.proto` file, with Swift types generated from it and used
unmodified by both the server and every Swift client, makes that class of
bug impossible to introduce silently — the field either exists on both
sides or the code doesn't compile.

This only pays off if the generated types are actually shared, not
regenerated independently on each side (which can drift if the `.proto`
itself gets out of sync). If your server and client are separate
repositories, publish the generated package, or generate at build time
from a `.proto` that lives in a package both sides depend on.

## 2. Adaptive polling instead of a fixed interval

Most real-time systems aren't real-time all the time — a match, an order,
a shipment is only "hot" for a fraction of its lifecycle. Polling a fixed
interval 24/7 means either:
- too slow when it matters (fixed interval tuned for the average case
  misses fast-changing moments), or
- wasteful/rate-limited when it doesn't (polling every 15 seconds against
  a resource that changes once a day burns API quota and money for
  nothing).

The fix is to make the interval a function of *how close you are to
something changing*, not a constant. A production system built on this
pattern polled every 15 seconds while a resource was live, and paced out
to a 24-hour check when nothing was scheduled — about a 5,000x range
between the two ends. The exact thresholds don't matter much; what matters
is the shape: fast near/during the event, slow far from it.

This only works as-shipped for domains that *have* a next-known-event to
count down to (a kickoff time, a delivery window). For continuous-monitoring
domains with no schedule at all — sensors, health checks, anything that's
just "on" the whole time — `nextKnownEvent` will always return `nil` and
the poller collapses to two states: `active` or `idle`, skipping the
in-between tiers entirely. That's not broken, just a smaller state machine
than the scheduled-event case; if you want finer-grained backoff for that
kind of domain (e.g. slow down the longer a reading has been unchanged,
speed back up the moment it moves), extend your domain's `Source` protocol
with your own signal instead of forcing a fake "next event" through
`nextKnownEvent`.

Two failure modes to design against:
- **Don't let a slow poll silently miss something.** If your source can
  tell you "yes, currently active" cheaply (a status field, a boolean),
  check that on every poll regardless of how long you slept — that's what
  flips you back to the fast interval.
- **Don't hot-loop on a failing upstream.** Back off (don't retry
  immediately) when `fetchUpdates` throws, or a flaky API turns into a
  self-inflicted denial of service.

## 3. Actor-isolated in-memory cache instead of an external store

For a single-instance or few-instance service, an in-process cache removes
a network hop and an operational dependency (nothing to provision, nothing
that can be down). The risk with any shared mutable cache is data races
between concurrent readers/writers — an `actor` removes that risk
entirely at compile time: the Swift compiler won't let you touch the
cache's storage without going through its isolated methods, so there's no
`Dictionary` compare-and-swap race to get subtly wrong under load.

Set TTLs per key based on how fast that specific piece of data actually
changes — not one global number. Reference/catalog data can cache for
hours; the resource that's currently "live" should cache for tens of
seconds at most, or you'll serve stale data to the very case you built
the fast poller for.

This pattern stops scaling once you have multiple server instances that
need a consistent view (instance A's cache doesn't know about a write on
instance B) — that's the point to move to a distributed cache like Redis,
not before. Don't reach for Redis on day one for a resource that just
needs to survive one process's uptime.

## 4. `AsyncStream`-based broadcast instead of a message broker

For "N clients, one process, all reading the same live feed," you don't
need Kafka or a WebSocket message broker — Swift's own `AsyncStream` gives
each subscriber an independent buffered channel, and an `actor` holding
the map of subscriber-to-continuation gives you safe concurrent
subscribe/unsubscribe/broadcast for free.

The key property: giving each subscriber its *own* stream (rather than one
shared stream fanned out manually) means a slow or disconnected client
can't block delivery to the others — each `AsyncStream.Continuation`
buffers independently. Clean up on `onTermination` so a client that
disconnects without calling an explicit "unsubscribe" doesn't leak.

This stops being the right tool once you need delivery across multiple
server processes (a message broker solves that), or persistence/replay of
missed messages beyond a small in-memory rolling window.

## Putting it together: HTTP and gRPC as sibling structured tasks

Running the HTTP server and the gRPC server in the same process, as two
tasks in one `withThrowingTaskGroup`, means:
- one deploy artifact, one process to monitor, one set of shared services
  (the cache, the broadcaster) reachable from both;
- if either server throws, the task group tears both down — you don't end
  up with a zombie process serving HTTP with a dead gRPC server (or vice
  versa) and no clear signal that anything's wrong.

If your HTTP and gRPC surfaces genuinely need independent scaling (e.g.
gRPC streaming connections vastly outnumber HTTP requests), that's a sign
to split them into separate processes/deployables later — but don't start
there. Start with one process and split when you actually measure the
need.
