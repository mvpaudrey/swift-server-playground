#!/bin/bash

# Monitor AFCON notifications in real-time
# Tracks match events and notification delivery

echo "🏆 AFCON Notification Monitor"
echo "=============================="
echo ""
echo "Current time: $(date -u '+%H:%M:%S UTC')"
echo ""
echo "Upcoming matches:"
echo "  1. Algeria vs Nigeria - 16:00 UTC"
echo "  2. Egypt vs Ivory Coast - 19:00 UTC"
echo ""
echo "Monitoring for:"
echo "  ⚽ Goal events"
echo "  🟥 Red card events"
echo "  📱 APNs notifications"
echo "  📊 Match status changes"
echo ""
echo "Press Ctrl+C to stop"
echo "=============================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Track last seen timestamp to avoid duplicates
LAST_TIMESTAMP=""

# Monitor logs in real-time
aws logs tail /ecs/staging-afcon-server \
  --region eu-north-1 \
  --follow \
  --since 5m \
  --format short | while read -r line; do

  # Extract timestamp and message
  TIMESTAMP=$(echo "$line" | cut -d' ' -f1-2)

  # Skip if we've already seen this timestamp
  if [ "$TIMESTAMP" == "$LAST_TIMESTAMP" ]; then
    continue
  fi
  LAST_TIMESTAMP="$TIMESTAMP"

  # Match started/live
  if echo "$line" | grep -q "🆕 New live match\|match_started\|Match started"; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🎬 MATCH STARTED${NC}"
    echo "$line"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
  fi

  # Goal events
  if echo "$line" | grep -q "⚽\|GOAL\|goal"; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}⚽ GOAL EVENT DETECTED${NC}"
    echo "$line"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
  fi

  # Notification sending
  if echo "$line" | grep -q "Sending goal notification\|sendGoalNotification"; then
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📤 SENDING NOTIFICATION${NC}"
    echo "$line"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
  fi

  # Subscriber count
  if echo "$line" | grep -q "notification subscribers"; then
    echo -e "${BLUE}📱 SUBSCRIBERS: $line${NC}"
    echo ""
  fi

  # APNs delivery
  if echo "$line" | grep -q "APNs sent\|📱 APNs"; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ APNs NOTIFICATION SENT${NC}"
    echo "$line"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
  fi

  # APNs errors
  if echo "$line" | grep -q "Failed to send APNs\|APNs.*error"; then
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}❌ APNs DELIVERY FAILED${NC}"
    echo "$line"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
  fi

  # Red card events
  if echo "$line" | grep -q "🟥\|RED CARD\|red card"; then
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}🟥 RED CARD EVENT${NC}"
    echo "$line"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
  fi

  # Live Activity updates
  if echo "$line" | grep -q "Live Activity update\|🔔 Live Activity"; then
    echo -e "${PURPLE}🔔 Live Activity: $line${NC}"
    echo ""
  fi

  # Polling updates (show less frequently)
  if echo "$line" | grep -q "Polled league.*live fixture"; then
    # Extract the live fixture count
    if echo "$line" | grep -q "Polled league 6: [1-9]"; then
      echo -e "${CYAN}📊 $line${NC}"
      echo ""
    fi
  fi

  # Match finished
  if echo "$line" | grep -q "🏁 Match finished\|match_finished"; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🏁 MATCH FINISHED${NC}"
    echo "$line"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
  fi
done
