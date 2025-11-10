# How to Start the AFCON Middleware Server

## Quick Start (Recommended)

Open Terminal and run:

```bash
cd /Users/audrey/Documents/Projects/Cheulah/CAN2025/APIPlayground.nosync

# 1. Make sure Redis is running
brew services start redis

# Or if you don't have Redis installed:
brew install redis
brew services start redis

# 2. Verify Redis is running
redis-cli ping
# Should output: PONG

# 3. Build the server
swift build

# 4. Run the server
swift run Run
```

The server should start and show:
```
🚀 Starting AFCON Middleware
📡 HTTP Server will run on port 8080
📡 gRPC Server will run on port 50051
✅ gRPC Server started on port 50051
[ NOTICE ] Server starting on http://0.0.0.0:8080
```

## Testing the Server

Once running, test in another Terminal window:

```bash
# Test HTTP endpoint
curl http://localhost:8080/health

# Should return: {"status":"ok"}

# Test with teams endpoint
curl http://localhost:8080/api/v1/league/6/season/2025/teams
```

## Troubleshooting

### Error: "Connection refused" or ports already in use

```bash
# Check if something is using port 8080
lsof -i :8080

# Check if something is using port 50051
lsof -i :50051

# Kill any process using these ports
kill -9 <PID>
```

### Error: Redis connection failed

```bash
# Check Redis status
brew services list | grep redis

# Restart Redis
brew services restart redis

# Check Redis logs
brew services info redis
```

### Error: Build failures

```bash
# Clean build
swift package clean

# Reset package
swift package reset

# Rebuild
swift build
```

### Error: Missing .env file

```bash
# Copy example
cp .env.example .env

# Edit if needed
nano .env
```

## Running in Background

To run the server in the background:

```bash
# Using nohup
nohup swift run Run > server.log 2>&1 &

# Check logs
tail -f server.log

# Find process ID
ps aux | grep "swift run"

# Stop the server
kill <PID>
```

## For DesignPlayground App

Once the server is running:

1. Open `DesignPlayground.xcodeproj` in Xcode
2. Build and run the app (Cmd+R)
3. The app will connect to `localhost:50051` for gRPC

If you get "GRPC.GRPCConnectionPoolError error 1":
- Make sure the server is actually running (check Terminal output)
- Make sure port 50051 is accessible: `lsof -i :50051`
- Try restarting the server

## Quick Debug Commands

```bash
# Is server running?
lsof -i :8080 -i :50051

# Test HTTP health
curl http://localhost:8080/health

# Check server logs (if running in background)
tail -f server.log

# Check Redis
redis-cli ping

# See what's in Redis cache
redis-cli
> KEYS *
> exit
```

## Common Issues

### 1. "Command 'swift' not found"
Install Xcode Command Line Tools:
```bash
xcode-select --install
```

### 2. "Module 'Vapor' not found"
Dependencies not fetched:
```bash
swift package resolve
swift build
```

### 3. "Address already in use"
Another server is running:
```bash
# Kill process on port 8080
lsof -ti:8080 | xargs kill -9

# Kill process on port 50051
lsof -ti:50051 | xargs kill -9
```

### 4. App shows "Connection error"
- Server isn't running
- Wrong host/port in app (should be localhost:50051)
- Firewall blocking connection

## Success Checklist

✅ Redis is running (`redis-cli ping` returns PONG)
✅ Server built successfully (`swift build` completes)
✅ Server is running (Terminal shows "Server starting on http://0.0.0.0:8080")
✅ HTTP works (`curl http://localhost:8080/health` returns {"status":"ok"})
✅ Port 50051 is listening (`lsof -i :50051` shows swift process)
✅ DesignPlayground app connects without errors
