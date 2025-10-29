#!/bin/bash
# update_message_stats.sh - Update message statistics from messages.json
# This should be called after sending a message

set -euo pipefail

REPO_DIR="/root/Build"
cd "$REPO_DIR"

# Pull latest
git pull origin main --quiet 2>/dev/null || true

MESSAGES_FILE="coordination/messages.json"
STATS_FILE="coordination/message_stats.json"

# Count total messages
TOTAL=$(jq '.messages | length' "$MESSAGES_FILE")

# Count by sender
BUILD1_TOTAL=$(jq '[.messages[] | select(.from == "build1")] | length' "$MESSAGES_FILE")
BUILD2_TOTAL=$(jq '[.messages[] | select(.from == "build2")] | length' "$MESSAGES_FILE")

# Get last message from each server
BUILD1_LAST_TIME=$(jq -r '[.messages[] | select(.from == "build1")] | sort_by(.timestamp) | last | .timestamp // null' "$MESSAGES_FILE")
BUILD1_LAST_SUBJECT=$(jq -r '[.messages[] | select(.from == "build1")] | sort_by(.timestamp) | last | .subject // null' "$MESSAGES_FILE")

BUILD2_LAST_TIME=$(jq -r '[.messages[] | select(.from == "build2")] | sort_by(.timestamp) | last | .timestamp // null' "$MESSAGES_FILE")
BUILD2_LAST_SUBJECT=$(jq -r '[.messages[] | select(.from == "build2")] | sort_by(.timestamp) | last | .subject // null' "$MESSAGES_FILE")

# Count by type for each server
BUILD1_INFO=$(jq '[.messages[] | select(.from == "build1" and .type == "info")] | length' "$MESSAGES_FILE")
BUILD1_WARNING=$(jq '[.messages[] | select(.from == "build1" and .type == "warning")] | length' "$MESSAGES_FILE")
BUILD1_ERROR=$(jq '[.messages[] | select(.from == "build1" and .type == "error")] | length' "$MESSAGES_FILE")
BUILD1_REQUEST=$(jq '[.messages[] | select(.from == "build1" and .type == "request")] | length' "$MESSAGES_FILE")

BUILD2_INFO=$(jq '[.messages[] | select(.from == "build2" and .type == "info")] | length' "$MESSAGES_FILE")
BUILD2_WARNING=$(jq '[.messages[] | select(.from == "build2" and .type == "warning")] | length' "$MESSAGES_FILE")
BUILD2_ERROR=$(jq '[.messages[] | select(.from == "build2" and .type == "error")] | length' "$MESSAGES_FILE")
BUILD2_REQUEST=$(jq '[.messages[] | select(.from == "build2" and .type == "request")] | length' "$MESSAGES_FILE")

# Count by recipient
BUILD1_RECEIVED=$(jq '[.messages[] | select(.to == "build1")] | length' "$MESSAGES_FILE")
BUILD2_RECEIVED=$(jq '[.messages[] | select(.to == "build2")] | length' "$MESSAGES_FILE")
ALL_BROADCAST=$(jq '[.messages[] | select(.to == "all")] | length' "$MESSAGES_FILE")

# Count unread
BUILD1_UNREAD=$(jq '[.messages[] | select((.to == "build1" or .to == "all") and .read == false)] | length' "$MESSAGES_FILE")
BUILD2_UNREAD=$(jq '[.messages[] | select((.to == "build2" or .to == "all") and .read == false)] | length' "$MESSAGES_FILE")

# Get last broadcast time
LAST_BROADCAST_TIME=$(jq -r '[.messages[] | select(.to == "all")] | sort_by(.timestamp) | last | .timestamp // null' "$MESSAGES_FILE")

# Get overall last message info
LAST_MSG=$(jq -r '.messages | sort_by(.timestamp) | last' "$MESSAGES_FILE")
LAST_FROM=$(echo "$LAST_MSG" | jq -r '.from // null')
LAST_TO=$(echo "$LAST_MSG" | jq -r '.to // null')
LAST_TIME=$(echo "$LAST_MSG" | jq -r '.timestamp // null')
LAST_TYPE=$(echo "$LAST_MSG" | jq -r '.type // null')

# Current timestamp
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Build stats JSON
cat > "$STATS_FILE" <<EOF
{
  "last_updated": "$NOW",
  "total_messages": $TOTAL,
  "by_server": {
    "build1": {
      "total_sent": $BUILD1_TOTAL,
      "last_message_time": $BUILD1_LAST_TIME,
      "last_message_subject": $BUILD1_LAST_SUBJECT,
      "messages_by_type": {
        "info": $BUILD1_INFO,
        "warning": $BUILD1_WARNING,
        "error": $BUILD1_ERROR,
        "request": $BUILD1_REQUEST
      }
    },
    "build2": {
      "total_sent": $BUILD2_TOTAL,
      "last_message_time": $BUILD2_LAST_TIME,
      "last_message_subject": $BUILD2_LAST_SUBJECT,
      "messages_by_type": {
        "info": $BUILD2_INFO,
        "warning": $BUILD2_WARNING,
        "error": $BUILD2_ERROR,
        "request": $BUILD2_REQUEST
      }
    }
  },
  "by_recipient": {
    "build1": {
      "total_received": $BUILD1_RECEIVED,
      "unread_count": $BUILD1_UNREAD
    },
    "build2": {
      "total_received": $BUILD2_RECEIVED,
      "unread_count": $BUILD2_UNREAD
    },
    "all": {
      "total_broadcast": $ALL_BROADCAST,
      "last_broadcast_time": $LAST_BROADCAST_TIME
    }
  },
  "recent_activity": {
    "last_message_from": $LAST_FROM,
    "last_message_to": $LAST_TO,
    "last_message_time": $LAST_TIME,
    "last_message_type": $LAST_TYPE
  }
}
EOF

# Commit and push
git add "$STATS_FILE"
git commit -m "Update message statistics: $(date -u +%H:%M:%S)" >/dev/null 2>&1 || true
git push origin main >/dev/null 2>&1 || true

echo "Message statistics updated: $TOTAL total messages"
