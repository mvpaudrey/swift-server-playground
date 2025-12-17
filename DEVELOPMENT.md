# Local Development Guide

Guide for developing the AFCON Swift gRPC server locally using the hybrid Docker approach.

## Quick Start

```bash
# 1. Start databases in Docker
docker compose up -d postgres redis

# 2. Run server locally (once Swift version issues resolved)
./run-local.sh

# 3. Test endpoints
curl http://localhost:8080/health
```

---

## Architecture: Hybrid Approach

**What runs where:**
- ✅ **PostgreSQL** - Docker container (port 5432)
- ✅ **Redis** - Docker container (port 6379)
- ⚠️ **Swift Server** - Local process (ports 8080, 50051)

**Why this approach?**
- PostgreSQL and Redis are stable and containerized
- Swift server has version compatibility issues in Docker
- Easier debugging when server runs locally
- Faster development iteration

---

## Prerequisites

### Required Software
```bash
# Install Homebrew (macOS)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install swift         # Swift 5.9 or 6.x
brew install protobuf      # Protocol Buffers compiler
brew install docker        # Docker Desktop
brew install grpcurl       # gRPC testing tool (optional)

# Verify installations
swift --version
protoc --version
docker --version
```

### Swift Version Compatibility

**Current Issue:**
The project has Swift version compatibility challenges:
- Swift 6.x is installed locally
- grpc-swift 1.24 requires Swift tools 5.9
- grpc-swift 2.x requires API migration

**Solutions:**

**Option 1: Use swiftenv** (Recommended)
```bash
# Install swiftenv
brew install kylef/formulae/swiftenv

# Install Swift 5.9
swiftenv install 5.9.2

# Set as default for this project
cd /path/to/project
swiftenv local 5.9.2

# Verify
swift --version  # Should show 5.9.2
```

**Option 2: Deploy to AWS directly**
Skip local development and deploy directly to AWS ECS where the environment is controlled.

**Option 3: Migrate to grpc-swift 2.x**
Update code to use the new API (requires code changes).

---

## Environment Setup

### 1. Clone and Configure

```bash
# Navigate to project
cd /path/to/swift-server-playground

# Copy environment template
cp .env.example .env

# Edit .env with your credentials
nano .env
```

### 2. Required Environment Variables

Edit `.env`:
```bash
# API-Football Configuration
API_FOOTBALL_KEY=your_api_key_here

# Database Configuration (Docker containers)
DATABASE_URL=postgres://postgres:postgres@localhost:5432/afcon?sslmode=disable
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=afcon

# Redis Configuration (Docker container)
REDIS_URL=redis://localhost:6379

# Server Configuration
PORT=8080
GRPC_PORT=50051
ENVIRONMENT=development
LOG_LEVEL=debug

# League Initialization
INIT_LEAGUES=6:2025:AFCON 2025
AUTO_INIT=true

# Push Notifications (Optional - leave empty for now)
APNS_KEY_ID=
APNS_TEAM_ID=
APNS_TOPIC=
APNS_ENVIRONMENT=sandbox
APNS_KEY_PATH=/app/secrets/apns-key.p8
FCM_SERVER_KEY=
```

---

## Development Workflow

### Start Development Environment

#### Step 1: Start Docker Services

```bash
# Start PostgreSQL and Redis
docker compose up -d postgres redis

# Verify they're running
docker compose ps

# Should show:
# afcon-postgres - Up (healthy)
# afcon-redis    - Up (healthy)

# View logs if needed
docker compose logs -f postgres redis
```

#### Step 2: Run Server Locally

```bash
# Option A: Use the helper script
./run-local.sh

# Option B: Run directly
swift run Run serve --hostname 0.0.0.0 --port 8080

# Option C: Build and run separately
swift build
.build/debug/Run serve --hostname 0.0.0.0 --port 8080
```

**Expected output:**
```
Starting AFCON server...
Database: postgres://postgres:postgres@localhost:5432/afcon
Redis: redis://localhost:6379
HTTP Port: 8080
gRPC Port: 50051

[ INFO ] Server starting on http://0.0.0.0:8080
[ INFO ] gRPC server starting on 0.0.0.0:50051
```

---

## Testing

### HTTP Endpoints

```bash
# Health check
curl http://localhost:8080/health

# Get league info
curl http://localhost:8080/api/v1/league/6/2025

# Get fixtures
curl http://localhost:8080/api/v1/fixtures?league=6&season=2025
```

### gRPC Endpoints

```bash
# List services
grpcurl -plaintext localhost:50051 list

# Get league
grpcurl -plaintext \
  -d '{"league_id": 6, "season": 2025}' \
  localhost:50051 \
  afcon.AFCONService/GetLeague

# Stream live matches
grpcurl -plaintext \
  -d '{"league_id": 6, "season": 2025}' \
  localhost:50051 \
  afcon.AFCONService/StreamLiveMatches
```

### Database Access

```bash
# Access PostgreSQL
docker exec -it afcon-postgres psql -U postgres -d afcon

# Run queries
\dt                        # List tables
SELECT * FROM fixtures;    # View fixtures
\q                         # Exit
```

### Redis Access

```bash
# Access Redis
docker exec -it afcon-redis redis-cli

# Check cached data
KEYS *                     # List all keys
GET league:6:2025          # Get specific cache
TTL league:6:2025          # Check expiration
FLUSHALL                   # Clear all cache (careful!)
exit
```

---

## Code Changes and Hot Reload

### Rebuild After Changes

```bash
# Kill running server (Ctrl+C)

# Rebuild
swift build

# Restart
./run-local.sh
```

### Watch for Changes (Optional)

Install a file watcher:
```bash
brew install fswatch

# Create watch script
cat > watch-and-rebuild.sh << 'EOF'
#!/bin/bash
fswatch -o Sources | while read change; do
  echo "Change detected, rebuilding..."
  swift build && echo "Rebuild complete!"
done
EOF

chmod +x watch-and-rebuild.sh
./watch-and-rebuild.sh
```

---

## Database Management

### Reset Database

```bash
# Stop and remove containers (data is lost)
docker compose down -v

# Start fresh
docker compose up -d postgres redis

# Server will auto-create tables on next start
./run-local.sh
```

### Run Migrations Manually

```bash
# Run migrations
swift run Run migrate --env development

# Revert last migration
swift run Run migrate --revert --env development
```

### Backup Database

```bash
# Export database
docker exec afcon-postgres pg_dump -U postgres afcon > backup.sql

# Restore database
docker exec -i afcon-postgres psql -U postgres -d afcon < backup.sql
```

---

## Protocol Buffers Development

### Update Proto Files

```bash
# Edit proto file
nano Protos/afcon.proto

# Regenerate Swift code
./update-protos.sh

# Or manually
protoc --proto_path="Protos" \
  --swift_out="Sources/AFCONClient/Generated" \
  --grpc-swift_out="Sources/AFCONClient/Generated" \
  --swift_opt=Visibility=Public \
  --grpc-swift_opt=Visibility=Public \
  "Protos/afcon.proto"

# Rebuild
swift build
```

---

## Troubleshooting

### Port Already in Use

```bash
# Find process using port 8080
lsof -ti:8080

# Kill it
lsof -ti:8080 | xargs kill -9

# Or kill by name
pkill -f "swift run"
```

### Database Connection Failed

```bash
# Check if PostgreSQL is running
docker compose ps postgres

# Check PostgreSQL logs
docker compose logs postgres

# Test connection
docker exec afcon-postgres pg_isready -U postgres

# Restart PostgreSQL
docker compose restart postgres
```

### Redis Connection Failed

```bash
# Check if Redis is running
docker compose ps redis

# Test connection
docker exec afcon-redis redis-cli ping
# Should return: PONG

# Restart Redis
docker compose restart redis
```

### Swift Build Errors

```bash
# Clean build artifacts
swift package clean

# Reset package dependencies
swift package reset

# Update dependencies
swift package update

# Rebuild
swift build
```

### gRPC Service Not Found

```bash
# Verify proto files are up to date
ls -la Sources/AFCONClient/Generated/
ls -la Sources/App/gRPC/Generated/

# Regenerate if needed
./update-protos.sh

# Check imports in Swift files
grep -r "import.*GRPC" Sources/
```

---

## Development Tips

### Enable Verbose Logging

```bash
# Run with verbose logging
LOG_LEVEL=trace swift run Run serve --hostname 0.0.0.0 --port 8080
```

### Use Xcode for Debugging

```bash
# Generate Xcode project
swift package generate-xcodeproj

# Open in Xcode
open swift-server-playground.xcodeproj
```

### Access pgAdmin (Optional)

```bash
# Start with pgAdmin
docker compose --profile tools up -d

# Access at http://localhost:5050
# Email: admin@afcon.local
# Password: admin
```

---

## Performance Monitoring

### Monitor Resource Usage

```bash
# Docker stats
docker stats afcon-postgres afcon-redis

# Server memory usage
ps aux | grep swift

# Database connections
docker exec afcon-postgres psql -U postgres -d afcon \
  -c "SELECT count(*) FROM pg_stat_activity;"
```

### Monitor API Calls

```bash
# Watch server logs
tail -f logs/server.log

# Monitor HTTP requests
tcpdump -i lo0 -A 'tcp port 8080'

# Monitor gRPC requests
grpcurl -plaintext localhost:50051 list
```

---

## Best Practices

### 1. Always Use Docker for Databases
- Don't install PostgreSQL/Redis locally
- Keep data isolated in containers
- Easy to reset and test

### 2. Keep Environment Variables Secure
- Never commit `.env` file
- Use `.env.example` as template
- Rotate API keys regularly

### 3. Test Before Deploying
- Run full test suite
- Verify database migrations
- Test all gRPC endpoints

### 4. Version Control
```bash
# Add only source files
git add Sources/ Protos/ Package.swift

# Never commit
git add .env          # ❌ Never
git add .build/       # ❌ Never
git add secrets/      # ❌ Never
```

---

## Next Steps

Once your local environment is working:

1. ✅ Test all endpoints locally
2. ✅ Add new features and test
3. ✅ Commit changes to git
4. ✅ Deploy to AWS (see `AWS_QUICKSTART.md`)
5. ✅ Set up CI/CD (see `.github/workflows/deploy.yml`)

---

**Need help?** Check `DEPLOYMENT.md` for production deployment or `AWS_QUICKSTART.md` for AWS setup.
