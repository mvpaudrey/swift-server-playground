# Quick Start Guide - AFCON Middleware

Get up and running with the AFCON gRPC Middleware in 5 minutes!

## Step 1: Prerequisites Check

Make sure you have the following installed:

```bash
# Check Swift version (6.0+ required, 6.2 recommended)
swift --version

# Verify macOS version (15.0+ required)
sw_vers

# Check if tools are installed
which protoc
which protoc-gen-swift
which redis-server
```

**Minimum Requirements:**
- Swift 6.0+ (tested with Swift 6.2)
- macOS 15.0 (Sequoia) or iOS 18.0+
- grpc-swift 2.x (installed automatically via Package.swift)

If any are missing:

```bash
# Install Protocol Buffers
brew install protobuf swift-protobuf

# Install Redis
brew install redis

# Install gRPC Swift plugin
git clone https://github.com/grpc/grpc-swift.git
cd grpc-swift
make plugins
sudo cp .build/release/protoc-gen-grpc-swift /usr/local/bin/
cd ..
```

## Step 2: Setup the Project

```bash
# Run the automated setup
make setup
```

This will:
- ✅ Verify all dependencies
- ✅ Create environment file
- ✅ Generate protocol buffer code

Alternatively, do it manually:

```bash
# Copy environment file
cp .env.example .env

# Generate protocol buffers
./generate-protos.sh
```

## Step 3: Start Redis

```bash
# Start Redis in background
make redis

# Or manually:
redis-server --daemonize yes
```

## Step 4: Build and Run

```bash
# Build the project
make build

# Run the server
make run
```

You should see:

```
🚀 Starting AFCON Middleware
📡 HTTP Server will run on port 8080
📡 gRPC Server will run on port 50051
✅ gRPC Server started on port 50051
[ INFO ] Server starting on http://127.0.0.1:8080
```

## Step 5: Test It!

Open a new terminal and try these commands:

### Test HTTP Endpoints

```bash
# Health check
curl http://localhost:8080/health

# Get AFCON 2025 league info
curl http://localhost:8080/api/v1/league/6/season/2025 | jq .

# Get teams
curl http://localhost:8080/api/v1/league/6/season/2025/teams | jq .

# Get fixtures
curl http://localhost:8080/api/v1/league/6/season/2025/fixtures | jq .
```

### Or use Make shortcuts

```bash
# Check health
make health

# Get teams
make teams

# Get live matches
make live
```

## Step 6: Try the gRPC Client (Optional)

```bash
# Build the example client
make client

# Run it
make run-client
```

## Common Issues

### "protoc not found"
```bash
brew install protobuf
```

### "Redis connection failed"
```bash
# Start Redis
make redis

# Check if running
redis-cli ping
# Should return: PONG
```

### "API Football error"
Check your API key in `.env`:
```bash
cat .env
# Make sure API_FOOTBALL_KEY is set correctly
```

### Port already in use
```bash
# Change ports in .env
PORT=8081
GRPC_PORT=50052
```

## Quick Reference

### Useful Make Commands

```bash
make help          # Show all available commands
make build         # Build the project
make run           # Run the server
make test          # Run tests
make clean         # Clean build artifacts
make redis         # Start Redis
make stop-redis    # Stop Redis
make teams         # Quick test: get AFCON teams
make live          # Quick test: get live matches
make flush-cache   # Clear Redis cache
```

### Environment Variables

Edit `.env` to configure:

```bash
API_FOOTBALL_KEY=your_api_key_here
REDIS_URL=redis://localhost:6379
PORT=8080
GRPC_PORT=50051
```

### AFCON 2025 Details

- **League ID**: 6
- **Season**: 2025
- **Start**: December 21, 2025
- **End**: December 31, 2025
- **Teams**: 24

### API Endpoints

**HTTP (Debug)**:
- `GET /health` - Health check
- `GET /api/v1/league/:id/season/:season` - League info
- `GET /api/v1/league/:id/season/:season/teams` - Teams
- `GET /api/v1/league/:id/season/:season/fixtures` - Fixtures
- `GET /api/v1/league/:id/live` - Live matches
- `GET /api/v1/league/:id/season/:season/standings` - Standings

**gRPC**:
- `GetLeague()` - League information
- `GetTeams()` - Team list
- `GetFixtures()` - Match fixtures
- `StreamLiveMatches()` - Live match streaming
- `GetStandings()` - League standings
- `GetTeamDetails()` - Team details

## Next Steps

1. **Read the full README**: `README.md`
2. **Explore the API**: Try different endpoints
3. **Build a client**: Use the example in `Examples/AFCONClient/`
4. **Customize**: Modify the code for your needs

## Getting Help

- 📖 Full documentation: [README.md](README.md)
- 🔧 API Football docs: https://www.api-football.com/documentation-v3
- 📝 Protocol buffers: [Protos/afcon.proto](Protos/afcon.proto)

## Production Checklist

Before deploying to production:

- [ ] Set a strong API key
- [ ] Configure Redis with persistence
- [ ] Set up monitoring and logging
- [ ] Enable HTTPS/TLS for gRPC
- [ ] Configure rate limiting
- [ ] Set up error tracking
- [ ] Add authentication
- [ ] Configure firewall rules
- [ ] Set up backup for Redis
- [ ] Configure environment for production

---

**Happy Coding!** ⚽🏆
