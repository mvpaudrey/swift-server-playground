# Database Initialization Scripts

## sync-fixtures.swift

A well-documented Swift script to initialize your AFCON database with fixtures for any league and season.

### Prerequisites

1. **Install grpcurl** (if not already installed):
   ```bash
   brew install grpcurl
   ```

2. **Start the server**:
   ```bash
   ./start-server.sh
   ```

   The server must be running on `localhost:50051` before running the sync script.

### Usage

#### Quick Start (from project root):

```bash
./sync-fixtures.sh <leagueID> <season> [competition]
```

#### Examples:

**UEFA Champions League (2024/2025 season):**
```bash
./sync-fixtures.sh 2 2025
```

**Premier League (2024/2025 season):**
```bash
./sync-fixtures.sh 39 2024
```

**AFCON with custom name:**
```bash
./sync-fixtures.sh 6 2024 "Africa Cup of Nations"
```

**Show help:**
```bash
./sync-fixtures.sh --help
```

### Common League IDs

| League ID | League Name | Typical Season |
|-----------|-------------|----------------|
| **2** | UEFA Champions League | 2025 |
| **6** | AFCON | 2024 |
| **39** | Premier League | 2024 |
| **140** | La Liga | 2024 |
| **78** | Bundesliga | 2024 |
| **135** | Serie A | 2024 |
| **61** | Ligue 1 | 2024 |

### What It Does

1. **Connects** to your gRPC server on `localhost:50051`
2. **Fetches** all fixtures from the external API for the specified league/season
3. **Stores** them in your PostgreSQL database
4. **Reports** success or failure with detailed messages

### Output Example

```
🔄 Syncing fixtures for UEFA Champions League (League ID: 2, Season: 2025)...
📡 Connecting to gRPC server at localhost:50051...

ℹ️  Auto-detected competition: UEFA Champions League

📤 Sending sync request...
   League: UEFA Champions League
   Season: 2025
   ID: 2

✅ Sync completed successfully!

Response:
{
  "success": true,
  "message": "Successfully synced 125 fixtures",
  "fixturesCount": 125
}

🎉 Database successfully initialized with UEFA Champions League fixtures!
   You can now use the API to fetch fixtures for this league.
```

### Running Directly (Swift)

If you prefer to run the Swift script directly:

```bash
cd /Users/audrey/Documents/Projects/Cheulah/CAN2025/APIPlayground.nosync
swift Scripts/sync-fixtures.swift 2 2025
```

### Troubleshooting

#### Error: "grpcurl is not installed"
**Solution:** Install grpcurl with Homebrew:
```bash
brew install grpcurl
```

#### Error: "Server is not running"
**Solution:** Start the server in another terminal:
```bash
cd /Users/audrey/Documents/Projects/Cheulah/CAN2025/APIPlayground.nosync
./start-server.sh
```

#### Error: "Sync failed: connection refused"
**Solution:**
1. Check if the server is running: `lsof -ti:50051`
2. Verify database connection in server logs
3. Ensure PostgreSQL is running: `docker ps` (if using Docker)

#### Error: "Invalid league ID"
**Solution:** Check that you're using a numeric league ID. Common IDs are listed above.

### Advanced Usage

#### Multiple Leagues

To initialize multiple leagues, run the script multiple times:

```bash
./sync-fixtures.sh 2 2025   # Champions League
./sync-fixtures.sh 39 2024  # Premier League
./sync-fixtures.sh 140 2024 # La Liga
```

#### Custom Competition Names

Override the auto-detected competition name:

```bash
./sync-fixtures.sh 2 2025 "My Custom Tournament Name"
```

### Script Location

- **Main Script**: `Scripts/sync-fixtures.swift`
- **Wrapper Script**: `sync-fixtures.sh` (project root)

### Integration with Development Workflow

**Typical workflow:**

1. Start database: `docker compose up -d postgres`
2. Start server: `./start-server.sh`
3. Initialize data: `./sync-fixtures.sh 2 2025`
4. Test iOS app with real data

### Notes

- The script uses `grpcurl` to communicate with the gRPC server
- It automatically detects competition names for common league IDs
- Competition names can be overridden with the third argument
- The script validates inputs and provides helpful error messages
- All output is color-coded for easy reading

### Files

- `Scripts/sync-fixtures.swift` - Main Swift script
- `sync-fixtures.sh` - Convenient wrapper script
- `Scripts/README.md` - This documentation

---

**Need help?** Run `./sync-fixtures.sh --help` for quick reference.
