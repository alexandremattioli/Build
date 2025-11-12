#!/bin/bash
################################################################################
# Script: share_file.sh
# Purpose: Share a file with other build servers via git-based file exchange
# Usage: ./share_file.sh <from> <to> <file_path> <category> <description>
#
# Arguments:
#   from        - Source server ID (build1, build2, build3, build4)
#   to          - Destination server ID (build1, build2, build3, build4, all)
#   file_path   - Path to the file to share (absolute or relative)
#   category    - File category (config, code, log, build, artifact, doc, other)
#   description - Brief description of the file
#
# File Storage:
#   Files are stored in: shared/files/<from_server>/<category>/<timestamp>_<filename>
#   Metadata tracked in: shared/file_registry.json
#
# Size Limits:
#   Maximum file size: 50 MB (GitHub recommended limit for reasonable performance)
#   Warning threshold: 10 MB
#
# Examples:
#   ./share_file.sh build1 build2 /root/maven.log log "Maven build log from job_123"
#   ./share_file.sh build2 all /etc/mysql/my.cnf config "MySQL configuration"
#   ./share_file.sh build1 build2 /root/build.tar.gz artifact "Compiled artifacts"
#
# Exit Codes:
#   0 - Success
#   1 - Validation error
#   2 - Git operation failed
#   3 - File operation failed
#
# Dependencies: jq, git, du
################################################################################

set -euo pipefail

# Configuration
MAX_FILE_SIZE_MB=50
WARN_FILE_SIZE_MB=10
MAX_FILE_SIZE_BYTES=$((MAX_FILE_SIZE_MB * 1024 * 1024))
WARN_FILE_SIZE_BYTES=$((WARN_FILE_SIZE_MB * 1024 * 1024))

FROM_SERVER="$1"
TO_SERVER="$2"
FILE_PATH="$3"
CATEGORY="$4"
DESCRIPTION="$5"

REPO_DIR="/root/Build"

# Input validation
validate_server_id() {
    local server="$1"
    if [[ ! "$server" =~ ^(build1|build2|build3|build4|all)$ ]]; then
        echo "ERROR: Invalid server ID: $server" >&2
        echo "Valid values: build1, build2, build3, build4, all" >&2
        exit 1
    fi
}

validate_category() {
    local cat="$1"
    if [[ ! "$cat" =~ ^(config|code|log|build|artifact|doc|other)$ ]]; then
        echo "ERROR: Invalid category: $cat" >&2
        echo "Valid values: config, code, log, build, artifact, doc, other" >&2
        exit 1
    fi
}

validate_file() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        echo "ERROR: File not found: $file" >&2
        exit 1
    fi
    
    if [ ! -r "$file" ]; then
        echo "ERROR: File not readable: $file" >&2
        exit 1
    fi
    
    local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    
    if [ "$file_size" -gt "$MAX_FILE_SIZE_BYTES" ]; then
        local size_mb=$((file_size / 1024 / 1024))
        echo "ERROR: File too large: ${size_mb}MB (max: ${MAX_FILE_SIZE_MB}MB)" >&2
        echo "File: $file" >&2
        echo "Consider compressing or splitting the file." >&2
        exit 1
    fi
    
    if [ "$file_size" -gt "$WARN_FILE_SIZE_BYTES" ]; then
        local size_mb=$((file_size / 1024 / 1024))
        echo "WARNING: Large file detected: ${size_mb}MB" >&2
        echo "This may take longer to push to GitHub." >&2
        echo "Proceeding in 3 seconds... (Ctrl+C to cancel)" >&2
        sleep 3
    fi
    
    echo "$file_size"
}

format_size() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt $((1024 * 1024)) ]; then
        echo "$((bytes / 1024))KB"
    else
        echo "$((bytes / 1024 / 1024))MB"
    fi
}

validate_server_id "$FROM_SERVER"
validate_server_id "$TO_SERVER"
validate_category "$CATEGORY"

echo "Validating file: $FILE_PATH"
FILE_SIZE=$(validate_file "$FILE_PATH")
FILE_SIZE_FORMATTED=$(format_size "$FILE_SIZE")

FILENAME=$(basename "$FILE_PATH")
TIMESTAMP=$(date +%Y%m%dT%H%M%SZ)
FILE_ID="file_$(date +%s)_$(shuf -i 1000-9999 -n 1)"

cd "$REPO_DIR"

# Acquire lock
LOCK_DIR="coordination/.locks"
mkdir -p "$LOCK_DIR"
LOCK_FILE="$LOCK_DIR/files.lock"
exec {lock_fd}>"$LOCK_FILE"
if ! flock -w "${LOCK_WAIT:-15}" "$lock_fd"; then
    echo "ERROR: Could not acquire files lock within ${LOCK_WAIT:-15}s" >&2
    exit 2
fi
trap "flock -u $lock_fd" EXIT

# Pull latest
echo "Pulling latest changes..."
git pull origin main --rebase --autostash --quiet

# Create directory structure
DEST_DIR="shared/files/${FROM_SERVER}/${CATEGORY}"
mkdir -p "$DEST_DIR"

# Copy file with timestamp prefix
DEST_FILE="${DEST_DIR}/${TIMESTAMP}_${FILENAME}"
echo "Copying file to: $DEST_FILE"
cp "$FILE_PATH" "$DEST_FILE"

# Initialize registry if it doesn't exist
REGISTRY_FILE="shared/file_registry.json"
if [ ! -f "$REGISTRY_FILE" ]; then
    echo '{"files": []}' > "$REGISTRY_FILE"
fi

# Add entry to registry
TMP_FILE=$(mktemp)
jq --arg id "$FILE_ID" \
   --arg from "$FROM_SERVER" \
   --arg to "$TO_SERVER" \
   --arg category "$CATEGORY" \
   --arg filename "$FILENAME" \
   --arg path "$DEST_FILE" \
   --argjson size "$FILE_SIZE" \
   --arg desc "$DESCRIPTION" \
   --arg ts "$TIMESTAMP" \
   '.files += [{
       id: $id,
       from: $from,
       to: $to,
       category: $category,
       filename: $filename,
       path: $path,
       size_bytes: $size,
       description: $desc,
       timestamp: $ts,
       downloaded_by: []
   }]' "$REGISTRY_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$REGISTRY_FILE"

# Commit and push
echo "Committing file share..."
git add "$DEST_FILE" "$REGISTRY_FILE"
git commit -m "File share: $FILENAME from $FROM_SERVER to $TO_SERVER ($CATEGORY)"

# Retry git push with exponential backoff
push_with_retry() {
    local max_attempts=5
    local attempt=1
    local delay=2
    while [ $attempt -le $max_attempts ]; do
        echo "Pushing to GitHub (attempt $attempt/$max_attempts)..."
        if git push origin main 2>/dev/null; then
            return 0
        fi
        echo "Push failed, retrying in ${delay}s..."
        sleep $delay
        git pull origin main --rebase --autostash --quiet
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
    [ -f scripts/log_error.sh ] && bash scripts/log_error.sh "share_file" "git push failed after $max_attempts attempts"
    echo "ERROR: git push failed after $max_attempts attempts" >&2
    return 1
}

push_with_retry

echo ""
echo "[OK] File shared successfully!"
echo "  File ID: $FILE_ID"
echo "  Source: $FROM_SERVER"
echo "  Destination: $TO_SERVER"
echo "  Category: $CATEGORY"
echo "  Size: $FILE_SIZE_FORMATTED"
echo "  Path: $DEST_FILE"
echo "  Description: $DESCRIPTION"
echo ""
echo "Recipients can download with:"
echo "  cd /root/Build/scripts && ./download_file.sh $FILE_ID"

# Send notification message if send_message.sh exists
if [ -f scripts/send_message.sh ]; then
    cd scripts
    SUBJECT="File shared: $FILENAME ($CATEGORY)"
    BODY="$FROM_SERVER has shared a file with you.

File: $FILENAME
Category: $CATEGORY
Size: $FILE_SIZE_FORMATTED
Description: $DESCRIPTION

Download with:
cd /root/Build/scripts && ./download_file.sh $FILE_ID

Or view in GitHub:
https://github.com/alexandremattioli/Build/blob/main/$DEST_FILE"

    ./send_message.sh "$FROM_SERVER" "$TO_SERVER" info "$SUBJECT" "$BODY" 2>/dev/null || true
fi

exit 0
