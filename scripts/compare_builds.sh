#!/bin/bash
# Build Comparison Tool
# Compare artifacts between build servers to verify reproducible builds

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

# Compare two manifests
compare_manifests() {
    local manifest1="$1"
    local manifest2="$2"
    
    if [ ! -f "$manifest1" ]; then
        log "Error: Manifest 1 not found: $manifest1"
        return 1
    fi
    
    if [ ! -f "$manifest2" ]; then
        log "Error: Manifest 2 not found: $manifest2"
        return 1
    fi
    
    log "Comparing manifests..."
    log "  Manifest 1: $manifest1"
    log "  Manifest 2: $manifest2"
    echo ""
    
    local server1=$(jq -r '.server' "$manifest1")
    local server2=$(jq -r '.server' "$manifest2")
    local branch1=$(jq -r '.branch' "$manifest1")
    local branch2=$(jq -r '.branch' "$manifest2")
    local commit1=$(jq -r '.commit' "$manifest1")
    local commit2=$(jq -r '.commit' "$manifest2")
    
    echo "Build Details:"
    echo "  $server1: branch=$branch1, commit=$commit1"
    echo "  $server2: branch=$branch2, commit=$commit2"
    echo ""
    
    if [ "$branch1" != "$branch2" ]; then
        log "[!]  Warning: Different branches ($branch1 vs $branch2)"
    fi
    
    if [ "$commit1" != "$commit2" ]; then
        log "[!]  Warning: Different commits ($commit1 vs $commit2)"
        echo ""
        echo "Builds are from different commits, comparison may not be meaningful."
        echo ""
    fi
    
    # Get artifact lists
    local artifacts1=$(jq -r '.artifacts[].name' "$manifest1" | sort)
    local artifacts2=$(jq -r '.artifacts[].name' "$manifest2" | sort)
    
    # Find common artifacts
    local common=$(comm -12 <(echo "$artifacts1") <(echo "$artifacts2"))
    local only1=$(comm -23 <(echo "$artifacts1") <(echo "$artifacts2"))
    local only2=$(comm -13 <(echo "$artifacts1") <(echo "$artifacts2"))
    
    echo "Artifact Comparison:"
    echo "  Common artifacts: $(echo "$common" | wc -l)"
    echo "  Only in $server1: $(echo "$only1" | wc -l)"
    echo "  Only in $server2: $(echo "$only2" | wc -l)"
    echo ""
    
    if [ -n "$only1" ]; then
        echo "Artifacts only in $server1:"
        echo "$only1" | sed 's/^/  /'
        echo ""
    fi
    
    if [ -n "$only2" ]; then
        echo "Artifacts only in $server2:"
        echo "$only2" | sed 's/^/  /'
        echo ""
    fi
    
    # Compare checksums for common artifacts
    local identical=0
    local different=0
    local size_diff=0
    
    echo "Checksum Comparison (common artifacts):"
    
    while IFS= read -r artifact_name; do
        if [ -z "$artifact_name" ]; then continue; fi
        
        local sha256_1=$(jq -r --arg name "$artifact_name" '.artifacts[] | select(.name == $name) | .checksums.sha256' "$manifest1")
        local sha256_2=$(jq -r --arg name "$artifact_name" '.artifacts[] | select(.name == $name) | .checksums.sha256' "$manifest2")
        local size1=$(jq -r --arg name "$artifact_name" '.artifacts[] | select(.name == $name) | .size_bytes' "$manifest1")
        local size2=$(jq -r --arg name "$artifact_name" '.artifacts[] | select(.name == $name) | .size_bytes' "$manifest2")
        
        if [ "$sha256_1" = "$sha256_2" ]; then
            echo "  [OK] $artifact_name - IDENTICAL"
            identical=$((identical + 1))
        else
            echo "  [X] $artifact_name - DIFFERENT"
            echo "     $server1: $sha256_1 ($(numfmt --to=iec-i --suffix=B $size1))"
            echo "     $server2: $sha256_2 ($(numfmt --to=iec-i --suffix=B $size2))"
            different=$((different + 1))
            
            if [ "$size1" != "$size2" ]; then
                local diff=$((size2 - size1))
                echo "     Size difference: $(numfmt --to=iec-i --suffix=B $diff)"
                size_diff=$((size_diff + 1))
            fi
        fi
    done <<< "$common"
    
    echo ""
    echo "Summary:"
    echo "  Identical: $identical"
    echo "  Different: $different"
    if [ $size_diff -gt 0 ]; then
        echo "  Size differences: $size_diff"
    fi
    echo ""
    
    if [ $different -eq 0 ] && [ -z "$only1" ] && [ -z "$only2" ]; then
        echo "[OK] REPRODUCIBLE BUILD VERIFIED"
        echo "Both servers produced identical artifacts!"
        return 0
    else
        echo "[X] BUILDS ARE NOT REPRODUCIBLE"
        echo "Differences found between artifacts."
        return 1
    fi
}

# Compare latest builds from two servers
compare_latest() {
    local server1="${1:-build1}"
    local server2="${2:-build2}"
    local artifact_type="${3:-debs}"
    
    log "Comparing latest $artifact_type builds from $server1 and $server2..."
    
    # Find exported manifests in git repo
    local manifest1=$(find "$REPO_ROOT/$server1/artifacts" -name "*_manifest.json" 2>/dev/null | sort -r | head -1)
    local manifest2=$(find "$REPO_ROOT/$server2/artifacts" -name "*_manifest.json" 2>/dev/null | sort -r | head -1)
    
    if [ -z "$manifest1" ]; then
        log "Error: No manifest found for $server1"
        return 1
    fi
    
    if [ -z "$manifest2" ]; then
        log "Error: No manifest found for $server2"
        return 1
    fi
    
    compare_manifests "$manifest1" "$manifest2"
}

# Compare specific job builds
compare_jobs() {
    local job1="$1"
    local job2="$2"
    
    log "Comparing builds for jobs: $job1 and $job2..."
    
    # Find manifests by job ID
    local manifest1=$(find "$REPO_ROOT" -name "${job1}_manifest.json" 2>/dev/null | head -1)
    local manifest2=$(find "$REPO_ROOT" -name "${job2}_manifest.json" 2>/dev/null | head -1)
    
    if [ -z "$manifest1" ]; then
        log "Error: Manifest not found for job $job1"
        return 1
    fi
    
    if [ -z "$manifest2" ]; then
        log "Error: Manifest not found for job $job2"
        return 1
    fi
    
    compare_manifests "$manifest1" "$manifest2"
}

# Generate comparison report
generate_report() {
    local manifest1="$1"
    local manifest2="$2"
    local output_file="$3"
    
    log "Generating comparison report..."
    
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local report_file="${output_file:-$REPO_ROOT/reports/comparison_${timestamp}.md}"
    
    mkdir -p "$(dirname "$report_file")"
    
    # Redirect output to file
    {
        echo "# Build Comparison Report"
        echo ""
        echo "**Generated**: $timestamp"
        echo ""
        compare_manifests "$manifest1" "$manifest2"
    } > "$report_file"
    
    log "Report saved to: $report_file"
    
    # Optionally commit to git
    cd "$REPO_ROOT"
    git add "$report_file"
    git commit -m "Add build comparison report [$timestamp]" || true
    
    echo "$report_file"
}

# Main command dispatcher
case "${1:-help}" in
    compare)
        compare_manifests "$2" "$3"
        ;;
    compare-latest)
        compare_latest "$2" "$3" "$4"
        ;;
    compare-jobs)
        compare_jobs "$2" "$3"
        ;;
    report)
        generate_report "$2" "$3" "$4"
        ;;
    help|*)
        cat <<EOF
Build Comparison Tool

Usage:
  $0 compare <manifest1> <manifest2>                      Compare two manifest files
  $0 compare-latest [server1] [server2] [type]           Compare latest builds (default: build1 build2 debs)
  $0 compare-jobs <job_id1> <job_id2>                    Compare specific job builds
  $0 report <manifest1> <manifest2> [output_file]        Generate comparison report

Examples:
  # Compare two specific manifests
  $0 compare /path/to/manifest1.json /path/to/manifest2.json
  
  # Compare latest builds from build1 and build2
  $0 compare-latest
  
  # Compare latest builds from specific servers
  $0 compare-latest build1 build2 debs
  
  # Compare specific jobs
  $0 compare-jobs job_12345 job_67890
  
  # Generate report
  $0 report /path/to/manifest1.json /path/to/manifest2.json ./comparison_report.md

Notes:
  - Manifests are created by artifact_manager.sh
  - For reproducible builds, artifacts should have identical checksums
  - Size differences indicate different build outputs
  - Branch/commit differences may explain checksum mismatches

EOF
        ;;
esac
