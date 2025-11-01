#!/bin/bash
################################################################################
# Script: unified_heartbeat.sh
# Purpose: Unified heartbeat script for all build servers
# Usage: ./unified_heartbeat.sh <server_id> [--daemon] [--interval SECONDS]
#
# Arguments:
#   server_id       - build1, build2, build3, or build4
#   --daemon        - Run continuously (default: one-shot)
#   --interval N    - Heartbeat interval in seconds (default: 60)
#
# Environment Variables:
#   HEARTBEAT_BRANCH       - Branch name, or 1/auto for heartbeat-<server>
#   HEARTBEAT_PUSH_EVERY   - Push every N beats (>=2, default: 5)
#   REPO_DIR               - Repository directory (default: /root/Build)
#
# Examples:
#   ./unified_heartbeat.sh build2
#   ./unified_heartbeat.sh build1 --daemon
#   ./unified_heartbeat.sh build3 --daemon --interval 30
#   HEARTBEAT_BRANCH=auto ./unified_heartbeat.sh build4 --daemon
#
# Exit Codes:
#   0 - Success
#   1 - Validation error
#   2 - Git operation failed
#
# Dependencies: jq, git
################################################################################

set -euo pipefail

# Default configuration
REPO_DIR="${REPO_DIR:-/root/Build}"
DAEMON_MODE=false
INTERVAL=60
MAX_RETRIES=3
RETRY_DELAY=5
HEARTBEAT_BRANCH="${HEARTBEAT_BRANCH:-}"
HEARTBEAT_PUSH_EVERY="${HEARTBEAT_PUSH_EVERY:-5}"
BEAT_COUNT=0

# Parse arguments
if [ $# -lt 1 ]; then
    echo "ERROR: Server ID required" >&2
    echo "Usage: $0 <server_id> [--daemon] [--interval SECONDS]" >&2
    exit 1
fi

SERVER_ID="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --daemon)
            DAEMON_MODE=true
            shift
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Input validation
validate_server_id() {
    local server="$1"
    if [[ ! "$server" =~ ^(build1|build2|build3|build4)$ ]]; then
        echo "ERROR: Invalid server ID: $server (must be build1, build2, build3, or build4)" >&2
        exit 1
    fi
}

validate_server_id "$SERVER_ID"

# Determine target branch for push
TARGET_BRANCH="main"
if [ -n "$HEARTBEAT_BRANCH" ]; then
    if [[ "$HEARTBEAT_BRANCH" == "1" ]] || [[ "$HEARTBEAT_BRANCH" == "auto" ]]; then
        TARGET_BRANCH="heartbeat-${SERVER_ID}"
    else
        TARGET_BRANCH="$HEARTBEAT_BRANCH"
    fi
fi

# Logging function
log() {
    echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] $*"
}

# Error logging
log_error() {
    log "ERROR: $*" >&2
}

# Git pull with retry
git_pull_with_retry() {
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        if git pull origin main --rebase --autostash >/dev/null 2>&1; then
            return 0
        fi
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            log "Pull failed, retrying in ${RETRY_DELAY}s... (attempt $retries/$MAX_RETRIES)"
            sleep $RETRY_DELAY
        fi
    done
    log_error "Failed to pull after $MAX_RETRIES attempts"
    return 2
}

# Git push with retry
git_push_with_retry() {
    local retries=0
    local push_target="origin HEAD:${TARGET_BRANCH}"
    
    while [ $retries -lt $MAX_RETRIES ]; do
        if git push $push_target >/dev/null 2>&1; then
            log "Pushed to $TARGET_BRANCH"
            return 0
        fi
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
            log "Push failed, pulling and retrying in ${RETRY_DELAY}s... (attempt $retries/$MAX_RETRIES)"
            git_pull_with_retry
            sleep $RETRY_DELAY
        fi
    done
    log_error "Failed to push after $MAX_RETRIES attempts"
    return 2
}

# Update heartbeat
update_heartbeat() {
    cd "$REPO_DIR"
    
    # Pull latest changes
    git_pull_with_retry || return 2
    
    # Get current timestamp and uptime
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    UPTIME=$(awk '{print int($1)}' /proc/uptime)
    
    # Get system metrics
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")
    MEMORY_USED=$(free -g | awk '/^Mem:/{print $3}' || echo "0")
    DISK_FREE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//' || echo "0")
    
    # Update heartbeat.json
    HEARTBEAT_FILE="${SERVER_ID}/heartbeat.json"
    
    if [ ! -f "$HEARTBEAT_FILE" ]; then
        log_error "Heartbeat file not found: $HEARTBEAT_FILE"
        return 1
    fi
    
    jq --arg ts "$TIMESTAMP" \
       --arg uptime "$UPTIME" \
       --arg cpu "$CPU_USAGE" \
       --arg mem "$MEMORY_USED" \
       --arg disk "$DISK_FREE" \
       --arg server "$SERVER_ID" \
       '.server = $server |
        .timestamp = $ts | \
        .uptime_seconds = ($uptime | tonumber) | \
        .healthy = true |
        .system.cpu_usage = ($cpu | tonumber) |
        .system.memory_used_gb = ($mem | tonumber) |
        .system.disk_free_gb = ($disk | tonumber)' \
       "$HEARTBEAT_FILE" > /tmp/heartbeat_${SERVER_ID}.json
    
    mv /tmp/heartbeat_${SERVER_ID}.json "$HEARTBEAT_FILE"
    
    # Commit changes
    git add "$HEARTBEAT_FILE"
    git commit -q -m "Heartbeat: ${SERVER_ID} $(date -u +%H:%M:%S)" || {
        log "No changes to commit"
        return 0
    }
    
    # Increment beat counter
    BEAT_COUNT=$((BEAT_COUNT + 1))
    
    # Push if interval reached
    if [ $((BEAT_COUNT % HEARTBEAT_PUSH_EVERY)) -eq 0 ]; then
        git_push_with_retry || return 2
        BEAT_COUNT=0
    else
        log "Committed (batch ${BEAT_COUNT}/${HEARTBEAT_PUSH_EVERY})"
    fi
    
    return 0
}

# Main execution
main() {
    log "Starting heartbeat for ${SERVER_ID}"
    log "Mode: $([ "$DAEMON_MODE" = true ] && echo "daemon" || echo "one-shot")"
    log "Interval: ${INTERVAL}s"
    log "Push target: ${TARGET_BRANCH}"
    log "Push every: ${HEARTBEAT_PUSH_EVERY} beats"
    
    if [ "$DAEMON_MODE" = false ]; then
        # One-shot mode
        update_heartbeat
        exit $?
    else
        # Daemon mode
        while true; do
            if ! update_heartbeat; then
                log_error "Heartbeat update failed, will retry in ${INTERVAL}s"
            fi
            sleep "$INTERVAL"
        done
    fi
}

# Trap signals for graceful shutdown
trap 'log "Received shutdown signal, pushing pending commits..."; [ $BEAT_COUNT -gt 0 ] && git_push_with_retry; exit 0' SIGTERM SIGINT

main