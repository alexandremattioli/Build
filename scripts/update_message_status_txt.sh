#!/bin/bash
################################################################################
# Script: update_message_status_txt.sh
# Purpose: Update message_status.txt with current messaging status
# Usage: ./update_message_status_txt.sh
#
# Output Format:
#   Line 1: Build1 messages: N  Last message: YYYY-MM-DD HH:MM
#   Line 2: Build2 messages: N  Last message: YYYY-MM-DD HH:MM
#   Line 3: Last message from: X to Y (subject)
#   Line 4: Waiting on: status
#   Line 5: Total messages: N  Unread: build1=X build2=Y build3=Z build4=W
#   Line 6: (blank)
#   Line 7+: Full last message body (all lines)
#
# Exit Codes:
#   0 - Success
#   2 - Error
#
# Dependencies: jq, git
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

# Pull latest
git pull origin main --quiet 2>/dev/null || true

MESSAGES_FILE="coordination/messages.json"
STATUS_FILE="message_status.txt"

# Get total message count
TOTAL=$(jq '.messages | length' "$MESSAGES_FILE")

# Count messages by sender
BUILD1_COUNT=$(jq '[.messages[] | select(.from == "build1")] | length' "$MESSAGES_FILE")
BUILD2_COUNT=$(jq '[.messages[] | select(.from == "build2")] | length' "$MESSAGES_FILE")
BUILD3_COUNT=$(jq '[.messages[] | select(.from == "build3")] | length' "$MESSAGES_FILE")
BUILD4_COUNT=$(jq '[.messages[] | select(.from == "build4")] | length' "$MESSAGES_FILE")

# Get last message time for each sender
BUILD1_LAST_TIME=$(jq -r '[.messages[] | select(.from == "build1")] | sort_by(.timestamp) | last // {} | .timestamp // "Never"' "$MESSAGES_FILE")
BUILD2_LAST_TIME=$(jq -r '[.messages[] | select(.from == "build2")] | sort_by(.timestamp) | last // {} | .timestamp // "Never"' "$MESSAGES_FILE")

# Format timestamps
format_time() {
    local ts="$1"
    if [ "$ts" = "Never" ] || [ "$ts" = "null" ]; then
        echo "Never"
    else
        # Convert ISO 8601 to YYYY-MM-DD HH:MM
        date -d "$ts" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "$ts"
    fi
}

BUILD1_LAST_FORMATTED=$(format_time "$BUILD1_LAST_TIME")
BUILD2_LAST_FORMATTED=$(format_time "$BUILD2_LAST_TIME")

# Pending acknowledgments
ACK_PENDING=$(jq '[.messages[] | select(.ack_required == true and (.ack_status == "pending" or .ack_status == null))] | length' "$MESSAGES_FILE")

# Get overall last message details
LAST_MSG=$(jq -c '.messages | sort_by(.timestamp) | last' "$MESSAGES_FILE")
LAST_FROM=$(echo "$LAST_MSG" | jq -r '.from')
LAST_TO=$(echo "$LAST_MSG" | jq -r '.to')
LAST_SUBJECT=$(echo "$LAST_MSG" | jq -r '.subject')
LAST_BODY=$(echo "$LAST_MSG" | jq -r '.body')

# Count unread messages for each server
BUILD1_UNREAD=$(jq '[.messages[] | select((.to == "build1" or .to == "all") and .read == false)] | length' "$MESSAGES_FILE")
BUILD2_UNREAD=$(jq '[.messages[] | select((.to == "build2" or .to == "all") and .read == false)] | length' "$MESSAGES_FILE")
BUILD3_UNREAD=$(jq '[.messages[] | select((.to == "build3" or .to == "all") and .read == false)] | length' "$MESSAGES_FILE")
BUILD4_UNREAD=$(jq '[.messages[] | select((.to == "build4" or .to == "all") and .read == false)] | length' "$MESSAGES_FILE")

# Determine "Waiting on" status
WAITING_ON="None"

# Check if any server has unread messages
if [ "$BUILD1_UNREAD" -gt 0 ]; then
    WAITING_ON="Build1 ($BUILD1_UNREAD unread)"
elif [ "$BUILD2_UNREAD" -gt 0 ]; then
    WAITING_ON="Build2 ($BUILD2_UNREAD unread)"
elif [ "$BUILD3_UNREAD" -gt 0 ]; then
    WAITING_ON="Build3 ($BUILD3_UNREAD unread)"
elif [ "$BUILD4_UNREAD" -gt 0 ]; then
    WAITING_ON="Build4 ($BUILD4_UNREAD unread)"
fi

# Generate the status file
cat > "$STATUS_FILE" << EOF
Build1 messages: $BUILD1_COUNT  Last message: $BUILD1_LAST_FORMATTED
Build2 messages: $BUILD2_COUNT  Last message: $BUILD2_LAST_FORMATTED
Last message from: $LAST_FROM to $LAST_TO ($LAST_SUBJECT)
Waiting on: $WAITING_ON
Ack pending: $ACK_PENDING
Total messages: $TOTAL  Unread: build1=$BUILD1_UNREAD build2=$BUILD2_UNREAD build3=$BUILD3_UNREAD build4=$BUILD4_UNREAD

Latest message body:
$LAST_BODY
EOF

# Commit and push
git add "$STATUS_FILE"
git commit -m "Update message status: $(date -u +%H:%M:%S)" >/dev/null 2>&1 || true

# Retry git push with exponential backoff
push_with_retry() {
  local max_attempts=5
  local attempt=1
  local delay=1
  while [ $attempt -le $max_attempts ]; do
    if git push origin main --quiet 2>/dev/null; then
      return 0
    fi
    echo "Push failed (attempt $attempt/$max_attempts), retrying in ${delay}s..." >&2
    sleep $delay
    git pull origin main --rebase --autostash --quiet 2>/dev/null
    delay=$((delay * 2))
    attempt=$((attempt + 1))
  done
  echo "ERROR: git push failed after $max_attempts attempts" >&2
  return 1
}

push_with_retry || true

echo "Message status updated: $TOTAL total, $BUILD1_UNREAD+$BUILD2_UNREAD+$BUILD3_UNREAD+$BUILD4_UNREAD unread"

exit 0
