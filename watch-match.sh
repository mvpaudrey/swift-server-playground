#!/bin/bash

# Periodic check script that increases frequency near match time

echo "🎯 Starting match watch scheduler"
echo "Will check more frequently as match approaches"
echo ""

MATCH_TIME=1768060800  # Algeria vs Nigeria at 16:00 UTC

while true; do
  CURRENT_TIME=$(date +%s)
  TIME_UNTIL_MATCH=$((MATCH_TIME - CURRENT_TIME))

  # Calculate hours and minutes
  HOURS=$((TIME_UNTIL_MATCH / 3600))
  MINUTES=$(((TIME_UNTIL_MATCH % 3600) / 60))

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "⏰ $(date -u '+%H:%M:%S UTC') - Time until kickoff: ${HOURS}h ${MINUTES}m"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # Run the event checker
  ./check-events.sh

  # Check match status via gRPC
  echo ""
  echo "📊 Checking match status via API..."
  grpcurl -plaintext \
    -proto Protos/afcon.proto \
    -d '{"league_id": 6, "season": 2025}' \
    staging-grpc-nlb-823dd7fe6a5be8b9.elb.eu-north-1.amazonaws.com:50051 \
    afcon.AFCONService/GetTodayUpcoming 2>/dev/null | \
    jq -r '.fixtures[0] | "Status: \(.status.short) - \(.teams.home.name) vs \(.teams.away.name)"' || echo "Could not fetch match status"

  echo ""

  # Determine sleep interval based on time until match
  if [ $TIME_UNTIL_MATCH -le 0 ]; then
    # Match is live or finished - check every 30 seconds
    SLEEP_TIME=30
    echo "⚽ MATCH IS LIVE - Checking every 30 seconds"
  elif [ $TIME_UNTIL_MATCH -le 600 ]; then
    # Less than 10 minutes - check every minute
    SLEEP_TIME=60
    echo "🔔 Match starting soon - Checking every 1 minute"
  elif [ $TIME_UNTIL_MATCH -le 1800 ]; then
    # Less than 30 minutes - check every 2 minutes
    SLEEP_TIME=120
    echo "⏰ Match starting in <30min - Checking every 2 minutes"
  elif [ $TIME_UNTIL_MATCH -le 3600 ]; then
    # Less than 1 hour - check every 5 minutes
    SLEEP_TIME=300
    echo "⏱️  Match starting in <1hr - Checking every 5 minutes"
  else
    # More than 1 hour - check every 10 minutes
    SLEEP_TIME=600
    echo "⏳ Checking every 10 minutes"
  fi

  echo "Next check in ${SLEEP_TIME}s..."
  echo ""
  sleep $SLEEP_TIME
done
