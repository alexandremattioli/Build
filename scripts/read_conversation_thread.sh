#!/bin/bash
################################################################################
# Script: read_conversation_thread.sh
# Purpose: Read and display the entire conversation thread from messages.json
# Usage: ./read_conversation_thread.sh [server_id] [--format text|json] [--limit N]
#
# Arguments:
#   server_id - Optional: build1, build2, build3, build4, or "all" (default: all)
#   --format  - Output format: text (default) or json
#   --limit   - Limit to last N messages (default: all)
#   --unread-only - Show only unread messages
#
# Exit Codes:
#   0 - Success
#   2 - Error
#
# Dependencies: jq, git
################################################################################

set -euo pipefail

REPO_DIR="/root/Build"
SERVER_ID="all"
FORMAT="text"
LIMIT=0
UNREAD_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        --unread-only)
            UNREAD_ONLY=true
            shift
            ;;
        build1|build2|build3|build4|all)
            SERVER_ID="$1"
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

cd "$REPO_DIR"

# Pull latest
git pull origin main --quiet 2>/dev/null || true

MESSAGES_FILE="coordination/messages.json"

# Build jq filter based on options
JQ_FILTER=".messages[]"

if [ "$SERVER_ID" != "all" ]; then
    JQ_FILTER="$JQ_FILTER | select(.to == \"$SERVER_ID\" or .to == \"all\" or .from == \"$SERVER_ID\")"
fi

if [ "$UNREAD_ONLY" = "true" ]; then
    if [ "$SERVER_ID" = "all" ]; then
        JQ_FILTER="$JQ_FILTER | select(.read == false)"
    else
        JQ_FILTER="$JQ_FILTER | select((.to == \"$SERVER_ID\" or .to == \"all\") and .read == false)"
    fi
fi

# Get messages and sort by timestamp
MESSAGES=$(jq -c "[$JQ_FILTER] | sort_by(.timestamp)" "$MESSAGES_FILE")

# Apply limit if specified
if [ "$LIMIT" -gt 0 ]; then
    MESSAGES=$(echo "$MESSAGES" | jq -c ".[-$LIMIT:]")
fi

MESSAGE_COUNT=$(echo "$MESSAGES" | jq 'length')

if [ "$FORMAT" = "json" ]; then
    echo "$MESSAGES" | jq '.'
    exit 0
fi

# Text format output
echo "════════════════════════════════════════════════════════════════════════"
if [ "$UNREAD_ONLY" = "true" ]; then
    echo "           UNREAD CONVERSATION THREAD"
else
    echo "           COMPLETE CONVERSATION THREAD"
fi
echo "════════════════════════════════════════════════════════════════════════"

if [ "$SERVER_ID" != "all" ]; then
    echo "Filter: Messages for/from $SERVER_ID"
fi

echo "Total Messages: $MESSAGE_COUNT"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "════════════════════════════════════════════════════════════════════════"
echo ""

if [ "$MESSAGE_COUNT" -eq 0 ]; then
    echo "No messages found."
    exit 0
fi

# Display each message
echo "$MESSAGES" | jq -r '.[] | 
"┌─────────────────────────────────────────────────────────────────────────┐
│ Message ID: \(.id)
│ From: \(.from) → To: \(.to)
│ Type: \(.type | ascii_upcase) | Priority: \(.priority // "normal")
│ Timestamp: \(.timestamp)
│ Status: \(if .read then "[OK] READ" else "[!]  UNREAD" end)
├─────────────────────────────────────────────────────────────────────────┤
│ Subject: \(.subject)
├─────────────────────────────────────────────────────────────────────────┤
│ \(.body | gsub("\n"; "\n│ "))
└─────────────────────────────────────────────────────────────────────────┘
"'

echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo "END OF CONVERSATION THREAD"
echo "════════════════════════════════════════════════════════════════════════"

# Summary by sender
echo ""
echo "MESSAGE SUMMARY:"
echo "────────────────"

for server in build1 build2 build3 build4; do
    COUNT=$(echo "$MESSAGES" | jq --arg srv "$server" '[.[] | select(.from == $srv)] | length')
    if [ "$COUNT" -gt 0 ]; then
        echo "  $server: $COUNT messages sent"
    fi
done

# Summary by type
echo ""
echo "BY TYPE:"
for type in info warning error request; do
    COUNT=$(echo "$MESSAGES" | jq --arg t "$type" '[.[] | select(.type == $t)] | length')
    if [ "$COUNT" -gt 0 ]; then
        echo "  $type: $COUNT messages"
    fi
done

# Unread summary
if [ "$UNREAD_ONLY" = "false" ]; then
    echo ""
    echo "UNREAD STATUS:"
    for server in build1 build2 build3 build4; do
        UNREAD=$(echo "$MESSAGES" | jq --arg srv "$server" '[.[] | select((.to == $srv or .to == "all") and .read == false)] | length')
        if [ "$UNREAD" -gt 0 ]; then
            echo "  $server: [!]  $UNREAD unread messages"
        else
            echo "  $server: [OK] No unread messages"
        fi
    done
fi

exit 0
