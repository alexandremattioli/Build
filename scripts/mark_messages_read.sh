#!/bin/bash
# mark_messages_read.sh - Mark messages as read for a server
# Usage: ./mark_messages_read.sh <server_id> [message_id]

set -euo pipefail

SERVER_ID="${1:-build2}"
SPECIFIC_MSG_ID="${2:-}"
REPO_DIR="/root/Build"

cd "$REPO_DIR"

# Pull latest
git pull origin main --rebase --autostash >/dev/null 2>&1 || true

if [ -n "$SPECIFIC_MSG_ID" ]; then
    # Mark specific message as read
    jq --arg msg_id "$SPECIFIC_MSG_ID" \
       '(.messages[] | select(.id == $msg_id)).read = true' \
       coordination/messages.json > tmp.json
    mv tmp.json coordination/messages.json
    echo "Marked message $SPECIFIC_MSG_ID as read"
else
    # Mark all messages to this server as read
    jq --arg server "$SERVER_ID" \
       '(.messages[] | select((.to == $server or .to == "all") and .read == false)).read = true' \
       coordination/messages.json > tmp.json
    mv tmp.json coordination/messages.json
    echo "Marked all unread messages for $SERVER_ID as read"
fi

# Commit and push
git add coordination/messages.json
git commit -m "[$SERVER_ID] Marked messages as read" >/dev/null 2>&1
git push origin main >/dev/null 2>&1

echo "✓ Messages marked as read in GitHub"
