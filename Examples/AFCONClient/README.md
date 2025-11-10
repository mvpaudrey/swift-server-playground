# AFCON gRPC Client Example

This is an example Swift client that demonstrates how to connect to the AFCON Middleware gRPC server and consume football data.

## Prerequisites

1. The AFCON Middleware server must be running:
   ```bash
   cd ../..
   swift run
   ```

2. Protocol buffers must be generated:
   ```bash
   cd ../..
   ./generate-protos.sh
   ```

3. Copy the generated proto files to this client project:
   ```bash
   cp ../../Sources/App/gRPC/Generated/*.swift Sources/Generated/
   ```

## Building

```bash
swift build
```

## Running

```bash
swift run AFCONClient
```

## What This Example Demonstrates

1. **Connecting to gRPC Server**
   - Creating a gRPC channel
   - Connecting to localhost:50051

2. **GetLeague RPC**
   - Fetching league information
   - Displaying season details

3. **GetTeams RPC**
   - Listing all teams in the competition
   - Showing team and venue information

4. **GetFixtures RPC**
   - Retrieving match fixtures
   - Displaying match details and scores

5. **StreamLiveMatches RPC (Server Streaming)**
   - Real-time streaming of live match updates
   - Handling different event types (goals, status changes, etc.)
   - Demonstrates long-running gRPC streams

## Sample Output

```
🏆 AFCON 2025 gRPC Client
Connecting to localhost:50051...
✅ Connected to gRPC server

📋 Fetching League Information...
────────────────────────────────
League: Africa Cup of Nations
Type: Cup
Country: World

Seasons:
  2015: 2015-01-17 to 2015-02-08
  2017: 2017-01-14 to 2017-02-05
  2019: 2017-03-22 to 2019-07-19
  2021: 2022-01-09 to 2022-02-06
  2023: 2024-01-13 to 2024-02-11
→ 2025: 2025-12-21 to 2025-12-31

⚽ Fetching Teams...
────────────────────────────────
Total Teams: 24

[SEN] Senegal
  Founded: 1960
  Venue: Stade Me Abdoulaye Wade, Diamniadio
  Capacity: 50000

[NIG] Nigeria
  Founded: 1945
  Venue: Godswill Akpabio International Stadium, Uyo
  Capacity: 31500

... and 22 more teams

📅 Fetching Fixtures...
────────────────────────────────
Total Fixtures: 48

[FT] Senegal 2 - 1 Nigeria
  Venue: Stade Me Abdoulaye Wade, Diamniadio
  Status: Match Finished

... and 47 more fixtures

🔴 Streaming Live Matches...
────────────────────────────────
Waiting for live match updates...

⚽ [14:23:15] Match Started: Morocco vs Egypt
⏱️  [14:23:25] Time: 5'
⏱️  [14:23:35] Time: 10'
🎯 [14:23:42] GOAL! Morocco 1 - 0 Egypt
📊 [14:38:15] Status: Halftime
⏱️  [14:53:25] Time: 50'
🎯 [14:58:32] GOAL! Morocco 2 - 0 Egypt
🏁 [15:08:15] Match Finished: Morocco 2 - 0 Egypt

✅ All examples completed successfully!
```

## Customization

You can modify `main.swift` to:

- Change the league ID or season
- Filter fixtures by date or team
- Get standings information
- Fetch player statistics
- Implement custom event handlers for live matches

## Integration

To integrate this into your own Swift application:

1. Add the gRPC dependencies to your `Package.swift`
2. Copy the generated protocol buffer files
3. Use the example code as a reference for making RPC calls
4. Build your UI on top of the gRPC client

## Error Handling

The client includes basic error handling. In production, you should:

- Handle connection failures
- Implement retry logic
- Add timeouts
- Handle stream interruptions
- Validate responses

## Performance Tips

- Reuse the gRPC channel across multiple requests
- Use connection pooling for high-load scenarios
- Implement client-side caching for non-live data
- Handle backpressure for streaming responses

## More Examples

For more advanced examples, see the main documentation:
- [Main README](../../README.md)
- [API Documentation](../../Protos/afcon.proto)
