#!/bin/bash
################################################################################
# Script: update_message_stats.sh
# Purpose: Update message statistics from messages.json
# Usage: ./update_message_stats.sh
#
# Exit Codes:
#   0 - Success
#   2 - Git operation failed
#
# Dependencies: jq, git
################################################################################

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

# Get last message from each server (preserve JSON nulls/strings)
BUILD1_LAST_TIME=$(jq -c '[.messages[] | select(.from == "build1")] | sort_by(.timestamp) | last // {} | .timestamp // null' "$MESSAGES_FILE")
BUILD1_LAST_SUBJECT=$(jq -c '[.messages[] | select(.from == "build1")] | sort_by(.timestamp) | last // {} | .subject // null' "$MESSAGES_FILE")

BUILD2_LAST_TIME=$(jq -c '[.messages[] | select(.from == "build2")] | sort_by(.timestamp) | last // {} | .timestamp // null' "$MESSAGES_FILE")
BUILD2_LAST_SUBJECT=$(jq -c '[.messages[] | select(.from == "build2")] | sort_by(.timestamp) | last // {} | .subject // null' "$MESSAGES_FILE")

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
LAST_BROADCAST_TIME=$(jq -c '[.messages[] | select(.to == "all")] | sort_by(.timestamp) | last // {} | .timestamp // null' "$MESSAGES_FILE")

# Get overall last message info
LAST_FROM=$(jq -c '.messages | sort_by(.timestamp) | last // {} | .from // null' "$MESSAGES_FILE")
LAST_TO=$(jq -c '.messages | sort_by(.timestamp) | last // {} | .to // null' "$MESSAGES_FILE")
LAST_TIME=$(jq -c '.messages | sort_by(.timestamp) | last // {} | .timestamp // null' "$MESSAGES_FILE")
LAST_TYPE=$(jq -c '.messages | sort_by(.timestamp) | last // {} | .type // null' "$MESSAGES_FILE")

# Current timestamp
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Build stats JSON
jq -n \
  --arg now "$NOW" \
  --argjson total "$TOTAL" \
  --argjson build1_total "$BUILD1_TOTAL" \
  --argjson build2_total "$BUILD2_TOTAL" \
  --argjson build1_last_time "$BUILD1_LAST_TIME" \
  --argjson build1_last_subject "$BUILD1_LAST_SUBJECT" \
  --argjson build2_last_time "$BUILD2_LAST_TIME" \
  --argjson build2_last_subject "$BUILD2_LAST_SUBJECT" \
  --argjson build1_info "$BUILD1_INFO" \
  --argjson build1_warning "$BUILD1_WARNING" \
  --argjson build1_error "$BUILD1_ERROR" \
  --argjson build1_request "$BUILD1_REQUEST" \
  --argjson build2_info "$BUILD2_INFO" \
  --argjson build2_warning "$BUILD2_WARNING" \
  --argjson build2_error "$BUILD2_ERROR" \
  --argjson build2_request "$BUILD2_REQUEST" \
  --argjson build1_received "$BUILD1_RECEIVED" \
  --argjson build2_received "$BUILD2_RECEIVED" \
  --argjson all_broadcast "$ALL_BROADCAST" \
  --argjson build1_unread "$BUILD1_UNREAD" \
  --argjson build2_unread "$BUILD2_UNREAD" \
  --argjson last_broadcast_time "$LAST_BROADCAST_TIME" \
  --argjson last_from "$LAST_FROM" \
  --argjson last_to "$LAST_TO" \
  --argjson last_time "$LAST_TIME" \
  --argjson last_type "$LAST_TYPE" \
  '{
    last_updated: $now,
    total_messages: $total,
    by_server: {
      build1: {
        total_sent: $build1_total,
        last_message_time: $build1_last_time,
        last_message_subject: $build1_last_subject,
        messages_by_type: {
          info: $build1_info,
          warning: $build1_warning,
          error: $build1_error,
          request: $build1_request
        }
      },
      build2: {
        total_sent: $build2_total,
        last_message_time: $build2_last_time,
        last_message_subject: $build2_last_subject,
        messages_by_type: {
          info: $build2_info,
          warning: $build2_warning,
          error: $build2_error,
          request: $build2_request
        }
      }
    },
    by_recipient: {
      build1: {
        total_received: $build1_received,
        unread_count: $build1_unread
      },
      build2: {
        total_received: $build2_received,
        unread_count: $build2_unread
      },
      all: {
        total_broadcast: $all_broadcast,
        last_broadcast_time: $last_broadcast_time
      }
    },
    recent_activity: {
      last_message_from: $last_from,
      last_message_to: $last_to,
      last_message_time: $last_time,
      last_message_type: $last_type
    }
  }' > "$STATS_FILE.tmp"

# Move atomically
mv "$STATS_FILE.tmp" "$STATS_FILE"

# Validate JSON
if [ -f scripts/validate_json.sh ]; then
    bash scripts/validate_json.sh "$STATS_FILE" || exit 2
fi

# Commit and push
git add "$STATS_FILE"
git commit -m "Update message statistics: $(date -u +%H:%M:%S)" >/dev/null 2>&1 || true

# Retry git push with exponential backoff
push_with_retry() {
  local max_attempts=5
  local attempt=1
  local delay=1
  while [ $attempt -le $max_attempts ]; do
    if git push origin main 2>/dev/null; then
      return 0
    fi
    echo "Push failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
    sleep $delay
    git pull origin main --rebase --autostash
    delay=$((delay * 2))
    attempt=$((attempt + 1))
  done
  [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "update_message_stats" "git push failed after $max_attempts attempts"
  echo "ERROR: git push failed after $max_attempts attempts" >&2
  return 1
}

push_with_retry || true

echo "Message statistics updated: $TOTAL total messages"
