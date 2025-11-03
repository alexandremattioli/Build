#!/bin/bash
# Job Queue Manager with Priority Support
# Handles job assignment with priority ordering and dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JOBS_FILE="$REPO_ROOT/coordination/jobs.json"
LOCKS_FILE="$REPO_ROOT/coordination/locks.json"

SERVER_ID=${SERVER_ID:-$(bash "$SCRIPT_DIR/server_id.sh" 2>/dev/null || echo "unknown")}

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

# Acquire lock
acquire_lock() {
    local lock_name="$1"
    local timeout="${2:-600}"  # 10 minutes default
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    exec 200>"$LOCKS_FILE.flock"
    flock -n 200 || {
        log "Failed to acquire file lock"
        return 1
    }
    
    local locked_by=$(jq -r ".locks.\"$lock_name\".locked_by" "$LOCKS_FILE")
    
    if [ "$locked_by" != "null" ] && [ "$locked_by" != "$SERVER_ID" ]; then
        # Check if lock is expired
        local expires_at=$(jq -r ".locks.\"$lock_name\".expires_at" "$LOCKS_FILE")
        local expires_epoch=$(date -d "$expires_at" +%s 2>/dev/null || echo 0)
        local now_epoch=$(date +%s)
        
        if [ "$expires_epoch" -gt "$now_epoch" ]; then
            log "Lock '$lock_name' is held by $locked_by"
            flock -u 200
            return 1
        fi
        
        log "Lock '$lock_name' expired, taking over..."
    fi
    
    # Acquire lock
    local locked_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local expires_at=$(date -u -d "+${timeout} seconds" +%Y-%m-%dT%H:%M:%SZ)
    
    local temp_file=$(mktemp)
    jq --arg lock "$lock_name" \
       --arg server "$SERVER_ID" \
       --arg locked_at "$locked_at" \
       --arg expires_at "$expires_at" \
       '.locks[$lock] = {
           "locked_by": $server,
           "locked_at": $locked_at,
           "expires_at": $expires_at
       }' "$LOCKS_FILE" > "$temp_file"
    mv "$temp_file" "$LOCKS_FILE"
    
    flock -u 200
    
    git add "$LOCKS_FILE"
    git commit -m "Acquire lock: $lock_name by $SERVER_ID"
    git push origin main --quiet
    
    log "Acquired lock: $lock_name"
    return 0
}

# Release lock
release_lock() {
    local lock_name="$1"
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    exec 200>"$LOCKS_FILE.flock"
    flock -n 200 || return 1
    
    local temp_file=$(mktemp)
    jq --arg lock "$lock_name" \
       '.locks[$lock] = {
           "locked_by": null,
           "locked_at": null,
           "expires_at": null
       }' "$LOCKS_FILE" > "$temp_file"
    mv "$temp_file" "$LOCKS_FILE"
    
    flock -u 200
    
    git add "$LOCKS_FILE"
    git commit -m "Release lock: $lock_name by $SERVER_ID"
    git push origin main --quiet
    
    log "Released lock: $lock_name"
}

# Add job to queue
add_job() {
    local branch="$1"
    local commit="$2"
    local priority="${3:-5}"
    local dependencies="${4:-}"  # Comma-separated job IDs
    
    acquire_lock "job_assignment" || return 1
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    local job_id="job_$(date +%s)_$(shuf -i 1000-9999 -n 1)"
    local created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    exec 200>"$JOBS_FILE.flock"
    flock -n 200 || {
        release_lock "job_assignment"
        return 1
    }
    
    local temp_file=$(mktemp)
    
    # Parse dependencies array
    local deps="[]"
    if [ -n "$dependencies" ]; then
        deps="[$(echo "$dependencies" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/')]"
    fi
    
    jq --arg id "$job_id" \
       --arg branch "$branch" \
       --arg commit "$commit" \
       --argjson priority "$priority" \
       --argjson deps "$deps" \
       --arg created_at "$created_at" \
       '.jobs += [{
           "id": $id,
           "type": "build",
           "priority": $priority,
           "branch": $branch,
           "commit": $commit,
           "dependencies": $deps,
           "assigned_to": null,
           "status": "queued",
           "created_at": $created_at,
           "started_at": null,
           "completed_at": null
       }]' "$JOBS_FILE" > "$temp_file"
    mv "$temp_file" "$JOBS_FILE"
    
    flock -u 200
    
    git add "$JOBS_FILE"
    git commit -m "Add job: $job_id (priority: $priority, branch: $branch)"
    git push origin main --quiet
    
    release_lock "job_assignment"
    
    log "Added job: $job_id"
    echo "$job_id"
}

# Check if dependencies are satisfied
check_dependencies() {
    local job_id="$1"
    
    local deps=$(jq -r --arg id "$job_id" '.jobs[] | select(.id == $id) | .dependencies[]?' "$JOBS_FILE")
    
    if [ -z "$deps" ]; then
        return 0  # No dependencies
    fi
    
    for dep_id in $deps; do
        local dep_status=$(jq -r --arg id "$dep_id" '.jobs[] | select(.id == $id) | .status' "$JOBS_FILE")
        
        if [ "$dep_status" != "completed" ]; then
            log "Dependency $dep_id not completed (status: $dep_status)"
            return 1
        fi
    done
    
    return 0
}

# Get next job (priority-based, dependency-aware)
get_next_job() {
    acquire_lock "job_assignment" || return 1
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    exec 200>"$JOBS_FILE.flock"
    flock -n 200 || {
        release_lock "job_assignment"
        return 1
    }
    
    # Get all queued jobs, sorted by priority (descending)
    local queued_jobs=$(jq -r '.jobs[] | select(.status == "queued") | @json' "$JOBS_FILE" | \
                        jq -s 'sort_by(-.priority) | .[]')
    
    local job_id=""
    
    # Find first job with satisfied dependencies
    while IFS= read -r job; do
        local id=$(echo "$job" | jq -r '.id')
        
        if check_dependencies "$id"; then
            job_id="$id"
            break
        else
            log "Job $id has unsatisfied dependencies, skipping..."
        fi
    done <<< "$queued_jobs"
    
    if [ -z "$job_id" ]; then
        log "No eligible jobs found"
        flock -u 200
        release_lock "job_assignment"
        return 1
    fi
    
    # Assign job to this server
    local started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local temp_file=$(mktemp)
    
    jq --arg id "$job_id" \
       --arg server "$SERVER_ID" \
       --arg started_at "$started_at" \
       '(.jobs[] | select(.id == $id)) |= {
           id: .id,
           type: .type,
           priority: .priority,
           branch: .branch,
           commit: .commit,
           dependencies: .dependencies,
           assigned_to: $server,
           status: "running",
           created_at: .created_at,
           started_at: $started_at,
           completed_at: null
       }' "$JOBS_FILE" > "$temp_file"
    mv "$temp_file" "$JOBS_FILE"
    
    flock -u 200
    
    git add "$JOBS_FILE"
    git commit -m "Assign job: $job_id to $SERVER_ID"
    git push origin main --quiet
    
    release_lock "job_assignment"
    
    # Return job details as JSON
    jq --arg id "$job_id" '.jobs[] | select(.id == $id)' "$JOBS_FILE"
}

# Complete job
complete_job() {
    local job_id="$1"
    local status="$2"  # completed or failed
    local duration="${3:-0}"
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    exec 200>"$JOBS_FILE.flock"
    flock -n 200 || return 1
    
    local completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local temp_file=$(mktemp)
    
    jq --arg id "$job_id" \
       --arg status "$status" \
       --arg completed_at "$completed_at" \
       --argjson duration "$duration" \
       '(.jobs[] | select(.id == $id)) |= (
           .status = $status |
           .completed_at = $completed_at |
           .duration_seconds = $duration
       )' "$JOBS_FILE" > "$temp_file"
    mv "$temp_file" "$JOBS_FILE"
    
    flock -u 200
    
    git add "$JOBS_FILE"
    git commit -m "Complete job: $job_id ($status)"
    git push origin main --quiet
    
    log "Job $job_id completed with status: $status"
}

# List jobs
list_jobs() {
    local status_filter="${1:-all}"  # all, queued, running, completed, failed
    
    if [ "$status_filter" = "all" ]; then
        jq -r '.jobs[] | "\(.id) [\(.status)] priority:\(.priority) \(.branch) assigned_to:\(.assigned_to // "none")"' "$JOBS_FILE"
    else
        jq -r --arg status "$status_filter" \
           '.jobs[] | select(.status == $status) | "\(.id) priority:\(.priority) \(.branch) assigned_to:\(.assigned_to // "none")"' \
           "$JOBS_FILE"
    fi
}

# Main command dispatcher
case "${1:-help}" in
    add)
        add_job "$2" "$3" "$4" "$5"
        ;;
    get-next)
        get_next_job
        ;;
    complete)
        complete_job "$2" "$3" "$4"
        ;;
    list)
        list_jobs "$2"
        ;;
    help|*)
        cat <<EOF
Job Queue Manager with Priority Support

Usage:
  $0 add <branch> <commit> [priority] [dependencies]    Add job to queue
  $0 get-next                                            Get next eligible job
  $0 complete <job_id> <status> [duration]              Mark job as complete
  $0 list [status]                                       List jobs (all/queued/running/completed/failed)

Priority:
  1-10, where 1 is highest priority, 10 is lowest (default: 5)

Dependencies:
  Comma-separated list of job IDs that must complete first

Examples:
  $0 add main abc123 1                    # High priority job
  $0 add feature def456 5 job_12345       # Normal priority with dependency
  $0 get-next                              # Get next job to run
  $0 complete job_12345 completed 1234    # Mark job complete
  $0 list queued                           # List queued jobs

EOF
        ;;
esac
