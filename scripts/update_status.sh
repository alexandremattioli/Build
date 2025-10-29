#!/bin/bash
# update_status.sh - Update server status
# Usage: ./update_status.sh <server_id> <status> [current_job_id]

set -euo pipefail

SERVER_ID="${1:-build2}"
STATUS="${2:-idle}"
JOB_ID="${3:-null}"

REPO_DIR="/root/Build"

cd "$REPO_DIR"

# Pull latest
git pull origin main --rebase --autostash

# Get current timestamp
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Update status file
STATUS_FILE="$SERVER_ID/status.json"

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
       "$STATUS_FILE" > tmp.json
else
    jq --arg ts "$TIMESTAMP" \
       --arg status "$STATUS" \
       '.timestamp = $ts | .status = $status | .current_job = null' \
       "$STATUS_FILE" > tmp.json
fi

mv tmp.json "$STATUS_FILE"

# Commit and push
git add "$STATUS_FILE"
git commit -m "[$SERVER_ID] Status: $STATUS at $TIMESTAMP" >/dev/null 2>&1 || true
git push origin main >/dev/null 2>&1 || true

echo "Status updated: $SERVER_ID -> $STATUS"
