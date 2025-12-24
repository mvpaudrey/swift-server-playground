# AFCONClient Troubleshooting Guide

Common issues and their solutions when using the AFCONClient library with SwiftData.

---

## CoreData/SwiftData "Failed to stat path" Error

### Error Message

```
CoreData: error: Failed to stat path '/Users/.../Library/Application Support/default.store',
errno 2 / No such file or directory.
```

### Cause

This error occurs on fresh installations when SwiftData tries to create its database file, but the parent directory doesn't exist yet.

### Solution

The `AFCONDataManager` now automatically creates the necessary directories. Make sure you're using the latest version:

#### ✅ CORRECT - Use `makeSharedContainer()`

```swift
@main
struct MyApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            // This creates the directory structure automatically
            self.modelContainer = try AFCONDataManager.makeSharedContainer()
        } catch {
            fatalError("Failed to initialize: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}
```

#### ❌ WRONG - Old initialization (no directory creation)

```swift
// Don't do this - may fail on fresh install
let dataManager = try AFCONDataManager()
```

### Additional Fixes

If you still see this error:

1. **Clean Build Folder** (Xcode → Product → Clean Build Folder)
2. **Reset Simulator** (Device → Erase All Content and Settings...)
3. **Delete Derived Data**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```

4. **Manual Directory Creation** (if needed):
   ```swift
   let appSupport = FileManager.default.urls(
       for: .applicationSupportDirectory,
       in: .userDomainMask
   ).first!

   let afconDir = appSupport.appendingPathComponent("AFCON")
   try? FileManager.default.createDirectory(
       at: afconDir,
       withIntermediateDirectories: true
   )
   ```

---

## "Cannot connect to gRPC server" Error

### Error Message

```
Failed to connect to server at localhost:50051
```

### Cause

The AFCON gRPC server is not running or is running on a different port.

### Solution

1. **Start the server**:
   ```bash
   cd /path/to/swift-server-playground
   swift run
   ```

2. **Verify server is running**:
   ```bash
   curl http://localhost:8080/health
   ```

3. **Check port configuration**:
   ```swift
   // Make sure port matches your server
   let service = try AFCONService(
       host: "localhost",
       port: 50051  // Default port
   )
   ```

4. **For iOS Simulator**, use localhost:
   ```swift
   let service = try AFCONService(host: "localhost", port: 50051)
   ```

5. **For iOS Device**, use your Mac's IP:
   ```swift
   // Find your Mac's IP with: ifconfig | grep "inet "
   let service = try AFCONService(host: "192.168.1.100", port: 50051)
   ```

---

## JSON Fallback Files Not Loading

### Symptom

App shows empty data even though you have JSON fallback files.

### Cause

JSON files are not properly added to the Xcode project target.

### Solution

1. **Verify files are in bundle**:
   ```swift
   if let url = Bundle.main.url(forResource: "fixtures_fallback", withExtension: "json") {
       print("✅ Found: \(url)")
   } else {
       print("❌ Not found in bundle!")
   }
   ```

2. **Add to Xcode project**:
   - Drag JSON files to Xcode
   - ✅ Check "Copy items if needed"
   - ✅ Add to your app target
   - ✅ Check they appear in Build Phases → Copy Bundle Resources

3. **Verify JSON format**:
   ```bash
   # Validate JSON syntax
   cat fixtures_fallback.json | python3 -m json.tool
   ```

---

## SwiftData Cache Not Updating

### Symptom

App shows stale data even after the server has new data.

### Cause

Cache hasn't expired or background refresh failed.

### Solution

1. **Force refresh**:
   ```swift
   // Clear cache and refetch
   try await dataManager.clearAllCache()
   let fresh = try await dataManager.getFixtures()
   ```

2. **Check cache expiration**:
   ```swift
   // Default is 1 hour, you can reduce it
   dataManager.cacheExpirationInterval = 300  // 5 minutes
   ```

3. **Manually trigger refresh**:
   ```swift
   // In SwiftUI with pull-to-refresh
   .refreshable {
       fixtures = try await dataManager.getFixtures()
   }
   ```

---

## "Type AFCONService not found" Compilation Error

### Cause

The proto-generated files are missing or not included in your target.

### Solution

1. **Generate proto files**:
   ```bash
   cd /path/to/swift-server-playground
   ./generate-protos-v2.sh
   ```

2. **Verify generated files exist**:
   ```bash
   ls -la Sources/AFCONClient/Generated/
   # Should show: afcon.pb.swift, afcon.grpc.swift
   ```

3. **Add to Xcode**:
   - Drag `Generated/` folder to Xcode project
   - ✅ Add to AFCONClient target

---

## App Crashes with "fatalError" on Launch

### Symptom

App crashes immediately with:
```
Fatal error: Failed to initialize AFCONDataManager: ...
```

### Cause

Initialization failed due to SwiftData or gRPC service error.

### Solution

**Use graceful error handling instead of fatalError:**

```swift
@main
struct MyApp: App {
    @State private var initError: Error?
    let modelContainer: ModelContainer?

    init() {
        do {
            self.modelContainer = try AFCONDataManager.makeSharedContainer()
        } catch {
            print("❌ Initialization error: \(error)")
            self.modelContainer = nil
            self.initError = error
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container = modelContainer {
                ContentView()
                    .modelContainer(container)
            } else {
                ErrorView(error: initError)
            }
        }
    }
}

struct ErrorView: View {
    let error: Error?

    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text("Failed to initialize app")
            if let error = error {
                Text(error.localizedDescription)
                    .font(.caption)
            }
            Button("Retry") {
                // Attempt to reinitialize
            }
        }
    }
}
```

---

## Proto Conversion Errors

### Symptom

```
Type mismatch when converting proto to SwiftData model
```

### Cause

Proto fields have changed or are nil.

### Solution

1. **Regenerate proto files** after server changes:
   ```bash
   ./generate-protos-v2.sh
   ```

2. **Handle optional fields**:
   ```swift
   // Use default values for nil fields
   let homeGoals = Int(proto.goals.home ?? 0)
   let awayGoals = Int(proto.goals.away ?? 0)
   ```

3. **Check proto version matches server**:
   ```bash
   # Compare proto file with server
   diff Protos/afcon.proto /path/to/server/Protos/afcon.proto
   ```

---

## Performance Issues / Slow Loading

### Symptom

App is slow to load data even with caching.

### Causes & Solutions

1. **Too many fixtures in database**:
   ```swift
   // Limit query results
   let descriptor = FetchDescriptor<FixtureModel>(
       predicate: #Predicate { $0.date > Date() },  // Only future matches
       sortBy: [SortDescriptor(\FixtureModel.date)]
   )
   descriptor.fetchLimit = 50  // Limit to 50 results
   ```

2. **No cache expiration**:
   ```swift
   // Set reasonable expiration
   dataManager.cacheExpirationInterval = 1800  // 30 minutes
   ```

3. **Fetch on main thread**:
   ```swift
   // Always use Task for async operations
   .task {
       fixtures = try await dataManager.getFixtures()
   }
   ```

---

## Common Build Errors

### "Cannot find type 'Afcon_Fixture' in scope"

**Solution**: Generate proto files:
```bash
./generate-protos-v2.sh
```

### "Argument type 'ServerRequest<T>' does not conform to expected type"

**Solution**: Update to grpc-swift 2.x (see SWIFT6_MIGRATION_GUIDE.md)

### "Module 'SwiftData' not found"

**Solution**: Set deployment target to macOS 15.0+ or iOS 18.0+:
```swift
// In Package.swift
platforms: [
    .macOS(.v15),
    .iOS(.v18)
]
```

---

## Debug Logging

Enable detailed logging to diagnose issues:

```swift
// Add to AFCONDataManager init
print("📦 SwiftData models registered:")
print("  - LeagueModel")
print("  - TeamModel")
print("  - FixtureModel")
print("  - StandingsModel")

print("🌐 gRPC Service configured:")
print("  - Host: \(service.host)")
print("  - Port: \(service.port)")

print("💾 Storage location:")
print("  - \(modelContainer.configurations.first?.url?.path ?? "in-memory")")
```

---

## Still Having Issues?

1. **Check logs** in Console.app (filter by your app name)
2. **Clean and rebuild** (⌘⇧K then ⌘B)
3. **Reset simulator** or reinstall app on device
4. **Verify server is running** and accessible
5. **Check network permissions** in Info.plist

For more help, see:
- `SWIFTDATA_CACHING_GUIDE.md` - Complete usage guide
- `Examples/DataManagerUsage.swift` - Working examples
- Server logs at `/tmp/afcon-server.log`
