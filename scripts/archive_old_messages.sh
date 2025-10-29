#!/bin/bash
################################################################################
# Script: archive_old_messages.sh
# Purpose: Move read messages older than 7 days to archive
# Usage: ./archive_old_messages.sh
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

# Acquire local write lock for messages to avoid concurrent edits on this host
LOCK_DIR="coordination/.locks"
mkdir -p "$LOCK_DIR"
LOCK_FILE="$LOCK_DIR/messages.lock"
exec {lock_fd}>"$LOCK_FILE"
if ! flock -w "${LOCK_WAIT:-10}" "$lock_fd"; then
    echo "ERROR: Could not acquire messages lock within ${LOCK_WAIT:-10}s" >&2
    [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "archive_old_messages" "lock acquisition failed"
    exit 2
fi
trap "flock -u $lock_fd" EXIT

CUTOFF=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)

TMP_FILE=$(mktemp)
jq --arg cutoff "$CUTOFF" '
    {
        archived: [.messages[] | select(.read == true and .timestamp < $cutoff)],
        messages: [.messages[] | select(.read == false or .timestamp >= $cutoff)]
    }
' coordination/messages.json > "$TMP_FILE"

ARCHIVE_FILE="coordination/archive/messages-$(date +%Y-%m).json"
mkdir -p coordination/archive
jq '.archived' "$TMP_FILE" > "$ARCHIVE_FILE"
jq '.messages' "$TMP_FILE" > coordination/messages.json
rm "$TMP_FILE"

# Validate JSON
if [ -f scripts/validate_json.sh ]; then
    bash scripts/validate_json.sh coordination/messages.json || exit 2
fi

# Commit and push changes
git add coordination/messages.json "$ARCHIVE_FILE"
git commit -m "Archive old messages at $(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true

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
    [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "archive_old_messages" "git push failed after $max_attempts attempts"
    echo "ERROR: git push failed after $max_attempts attempts" >&2
    return 1
}

push_with_retry || true

echo "Archived old messages to $ARCHIVE_FILE"
