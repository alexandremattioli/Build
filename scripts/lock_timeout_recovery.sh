#!/bin/bash
# Lock Timeout Recovery Script
# Automatically cleanup expired locks to prevent deadlocks
# Run this periodically via cron (e.g., every 5 minutes)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCKS_FILE="$REPO_ROOT/coordination/locks.json"

# Default lock timeout in seconds (10 minutes)
LOCK_TIMEOUT=${LOCK_TIMEOUT:-600}

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

check_lock_expired() {
    local expires_at="$1"
    if [ -z "$expires_at" ] || [ "$expires_at" = "null" ]; then
        return 1  # No expiration set, consider it expired
    fi
    
    local expires_epoch=$(date -d "$expires_at" +%s 2>/dev/null || echo 0)
    local now_epoch=$(date +%s)
    
    if [ "$expires_epoch" -lt "$now_epoch" ]; then
        return 0  # Lock is expired
    fi
    return 1  # Lock is still valid
}

cleanup_locks() {
    log "Checking for expired locks..."
    
    if [ ! -f "$LOCKS_FILE" ]; then
        log "Locks file not found: $LOCKS_FILE"
        return 0
    fi
    
    cd "$REPO_ROOT"
    git pull origin main --quiet || log "Warning: Failed to pull latest changes"
    
    # Use flock to prevent concurrent modifications on same host
    exec 200>"$LOCKS_FILE.flock"
    flock -n 200 || {
        log "Another process is modifying locks, skipping..."
        return 0
    }
    
    local updated=false
    local temp_file=$(mktemp)
    
    # Read current locks
    local locks=$(jq -r '.locks | keys[]' "$LOCKS_FILE" 2>/dev/null || echo "")
    
    for lock_name in $locks; do
        local locked_by=$(jq -r ".locks.\"$lock_name\".locked_by" "$LOCKS_FILE")
        local expires_at=$(jq -r ".locks.\"$lock_name\".expires_at" "$LOCKS_FILE")
        
        if [ "$locked_by" != "null" ]; then
            if check_lock_expired "$expires_at"; then
                log "Lock '$lock_name' expired (held by: $locked_by, expired at: $expires_at)"
                
                # Release the lock
                jq ".locks.\"$lock_name\" = {\"locked_by\": null, \"locked_at\": null, \"expires_at\": null}" \
                    "$LOCKS_FILE" > "$temp_file"
                mv "$temp_file" "$LOCKS_FILE"
                updated=true
                
                # Log to messages
                local msg_id="msg_$(date +%s)_$(shuf -i 1000-9999 -n 1)"
                local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
                
                jq --arg id "$msg_id" \
                   --arg from "system" \
                   --arg to "all" \
                   --arg subject "Lock timeout recovery" \
                   --arg body "Released expired lock '$lock_name' that was held by $locked_by" \
                   --arg timestamp "$timestamp" \
                   '.messages += [{
                       "id": $id,
                       "from": $from,
                       "to": $to,
                       "type": "warning",
                       "subject": $subject,
                       "body": $body,
                       "timestamp": $timestamp,
                       "read": false
                   }]' "$REPO_ROOT/coordination/messages.json" > "$temp_file"
                mv "$temp_file" "$REPO_ROOT/coordination/messages.json"
            fi
        fi
    done
    
    flock -u 200
    
    if [ "$updated" = true ]; then
        log "Locks cleaned up, committing changes..."
        git add coordination/locks.json coordination/messages.json
        git commit -m "Lock timeout recovery: Released expired locks [$(date -u +%Y-%m-%dT%H:%M:%SZ)]"
        git push origin main || log "Warning: Failed to push changes"
        log "Changes pushed successfully"
    else
        log "No expired locks found"
    fi
}

# Main execution
log "Lock timeout recovery script started (timeout: ${LOCK_TIMEOUT}s)"
cleanup_locks
log "Lock timeout recovery script completed"
