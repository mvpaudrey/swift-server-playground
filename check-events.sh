#!/bin/bash

# Quick check for notification events

LOG_FILE="/tmp/afcon-monitor.log"
LAST_CHECK_FILE="/tmp/afcon-last-check.txt"

# Get last check time
if [ -f "$LAST_CHECK_FILE" ]; then
  LAST_CHECK=$(cat "$LAST_CHECK_FILE")
else
  LAST_CHECK=0
fi

# Get current line count
CURRENT_LINES=$(wc -l < "$LOG_FILE" 2>/dev/null || echo "0")

# Update last check
echo "$CURRENT_LINES" > "$LAST_CHECK_FILE"

# Show new lines since last check
if [ "$CURRENT_LINES" -gt "$LAST_CHECK" ]; then
  LINES_TO_SHOW=$((CURRENT_LINES - LAST_CHECK))
  echo "📋 New events (last $LINES_TO_SHOW lines):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  tail -n "$LINES_TO_SHOW" "$LOG_FILE"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  echo "No new events since last check ($(date -u '+%H:%M:%S UTC'))"
fi

echo ""
echo "⏱️  Time until Algeria vs Nigeria: $(python3 -c "from datetime import datetime; import sys; kickoff = datetime(2026, 1, 10, 16, 0); now = datetime.utcnow(); diff = kickoff - now; hours = int(diff.total_seconds() // 3600); minutes = int((diff.total_seconds() % 3600) // 60); print(f'{hours}h {minutes}m')" 2>/dev/null || echo "calculating...")"
