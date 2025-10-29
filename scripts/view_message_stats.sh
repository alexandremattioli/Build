
#!/bin/bash
################################################################################
# Script: view_message_stats.sh
# Purpose: View current message statistics for all servers
# Usage: ./view_message_stats.sh
#
# Exit Codes:
#   0 - Success
#   1 - Validation error
#   2 - Git operation failed
#
# Dependencies: jq, git
################################################################################

REPO_DIR="/root/Build"

if [ ! -d "$REPO_DIR" ]; then
    echo "Repository not found at $REPO_DIR"
    exit 1
fi

cd "$REPO_DIR"

git pull origin main --quiet 2>/dev/null || true

STATS_FILE="coordination/message_stats.json"

if [ ! -f "$STATS_FILE" ]; then
    echo "Statistics file not found. Run update_message_stats.sh first."
    exit 1
fi

echo "=== Message Statistics ==="
echo ""
TMP_FILE=$(mktemp)
jq -r '.last_updated' "$STATS_FILE" > "$TMP_FILE"
echo "Last Updated: $(cat "$TMP_FILE")"
jq -r '.total_messages' "$STATS_FILE" > "$TMP_FILE"
echo "Total Messages: $(cat "$TMP_FILE")"
rm "$TMP_FILE"
echo ""

echo "--- Build1 (Codex) ---"
echo "  Total Sent: $(jq -r '.by_server.build1.total_sent' "$STATS_FILE")"
echo "  Last Message: $(jq -r '.by_server.build1.last_message_time // "None"' "$STATS_FILE")"
echo "  Last Subject: $(jq -r '.by_server.build1.last_message_subject // "None"' "$STATS_FILE")"
echo "  Info: $(jq -r '.by_server.build1.messages_by_type.info' "$STATS_FILE") | Warning: $(jq -r '.by_server.build1.messages_by_type.warning' "$STATS_FILE") | Error: $(jq -r '.by_server.build1.messages_by_type.error' "$STATS_FILE") | Request: $(jq -r '.by_server.build1.messages_by_type.request' "$STATS_FILE")"
echo "  Unread Messages: $(jq -r '.by_recipient.build1.unread_count' "$STATS_FILE")"
echo ""

echo "--- Build2 (Copilot) ---"
echo "  Total Sent: $(jq -r '.by_server.build2.total_sent' "$STATS_FILE")"
echo "  Last Message: $(jq -r '.by_server.build2.last_message_time // "None"' "$STATS_FILE")"
echo "  Last Subject: $(jq -r '.by_server.build2.last_message_subject // "None"' "$STATS_FILE")"
echo "  Info: $(jq -r '.by_server.build2.messages_by_type.info' "$STATS_FILE") | Warning: $(jq -r '.by_server.build2.messages_by_type.warning' "$STATS_FILE") | Error: $(jq -r '.by_server.build2.messages_by_type.error' "$STATS_FILE") | Request: $(jq -r '.by_server.build2.messages_by_type.request' "$STATS_FILE")"
echo "  Unread Messages: $(jq -r '.by_recipient.build2.unread_count' "$STATS_FILE")"
echo ""

echo "--- Broadcast Messages ---"
echo "  Total: $(jq -r '.by_recipient.all.total_broadcast' "$STATS_FILE")"
echo "  Last Broadcast: $(jq -r '.by_recipient.all.last_broadcast_time // "None"' "$STATS_FILE")"
echo ""

echo "--- Recent Activity ---"
echo "  Last Message From: $(jq -r '.recent_activity.last_message_from // "None"' "$STATS_FILE")"
echo "  Last Message To: $(jq -r '.recent_activity.last_message_to // "None"' "$STATS_FILE")"
echo "  Last Message Time: $(jq -r '.recent_activity.last_message_time // "None"' "$STATS_FILE")"
echo "  Last Message Type: $(jq -r '.recent_activity.last_message_type // "None"' "$STATS_FILE")"
echo ""
