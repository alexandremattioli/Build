#!/bin/bash
################################################################################
# Script: read_messages.sh
# Purpose: Read unread messages for a server
# Usage: ./read_messages.sh <server_id>
#
# Arguments:
#   server_id - build1 or build2
#
# Exit Codes:
#   0 - Success
#   1 - Validation error
#
# Dependencies: jq, git
################################################################################

set -euo pipefail

SERVER_ID="$1"

# Input validation
validate_server_id() {
    local server="$1"
    if [[ ! "$server" =~ ^(build1|build2)$ ]]; then
        echo "ERROR: Invalid server ID: $server" >&2
        exit 1
    fi
}

validate_server_id "$SERVER_ID"
REPO_DIR="/root/Build"

cd "$REPO_DIR"

# Pull latest
git pull origin main --quiet

# Get unread messages
MESSAGES=$(jq --arg server "$SERVER_ID" '
    [.messages[] | select((.to == $server or .to == "all") and .read == false)] |
    sort_by(
        if .type == "error" then 0
        elif .type == "warning" then 1
        elif .type == "request" then 2
        else 3
        end,
        .timestamp
    )
' coordination/messages.json)

COUNT=$(echo "$MESSAGES" | jq 'length')

if [ "$COUNT" -eq 0 ]; then
    echo "No unread messages for $SERVER_ID"
    exit 0
fi

echo "=== Unread Messages for $SERVER_ID ($COUNT) ==="
echo ""

echo "$MESSAGES" | jq -r '.[] | "[\(.type | ascii_upcase)] \(.from) -> \(.to)\nSubject: \(.subject)\nTime: \(.timestamp)\n\(.body)\n---"'
