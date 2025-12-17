# Environment Variables Configuration

This document describes all environment variables that can be used to configure the AFCON Middleware server.

## Server Configuration

### HTTP_PORT
- **Description**: Port for the HTTP/REST API server
- **Default**: `8080`
- **Example**: `PORT=3000`

### GRPC_PORT
- **Description**: Port for the gRPC server
- **Default**: `50051`
- **Example**: `GRPC_PORT=9090`

### DATABASE_URL
- **Description**: PostgreSQL connection string
- **Default**: `postgresql://postgres:postgres@localhost:5432/afcon`
- **Example**: `DATABASE_URL=postgresql://user:password@host:5432/dbname`

### API_FOOTBALL_KEY
- **Description**: API key for API-Football.com
- **Required**: Yes (for production use)
- **Example**: `API_FOOTBALL_KEY=your_api_key_here`
- **Get your key at**: https://www.api-football.com/

## Database Auto-Initialization

The server can automatically initialize the database with fixture data on startup. This is controlled by the following environment variables:

### AUTO_INIT
- **Description**: Enable or disable automatic database initialization on startup
- **Default**: `true` (enabled)
- **Values**: `true` or `false`
- **Example**: `AUTO_INIT=false`

**Use Cases**:
- Set to `false` in production if you want to manually control when data is loaded
- Set to `false` if you're using the sync script to populate data
- Keep as `true` (default) for development convenience

### INIT_LEAGUES
- **Description**: Configure which leagues to auto-initialize on startup
- **Format**: Comma-separated list of `leagueID:season:name`
- **Default**: `6:2025:AFCON 2025` (only AFCON 2025)
- **Example**: `INIT_LEAGUES="6:2025:AFCON 2025,39:2024:Premier League,2:2025:Champions League"`

**⚠️ IMPORTANT**: When using `./start-server.sh`, you MUST set `INIT_LEAGUES` in the `.env` file. Shell-exported variables will be overridden because the script sources `.env`.

**Format Rules**:
- Each league definition has three parts separated by colons: `id:season:name`
- Multiple leagues are separated by commas
- League name can contain spaces
- Invalid definitions are logged and skipped

**Common League IDs**:
- `6` - AFCON (Africa Cup of Nations)
- `2` - UEFA Champions League
- `39` - Premier League
- `140` - La Liga
- `78` - Bundesliga
- `135` - Serie A
- `61` - Ligue 1

## Usage Examples

### Example 1: Using start-server.sh (Recommended for Development)

When using `./start-server.sh`, edit the `.env` file:

```bash
# Edit .env file and add/update:
# INIT_LEAGUES=39:2025:Premier League

./start-server.sh
```

Or use a text editor:
```bash
echo "INIT_LEAGUES=39:2025:Premier League" >> .env
./start-server.sh
```

### Example 2: Running Directly with swift run

When running `swift run Run` directly (without start-server.sh), shell exports work:

```bash
# Export works because you're not sourcing .env
export INIT_LEAGUES="6:2025:AFCON 2025,39:2025:Premier League"
swift run Run
```

### Example 3: Disable Auto-Initialization
```bash
# Edit .env file:
# AUTO_INIT=false

./start-server.sh
```

### Example 4: Initialize Multiple Leagues
```bash
# Edit .env file and set:
# INIT_LEAGUES=6:2025:AFCON 2025,39:2025:Premier League,2:2025:Champions League

./start-server.sh
```

### Example 6: Production Deployment (Direct Run)
```bash
# Production configuration - no auto-init, use remote database
export AUTO_INIT=false
export DATABASE_URL="postgresql://prod_user:secure_pass@db.example.com:5432/afcon_prod"
export API_FOOTBALL_KEY="production_api_key"
export PORT=80
export GRPC_PORT=443
swift run Run
```

## Docker Deployment

When using Docker, pass environment variables via `-e` flag or `.env` file:

### Using -e flags:
```bash
docker run -d \
  -e AUTO_INIT=false \
  -e DATABASE_URL="postgresql://user:pass@db-host:5432/afcon" \
  -e API_FOOTBALL_KEY="your_key" \
  -e INIT_LEAGUES="6:2025:AFCON 2025,39:2024:Premier League" \
  -p 8080:8080 \
  -p 50051:50051 \
  afcon-server
```

### Using docker-compose.yml:
```yaml
version: '3.8'
services:
  afcon-server:
    image: afcon-server
    environment:
      - AUTO_INIT=true
      - INIT_LEAGUES=6:2025:AFCON 2025,39:2024:Premier League
      - DATABASE_URL=postgresql://postgres:postgres@postgres:5432/afcon
      - API_FOOTBALL_KEY=${API_FOOTBALL_KEY}
      - PORT=8080
      - GRPC_PORT=50051
    ports:
      - "8080:8080"
      - "50051:50051"
    depends_on:
      - postgres

  postgres:
    image: postgres:16
    environment:
      - POSTGRES_DB=afcon
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## Verification

After starting the server, check the logs to verify your configuration:

```bash
./start-server.sh
```

You should see log messages like:
```
ℹ️  Using default leagues (set INIT_LEAGUES to customize)
✅ Configured league: AFCON 2025 (ID: 6, Season: 2025)
🔍 Checking fixtures database initialization...
✅ Database already initialized for AFCON 2025 (125 fixtures)
```

Or if you disabled auto-init:
```
ℹ️  Auto-initialization disabled via AUTO_INIT=false
```

## Troubleshooting

### Issue: INIT_LEAGUES environment variable is ignored

**Problem**: You set `INIT_LEAGUES="39:2025:Premier League"` in your shell, but the server still initializes with AFCON.

**Root Cause**: The `start-server.sh` script sources the `.env` file (line 29: `source .env`), which overwrites any environment variables you set in your shell before running the script.

**Solution**:
1. Add `INIT_LEAGUES` to your `.env` file:
   ```bash
   echo "INIT_LEAGUES=39:2025:Premier League" >> .env
   ```

2. Clear existing fixtures if you already ran with the wrong league:
   ```bash
   docker exec afcon-postgres psql -U postgres -d afcon -c 'DELETE FROM fixtures;'
   ```

3. Restart the server:
   ```bash
   ./start-server.sh
   ```

**Alternative**: Run the server directly without the script if you prefer shell exports:
```bash
export INIT_LEAGUES="39:2025:Premier League"
swift run Run
```

### Issue: Server uses wrong league (general)
**Solution**: Check if `INIT_LEAGUES` is set in your `.env` file when using `./start-server.sh`.

### Issue: Auto-initialization takes too long
**Solution**: Set `AUTO_INIT=false` and use the sync script instead:
```bash
export AUTO_INIT=false
./start-server.sh &
./sync-fixtures.sh 6 2025
```

### Issue: Invalid league definition error
**Problem**: `⚠️  Invalid league definition: 'xyz'. Expected format: 'id:season:name'`
**Solution**: Ensure your `INIT_LEAGUES` format is correct: `id:season:name`
- IDs and seasons must be numbers
- Use colons (`:`) to separate parts
- Use commas (`,`) to separate multiple leagues

### Issue: Database already initialized message but no fixtures
**Solution**: The database may have been initialized but fixtures were deleted. Clear the database and restart:
```bash
docker exec afcon-postgres psql -U postgres -d afcon -c 'DELETE FROM fixtures;'
./start-server.sh
```

## Best Practices

### Development
- **Use**: `AUTO_INIT=true` with `INIT_LEAGUES` set to your test data
- **Why**: Convenient automatic setup on every restart
- **Example**:
  ```bash
  export INIT_LEAGUES="6:2025:AFCON 2025"
  ./start-server.sh
  ```

### Production
- **Use**: `AUTO_INIT=false` and pre-populate data via sync script
- **Why**: More control over when expensive API calls happen
- **Example**:
  ```bash
  export AUTO_INIT=false
  export DATABASE_URL="postgresql://prod_user:secure_pass@db.example.com/afcon"
  swift run Run &

  # Later, populate data via sync script
  ./sync-fixtures.sh 6 2025
  ./sync-fixtures.sh 39 2024
  ```

### Testing
- **Use**: Empty database with specific test leagues
- **Example**:
  ```bash
  docker compose down -v  # Clear all data
  export INIT_LEAGUES="2:2025:Champions League"
  ./start-server.sh
  ```

## Related Documentation

- [Database Initialization Scripts](Scripts/README.md) - Manual sync script documentation
- [Testing Guide](TESTING.md) - How to test the API
- [Docker Setup](docker-compose.yml) - Container deployment

## Summary

| Variable | Default | Purpose |
|----------|---------|---------|
| `AUTO_INIT` | `true` | Enable/disable auto-initialization |
| `INIT_LEAGUES` | `6:2025:AFCON 2025` | Which leagues to initialize |
| `PORT` | `8080` | HTTP API port |
| `GRPC_PORT` | `50051` | gRPC server port |
| `DATABASE_URL` | `postgresql://...` | Database connection |
| `API_FOOTBALL_KEY` | (none) | API-Football.com key |
