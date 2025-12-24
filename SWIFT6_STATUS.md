# Swift 6.2 Migration Status

**Date:** December 17, 2024
**Target:** Swift 6.0+ with grpc-swift 2.x
**Status:** 🟡 In Progress

---

## ✅ Completed Steps

### 1. Package.swift Updated for Swift 6.0+
**File:** `Package.swift`

- Swift tools version: `6.0`
- Minimum macOS version: `14.0`
- Dependencies upgraded:
  - grpc-swift: `2.0.0+` (was `1.21.0`)
  - grpc-swift-nio-transport: `1.0.0+` (new)
  - grpc-swift-protobuf: `1.0.0+` (new)
  - SwiftProtobuf: `1.28.0+` (was `1.25.0`)
- Swift 6 concurrency features enabled:
  - `ExistentialAny`
  - `StrictConcurrency`

### 2. Swift PM Plugins Configured
**Files:** `Package.swift`, `Sources/App/Protos/`, `Sources/AFCONClient/Protos/`

- Added `GRPCProtobufGenerator` plugin to both `App` and `AFCONClient` targets
- Copied `afcon.proto` to target-specific Protos directories
- Plugin will auto-generate gRPC code during build

### 3. Migration Guide Created
**File:** `SWIFT6_MIGRATION_GUIDE.md`

Complete guide covering:
- API differences between grpc-swift 1.x and 2.x
- Code generation with Swift PM plugins
- Service provider migration
- Server initialization updates
- Streaming API changes
- Client code migration
- Docker configuration
- Troubleshooting

### 4. Dockerfile Already Compatible
**File:** `Dockerfile`

- Uses `swift:6.0-jammy` base image
- Multi-stage build optimized for production
- No changes needed

---

## 🟡 In Progress

### 5. Testing Swift 6.0 Build
**Status:** Build running in background

Command: `swift build`

Waiting to see if:
- Dependencies resolve correctly
- Swift PM plugin generates proto code
- Build completes without errors

---

## ⏳ Pending Steps

### 6. Migrate AFCONServiceProvider to GRPCCore API
**File:** `Sources/App/gRPC/Server/AFCONServiceProvider.swift` (~1400 lines)

**Required Changes:**

#### Before (grpc-swift 1.x):
```swift
import GRPC
import NIO

public final class AFCONServiceProvider: Afcon_AFCONServiceAsyncProvider {
    public func getLeague(
        request: Afcon_LeagueRequest,
        context: GRPC.GRPCAsyncServerCallContext
    ) async throws -> Afcon_LeagueResponse {
        // Implementation
    }

    public func streamLiveMatches(
        request: Afcon_LiveMatchRequest,
        context: StreamingResponseCallContext<Afcon_LiveMatchUpdate>
    ) -> EventLoopFuture<GRPCStatus> {
        // Implementation
    }
}
```

#### After (grpc-swift 2.x):
```swift
import GRPCCore
import GRPCProtobuf

public final class AFCONServiceProvider: Afcon_AFCONServiceProtocol {
    public func getLeague(
        request: ServerRequest.Single<Afcon_LeagueRequest>
    ) async throws -> ServerResponse.Single<Afcon_LeagueResponse> {
        let req = request.message
        // Implementation
        return ServerResponse.Single(message: response)
    }

    public func streamLiveMatches(
        request: ServerRequest.Single<Afcon_LiveMatchRequest>
    ) async throws -> ServerResponse.Stream<Afcon_LiveMatchUpdate> {
        return ServerResponse.Stream { writer in
            while !Task.isCancelled {
                let update = // ... fetch update
                try await writer.write(update)
                try await Task.sleep(for: .seconds(30))
            }
            return [:]  // Metadata
        }
    }
}
```

**Key Changes:**
1. Import `GRPCCore` instead of `GRPC`
2. Conform to generated protocol (name TBD after plugin runs)
3. Wrap requests in `ServerRequest.Single<T>`
4. Wrap responses in `ServerResponse.Single<T>` or `ServerResponse.Stream<T>`
5. Remove `EventLoopFuture` - use async/await directly
6. Update streaming to use `ServerResponse.Stream { writer in ... }`

**Affected Methods (18 total):**
1. `getLeague` - Unary
2. `getTeams` - Unary
3. `getFixtures` - Unary
4. `getTodayUpcoming` - Unary
5. `getFixtureById` - Unary
6. `getFixtureEvents` - Unary
7. `getFixturesByDate` - Unary
8. `streamLiveMatches` - Server streaming ⚠️ Complex
9. `getStandings` - Unary
10. `getTeamDetails` - Unary
11. `getLineups` - Unary
12. `getNextUpcoming` - Unary
13. `syncFixtures` - Unary
14. `registerDevice` - Unary (push notifications)
15. `updateSubscriptions` - Unary (push notifications)
16. `getSubscriptions` - Unary (push notifications)
17. `unregisterDevice` - Unary (push notifications)
18. `updateDeviceToken` - Unary (push notifications)

### 7. Update Server Initialization
**Files:** `Sources/App/configure.swift`, `Sources/Run/main.swift`

#### Current (grpc-swift 1.x):
```swift
// In configure.swift
import GRPC
import NIO

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let server = Server.insecure(group: group)
    .withServiceProviders([serviceProvider])
    .bind(host: "0.0.0.0", port: 50051)

try server.wait()
```

#### Target (grpc-swift 2.x):
```swift
// In configure.swift
import GRPCCore
import GRPCNIOTransportHTTP2

let server = GRPCServer(
    transport: .http2NIOPosix(
        address: .ipv4(host: "0.0.0.0", port: 50051),
        config: .defaults()
    ),
    services: [serviceProvider]
)

try await server.run()
```

### 8. Update Client Library (AFCONClient)
**File:** `Sources/AFCONClient/...` (if you have client code)

Similar migration: Replace `GRPC` imports with `GRPCCore`, use `GRPCClient` instead of `ClientConnection`.

### 9. Test All Endpoints
Once build succeeds:

```bash
# Start server
swift run Run serve --hostname 0.0.0.0 --port 8080

# Test HTTP
curl http://localhost:8080/health

# Test gRPC (requires grpcurl)
grpcurl -plaintext localhost:50051 list
grpcurl -plaintext -d '{"league_id": 6, "season": 2025}' \
    localhost:50051 afcon.AFCONService/GetLeague
```

### 10. Test Docker Build

```bash
docker build -t afcon-server:swift6 .
docker run -p 8080:8080 -p 50051:50051 afcon-server:swift6
```

---

## 🔍 Key Migration Challenges

### 1. Streaming API Complexity
The `streamLiveMatches` method (lines 800-1400) is the most complex:
- Current: Uses `EventLoopFuture` + Task + Promise pattern
- Target: Pure async/await with `ServerResponse.Stream`
- Includes notification triggers (goals, red cards, match start/end)
- Needs careful testing for cancellation handling

### 2. NIO EventLoop Dependencies
Current code may have NIO EventLoop dependencies:
- Search for `EventLoop`, `EventLoopPromise`, `EventLoopFuture`
- Replace with Swift Concurrency primitives
- Use `withCheckedThrowingContinuation` if needed

### 3. Actor Isolation
`NotificationService` is an actor - ensure proper async/await usage:
```swift
try await notificationService.sendGoalNotification(...)
```

---

## 📝 Migration Checklist

- [x] Update Package.swift to Swift 6.0+ and grpc-swift 2.x
- [x] Configure Swift PM plugins for code generation
- [x] Create migration guide
- [x] Update Dockerfile (already compatible)
- [ ] Test build with new configuration (in progress)
- [ ] Verify generated proto code uses GRPCCore API
- [ ] Migrate AFCONServiceProvider (18 methods)
- [ ] Update server initialization
- [ ] Test all gRPC endpoints
- [ ] Test push notifications
- [ ] Test streaming (`streamLiveMatches`)
- [ ] Test Docker build
- [ ] Update CI/CD (GitHub Actions)
- [ ] Deploy to AWS ECS

---

## 🚀 Next Steps (After Build Completes)

### If Build Succeeds:
1. Inspect generated proto code in:
   - `Sources/App/Protos/` (or `.build/plugins/...`)
   - `Sources/AFCONClient/Protos/`
2. Start migrating `AFCONServiceProvider.swift`
3. Update server initialization
4. Test endpoints incrementally

### If Build Fails:
1. Review error messages
2. Check plugin output
3. May need to adjust proto file location or plugin configuration
4. Fallback: Use manual protoc approach (see `SWIFT6_MIGRATION_GUIDE.md`)

---

## 📚 Resources

- **Migration Guide:** `SWIFT6_MIGRATION_GUIDE.md`
- **grpc-swift 2.x Docs:** https://swiftpackageindex.com/grpc/grpc-swift/2.0.0/documentation/grpc
- **GRPCCore API:** https://swiftpackageindex.com/grpc/grpc-swift/2.0.0/documentation/grpccore
- **Swift Concurrency:** https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html

---

## ⏱️ Estimated Time Remaining

- Service provider migration: **3-4 hours**
- Server initialization: **30 minutes**
- Testing: **1-2 hours**
- Docker build & deployment: **1 hour**
- **Total:** **5-7 hours**

---

## 🆘 Rollback Plan

If critical issues arise:

```bash
# Revert all changes
git checkout HEAD -- Package.swift
git checkout HEAD -- Sources/

# Rebuild with Swift 5.9 + grpc-swift 1.x
swift package clean
swift build
```

---

**Status:** Waiting for build to complete to proceed with next steps.
