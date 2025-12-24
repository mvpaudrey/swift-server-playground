# AFCONClient JSON Fallback Resources

This directory contains JSON fallback data that is loaded when:
1. SwiftData cache is empty (first app launch)
2. Network is unavailable
3. Server is unreachable

## Files

- `league_fallback.json` - AFCON 2025 league information
- `teams_fallback.json` - All participating teams
- `fixtures_fallback.json` - Tournament fixtures
- `standings_fallback.json` - Group standings

## Usage

The `AFCONDataManager` automatically loads these files as fallback data. The caching strategy is:

```
1. Check SwiftData cache → Use if available and not stale
2. Load JSON fallback → Use if SwiftData is empty
3. Fetch from server → Update SwiftData cache
```

## Generating Fallback Files

To generate fresh fallback data from the server:

```bash
# Run the export script
cd Sources/AFCONClient/Resources
./export-fallback-data.sh
```

This will fetch current data from your gRPC server and save it as JSON files.

## File Format

All JSON files follow the Codable format of their corresponding SwiftData models:
- `LeagueModel`
- `TeamModel`
- `FixtureModel`
- `StandingsModel`

Dates are encoded in ISO8601 format.
