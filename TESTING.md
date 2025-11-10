# Testing Guide for AFCON Middleware

This guide covers different approaches to test the AFCON Middleware gRPC and HTTP APIs.

## Prerequisites

Make sure the server is running:
```bash
swift run Run
```

The server will start on:
- **HTTP**: `http://localhost:8080`
- **gRPC**: `localhost:50051`

---

## 1. Testing with the Swift gRPC Client

### Run the Test Client

We've created a comprehensive test client that tests all gRPC endpoints:

```bash
swift run GRPCClient
```

### What It Tests

1. **GetLeague** - Fetches AFCON 2025 league information
2. **GetTeams** - Fetches all 24 teams
3. **GetFixtures** - Fetches all fixtures
4. **GetTeamDetails** - Fetches specific team details
5. **StreamLiveMatches** - Tests server-side streaming (10 second timeout)

### Sample Output

```
🧪 AFCON Middleware gRPC Test Client
=====================================
📡 Connected to gRPC server at localhost:50051

Test 1: GetLeague (AFCON 2025)
--------------------------------
✅ League: Africa Cup of Nations
   Country: World
   Type: Cup
   Seasons: 1
   Current Season: 2025

Test 2: GetTeams (AFCON 2025)
--------------------------------
✅ Found 24 teams:
   1. Senegal (Senegal)
   2. Nigeria (Nigeria)
   3. Tunisia (Tunisia)
   4. Morocco (Morocco)
   5. Egypt (Egypt)
   ... and 19 more

✅ All tests completed!
```

---

## 2. Testing HTTP REST API (for debugging)

### Using curl

#### Health Check
```bash
curl http://localhost:8080/health
```

#### Get League Info
```bash
curl "http://localhost:8080/api/v1/league/6/season/2025" | jq .
```

#### Get Teams
```bash
curl "http://localhost:8080/api/v1/league/6/season/2025/teams" | jq .
```

#### Get Fixtures
```bash
# All fixtures
curl "http://localhost:8080/api/v1/league/6/season/2025/fixtures" | jq .

# Fixtures for a specific date
curl "http://localhost:8080/api/v1/league/6/season/2025/fixtures?date=2025-01-15" | jq .

# Fixtures for a specific team
curl "http://localhost:8080/api/v1/league/6/season/2025/fixtures?team=1503" | jq .
```

#### Get Live Fixtures
```bash
curl "http://localhost:8080/api/v1/league/6/live" | jq .
```

#### Get Standings
```bash
curl "http://localhost:8080/api/v1/league/6/season/2025/standings" | jq .
```

#### Get Team Details
```bash
curl "http://localhost:8080/api/v1/team/1503" | jq .
```

#### Clear Cache
```bash
curl -X DELETE "http://localhost:8080/api/v1/cache/league/6/season/2025"
```

---

## 3. Testing with grpcurl (Command-line gRPC client)

### Install grpcurl
```bash
brew install grpcurl
```

### List Available Services
```bash
grpcurl -plaintext localhost:50051 list
```

### List Methods for AFCONService
```bash
grpcurl -plaintext localhost:50051 list afcon.AFCONService
```

### Call GetLeague
```bash
grpcurl -plaintext \
  -d '{"league_id": 6, "season": 2025}' \
  localhost:50051 \
  afcon.AFCONService/GetLeague
```

### Call GetTeams
```bash
grpcurl -plaintext \
  -d '{"league_id": 6, "season": 2025}' \
  localhost:50051 \
  afcon.AFCONService/GetTeams
```

### Call GetFixtures
```bash
grpcurl -plaintext \
  -d '{"league_id": 6, "season": 2025, "live": false}' \
  localhost:50051 \
  afcon.AFCONService/GetFixtures
```

### Call StreamLiveMatches (server streaming)
```bash
grpcurl -plaintext \
  -d '{"league_id": 6}' \
  localhost:50051 \
  afcon.AFCONService/StreamLiveMatches
```

---

## 4. Testing with BloomRPC (GUI client)

### Install BloomRPC
Download from: https://github.com/bloomrpc/bloomrpc/releases

### Setup
1. Open BloomRPC
2. Click "Import Paths" → Add `Protos` directory
3. Click "Import Protos" → Select `afcon.proto`
4. Set server address: `localhost:50051`
5. Ensure "TLS" is **disabled**

### Make Requests
1. Select a method from the left panel
2. Fill in the request JSON
3. Click "Play" button
4. View response on the right

Example request for GetLeague:
```json
{
  "league_id": 6,
  "season": 2025
}
```

---

## 5. Creating Your Own Client

### Swift Client

```swift
import GRPC
import NIO
import App

let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
defer { try? group.syncShutdownGracefully() }

let channel = try GRPCChannelPool.with(
    target: .host("localhost", port: 50051),
    transportSecurity: .plaintext,
    eventLoopGroup: group
)
defer { try? channel.close().wait() }

let client = Afcon_AFCONServiceAsyncClient(channel: channel)

// Get teams
var request = Afcon_TeamsRequest()
request.leagueID = 6
request.season = 2025

let response = try await client.getTeams(request)
print("Teams: \\(response.teams.count)")
```

### Python Client

```python
import grpc
import afcon_pb2
import afcon_pb2_grpc

# Connect to server
channel = grpc.insecure_channel('localhost:50051')
stub = afcon_pb2_grpc.AFCONServiceStub(channel)

# Get teams
request = afcon_pb2.TeamsRequest(league_id=6, season=2025)
response = stub.GetTeams(request)

print(f"Teams: {len(response.teams)}")
for team in response.teams:
    print(f"- {team.team.name}")
```

### Go Client

```go
package main

import (
    "context"
    "log"

    "google.golang.org/grpc"
    pb "path/to/generated/afcon"
)

func main() {
    conn, err := grpc.Dial("localhost:50051", grpc.WithInsecure())
    if err != nil {
        log.Fatal(err)
    }
    defer conn.Close()

    client := pb.NewAFCONServiceClient(conn)

    req := &pb.TeamsRequest{
        LeagueId: 6,
        Season: 2025,
    }

    resp, err := client.GetTeams(context.Background(), req)
    if err != nil {
        log.Fatal(err)
    }

    log.Printf("Teams: %d", len(resp.Teams))
}
```

---

## 6. Performance Testing

### Load Testing with ghz

Install ghz (gRPC benchmarking tool):
```bash
brew install ghz
```

Test GetTeams endpoint:
```bash
ghz --insecure \
  --proto Protos/afcon.proto \
  --call afcon.AFCONService/GetTeams \
  -d '{"league_id": 6, "season": 2025}' \
  -n 100 \
  -c 10 \
  localhost:50051
```

This will make 100 requests with 10 concurrent connections.

---

## 7. Monitoring Server Logs

Watch server logs in real-time:
```bash
# Server logs show:
# - HTTP requests with request IDs
# - gRPC method calls
# - API-Football API calls
# - Cache hits/misses
# - Response times
```

Example server output:
```
[ INFO ] gRPC: GetLeague - id=6, season=2025
[ INFO ] API Football Request: https://v3.football.api-sports.io/leagues?id=6&season=2025
[ INFO ] API Football Response: 1 results
```

---

## Test Data

### AFCON 2025 Details
- **League ID**: 6
- **Season**: 2025
- **Teams**: 24 teams
- **Fixtures**: 36 fixtures
- **Tournament**: Morocco (host country)

### Sample Team IDs
- Senegal: 1503
- Nigeria: 1501
- Morocco: 1513
- Egypt: 1533
- Algeria: 1569

---

## Troubleshooting

### Server not responding
```bash
# Check if server is running
lsof -i :50051  # gRPC
lsof -i :8080   # HTTP
```

### gRPC errors
- Ensure server is running with `swift run Run`
- Verify you're using `plaintext` (not TLS)
- Check firewall settings

### API rate limits
- API-Football has rate limits
- Middleware implements caching to reduce API calls
- Clear cache if needed: `DELETE /api/v1/cache/league/:id/season/:season`

---

## Next Steps

1. **Build a mobile app** - Use the Swift client code in iOS/macOS apps
2. **Build a web app** - Use gRPC-Web or the HTTP REST API
3. **Add authentication** - Implement API keys or JWT tokens
4. **Deploy to production** - Use Docker and deploy to cloud platforms
5. **Add more features** - Player stats, live commentary, predictions

---

## Summary

✅ **Swift gRPC Client** - Comprehensive automated testing
✅ **HTTP REST API** - Debug endpoints with curl
✅ **grpcurl** - Command-line gRPC testing
✅ **BloomRPC** - GUI for interactive testing
✅ **Custom Clients** - Examples in Swift, Python, Go
✅ **Performance Testing** - Load testing with ghz

The middleware is production-ready and can be integrated with any gRPC-compatible client!
