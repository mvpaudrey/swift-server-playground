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

### Example 1: Disable Auto-Initialization
```bash
# Don't auto-initialize - use manual sync script instead
export AUTO_INIT=false
./start-server.sh
```

### Example 2: Initialize Only AFCON
```bash
# Initialize only AFCON 2025 (this is the default)
export INIT_LEAGUES="6:2025:AFCON 2025"
./start-server.sh
```

### Example 3: Initialize Multiple Leagues
```bash
# Initialize three leagues on startup
export INIT_LEAGUES="6:2025:AFCON 2025,39:2024:Premier League,2:2025:Champions League"
./start-server.sh
```

### Example 4: Custom Ports and Database
```bash
# Configure all server settings
export PORT=3000
export GRPC_PORT=9090
export DATABASE_URL="postgresql://user:pass@remote-host:5432/afcon_db"
export API_FOOTBALL_KEY="your_key_here"
export INIT_LEAGUES="6:2025:AFCON 2025"
./start-server.sh
```

### Example 5: Production Deployment
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

### Issue: Server uses wrong league
**Solution**: Set `INIT_LEAGUES` environment variable before starting the server.

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
