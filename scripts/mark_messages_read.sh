
#!/bin/bash
################################################################################
# Script: mark_messages_read.sh
# Purpose: Mark messages as read for a server or specific message
# Usage: ./mark_messages_read.sh <server_id> [message_id]
#
# Arguments:
#   server_id   - build1 or build2
#   message_id  - (optional) message id to mark as read
#
# Exit Codes:
#   0 - Success
#   1 - Validation error
#   2 - Git operation failed
#
# Dependencies: jq, git
################################################################################

set -euo pipefail


SERVER_ID="${1:-build2}"
SPECIFIC_MSG_ID="${2:-}"

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

# Acquire local write lock for messages to avoid concurrent edits on this host
LOCK_DIR="coordination/.locks"
mkdir -p "$LOCK_DIR"
LOCK_FILE="$LOCK_DIR/messages.lock"
exec {lock_fd}>"$LOCK_FILE"
if ! flock -w "${LOCK_WAIT:-10}" "$lock_fd"; then
    echo "ERROR: Could not acquire messages lock within ${LOCK_WAIT:-10}s" >&2
    [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "mark_messages_read" "lock acquisition failed"
    exit 2
fi
trap "flock -u $lock_fd" EXIT

# Pull latest
git pull origin main --rebase --autostash >/dev/null 2>&1 || true

if [ -n "$SPECIFIC_MSG_ID" ]; then
    # Look up the message and current read state
    MSG_RESULT=$(jq --arg msg_id "$SPECIFIC_MSG_ID" '[.messages[] | select(.id == $msg_id)] | first' coordination/messages.json)

    if [ "$MSG_RESULT" = "null" ]; then
        echo "Message $SPECIFIC_MSG_ID not found"
        exit 1
    fi

    MSG_ALREADY_READ=$(echo "$MSG_RESULT" | jq -r '.read')
    if [ "$MSG_ALREADY_READ" = "true" ]; then
        echo "Message $SPECIFIC_MSG_ID already marked as read"
        exit 0
    fi

     TMP_FILE=$(mktemp)
     jq --arg msg_id "$SPECIFIC_MSG_ID" \
         '(.messages[] | select(.id == $msg_id)).read = true' \
         coordination/messages.json > "$TMP_FILE"
     mv "$TMP_FILE" coordination/messages.json
    echo "Marked message $SPECIFIC_MSG_ID as read"
else
    UNREAD_COUNT=$(jq --arg server "$SERVER_ID" \
        '[.messages[] | select((.to == $server or .to == "all") and .read == false)] | length' \
        coordination/messages.json)

    if [ "$UNREAD_COUNT" -eq 0 ]; then
        echo "No unread messages for $SERVER_ID"
        exit 0
    fi

     TMP_FILE=$(mktemp)
     jq --arg server "$SERVER_ID" \
         '(.messages[] | select((.to == $server or .to == "all") and .read == false)).read = true' \
         coordination/messages.json > "$TMP_FILE"
     mv "$TMP_FILE" coordination/messages.json
    echo "Marked all unread messages for $SERVER_ID as read"
fi

# Commit and push
git add coordination/messages.json
if git diff --cached --quiet; then
    echo "No changes to commit"
    exit 0
fi

git commit -m "[$SERVER_ID] Marked messages as read" >/dev/null 2>&1
git push origin main >/dev/null 2>&1

echo "[OK] Messages marked as read in GitHub"

# Update statistics
cd scripts
./update_message_stats.sh >/dev/null 2>&1 || true
