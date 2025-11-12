#!/bin/bash
# Build Rollback Mechanism
# Tag successful builds and provide quick rollback capability

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

# Tag a successful build
tag_successful_build() {
    local job_id="$1"
    local branch="$2"
    local commit="$3"
    local manifest_file="$4"
    
    if [ -z "$job_id" ] || [ -z "$branch" ] || [ -z "$commit" ]; then
        echo "Usage: $0 tag <job_id> <branch> <commit> [manifest_file]"
        return 1
    fi
    
    cd "$REPO_ROOT"
    
    local tag_name="build-success-${branch//\//-}-$(date -u +%Y%m%dT%H%M%SZ)"
    local tag_message="Successful build: $job_id
Branch: $branch
Commit: $commit
Job ID: $job_id"
    
    if [ -n "$manifest_file" ] && [ -f "$manifest_file" ]; then
        local artifact_count=$(jq -r '.artifact_count' "$manifest_file")
        tag_message="$tag_message
Artifacts: $artifact_count"
    fi
    
    # Create annotated tag
    git tag -a "$tag_name" -m "$tag_message"
    git push origin "$tag_name"
    
    log "Created tag: $tag_name"
    
    # Update success marker file
    local success_file="$REPO_ROOT/shared/last_successful_builds.json"
    
    if [ ! -f "$success_file" ]; then
        echo '{"builds":{}}' > "$success_file"
    fi
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local temp_file=$(mktemp)
    
    jq --arg branch "$branch" \
       --arg tag "$tag_name" \
       --arg commit "$commit" \
       --arg job_id "$job_id" \
       --arg timestamp "$timestamp" \
       '.builds[$branch] = {
           tag: $tag,
           commit: $commit,
           job_id: $job_id,
           timestamp: $timestamp
       }' "$success_file" > "$temp_file"
    mv "$temp_file" "$success_file"
    
    git add "$success_file"
    git commit -m "Record successful build: $tag_name"
    git push origin main
    
    log "Updated last successful builds registry"
}

# List available rollback points
list_rollback_points() {
    local branch="$1"
    
    cd "$REPO_ROOT"
    
    if [ -n "$branch" ]; then
        log "Successful builds for branch: $branch"
        git tag -l "build-success-${branch//\//-}-*" --sort=-creatordate | head -20
    else
        log "All successful builds (last 20):"
        git tag -l "build-success-*" --sort=-creatordate | head -20
    fi
}

# Show details for a tagged build
show_build_details() {
    local tag_name="$1"
    
    if [ -z "$tag_name" ]; then
        echo "Usage: $0 show <tag_name>"
        return 1
    fi
    
    cd "$REPO_ROOT"
    
    log "Build details for: $tag_name"
    echo ""
    
    # Show tag annotation
    git tag -n99 "$tag_name"
    echo ""
    
    # Show commit
    local commit=$(git rev-list -n 1 "$tag_name")
    echo "Tagged Commit:"
    git show --stat "$commit"
}

# Get last known good build for a branch
get_last_good_build() {
    local branch="$1"
    
    if [ -z "$branch" ]; then
        echo "Usage: $0 last-good <branch>"
        return 1
    fi
    
    local success_file="$REPO_ROOT/shared/last_successful_builds.json"
    
    if [ ! -f "$success_file" ]; then
        log "No successful builds recorded"
        return 1
    fi
    
    local build_info=$(jq -r --arg branch "$branch" '.builds[$branch]' "$success_file")
    
    if [ "$build_info" = "null" ]; then
        log "No successful build found for branch: $branch"
        return 1
    fi
    
    echo "$build_info" | jq .
}

# Rollback to a specific tag
rollback_to_tag() {
    local tag_name="$1"
    local target_repo="${2:-/root/cloudstack}"
    
    if [ -z "$tag_name" ]; then
        echo "Usage: $0 rollback <tag_name> [target_repo]"
        return 1
    fi
    
    if [ ! -d "$target_repo" ]; then
        log "Error: Target repository not found: $target_repo"
        return 1
    fi
    
    cd "$REPO_ROOT"
    
    # Get commit from tag
    local commit=$(git rev-list -n 1 "$tag_name" 2>/dev/null)
    
    if [ -z "$commit" ]; then
        log "Error: Tag not found: $tag_name"
        return 1
    fi
    
    log "Rolling back to: $tag_name"
    log "  Commit: $commit"
    
    # Extract branch and commit from tag message
    local tag_message=$(git tag -n99 "$tag_name")
    local source_commit=$(echo "$tag_message" | grep "^Commit:" | awk '{print $2}')
    local source_branch=$(echo "$tag_message" | grep "^Branch:" | awk '{print $2}')
    
    if [ -z "$source_commit" ]; then
        log "Error: Could not extract commit information from tag"
        return 1
    fi
    
    log "  Source Branch: $source_branch"
    log "  Source Commit: $source_commit"
    
    # Perform rollback in target repo
    cd "$target_repo"
    
    log "Current branch: $(git branch --show-current)"
    
    # Create rollback branch
    local rollback_branch="rollback-$(date -u +%Y%m%dT%H%M%SZ)"
    
    git fetch origin "$source_branch" || log "Warning: Could not fetch $source_branch"
    git checkout -b "$rollback_branch" "$source_commit"
    
    log "[OK] Rolled back to commit: $source_commit"
    log "   New branch: $rollback_branch"
    log ""
    log "To switch back to $source_branch: git checkout $source_branch"
    log "To apply rollback to $source_branch: git checkout $source_branch && git merge $rollback_branch"
}

# Cleanup old success tags
cleanup_old_tags() {
    local keep="${1:-20}"
    local branch="$2"
    
    cd "$REPO_ROOT"
    
    log "Cleaning up old success tags (keeping last $keep)..."
    
    local pattern="build-success-"
    if [ -n "$branch" ]; then
        pattern="build-success-${branch//\//-}-"
    fi
    
    local tags=$(git tag -l "${pattern}*" --sort=-creatordate)
    local total=$(echo "$tags" | wc -l)
    
    if [ $total -le $keep ]; then
        log "Only $total tags found, nothing to cleanup"
        return 0
    fi
    
    local to_remove=$(echo "$tags" | tail -n +$((keep + 1)))
    local count=0
    
    while IFS= read -r tag; do
        if [ -n "$tag" ]; then
            log "  Removing tag: $tag"
            git tag -d "$tag"
            git push origin ":refs/tags/$tag" 2>/dev/null || true
            count=$((count + 1))
        fi
    done <<< "$to_remove"
    
    log "Cleanup complete: removed $count tags"
}

# Main command dispatcher
case "${1:-help}" in
    tag)
        tag_successful_build "$2" "$3" "$4" "$5"
        ;;
    list)
        list_rollback_points "$2"
        ;;
    show)
        show_build_details "$2"
        ;;
    last-good)
        get_last_good_build "$2"
        ;;
    rollback)
        rollback_to_tag "$2" "$3"
        ;;
    cleanup)
        cleanup_old_tags "$2" "$3"
        ;;
    help|*)
        cat <<EOF
Build Rollback Mechanism

Usage:
  $0 tag <job_id> <branch> <commit> [manifest]     Tag a successful build
  $0 list [branch]                                  List available rollback points
  $0 show <tag_name>                                Show details for a tagged build
  $0 last-good <branch>                             Get last known good build for branch
  $0 rollback <tag_name> [target_repo]             Rollback to a specific tag
  $0 cleanup [keep] [branch]                        Remove old tags (default: keep 20)

Examples:
  # Tag a successful build
  $0 tag job_12345 main abc123def /path/to/manifest.json
  
  # List rollback points for main branch
  $0 list main
  
  # Show details of a specific build
  $0 show build-success-main-20251103T120000Z
  
  # Get last good build
  $0 last-good main
  
  # Rollback to a specific tag
  $0 rollback build-success-main-20251103T120000Z /root/cloudstack
  
  # Cleanup old tags (keep last 10)
  $0 cleanup 10

Notes:
  - Tags are created as annotated git tags with build metadata
  - Rollback creates a new branch to avoid disrupting current work
  - Last successful builds are tracked in shared/last_successful_builds.json
  - Use 'git tag -d <tag>' to manually delete a tag if needed

EOF
        ;;
esac
