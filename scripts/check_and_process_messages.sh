#!/bin/bash
# check_and_process_messages.sh - Check for new messages and process them
# Usage: ./check_and_process_messages.sh <server_id>

set -euo pipefail

SERVER_ID="${1:-build2}"
REPO_DIR="/root/Build"

cd "$REPO_DIR"

# Pull latest (quietly)
git pull origin main --quiet 2>/dev/null || {
    echo "Warning: Git pull failed" >&2
    exit 1
}

# Get unread messages for this server
MESSAGES=$(jq --arg server "$SERVER_ID" '[.messages[] | select((.to == $server or .to == "all") and .read == false)]' coordination/messages.json)
COUNT=$(echo "$MESSAGES" | jq 'length')

if [ "$COUNT" -eq 0 ]; then
    exit 0  # No messages, silent exit
fi

# Log messages to file
LOG_FILE="/var/log/build-messages-$SERVER_ID.log"
echo "=== New Messages $(date -u +%Y-%m-%dT%H:%M:%SZ) ===" >> "$LOG_FILE"
echo "$MESSAGES" | jq -r '.[] | "[\(.type | ascii_upcase)] \(.from) -> \(.to)\nID: \(.id)\nSubject: \(.subject)\nTime: \(.timestamp)\n\(.body)\n---"' >> "$LOG_FILE"

# Display on console
echo "📬 $COUNT new message(s) for $SERVER_ID"
echo "$MESSAGES" | jq -r '.[] | "  [\(.type)] \(.from): \(.subject)"'

# Auto-process based on message type
echo "$MESSAGES" | jq -c '.[]' | while read -r msg; do
    MSG_ID=$(echo "$msg" | jq -r '.id')
    MSG_TYPE=$(echo "$msg" | jq -r '.type')
    MSG_FROM=$(echo "$msg" | jq -r '.from')
    MSG_SUBJECT=$(echo "$msg" | jq -r '.subject')
    MSG_BODY=$(echo "$msg" | jq -r '.body')
    
    # Process based on type
    case "$MSG_TYPE" in
        error)
            echo "⚠️  ERROR from $MSG_FROM: $MSG_SUBJECT" >&2
            # Could trigger alert here
            ;;
        warning)
            echo "⚠️  WARNING from $MSG_FROM: $MSG_SUBJECT"
            ;;
        request)
            echo "📋 REQUEST from $MSG_FROM: $MSG_SUBJECT"
            # Could trigger automated action here
            ;;
        info)
            echo "ℹ️  INFO from $MSG_FROM: $MSG_SUBJECT"
            ;;
    esac
done

echo ""
echo "Full messages saved to: $LOG_FILE"
echo "To mark messages as read, run: ./mark_messages_read.sh $SERVER_ID"
