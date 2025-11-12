#!/bin/bash
# Multi-Branch Build Support
# Manage builds for multiple CloudStack branches simultaneously

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BRANCHES_CONFIG="$REPO_ROOT/shared/branches_config.json"
CLOUDSTACK_REPO="${CLOUDSTACK_REPO:-/root/cloudstack}"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

# Initialize branches configuration
init_branches_config() {
    if [ -f "$BRANCHES_CONFIG" ]; then
        log "Branches config already exists: $BRANCHES_CONFIG"
        return 0
    fi
    
    mkdir -p "$(dirname "$BRANCHES_CONFIG")"
    
    cat > "$BRANCHES_CONFIG" <<'EOF'
{
  "branches": {
    "main": {
      "enabled": true,
      "priority": 1,
      "auto_build": true,
      "build_triggers": ["push", "schedule"],
      "schedule": "0 */6 * * *",
      "repo_path": "/root/cloudstack",
      "artifact_types": ["debs", "rpms"]
    },
    "ExternalNew": {
      "enabled": true,
      "priority": 2,
      "auto_build": true,
      "build_triggers": ["push"],
      "schedule": null,
      "repo_path": "/root/cloudstack_VNFCopilot",
      "artifact_types": ["debs"]
    }
  },
  "defaults": {
    "enabled": false,
    "priority": 5,
    "auto_build": false,
    "build_triggers": ["manual"],
    "artifact_types": ["debs"]
  }
}
EOF
    
    cd "$REPO_ROOT"
    git add "$BRANCHES_CONFIG"
    git commit -m "Initialize branches configuration"
    git push origin main
    
    log "Branches config initialized: $BRANCHES_CONFIG"
}

# Add a branch to configuration
add_branch() {
    local branch="$1"
    local repo_path="$2"
    local priority="${3:-5}"
    local auto_build="${4:-false}"
    
    if [ -z "$branch" ]; then
        echo "Usage: $0 add-branch <branch> <repo_path> [priority] [auto_build]"
        return 1
    fi
    
    if [ ! -f "$BRANCHES_CONFIG" ]; then
        init_branches_config
    fi
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    log "Adding branch: $branch"
    
    local temp_file=$(mktemp)
    jq --arg branch "$branch" \
       --arg repo "$repo_path" \
       --argjson priority "$priority" \
       --argjson auto "$auto_build" \
       '.branches[$branch] = {
           enabled: true,
           priority: $priority,
           auto_build: $auto,
           build_triggers: ["manual"],
           schedule: null,
           repo_path: $repo,
           artifact_types: ["debs"]
       }' "$BRANCHES_CONFIG" > "$temp_file"
    mv "$temp_file" "$BRANCHES_CONFIG"
    
    git add "$BRANCHES_CONFIG"
    git commit -m "Add branch configuration: $branch"
    git push origin main
    
    log "Branch $branch added to configuration"
}

# List configured branches
list_branches() {
    if [ ! -f "$BRANCHES_CONFIG" ]; then
        log "No branches configured"
        return 1
    fi
    
    log "Configured branches:"
    echo ""
    
    jq -r '.branches | to_entries[] | "\(.key):\n  Enabled: \(.value.enabled)\n  Priority: \(.value.priority)\n  Auto-build: \(.value.auto_build)\n  Repo: \(.value.repo_path)\n"' "$BRANCHES_CONFIG"
}

# Enable/disable a branch
toggle_branch() {
    local branch="$1"
    local enabled="$2"
    
    if [ -z "$branch" ] || [ -z "$enabled" ]; then
        echo "Usage: $0 toggle-branch <branch> <true|false>"
        return 1
    fi
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    local temp_file=$(mktemp)
    jq --arg branch "$branch" \
       --argjson enabled "$enabled" \
       '.branches[$branch].enabled = $enabled' \
       "$BRANCHES_CONFIG" > "$temp_file"
    mv "$temp_file" "$BRANCHES_CONFIG"
    
    git add "$BRANCHES_CONFIG"
    git commit -m "Toggle branch $branch: enabled=$enabled"
    git push origin main
    
    log "Branch $branch enabled=$enabled"
}

# Queue builds for all enabled branches
queue_all_enabled() {
    if [ ! -f "$BRANCHES_CONFIG" ]; then
        log "No branches configured"
        return 1
    fi
    
    log "Queuing builds for all enabled branches..."
    
    local branches=$(jq -r '.branches | to_entries[] | select(.value.enabled == true) | .key' "$BRANCHES_CONFIG")
    
    while IFS= read -r branch; do
        if [ -z "$branch" ]; then continue; fi
        
        local repo_path=$(jq -r --arg branch "$branch" '.branches[$branch].repo_path' "$BRANCHES_CONFIG")
        local priority=$(jq -r --arg branch "$branch" '.branches[$branch].priority' "$BRANCHES_CONFIG")
        
        if [ ! -d "$repo_path" ]; then
            log "[!]  Skipping $branch: repo not found at $repo_path"
            continue
        fi
        
        # Get latest commit
        local commit=$(cd "$repo_path" && git rev-parse HEAD)
        
        log "Queuing build for $branch (priority: $priority, commit: ${commit:0:7})"
        
        # Add job using job_queue.sh
        bash "$SCRIPT_DIR/job_queue.sh" add "$branch" "$commit" "$priority"
        
    done <<< "$branches"
    
    log "Build queueing complete"
}

# Check for updates in all branches
check_branch_updates() {
    if [ ! -f "$BRANCHES_CONFIG" ]; then
        log "No branches configured"
        return 1
    fi
    
    log "Checking for updates in configured branches..."
    
    local branches=$(jq -r '.branches | to_entries[] | select(.value.enabled == true and .value.auto_build == true) | .key' "$BRANCHES_CONFIG")
    
    while IFS= read -r branch; do
        if [ -z "$branch" ]; then continue; fi
        
        local repo_path=$(jq -r --arg branch "$branch" '.branches[$branch].repo_path' "$BRANCHES_CONFIG")
        
        if [ ! -d "$repo_path" ]; then
            log "[!]  Skipping $branch: repo not found at $repo_path"
            continue
        fi
        
        cd "$repo_path"
        
        # Fetch latest
        git fetch origin "$branch" --quiet 2>/dev/null || {
            log "[!]  Failed to fetch $branch"
            continue
        }
        
        local local_commit=$(git rev-parse HEAD)
        local remote_commit=$(git rev-parse "origin/$branch" 2>/dev/null || echo "")
        
        if [ -z "$remote_commit" ]; then
            log "[!]  Could not determine remote commit for $branch"
            continue
        fi
        
        if [ "$local_commit" != "$remote_commit" ]; then
            log "📢 Update detected in $branch: ${local_commit:0:7} -> ${remote_commit:0:7}"
            
            # Check if already queued
            local queued=$(jq -r --arg branch "$branch" --arg commit "$remote_commit" \
                          '[.jobs[] | select(.branch == $branch and .commit == $commit and .status == "queued")] | length' \
                          "$REPO_ROOT/coordination/jobs.json")
            
            if [ "$queued" -eq 0 ]; then
                local priority=$(jq -r --arg branch "$branch" '.branches[$branch].priority' "$BRANCHES_CONFIG")
                log "  Queueing build (priority: $priority)..."
                bash "$SCRIPT_DIR/job_queue.sh" add "$branch" "$remote_commit" "$priority"
            else
                log "  Build already queued"
            fi
        else
            log "[OK] $branch is up to date (${local_commit:0:7})"
        fi
        
    done <<< "$branches"
}

# Setup worktrees for each branch
setup_worktrees() {
    local base_repo="$1"
    local worktree_base="${2:-/root/cloudstack_worktrees}"
    
    if [ -z "$base_repo" ]; then
        echo "Usage: $0 setup-worktrees <base_repo> [worktree_base]"
        return 1
    fi
    
    if [ ! -d "$base_repo" ]; then
        log "Error: Base repository not found: $base_repo"
        return 1
    fi
    
    mkdir -p "$worktree_base"
    
    log "Setting up worktrees for configured branches..."
    
    local branches=$(jq -r '.branches | keys[]' "$BRANCHES_CONFIG")
    
    while IFS= read -r branch; do
        if [ -z "$branch" ]; then continue; fi
        
        local worktree_path="$worktree_base/${branch//\//_}"
        
        if [ -d "$worktree_path" ]; then
            log "[OK] Worktree already exists: $worktree_path"
            continue
        fi
        
        log "Creating worktree for $branch at $worktree_path..."
        
        cd "$base_repo"
        git worktree add "$worktree_path" "$branch" || {
            log "[!]  Failed to create worktree for $branch"
            continue
        }
        
        # Update branch config with worktree path
        local temp_file=$(mktemp)
        jq --arg branch "$branch" \
           --arg path "$worktree_path" \
           '.branches[$branch].repo_path = $path' \
           "$BRANCHES_CONFIG" > "$temp_file"
        mv "$temp_file" "$BRANCHES_CONFIG"
        
        log "[OK] Worktree created: $worktree_path"
        
    done <<< "$branches"
    
    cd "$REPO_ROOT"
    git add "$BRANCHES_CONFIG"
    git commit -m "Update branch configurations with worktree paths"
    git push origin main
    
    log "Worktree setup complete"
}

# Main command dispatcher
case "${1:-help}" in
    init)
        init_branches_config
        ;;
    add-branch)
        add_branch "$2" "$3" "$4" "$5"
        ;;
    list)
        list_branches
        ;;
    toggle)
        toggle_branch "$2" "$3"
        ;;
    queue-all)
        queue_all_enabled
        ;;
    check-updates)
        check_branch_updates
        ;;
    setup-worktrees)
        setup_worktrees "$2" "$3"
        ;;
    help|*)
        cat <<EOF
Multi-Branch Build Support

Usage:
  $0 init                                                    Initialize branches configuration
  $0 add-branch <branch> <repo_path> [priority] [auto]     Add branch to configuration
  $0 list                                                    List configured branches
  $0 toggle <branch> <true|false>                           Enable/disable a branch
  $0 queue-all                                               Queue builds for all enabled branches
  $0 check-updates                                           Check for updates and queue builds
  $0 setup-worktrees <base_repo> [worktree_base]           Setup git worktrees for all branches

Examples:
  # Initialize configuration
  $0 init
  
  # Add a branch
  $0 add-branch feature-x /root/cloudstack_feature_x 3 true
  
  # List branches
  $0 list
  
  # Disable a branch
  $0 toggle ExternalNew false
  
  # Queue all enabled branches
  $0 queue-all
  
  # Check for updates (run periodically)
  $0 check-updates
  
  # Setup worktrees for all branches
  $0 setup-worktrees /root/cloudstack /root/cloudstack_worktrees

Notes:
  - Branches are configured in shared/branches_config.json
  - Priority: 1 (highest) to 10 (lowest)
  - Auto-build: if true, builds are queued automatically on updates
  - Git worktrees allow multiple branches to be checked out simultaneously
  - Run 'check-updates' periodically (cron) for automatic builds

Cron Example (check every 15 minutes):
  */15 * * * * cd /root/Build/scripts && ./multi_branch.sh check-updates

EOF
        ;;
esac
