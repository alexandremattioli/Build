#!/bin/bash
################################################################################
# Script: create_job.sh
# Purpose: Add job to queue in jobs.json
# Usage: ./create_job.sh <type> <priority> <description>
#
# Arguments:
#   type        - Job type (string)
#   priority    - Job priority (integer, default 5)
#   description - Job description (string)
#
# Exit Codes:
#   0 - Success
#   1 - Validation error
#   2 - Git operation failed
#
# Dependencies: jq, git
################################################################################

set -euo pipefail

JOB_TYPE="$1"
PRIORITY="${2:-5}"
DESCRIPTION="$3"

# Input validation
validate_priority() {
    local prio="$1"
    if ! [[ "$prio" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Invalid priority: $prio" >&2
        exit 1
    fi
}

if [ -z "${JOB_TYPE:-}" ] || [ -z "${DESCRIPTION:-}" ]; then
    echo "Usage: ./create_job.sh <type> <priority> <description>" >&2
    exit 1
fi

validate_priority "$PRIORITY"

REPO_DIR="/root/Build"
cd "$REPO_DIR"

# Acquire local write lock for jobs to avoid concurrent edits on this host
LOCK_DIR="coordination/.locks"
mkdir -p "$LOCK_DIR"
LOCK_FILE="$LOCK_DIR/jobs.lock"
exec {lock_fd}>"$LOCK_FILE"
if ! flock -w "${LOCK_WAIT:-10}" "$lock_fd"; then
    echo "ERROR: Could not acquire jobs lock within ${LOCK_WAIT:-10}s" >&2
    [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "create_job" "lock acquisition failed"
    exit 2
fi
trap "flock -u $lock_fd" EXIT

JOB_ID="job_$(date +%s)_$(shuf -i 1000-9999 -n 1)"

# Pull latest
git pull origin main --rebase --autostash

TMP_FILE=$(mktemp)
jq --arg id "$JOB_ID" \
   --arg type "$JOB_TYPE" \
   --argjson priority "$PRIORITY" \
   --arg desc "$DESCRIPTION" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.jobs += [{
       id: $id,
       type: $type,
       priority: $priority,
       description: $desc,
       status: "queued",
       assigned_to: null,
       created_at: $ts,
       started_at: null,
       completed_at: null
   }]' coordination/jobs.json > "$TMP_FILE"
mv "$TMP_FILE" coordination/jobs.json

# Validate JSON
if [ -f scripts/validate_json.sh ]; then
    bash scripts/validate_json.sh coordination/jobs.json || exit 2
fi
git add coordination/jobs.json
git commit -m "Job created: $JOB_ID"

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
    [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "create_job" "git push failed after $max_attempts attempts"
    echo "ERROR: git push failed after $max_attempts attempts" >&2
    return 1
}

push_with_retry

echo "Job created: $JOB_ID"
