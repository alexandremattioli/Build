#!/bin/bash
# Structured Logging Helper
# Creates both JSON and Markdown logs for builds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Get server ID
SERVER_ID=${SERVER_ID:-$(bash "$SCRIPT_DIR/server_id.sh" 2>/dev/null || echo "unknown")}
LOG_DIR="$REPO_ROOT/build${SERVER_ID#build}/logs"

# Initialize log entry
init_log() {
    local job_id="$1"
    local branch="$2"
    local commit="$3"
    
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    LOG_ID="${job_id}_${TIMESTAMP}"
    
    JSON_LOG="$LOG_DIR/${LOG_ID}.json"
    MD_LOG="$LOG_DIR/${LOG_ID}.md"
    
    mkdir -p "$LOG_DIR"
    
    # Initialize JSON log
    cat > "$JSON_LOG" <<EOF
{
  "log_id": "$LOG_ID",
  "job_id": "$job_id",
  "server": "$SERVER_ID",
  "branch": "$branch",
  "commit": "$commit",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "events": [],
  "status": "running",
  "exit_code": null,
  "completed_at": null,
  "duration_seconds": null
}
EOF
    
    # Initialize Markdown log
    cat > "$MD_LOG" <<EOF
# Build Log: $job_id

**Server**: $SERVER_ID  
**Branch**: $branch  
**Commit**: $commit  
**Started**: $(date -u +%Y-%m-%dT%H:%M:%SZ)

---

EOF
    
    echo "$LOG_ID"
}

# Log an event (both JSON and Markdown)
log_event() {
    local log_id="$1"
    local level="$2"  # info, warning, error, success
    local message="$3"
    local details="${4:-}"
    
    local json_log="$LOG_DIR/${log_id}.json"
    local md_log="$LOG_DIR/${log_id}.md"
    
    if [ ! -f "$json_log" ]; then
        echo "Error: Log not initialized: $log_id"
        return 1
    fi
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Add to JSON log
    local temp_file=$(mktemp)
    jq --arg ts "$timestamp" \
       --arg lvl "$level" \
       --arg msg "$message" \
       --arg det "$details" \
       '.events += [{
           "timestamp": $ts,
           "level": $lvl,
           "message": $msg,
           "details": $det
       }]' "$json_log" > "$temp_file"
    mv "$temp_file" "$json_log"
    
    # Add to Markdown log
    local emoji
    case "$level" in
        info) emoji="[i]" ;;
        warning) emoji="[!]" ;;
        error) emoji="[X]" ;;
        success) emoji="[OK]" ;;
        *) emoji="[*]" ;;
    esac
    
    cat >> "$md_log" <<EOF
## $emoji $level: $message

**Time**: $timestamp

EOF
    
    if [ -n "$details" ]; then
        cat >> "$md_log" <<EOF
\`\`\`
$details
\`\`\`

EOF
    fi
}

# Log command execution (captures output and exit code)
log_command() {
    local log_id="$1"
    local command_name="$2"
    shift 2
    local command=("$@")
    
    log_event "$log_id" "info" "Executing: $command_name"
    
    local output_file=$(mktemp)
    local start_time=$(date +%s)
    
    # Execute command and capture output
    set +e
    "${command[@]}" > "$output_file" 2>&1
    local exit_code=$?
    set -e
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    local output=$(cat "$output_file")
    rm "$output_file"
    
    # Truncate very long output
    if [ ${#output} -gt 10000 ]; then
        output="${output:0:5000}
... (output truncated, ${#output} bytes total) ...
${output: -5000}"
    fi
    
    if [ $exit_code -eq 0 ]; then
        log_event "$log_id" "success" "$command_name completed (${duration}s)" "$output"
    else
        log_event "$log_id" "error" "$command_name failed with exit code $exit_code (${duration}s)" "$output"
    fi
    
    return $exit_code
}

# Finalize log (mark as complete or failed)
finalize_log() {
    local log_id="$1"
    local status="$2"  # success or failed
    local exit_code="${3:-0}"
    
    local json_log="$LOG_DIR/${log_id}.json"
    local md_log="$LOG_DIR/${log_id}.md"
    
    if [ ! -f "$json_log" ]; then
        echo "Error: Log not found: $log_id"
        return 1
    fi
    
    local completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local started_at=$(jq -r '.started_at' "$json_log")
    
    # Calculate duration
    local start_epoch=$(date -d "$started_at" +%s)
    local end_epoch=$(date +%s)
    local duration=$((end_epoch - start_epoch))
    
    # Update JSON log
    local temp_file=$(mktemp)
    jq --arg status "$status" \
       --arg completed "$completed_at" \
       --argjson exit_code "$exit_code" \
       --argjson duration "$duration" \
       '.status = $status |
        .completed_at = $completed |
        .exit_code = $exit_code |
        .duration_seconds = $duration' \
       "$json_log" > "$temp_file"
    mv "$temp_file" "$json_log"
    
    # Finalize Markdown log
    cat >> "$md_log" <<EOF

---

**Status**: $status  
**Exit Code**: $exit_code  
**Completed**: $completed_at  
**Duration**: ${duration}s ($(printf '%02d:%02d:%02d' $((duration/3600)) $((duration%3600/60)) $((duration%60))))
EOF
}

# Export functions for use in other scripts
export -f init_log log_event log_command finalize_log

# CLI interface
case "${1:-help}" in
    init)
        init_log "$2" "$3" "$4"
        ;;
    event)
        log_event "$2" "$3" "$4" "$5"
        ;;
    finalize)
        finalize_log "$2" "$3" "$4"
        ;;
    help|*)
        cat <<EOF
Structured Logging Helper

Usage:
  source $0                              Source functions in your script
  $0 init <job_id> <branch> <commit>   Initialize new log
  $0 event <log_id> <level> <message> [details]   Log an event
  $0 finalize <log_id> <status> [exit_code]       Finalize log

Functions (when sourced):
  init_log <job_id> <branch> <commit>
  log_event <log_id> <level> <message> [details]
  log_command <log_id> <command_name> <command...>
  finalize_log <log_id> <status> [exit_code]

Example:
  source $0
  LOG_ID=\$(init_log "job123" "main" "abc123")
  log_event "\$LOG_ID" "info" "Starting build"
  log_command "\$LOG_ID" "Maven clean" mvn clean
  finalize_log "\$LOG_ID" "success" 0

EOF
        ;;
esac
