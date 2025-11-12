
#!/bin/bash
################################################################################
# Script: check_health.sh
# Purpose: Monitor health of all servers and job/message status
# Usage: ./check_health.sh
#
# Exit Codes:
#   0 - Success
#   1 - Validation error
#   2 - Git operation failed
#
# Dependencies: jq, git
################################################################################

set -euo pipefail

REPO_DIR="/root/Build"
cd "$REPO_DIR"

# Pull latest
git pull origin main --quiet

echo "=== Build Server Health Check ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Check each server
for SERVER in build1 build2; do
    echo "[$SERVER]"
    
    # Check heartbeat
    if [ -f "$SERVER/heartbeat.json" ]; then
        LAST_BEAT=$(jq -r '.timestamp' "$SERVER/heartbeat.json")
        HEALTHY=$(jq -r '.healthy' "$SERVER/heartbeat.json")
        
        LAST_BEAT_TS=$(date -d "$LAST_BEAT" +%s 2>/dev/null || echo 0)
        NOW_TS=$(date +%s)
        AGE=$((NOW_TS - LAST_BEAT_TS))
        
        echo "  Heartbeat: $LAST_BEAT ($AGE seconds ago)"
        
        if [ $AGE -gt 300 ]; then
            echo "  [!]  WARNING: Heartbeat is stale (>5 minutes)"
            if [ "${LOCAL_SERVER_ID:-}" = "$SERVER" ] && [ -f scripts/recover_stale_heartbeat.sh ]; then
                echo "  → Attempting recovery via recover_stale_heartbeat.sh ($SERVER)"
                bash scripts/recover_stale_heartbeat.sh "$SERVER" || echo "  ! Recovery attempt failed"
            fi
        elif [ $AGE -gt 120 ]; then
            echo "  [!]  CAUTION: Heartbeat is aging (>2 minutes)"
        else
            echo "  [OK] Heartbeat OK"
        fi
    else
        echo "  [X] ERROR: No heartbeat file found"
    fi
    
    # Check status
    if [ -f "$SERVER/status.json" ]; then
        STATUS=$(jq -r '.status' "$SERVER/status.json")
        MANAGER=$(jq -r '.manager' "$SERVER/status.json")
        IP=$(jq -r '.ip' "$SERVER/status.json")
        
        echo "  Status: $STATUS"
        echo "  Manager: $MANAGER"
        echo "  IP: $IP"
        
        if [ "$STATUS" = "building" ]; then
            JOB_ID=$(jq -r '.current_job.id // "unknown"' "$SERVER/status.json")
            STARTED=$(jq -r '.current_job.started_at // "unknown"' "$SERVER/status.json")
            echo "  Current Job: $JOB_ID (started: $STARTED)"
        fi
    else
        echo "  [X] ERROR: No status file found"
    fi
    
    echo ""
done

# Check job queue
echo "[Job Queue]"

TMP_FILE=$(mktemp)
jq '[.jobs[] | select(.status == "queued")] | length' coordination/jobs.json > "$TMP_FILE"
QUEUED=$(cat "$TMP_FILE")
jq '[.jobs[] | select(.status == "running")] | length' coordination/jobs.json > "$TMP_FILE"
RUNNING=$(cat "$TMP_FILE")
jq '[.jobs[] | select(.status == "completed")] | length' coordination/jobs.json > "$TMP_FILE"
COMPLETED=$(cat "$TMP_FILE")
jq '[.jobs[] | select(.status == "failed")] | length' coordination/jobs.json > "$TMP_FILE"
FAILED=$(cat "$TMP_FILE")
rm "$TMP_FILE"

echo "  Queued: $QUEUED"
echo "  Running: $RUNNING"
echo "  Completed: $COMPLETED"
echo "  Failed: $FAILED"

# Check for stuck jobs
STUCK=$(jq --argjson now "$(date +%s)" '[.jobs[] | select(.status == "running" and (($now - (.started_at | sub("Z$";"") | sub("T"; " ") | strptime("%Y-%m-%d %H:%M:%S") | mktime)) > 3600))] | length' coordination/jobs.json 2>/dev/null || echo 0)

if [ "$STUCK" -gt 0 ]; then
    echo "  [!]  WARNING: $STUCK job(s) running for >1 hour"
fi

echo ""

# Check messages
UNREAD=$(jq '[.messages[] | select(.read == false)] | length' coordination/messages.json)
echo "[Messages]"
echo "  Unread: $UNREAD"

if [ "$UNREAD" -gt 0 ]; then
    echo "  Recent messages:"
    jq -r '.messages[] | select(.read == false) | "    \(.from) -> \(.to): \(.subject)"' coordination/messages.json | head -5
fi

echo ""
echo "=== End Health Check ==="
