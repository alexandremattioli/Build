#!/bin/bash
# Artifact Management System
# Creates manifests with checksums and manages artifact lifecycle

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SERVER_ID=${SERVER_ID:-$(bash "$SCRIPT_DIR/server_id.sh" 2>/dev/null || echo "unknown")}
ARTIFACTS_DIR="/root/artifacts/$(hostname)"
KEEP_BUILDS=${KEEP_BUILDS:-5}  # Keep last N builds

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

# Create artifact manifest with checksums
create_manifest() {
    local build_dir="$1"
    local job_id="$2"
    local branch="$3"
    local commit="$4"
    
    if [ ! -d "$build_dir" ]; then
        log "Error: Build directory not found: $build_dir"
        return 1
    fi
    
    local manifest_file="$build_dir/manifest.json"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    log "Creating artifact manifest for $build_dir..."
    
    # Initialize manifest
    cat > "$manifest_file" <<EOF
{
  "job_id": "$job_id",
  "server": "$SERVER_ID",
  "branch": "$branch",
  "commit": "$commit",
  "created_at": "$timestamp",
  "build_dir": "$build_dir",
  "artifacts": []
}
EOF
    
    # Find all artifact files (DEBs, RPMs, etc.)
    local artifacts=()
    
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")
            local md5sum=$(md5sum "$file" | awk '{print $1}')
            local sha256sum=$(sha256sum "$file" | awk '{print $1}')
            local sha512sum=$(sha512sum "$file" | awk '{print $1}')
            
            local artifact_json=$(jq -n \
                --arg name "$filename" \
                --arg path "$file" \
                --argjson size "$size" \
                --arg md5 "$md5sum" \
                --arg sha256 "$sha256sum" \
                --arg sha512 "$sha512sum" \
                '{
                    name: $name,
                    path: $path,
                    size_bytes: $size,
                    checksums: {
                        md5: $md5,
                        sha256: $sha256,
                        sha512: $sha512
                    }
                }')
            
            artifacts+=("$artifact_json")
            log "  Added: $filename ($(numfmt --to=iec-i --suffix=B $size))"
        fi
    done < <(find "$build_dir" -type f \( -name "*.deb" -o -name "*.rpm" -o -name "*.tar.gz" -o -name "*.war" \))
    
    # Add artifacts to manifest
    local temp_file=$(mktemp)
    local artifacts_json=$(printf '%s\n' "${artifacts[@]}" | jq -s '.')
    
    jq --argjson artifacts "$artifacts_json" \
       '.artifacts = $artifacts |
        .artifact_count = ($artifacts | length) |
        .total_size_bytes = ([$artifacts[].size_bytes] | add)' \
       "$manifest_file" > "$temp_file"
    mv "$temp_file" "$manifest_file"
    
    log "Manifest created: $manifest_file"
    log "  Artifacts: $(jq -r '.artifact_count' "$manifest_file")"
    log "  Total size: $(numfmt --to=iec-i --suffix=B $(jq -r '.total_size_bytes' "$manifest_file"))"
    
    echo "$manifest_file"
}

# Verify artifacts against manifest
verify_artifacts() {
    local manifest_file="$1"
    
    if [ ! -f "$manifest_file" ]; then
        log "Error: Manifest not found: $manifest_file"
        return 1
    fi
    
    log "Verifying artifacts from $manifest_file..."
    
    local artifacts=$(jq -r '.artifacts[] | @json' "$manifest_file")
    local failed=0
    local verified=0
    
    while IFS= read -r artifact; do
        local path=$(echo "$artifact" | jq -r '.path')
        local name=$(echo "$artifact" | jq -r '.name')
        local expected_sha256=$(echo "$artifact" | jq -r '.checksums.sha256')
        
        if [ ! -f "$path" ]; then
            log "  [X] MISSING: $name"
            failed=$((failed + 1))
            continue
        fi
        
        local actual_sha256=$(sha256sum "$path" | awk '{print $1}')
        
        if [ "$actual_sha256" = "$expected_sha256" ]; then
            log "  [OK] OK: $name"
            verified=$((verified + 1))
        else
            log "  [X] CHECKSUM MISMATCH: $name"
            log "     Expected: $expected_sha256"
            log "     Got:      $actual_sha256"
            failed=$((failed + 1))
        fi
    done <<< "$artifacts"
    
    log "Verification complete: $verified verified, $failed failed"
    
    return $failed
}

# List all builds
list_builds() {
    local artifact_type="${1:-debs}"  # debs, rpms, etc.
    local builds_dir="$ARTIFACTS_DIR/$artifact_type"
    
    if [ ! -d "$builds_dir" ]; then
        log "No builds found in $builds_dir"
        return 0
    fi
    
    log "Builds in $builds_dir:"
    
    find "$builds_dir" -maxdepth 1 -type d -name "*T*" | sort -r | while read -r build_dir; do
        local manifest="$build_dir/manifest.json"
        if [ -f "$manifest" ]; then
            local timestamp=$(basename "$build_dir")
            local job_id=$(jq -r '.job_id' "$manifest")
            local branch=$(jq -r '.branch' "$manifest")
            local count=$(jq -r '.artifact_count' "$manifest")
            local size=$(jq -r '.total_size_bytes' "$manifest")
            
            echo "  $timestamp - $job_id - $branch - $count artifacts ($(numfmt --to=iec-i --suffix=B $size))"
        else
            echo "  $(basename "$build_dir") - No manifest"
        fi
    done
}

# Cleanup old builds
cleanup_old_builds() {
    local artifact_type="${1:-debs}"
    local keep="${2:-$KEEP_BUILDS}"
    
    local builds_dir="$ARTIFACTS_DIR/$artifact_type"
    
    if [ ! -d "$builds_dir" ]; then
        log "No builds directory found: $builds_dir"
        return 0
    fi
    
    log "Cleaning up old builds (keeping last $keep)..."
    
    # Get all build directories sorted by timestamp (newest first)
    local builds=($(find "$builds_dir" -maxdepth 1 -type d -name "*T*" | sort -r))
    local total=${#builds[@]}
    
    if [ $total -le $keep ]; then
        log "Only $total builds found, nothing to cleanup"
        return 0
    fi
    
    local to_remove=$((total - keep))
    log "Found $total builds, removing oldest $to_remove..."
    
    local removed=0
    local freed=0
    
    for ((i=keep; i<total; i++)); do
        local build_dir="${builds[$i]}"
        local manifest="$build_dir/manifest.json"
        
        if [ -f "$manifest" ]; then
            local size=$(jq -r '.total_size_bytes' "$manifest")
            freed=$((freed + size))
        fi
        
        log "  Removing: $(basename "$build_dir")"
        rm -rf "$build_dir"
        removed=$((removed + 1))
    done
    
    log "Cleanup complete: removed $removed builds, freed $(numfmt --to=iec-i --suffix=B $freed)"
}

# Export artifact manifest to git
export_manifest() {
    local manifest_file="$1"
    
    if [ ! -f "$manifest_file" ]; then
        log "Error: Manifest not found: $manifest_file"
        return 1
    fi
    
    local job_id=$(jq -r '.job_id' "$manifest_file")
    local export_dir="$REPO_ROOT/build${SERVER_ID#build}/artifacts"
    
    mkdir -p "$export_dir"
    
    cp "$manifest_file" "$export_dir/${job_id}_manifest.json"
    
    cd "$REPO_ROOT"
    git add "$export_dir/${job_id}_manifest.json"
    git commit -m "Export artifact manifest for $job_id [$SERVER_ID]"
    git push origin main --quiet
    
    log "Manifest exported to git: $export_dir/${job_id}_manifest.json"
}

# Main command dispatcher
case "${1:-help}" in
    create-manifest)
        create_manifest "$2" "$3" "$4" "$5"
        ;;
    verify)
        verify_artifacts "$2"
        ;;
    list)
        list_builds "$2"
        ;;
    cleanup)
        cleanup_old_builds "$2" "$3"
        ;;
    export)
        export_manifest "$2"
        ;;
    help|*)
        cat <<EOF
Artifact Management System

Usage:
  $0 create-manifest <build_dir> <job_id> <branch> <commit>   Create manifest with checksums
  $0 verify <manifest_file>                                    Verify artifacts against manifest
  $0 list [type]                                               List all builds (default: debs)
  $0 cleanup [type] [keep]                                     Remove old builds (default: keep $KEEP_BUILDS)
  $0 export <manifest_file>                                    Export manifest to git repo

Environment Variables:
  KEEP_BUILDS        Number of builds to keep during cleanup (default: 5)

Examples:
  $0 create-manifest /root/artifacts/ll-ACSBuilder1/debs/20251103T120000Z job_123 main abc123
  $0 verify /root/artifacts/ll-ACSBuilder1/debs/20251103T120000Z/manifest.json
  $0 list debs
  $0 cleanup debs 3
  $0 export /root/artifacts/ll-ACSBuilder1/debs/20251103T120000Z/manifest.json

EOF
        ;;
esac
