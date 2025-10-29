
#!/bin/bash
################################################################################
# Script: send_message.sh
# Purpose: Send a message to another build server via git-based messaging
# Usage: ./send_message.sh <from> <to> <type> <subject> <body>
#
# Arguments:
#   from    - Source server ID (build1, build2)
#   to      - Destination server ID (build1, build2, all)
#   type    - Message type (info, warning, error, request)
#   subject - Message subject line (max 100 chars)
#   body    - Message body text
#
# Examples:
#   ./send_message.sh build1 build2 info "Build Complete" "Build finished successfully"
#   ./send_message.sh build2 all warning "Disk Space Low" "Only 10GB remaining"
#
# Exit Codes:
#   0 - Success
#   1 - Validation error
#   2 - Git operation failed
#
# Dependencies: jq, git
################################################################################

set -euo pipefail


FROM_SERVER="$1"
TO_SERVER="$2"
MSG_TYPE="$3"
SUBJECT="$4"
BODY="$5"

# Input validation
validate_server_id() {
    local server="$1"
    if [[ ! "$server" =~ ^(build1|build2|all)$ ]]; then
        echo "ERROR: Invalid server ID: $server" >&2
        exit 1
    fi
}

validate_message_type() {
    local type="$1"
    if [[ ! "$type" =~ ^(info|warning|error|request)$ ]]; then
        echo "ERROR: Invalid message type: $type" >&2
        exit 1
    fi
}

validate_server_id "$FROM_SERVER"
validate_server_id "$TO_SERVER"
validate_message_type "$MSG_TYPE"

REPO_DIR="/root/Build"
cd "$REPO_DIR"

# Acquire local write lock for messages to avoid concurrent edits on this host
LOCK_DIR="coordination/.locks"
mkdir -p "$LOCK_DIR"
LOCK_FILE="$LOCK_DIR/messages.lock"
exec {lock_fd}>"$LOCK_FILE"
if ! flock -w "${LOCK_WAIT:-10}" "$lock_fd"; then
    echo "ERROR: Could not acquire messages lock within ${LOCK_WAIT:-10}s" >&2
    [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "send_message" "lock acquisition failed"
    exit 2
fi
trap "flock -u $lock_fd" EXIT

# Generate UUID
MSG_ID="msg_$(date +%s)_$(shuf -i 1000-9999 -n 1)"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Pull latest
git pull origin main --rebase --autostash


# Add message using secure temp file
TMP_FILE=$(mktemp)
jq --arg id "$MSG_ID" \
   --arg from "$FROM_SERVER" \
   --arg to "$TO_SERVER" \
   --arg type "$MSG_TYPE" \
   --arg subject "$SUBJECT" \
   --arg body "$BODY" \
   --arg ts "$TIMESTAMP" \
   '.messages += [{
       id: $id,
       from: $from,
       to: $to,
       type: $type,
       subject: $subject,
       body: $body,
       timestamp: $ts,
       read: false
   }]' coordination/messages.json > "$TMP_FILE"
mv "$TMP_FILE" coordination/messages.json

# Commit and push
git add coordination/messages.json
git commit -m "Message from $FROM_SERVER to $TO_SERVER: $SUBJECT"

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
    [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "send_message" "git push failed after $max_attempts attempts"
    echo "ERROR: git push failed after $max_attempts attempts" >&2
    return 1
}

push_with_retry

# Validate messages JSON (post-commit check)
if [ -f scripts/validate_json.sh ]; then
    bash scripts/validate_json.sh coordination/messages.json || true
fi

echo "Message sent: $MSG_ID"

# Update statistics
cd scripts
./update_message_stats.sh >/dev/null 2>&1 || true
