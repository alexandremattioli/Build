#!/bin/bash
# Health Dashboard Metrics Updater
# Aggregates metrics from build servers and updates shared dashboard

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD_FILE="$REPO_ROOT/shared/health_dashboard.json"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

update_metrics() {
    log "Updating health dashboard metrics..."
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Initialize dashboard if it doesn't exist
    if [ ! -f "$DASHBOARD_FILE" ]; then
        mkdir -p "$(dirname "$DASHBOARD_FILE")"
        echo '{"servers":[],"aggregate":{},"history":[],"updated_at":null}' > "$DASHBOARD_FILE"
    fi
    
    # Collect server data
    local servers=()
    local total_builds=0
    local successful_builds=0
    local failed_builds=0
    local total_duration=0
    local build_count=0
    local servers_online=0
    local total_cpu=0
    local total_memory=0
    local server_count=0
    
    for server in build1 build2 build3 build4; do
        local status_file="$REPO_ROOT/${server}/status.json"
        local heartbeat_file="$REPO_ROOT/${server}/heartbeat.json"
        
        if [ ! -f "$status_file" ]; then
            continue
        fi
        
        server_count=$((server_count + 1))
        
        # Read server data
        local status=$(jq -r '.status' "$status_file" 2>/dev/null || echo "unknown")
        local ip=$(jq -r '.ip' "$status_file" 2>/dev/null || echo "N/A")
        local manager=$(jq -r '.manager' "$status_file" 2>/dev/null || echo "N/A")
        local cpu=$(jq -r '.system.cpu_usage' "$status_file" 2>/dev/null || echo "0")
        local memory=$(jq -r '.system.memory_used_gb' "$status_file" 2>/dev/null || echo "0")
        local disk=$(jq -r '.system.disk_free_gb' "$status_file" 2>/dev/null || echo "0")
        
        # Check heartbeat
        local healthy=false
        if [ -f "$heartbeat_file" ]; then
            local hb_timestamp=$(jq -r '.timestamp' "$heartbeat_file" 2>/dev/null)
            local hb_epoch=$(date -d "$hb_timestamp" +%s 2>/dev/null || echo 0)
            local now_epoch=$(date +%s)
            local age=$((now_epoch - hb_epoch))
            
            if [ $age -lt 300 ]; then  # Less than 5 minutes
                healthy=true
                servers_online=$((servers_online + 1))
            fi
        fi
        
        # Aggregate CPU and memory
        if [ "$cpu" != "null" ] && [ "$cpu" != "0" ]; then
            total_cpu=$(echo "$total_cpu + $cpu" | bc)
        fi
        if [ "$memory" != "null" ] && [ "$memory" != "0" ]; then
            total_memory=$(echo "$total_memory + $memory" | bc)
        fi
        
        # Count builds
        local last_build_status=$(jq -r '.last_build.status' "$status_file" 2>/dev/null || echo "null")
        if [ "$last_build_status" != "null" ]; then
            total_builds=$((total_builds + 1))
            
            if [ "$last_build_status" = "success" ]; then
                successful_builds=$((successful_builds + 1))
            elif [ "$last_build_status" = "failed" ]; then
                failed_builds=$((failed_builds + 1))
            fi
            
            local duration=$(jq -r '.last_build.duration_seconds' "$status_file" 2>/dev/null || echo "0")
            if [ "$duration" != "null" ] && [ "$duration" -gt 0 ]; then
                total_duration=$((total_duration + duration))
                build_count=$((build_count + 1))
            fi
        fi
        
        # Add server to array
        servers+=("$(jq -n \
            --arg server "$server" \
            --arg status "$status" \
            --arg ip "$ip" \
            --arg manager "$manager" \
            --argjson cpu "$cpu" \
            --argjson memory "$memory" \
            --argjson disk "$disk" \
            --argjson healthy "$healthy" \
            '{
                server: $server,
                status: $status,
                ip: $ip,
                manager: $manager,
                healthy: $healthy,
                metrics: {
                    cpu_usage: $cpu,
                    memory_used_gb: $memory,
                    disk_free_gb: $disk
                }
            }')")
    done
    
    # Calculate aggregates
    local success_rate=0
    if [ $total_builds -gt 0 ]; then
        success_rate=$(echo "scale=2; $successful_builds * 100 / $total_builds" | bc)
    fi
    
    local avg_build_time=0
    if [ $build_count -gt 0 ]; then
        avg_build_time=$((total_duration / build_count))
    fi
    
    local avg_cpu=0
    if [ $server_count -gt 0 ] && [ "$total_cpu" != "0" ]; then
        avg_cpu=$(echo "scale=2; $total_cpu / $server_count" | bc)
    fi
    
    local avg_memory=0
    if [ $server_count -gt 0 ] && [ "$total_memory" != "0" ]; then
        avg_memory=$(echo "scale=2; $total_memory / $server_count" | bc)
    fi
    
    # Count queued jobs
    local queued_jobs=0
    local running_jobs=0
    if [ -f "$REPO_ROOT/coordination/jobs.json" ]; then
        queued_jobs=$(jq '[.jobs[] | select(.status == "queued")] | length' "$REPO_ROOT/coordination/jobs.json")
        running_jobs=$(jq '[.jobs[] | select(.status == "running")] | length' "$REPO_ROOT/coordination/jobs.json")
    fi
    
    # Create servers array JSON
    local servers_json=$(printf '%s\n' "${servers[@]}" | jq -s '.')
    
    # Update dashboard
    local temp_file=$(mktemp)
    jq --argjson servers "$servers_json" \
       --arg timestamp "$timestamp" \
       --argjson total_builds "$total_builds" \
       --argjson successful_builds "$successful_builds" \
       --argjson failed_builds "$failed_builds" \
       --argjson success_rate "$success_rate" \
       --argjson avg_build_time "$avg_build_time" \
       --argjson servers_online "$servers_online" \
       --argjson server_count "$server_count" \
       --argjson avg_cpu "$avg_cpu" \
       --argjson avg_memory "$avg_memory" \
       --argjson queued_jobs "$queued_jobs" \
       --argjson running_jobs "$running_jobs" \
       '.servers = $servers |
        .aggregate = {
            total_builds: $total_builds,
            successful_builds: $successful_builds,
            failed_builds: $failed_builds,
            success_rate: $success_rate,
            avg_build_time_seconds: $avg_build_time,
            servers_online: $servers_online,
            servers_total: $server_count,
            avg_cpu_usage: $avg_cpu,
            avg_memory_gb: $avg_memory,
            queued_jobs: $queued_jobs,
            running_jobs: $running_jobs
        } |
        .updated_at = $timestamp |
        .history += [{
            timestamp: $timestamp,
            servers_online: $servers_online,
            success_rate: $success_rate,
            avg_cpu: $avg_cpu,
            queued_jobs: $queued_jobs
        }] |
        .history = .history[-100:]' \
       "$DASHBOARD_FILE" > "$temp_file"
    mv "$temp_file" "$DASHBOARD_FILE"
    
    git add "$DASHBOARD_FILE"
    git commit -m "Update health dashboard metrics [$timestamp]"
    git push origin main --quiet
    
    log "Health dashboard updated successfully"
    log "  Servers online: $servers_online/$server_count"
    log "  Total builds: $total_builds (success rate: ${success_rate}%)"
    log "  Avg build time: ${avg_build_time}s"
    log "  Queue depth: $queued_jobs queued, $running_jobs running"
}

show_dashboard() {
    if [ ! -f "$DASHBOARD_FILE" ]; then
        echo "Dashboard not initialized"
        return 1
    fi
    
    echo "=== Build Coordination Health Dashboard ==="
    echo ""
    
    local updated_at=$(jq -r '.updated_at' "$DASHBOARD_FILE")
    echo "Last Updated: $updated_at"
    echo ""
    
    echo "--- Servers ---"
    jq -r '.servers[] | "\(.server) (\(.ip)): \(.status) - \(if .healthy then "[OK] Healthy" else "[X] Offline" end)"' "$DASHBOARD_FILE"
    echo ""
    
    echo "--- Aggregate Metrics ---"
    jq -r '.aggregate | "Total Builds: \(.total_builds) (\(.successful_builds) success, \(.failed_builds) failed)
Success Rate: \(.success_rate)%
Avg Build Time: \(.avg_build_time_seconds)s
Servers Online: \(.servers_online)/\(.servers_total)
Avg CPU Usage: \(.avg_cpu_usage)%
Avg Memory: \(.avg_memory_gb) GB
Job Queue: \(.queued_jobs) queued, \(.running_jobs) running"' "$DASHBOARD_FILE"
}

# Main command dispatcher
case "${1:-update}" in
    update)
        update_metrics
        ;;
    show)
        show_dashboard
        ;;
    help)
        cat <<EOF
Health Dashboard Metrics Updater

Usage:
  $0 update    Update dashboard with latest metrics (default)
  $0 show      Display current dashboard
  $0 help      Show this help

This script should be run periodically (e.g., every 5 minutes via cron) to keep
the dashboard updated with latest metrics from all build servers.

EOF
        ;;
    *)
        update_metrics
        ;;
esac
