#!/bin/bash
# read_messages.sh - Read unread messages for a server
# Usage: ./read_messages.sh <server_id>

set -euo pipefail

SERVER_ID="$1"
REPO_DIR="/root/Build"

cd "$REPO_DIR"

# Pull latest
git pull origin main --quiet

# Get unread messages
MESSAGES=$(jq --arg server "$SERVER_ID" '[.messages[] | select((.to == $server or .to == "all") and .read == false)]' coordination/messages.json)

COUNT=$(echo "$MESSAGES" | jq 'length')

if [ "$COUNT" -eq 0 ]; then
    echo "No unread messages for $SERVER_ID"
    exit 0
fi

echo "=== Unread Messages for $SERVER_ID ($COUNT) ==="
echo ""

echo "$MESSAGES" | jq -r '.[] | "[\(.type | ascii_upcase)] \(.from) -> \(.to)\nSubject: \(.subject)\nTime: \(.timestamp)\n\(.body)\n---"'
