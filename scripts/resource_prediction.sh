#!/bin/bash
# Resource Prediction System
# Track and predict build duration to optimize job assignment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

METRICS_FILE="$REPO_ROOT/shared/build_metrics.json"
PREDICTIONS_FILE="$REPO_ROOT/shared/predictions.json"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

# Initialize metrics storage
init_metrics() {
    if [ -f "$METRICS_FILE" ]; then
        return 0
    fi
    
    mkdir -p "$(dirname "$METRICS_FILE")"
    
    cat > "$METRICS_FILE" <<'EOF'
{
  "builds": [],
  "statistics": {
    "by_branch": {},
    "by_server": {},
    "by_hour": {},
    "by_day_of_week": {}
  }
}
EOF
    
    cd "$REPO_ROOT"
    git add "$METRICS_FILE"
    git commit -m "Initialize build metrics storage"
    git push origin main
    
    log "Metrics storage initialized"
}

# Record build metrics
record_build() {
    local job_id="$1"
    local server="$2"
    local branch="$3"
    local commit="$4"
    local duration="$5"
    local status="$6"
    local artifact_count="${7:-0}"
    local artifact_size="${8:-0}"
    
    if [ -z "$job_id" ] || [ -z "$duration" ]; then
        echo "Usage: $0 record <job_id> <server> <branch> <commit> <duration> <status> [artifact_count] [artifact_size]"
        return 1
    fi
    
    if [ ! -f "$METRICS_FILE" ]; then
        init_metrics
    fi
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local hour=$(date -u +%H)
    local day_of_week=$(date -u +%u)  # 1=Monday, 7=Sunday
    
    # Get commit stats if possible
    local files_changed=0
    local insertions=0
    local deletions=0
    
    if [ -f "$REPO_ROOT/build${server#build}/status.json" ]; then
        local repo_path=$(jq -r '.current_job.repo_path // empty' "$REPO_ROOT/build${server#build}/status.json")
        if [ -n "$repo_path" ] && [ -d "$repo_path" ]; then
            local stats=$(cd "$repo_path" && git show --stat --format="" "$commit" 2>/dev/null | tail -1)
            files_changed=$(echo "$stats" | awk '{print $1}' | grep -o '[0-9]*' | head -1)
            insertions=$(echo "$stats" | grep -o '[0-9]* insertion' | grep -o '[0-9]*')
            deletions=$(echo "$stats" | grep -o '[0-9]* deletion' | grep -o '[0-9]*')
        fi
    fi
    
    log "Recording build metrics for $job_id..."
    
    local temp_file=$(mktemp)
    jq --arg job_id "$job_id" \
       --arg server "$server" \
       --arg branch "$branch" \
       --arg commit "$commit" \
       --argjson duration "$duration" \
       --arg status "$status" \
       --arg timestamp "$timestamp" \
       --argjson hour "$hour" \
       --argjson day "$day_of_week" \
       --argjson files "${files_changed:-0}" \
       --argjson insertions "${insertions:-0}" \
       --argjson deletions "${deletions:-0}" \
       --argjson artifacts "$artifact_count" \
       --argjson size "$artifact_size" \
       '.builds += [{
           job_id: $job_id,
           server: $server,
           branch: $branch,
           commit: $commit,
           duration_seconds: $duration,
           status: $status,
           timestamp: $timestamp,
           hour_of_day: $hour,
           day_of_week: $day,
           commit_stats: {
               files_changed: $files,
               insertions: $insertions,
               deletions: $deletions
           },
           artifacts: {
               count: $artifacts,
               size_bytes: $size
           }
       }] | .builds = .builds[-1000:]' \
       "$METRICS_FILE" > "$temp_file"
    mv "$temp_file" "$METRICS_FILE"
    
    git add "$METRICS_FILE"
    git commit -m "Record build metrics: $job_id [$server]"
    git push origin main --quiet
    
    log "Build metrics recorded"
    
    # Update statistics
    update_statistics
}

# Update aggregated statistics
update_statistics() {
    if [ ! -f "$METRICS_FILE" ]; then
        return 0
    fi
    
    log "Updating build statistics..."
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    local temp_file=$(mktemp)
    
    # Calculate statistics using jq
    jq '.statistics.by_branch = (
            .builds | group_by(.branch) | 
            map({
                key: .[0].branch,
                value: {
                    count: length,
                    avg_duration: (map(.duration_seconds) | add / length),
                    min_duration: (map(.duration_seconds) | min),
                    max_duration: (map(.duration_seconds) | max),
                    success_rate: ((map(select(.status == "completed")) | length) * 100 / length)
                }
            }) | from_entries
        ) |
        .statistics.by_server = (
            .builds | group_by(.server) |
            map({
                key: .[0].server,
                value: {
                    count: length,
                    avg_duration: (map(.duration_seconds) | add / length),
                    success_rate: ((map(select(.status == "completed")) | length) * 100 / length)
                }
            }) | from_entries
        ) |
        .statistics.by_hour = (
            .builds | group_by(.hour_of_day) |
            map({
                key: (.[0].hour_of_day | tostring),
                value: {
                    count: length,
                    avg_duration: (map(.duration_seconds) | add / length)
                }
            }) | from_entries
        ) |
        .statistics.by_day_of_week = (
            .builds | group_by(.day_of_week) |
            map({
                key: (.[0].day_of_week | tostring),
                value: {
                    count: length,
                    avg_duration: (map(.duration_seconds) | add / length)
                }
            }) | from_entries
        )' "$METRICS_FILE" > "$temp_file"
    
    mv "$temp_file" "$METRICS_FILE"
    
    git add "$METRICS_FILE"
    git commit -m "Update build statistics"
    git push origin main --quiet
    
    log "Statistics updated"
}

# Predict build duration
predict_duration() {
    local branch="$1"
    local server="${2:-}"
    
    if [ -z "$branch" ]; then
        echo "Usage: $0 predict <branch> [server]"
        return 1
    fi
    
    if [ ! -f "$METRICS_FILE" ]; then
        echo "No metrics available"
        return 1
    fi
    
    local hour=$(date -u +%H)
    local day=$(date -u +%u)
    
    log "Predicting build duration for branch: $branch"
    
    # Get average duration for this branch
    local branch_avg=$(jq -r --arg branch "$branch" \
                          '.statistics.by_branch[$branch].avg_duration // 0' \
                          "$METRICS_FILE")
    
    if [ "$branch_avg" = "0" ] || [ "$branch_avg" = "null" ]; then
        log "No historical data for branch: $branch"
        echo "No prediction available"
        return 1
    fi
    
    # Get time-of-day factor
    local hour_avg=$(jq -r --arg hour "$hour" \
                        '.statistics.by_hour[$hour].avg_duration // 0' \
                        "$METRICS_FILE")
    
    local overall_avg=$(jq -r '[.builds[].duration_seconds] | add / length' "$METRICS_FILE")
    
    local time_factor=1.0
    if [ "$hour_avg" != "0" ] && [ "$hour_avg" != "null" ] && [ "$overall_avg" != "0" ]; then
        time_factor=$(echo "scale=2; $hour_avg / $overall_avg" | bc)
    fi
    
    # Adjust prediction based on time of day
    local predicted=$(echo "scale=0; $branch_avg * $time_factor / 1" | bc)
    
    log "  Branch average: ${branch_avg}s"
    log "  Time of day factor: $time_factor"
    log "  Predicted duration: ${predicted}s ($(printf '%02d:%02d:%02d' $((predicted/3600)) $((predicted%3600/60)) $((predicted%60))))"
    
    echo "$predicted"
}

# Recommend best server for a job
recommend_server() {
    local branch="$1"
    
    if [ -z "$branch" ]; then
        echo "Usage: $0 recommend <branch>"
        return 1
    fi
    
    if [ ! -f "$METRICS_FILE" ]; then
        echo "build1"  # Default
        return 0
    fi
    
    log "Recommending server for branch: $branch"
    
    # Get performance stats for each server on this branch
    local servers=$(jq -r '[.builds[] | select(.branch == "'$branch'") | .server] | unique[]' "$METRICS_FILE")
    
    if [ -z "$servers" ]; then
        log "No historical data, recommending build1"
        echo "build1"
        return 0
    fi
    
    local best_server=""
    local best_time=999999
    
    while IFS= read -r server; do
        if [ -z "$server" ]; then continue; fi
        
        local avg_duration=$(jq -r --arg server "$server" --arg branch "$branch" \
                               '[.builds[] | select(.server == $server and .branch == $branch) | .duration_seconds] | add / length' \
                               "$METRICS_FILE")
        
        if [ "$avg_duration" != "null" ]; then
            log "  $server: ${avg_duration}s average"
            
            if [ $(echo "$avg_duration < $best_time" | bc) -eq 1 ]; then
                best_time=$avg_duration
                best_server=$server
            fi
        fi
    done <<< "$servers"
    
    if [ -z "$best_server" ]; then
        best_server="build1"
    fi
    
    log "Recommended server: $best_server (avg: ${best_time}s)"
    echo "$best_server"
}

# Show statistics
show_stats() {
    if [ ! -f "$METRICS_FILE" ]; then
        log "No metrics available"
        return 1
    fi
    
    echo "=== Build Metrics Statistics ==="
    echo ""
    
    local total_builds=$(jq -r '.builds | length' "$METRICS_FILE")
    echo "Total builds recorded: $total_builds"
    echo ""
    
    echo "--- By Branch ---"
    jq -r '.statistics.by_branch | to_entries[] | "  \(.key):\n    Builds: \(.value.count)\n    Avg Duration: \(.value.avg_duration | floor)s\n    Success Rate: \(.value.success_rate | floor)%\n"' "$METRICS_FILE"
    
    echo "--- By Server ---"
    jq -r '.statistics.by_server | to_entries[] | "  \(.key):\n    Builds: \(.value.count)\n    Avg Duration: \(.value.avg_duration | floor)s\n    Success Rate: \(.value.success_rate | floor)%\n"' "$METRICS_FILE"
    
    echo "--- By Hour of Day (UTC) ---"
    jq -r '.statistics.by_hour | to_entries | sort_by(.key | tonumber) | .[] | "  \(.key):00 - Avg: \(.value.avg_duration | floor)s (\(.value.count) builds)"' "$METRICS_FILE"
}

# Main command dispatcher
case "${1:-help}" in
    init)
        init_metrics
        ;;
    record)
        record_build "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
        ;;
    update-stats)
        update_statistics
        ;;
    predict)
        predict_duration "$2" "$3"
        ;;
    recommend)
        recommend_server "$2"
        ;;
    stats)
        show_stats
        ;;
    help|*)
        cat <<EOF
Resource Prediction System

Usage:
  $0 init                                                              Initialize metrics storage
  $0 record <job_id> <server> <branch> <commit> <duration> <status> [artifacts] [size]
  $0 update-stats                                                      Update aggregated statistics
  $0 predict <branch> [server]                                        Predict build duration
  $0 recommend <branch>                                                Recommend best server
  $0 stats                                                             Show statistics

Examples:
  # Record a build
  $0 record job_123 build1 main abc123 1234 completed 5 104857600
  
  # Predict duration
  $0 predict main
  
  # Recommend server
  $0 recommend ExternalNew
  
  # Show statistics
  $0 stats

Notes:
  - Metrics are stored in shared/build_metrics.json
  - Predictions use historical data and time-of-day factors
  - Server recommendations are based on past performance
  - Statistics are automatically updated after each recording
  - Keeps last 1000 builds to avoid file growth

Integration:
  Call 'record' at the end of each build to track metrics
  Use 'recommend' when assigning jobs to servers
  Use 'predict' for scheduling and capacity planning

EOF
        ;;
esac
