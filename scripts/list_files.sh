#!/bin/bash
################################################################################
# Script: list_files.sh
# Purpose: Browse shared files in the file exchange system
# Usage: ./list_files.sh [options]
#
# Options:
#   --from <server>     - Filter by sender (build1-4)
#   --to <server>       - Filter by recipient (build1-4, all)
#   --category <cat>    - Filter by category (config, code, log, build, artifact, doc, other)
#   --undownloaded      - Show only files not yet downloaded by current server
#   --format <fmt>      - Output format: table (default), json, csv
#   --limit <n>         - Show only the most recent N files
#
# Examples:
#   ./list_files.sh                          # Show all files
#   ./list_files.sh --from build1            # Files from build1
#   ./list_files.sh --to build2              # Files for build2
#   ./list_files.sh --category log           # Only log files
#   ./list_files.sh --undownloaded           # Files I haven't downloaded
#   ./list_files.sh --from build1 --category config --limit 5
#   ./list_files.sh --format json            # JSON output
#
# Exit Codes:
#   0 - Success
#   1 - Validation error
#   2 - Git operation failed
#
# Dependencies: jq, git
################################################################################

set -euo pipefail

# Default options
FILTER_FROM=""
FILTER_TO=""
FILTER_CATEGORY=""
UNDOWNLOADED_ONLY=false
FORMAT="table"
LIMIT=""
SERVER_ID="${SERVER_ID:-$(hostname | grep -oP 'build\d+' || echo 'unknown')}"

REPO_DIR="/root/Build"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --from)
            FILTER_FROM="$2"
            shift 2
            ;;
        --to)
            FILTER_TO="$2"
            shift 2
            ;;
        --category)
            FILTER_CATEGORY="$2"
            shift 2
            ;;
        --undownloaded)
            UNDOWNLOADED_ONLY=true
            shift
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

cd "$REPO_DIR"

# Pull latest
echo "Pulling latest changes from GitHub..." >&2
git pull origin main --quiet 2>/dev/null || git pull origin main

REGISTRY_FILE="shared/file_registry.json"

if [ ! -f "$REGISTRY_FILE" ]; then
    echo "ERROR: File registry not found: $REGISTRY_FILE" >&2
    echo "No files have been shared yet." >&2
    exit 1
fi

# Build jq filter
JQ_FILTER=".files[]"

if [ -n "$FILTER_FROM" ]; then
    JQ_FILTER="$JQ_FILTER | select(.from == \"$FILTER_FROM\")"
fi

if [ -n "$FILTER_TO" ]; then
    JQ_FILTER="$JQ_FILTER | select(.to == \"$FILTER_TO\" or .to == \"all\")"
fi

if [ -n "$FILTER_CATEGORY" ]; then
    JQ_FILTER="$JQ_FILTER | select(.category == \"$FILTER_CATEGORY\")"
fi

if [ "$UNDOWNLOADED_ONLY" = true ]; then
    JQ_FILTER="$JQ_FILTER | select(.downloaded_by | map(.server) | contains([\"$SERVER_ID\"]) | not)"
fi

# Get filtered files
FILES=$(jq -c "$JQ_FILTER" "$REGISTRY_FILE" 2>/dev/null || echo "")

if [ -z "$FILES" ]; then
    echo "No files match the specified criteria." >&2
    exit 0
fi

# Apply limit if specified
if [ -n "$LIMIT" ]; then
    FILES=$(echo "$FILES" | tail -n "$LIMIT")
fi

# Count files
FILE_COUNT=$(echo "$FILES" | wc -l)

# Output based on format
case "$FORMAT" in
    json)
        echo "{"
        echo "  \"total\": $FILE_COUNT,"
        echo "  \"files\": ["
        echo "$FILES" | sed 's/$/,/' | sed '$ s/,$//'
        echo "  ]"
        echo "}"
        ;;
    
    csv)
        echo "ID,From,To,Category,Filename,Size,Timestamp,Description,Downloaded"
        echo "$FILES" | while IFS= read -r file; do
            ID=$(echo "$file" | jq -r '.id')
            FROM=$(echo "$file" | jq -r '.from')
            TO=$(echo "$file" | jq -r '.to')
            CAT=$(echo "$file" | jq -r '.category')
            NAME=$(echo "$file" | jq -r '.filename')
            SIZE=$(echo "$file" | jq -r '.size_bytes')
            TS=$(echo "$file" | jq -r '.timestamp')
            DESC=$(echo "$file" | jq -r '.description // "N/A"' | sed 's/,/;/g')
            DOWNLOADED=$(echo "$file" | jq -r '.downloaded_by | length')
            
            # Format size
            if [ "$SIZE" -lt 1024 ]; then
                FSIZE="${SIZE}B"
            elif [ "$SIZE" -lt $((1024 * 1024)) ]; then
                FSIZE="$((SIZE / 1024))KB"
            else
                FSIZE="$((SIZE / 1024 / 1024))MB"
            fi
            
            echo "$ID,$FROM,$TO,$CAT,$NAME,$FSIZE,$TS,\"$DESC\",$DOWNLOADED"
        done
        ;;
    
    table|*)
        echo "" >&2
        echo "════════════════════════════════════════════════════════════════════════════════" >&2
        echo "SHARED FILES" >&2
        echo "════════════════════════════════════════════════════════════════════════════════" >&2
        
        # Show filters if any
        FILTERS=""
        [ -n "$FILTER_FROM" ] && FILTERS="$FILTERS From: $FILTER_FROM |"
        [ -n "$FILTER_TO" ] && FILTERS="$FILTERS To: $FILTER_TO |"
        [ -n "$FILTER_CATEGORY" ] && FILTERS="$FILTERS Category: $FILTER_CATEGORY |"
        [ "$UNDOWNLOADED_ONLY" = true ] && FILTERS="$FILTERS Undownloaded only |"
        [ -n "$LIMIT" ] && FILTERS="$FILTERS Limit: $LIMIT |"
        
        if [ -n "$FILTERS" ]; then
            FILTERS=$(echo "$FILTERS" | sed 's/ |$//')
            echo "Filters: $FILTERS" >&2
        fi
        
        echo "Total files: $FILE_COUNT" >&2
        echo "────────────────────────────────────────────────────────────────────────────────" >&2
        
        # Print files
        COUNTER=0
        echo "$FILES" | while IFS= read -r file; do
            COUNTER=$((COUNTER + 1))
            
            ID=$(echo "$file" | jq -r '.id')
            FROM=$(echo "$file" | jq -r '.from')
            TO=$(echo "$file" | jq -r '.to')
            CAT=$(echo "$file" | jq -r '.category')
            NAME=$(echo "$file" | jq -r '.filename')
            SIZE=$(echo "$file" | jq -r '.size_bytes')
            TS=$(echo "$file" | jq -r '.timestamp')
            DESC=$(echo "$file" | jq -r '.description // "N/A"')
            DOWNLOADED_BY=$(echo "$file" | jq -r '.downloaded_by | map(.server) | join(", ") // "none"')
            
            # Format size
            if [ "$SIZE" -lt 1024 ]; then
                FSIZE="${SIZE}B"
            elif [ "$SIZE" -lt $((1024 * 1024)) ]; then
                FSIZE="$((SIZE / 1024))KB"
            else
                FSIZE="$((SIZE / 1024 / 1024))MB"
            fi
            
            # Check if current server downloaded
            DOWNLOADED_ICON=""
            if echo "$DOWNLOADED_BY" | grep -q "$SERVER_ID"; then
                DOWNLOADED_ICON="[OK]"
            fi
            
            echo "" >&2
            echo "[$COUNTER] $NAME $DOWNLOADED_ICON" >&2
            echo "    ID: $ID" >&2
            echo "    From: $FROM → To: $TO" >&2
            echo "    Category: $CAT | Size: $FSIZE | Shared: $TS" >&2
            echo "    Description: $DESC" >&2
            echo "    Downloaded by: $DOWNLOADED_BY" >&2
            echo "    Download: ./scripts/download_file.sh $ID" >&2
        done
        
        echo "" >&2
        echo "════════════════════════════════════════════════════════════════════════════════" >&2
        ;;
esac

exit 0
