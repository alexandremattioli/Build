
#!/bin/bash
################################################################################
# Script: update_status.sh
# Purpose: Update server status in status.json
# Usage: ./update_status.sh <server_id> <status> [current_job_id]
#
# Arguments:
#   server_id      - build1 or build2
#   status         - idle, building, error, etc.
#   current_job_id - (optional) job id
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
STATUS="${2:-idle}"
JOB_ID="${3:-null}"

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
git pull origin main --rebase --autostash

# Get current timestamp
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Update status file
STATUS_FILE="$SERVER_ID/status.json"


# Use secure temp file
TMP_FILE=$(mktemp)
if [ "$JOB_ID" != "null" ]; then
    jq --arg ts "$TIMESTAMP" \
       --arg status "$STATUS" \
       --arg job "$JOB_ID" \
       '. as $orig
        | .timestamp = $ts
        | .status = $status
        | .current_job = (
            if ($orig.current_job // null) and (($orig.current_job.id // null) == $job) then
                $orig.current_job
            else
                {}
            end
          )
        | .current_job.id = $job
        | .current_job.started_at = (
            if ($orig.current_job // null) and (($orig.current_job.id // null) == $job) and ($orig.current_job.started_at // null) then
                $orig.current_job.started_at
            else
                $ts
            end
          )' \
       "$STATUS_FILE" > "$TMP_FILE"
else
    jq --arg ts "$TIMESTAMP" \
       --arg status "$STATUS" \
       '.timestamp = $ts | .status = $status | .current_job = null' \
       "$STATUS_FILE" > "$TMP_FILE"
fi
mv "$TMP_FILE" "$STATUS_FILE"

# Commit and push
git add "$STATUS_FILE"
git commit -m "[$SERVER_ID] Status: $STATUS at $TIMESTAMP" >/dev/null 2>&1 || true

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
    [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "update_status" "git push failed after $max_attempts attempts"
    echo "ERROR: git push failed after $max_attempts attempts" >&2
    return 1
}

push_with_retry

# Validate status JSON
if [ -f scripts/validate_json.sh ]; then
    bash scripts/validate_json.sh "$STATUS_FILE" || true
fi

echo "Status updated: $SERVER_ID -> $STATUS"
