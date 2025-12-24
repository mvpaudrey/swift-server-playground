#!/bin/bash

# Export Fallback Data from gRPC Server
# This script fetches current data from the AFCON gRPC server
# and saves it as JSON files for offline fallback

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SERVER_HOST="${AFCON_SERVER_HOST:-localhost}"
SERVER_PORT="${AFCON_SERVER_PORT:-50051}"
LEAGUE_ID="${AFCON_LEAGUE_ID:-6}"
SEASON="${AFCON_SEASON:-2025}"

echo "🏆 AFCON Fallback Data Exporter"
echo "================================"
echo "Server: $SERVER_HOST:$SERVER_PORT"
echo "League: $LEAGUE_ID, Season: $SEASON"
echo ""

# Check if grpcurl is installed
if ! command -v grpcurl &> /dev/null; then
    echo "❌ Error: grpcurl is not installed"
    echo ""
    echo "Install grpcurl:"
    echo "  macOS:  brew install grpcurl"
    echo "  Linux:  apt install grpcurl"
    echo ""
    exit 1
fi

echo "✅ grpcurl found"

# Check if server is running
echo "🔍 Checking server connection..."
if ! grpcurl -plaintext "$SERVER_HOST:$SERVER_PORT" list > /dev/null 2>&1; then
    echo "❌ Error: Cannot connect to gRPC server at $SERVER_HOST:$SERVER_PORT"
    echo ""
    echo "Make sure the server is running:"
    echo "  cd /path/to/swift-server-playground"
    echo "  swift run"
    echo ""
    exit 1
fi

echo "✅ Server is running"
echo ""

# Function to convert proto response to SwiftData model JSON
# This is a simplified version - you may need to adjust based on actual proto structure

# Export League
echo "📋 Exporting league data..."
LEAGUE_RESPONSE=$(grpcurl -plaintext -d "{\"leagueID\": $LEAGUE_ID, \"season\": $SEASON}" \
    "$SERVER_HOST:$SERVER_PORT" \
    afcon.AFCONService/GetLeague)

if [ -z "$LEAGUE_RESPONSE" ]; then
    echo "❌ Failed to fetch league data"
    exit 1
fi

# Convert to SwiftData model format
echo "$LEAGUE_RESPONSE" | jq '{
    id: .league.id,
    name: .league.name,
    type: .league.type,
    logoURL: .league.logo,
    countryName: .country.name,
    countryCode: .country.code,
    countryFlagURL: .country.flag,
    season: .seasons[0].year,
    lastUpdated: now | todate
}' > "$SCRIPT_DIR/league_fallback.json"

echo "✅ Saved league_fallback.json"

# Export Teams
echo "⚽ Exporting teams data..."
TEAMS_RESPONSE=$(grpcurl -plaintext -d "{\"leagueID\": $LEAGUE_ID, \"season\": $SEASON}" \
    "$SERVER_HOST:$SERVER_PORT" \
    afcon.AFCONService/GetTeams)

if [ -z "$TEAMS_RESPONSE" ]; then
    echo "❌ Failed to fetch teams data"
    exit 1
fi

echo "$TEAMS_RESPONSE" | jq '.teams | map({
    id: .team.id,
    name: .team.name,
    code: .team.code,
    country: .team.country,
    founded: .team.founded,
    logoURL: .team.logo,
    venueName: .venue.name,
    venueCity: .venue.city,
    venueCapacity: .venue.capacity,
    season: '"$SEASON"',
    lastUpdated: now | todate
})' > "$SCRIPT_DIR/teams_fallback.json"

TEAM_COUNT=$(jq 'length' "$SCRIPT_DIR/teams_fallback.json")
echo "✅ Saved teams_fallback.json ($TEAM_COUNT teams)"

# Export Fixtures
echo "📅 Exporting fixtures data..."
FIXTURES_RESPONSE=$(grpcurl -plaintext -d "{\"leagueID\": $LEAGUE_ID, \"season\": $SEASON}" \
    "$SERVER_HOST:$SERVER_PORT" \
    afcon.AFCONService/GetFixtures)

if [ -z "$FIXTURES_RESPONSE" ]; then
    echo "❌ Failed to fetch fixtures data"
    exit 1
fi

echo "$FIXTURES_RESPONSE" | jq '.fixtures | map({
    id: .fixture.id,
    referee: .fixture.referee,
    timezone: .fixture.timezone,
    date: (.fixture.timestamp | todate),
    timestamp: .fixture.timestamp,
    venueName: .fixture.venue.name,
    venueCity: .fixture.venue.city,
    homeTeamId: .teams.home.id,
    homeTeamName: .teams.home.name,
    homeTeamLogoURL: .teams.home.logo,
    awayTeamId: .teams.away.id,
    awayTeamName: .teams.away.name,
    awayTeamLogoURL: .teams.away.logo,
    homeGoals: .goals.home,
    awayGoals: .goals.away,
    statusLong: .status.long,
    statusShort: .status.short,
    statusElapsed: .status.elapsed,
    leagueId: .league.id,
    leagueName: .league.name,
    leagueSeason: .league.season,
    leagueRound: .league.round,
    lastUpdated: now | todate
})' > "$SCRIPT_DIR/fixtures_fallback.json"

FIXTURE_COUNT=$(jq 'length' "$SCRIPT_DIR/fixtures_fallback.json")
echo "✅ Saved fixtures_fallback.json ($FIXTURE_COUNT fixtures)"

# Export Standings
echo "📊 Exporting standings data..."
STANDINGS_RESPONSE=$(grpcurl -plaintext -d "{\"leagueID\": $LEAGUE_ID, \"season\": $SEASON}" \
    "$SERVER_HOST:$SERVER_PORT" \
    afcon.AFCONService/GetStandings)

if [ -z "$STANDINGS_RESPONSE" ]; then
    echo "❌ Failed to fetch standings data"
    exit 1
fi

echo "$STANDINGS_RESPONSE" | jq '[.standings[] | .teams[] | {
    id: "\(.team.id)_'"$LEAGUE_ID"'_'"$SEASON"'",
    leagueId: '"$LEAGUE_ID"',
    season: '"$SEASON"',
    groupName: "Group Stage",
    teamId: .team.id,
    teamName: .team.name,
    teamLogoURL: .team.logo,
    rank: .rank,
    points: .points,
    played: .all.played,
    win: .all.win,
    draw: .all.draw,
    lose: .all.lose,
    goalsFor: .all.goalsFor,
    goalsAgainst: .all.goalsAgainst,
    goalsDiff: .goalsDiff,
    form: .form,
    lastUpdated: now | todate
}]' > "$SCRIPT_DIR/standings_fallback.json"

STANDING_COUNT=$(jq 'length' "$SCRIPT_DIR/standings_fallback.json")
echo "✅ Saved standings_fallback.json ($STANDING_COUNT entries)"

echo ""
echo "✅ All fallback data exported successfully!"
echo ""
echo "Files created:"
echo "  - league_fallback.json"
echo "  - teams_fallback.json ($TEAM_COUNT teams)"
echo "  - fixtures_fallback.json ($FIXTURE_COUNT fixtures)"
echo "  - standings_fallback.json ($STANDING_COUNT entries)"
echo ""
echo "📝 Next steps:"
echo "  1. Add these files to your Xcode project"
echo "  2. Make sure they're added to your app target"
echo "  3. Rebuild your app"
echo ""
echo "🎉 Done!"
