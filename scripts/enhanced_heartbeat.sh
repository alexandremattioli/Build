
#!/bin/bash
################################################################################
# Script: enhanced_heartbeat.sh
# Purpose: Send heartbeat and check for messages
# Usage: ./enhanced_heartbeat.sh <server_id>
#
# Arguments:
#   server_id - build1 or build2
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
git pull origin main --rebase --autostash >/dev/null 2>&1 || true

# Get current timestamp and uptime
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
UPTIME=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)

# Update heartbeat file
HEARTBEAT_FILE="$SERVER_ID/heartbeat.json"


# Use secure temp file
TMP_FILE=$(mktemp)
jq --arg ts "$TIMESTAMP" \
   --argjson uptime "$UPTIME" \
   '.timestamp = $ts | .uptime_seconds = $uptime | .healthy = true' \
   "$HEARTBEAT_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$HEARTBEAT_FILE"

# Commit and push heartbeat
git add "$HEARTBEAT_FILE"
git commit -m "[$SERVER_ID] Heartbeat $(date -u +%H:%M:%S)" >/dev/null 2>&1 || true

# Retry git push with exponential backoff
push_with_retry() {
   local max_attempts=5
   local attempt=1
   local delay=1
   while [ $attempt -le $max_attempts ]; do
      # Determine target branch for heartbeat pushes
      local branch_target="${HEARTBEAT_BRANCH:-main}"
      if [ "$branch_target" = "1" ] || [ "$branch_target" = "auto" ]; then
         branch_target="heartbeat-$SERVER_ID"
      fi
      # Push current HEAD to the target branch without changing local branch
      if git push origin HEAD:"$branch_target" 2>/dev/null; then
         return 0
      fi
      echo "Push failed (attempt $attempt/$max_attempts), retrying in ${delay}s..."
      sleep $delay
      git pull origin main --rebase --autostash
      delay=$((delay * 2))
      attempt=$((attempt + 1))
   done
   echo "ERROR: git push failed after $max_attempts attempts" >&2
   return 1
}

should_push() {
   local server_id="$1"
   local every="${HEARTBEAT_PUSH_EVERY:-5}"
   # Always push if set to 1
   if [ "$every" -le 1 ]; then
      echo 1; return
   fi
   local counter_file="/var/tmp/heartbeat-${server_id}.count"
   local count=0
   if [ -f "$counter_file" ]; then
      count=$(cat "$counter_file" 2>/dev/null || echo 0)
   fi
   count=$((count + 1))
   echo "$count" > "$counter_file"
   if [ $((count % every)) -eq 0 ]; then
      echo 1
   else
      echo 0
   fi
}

if [ "$(should_push "$SERVER_ID")" -eq 1 ]; then
   push_with_retry || { [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "enhanced_heartbeat" "git push failed after retries"; echo "Warning: Heartbeat push failed"; }
fi

# Validate heartbeat JSON
if [ -f scripts/validate_json.sh ]; then
   bash scripts/validate_json.sh "$HEARTBEAT_FILE" || true
fi

# Check for new messages
cd scripts
./check_and_process_messages.sh "$SERVER_ID" 2>/dev/null || true

# Auto-reply to unread messages using rules
python3 auto_reply.py 2>/dev/null || true

exit 0
