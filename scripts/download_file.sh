#!/bin/bash
################################################################################
# Script: download_file.sh
# Purpose: Download a shared file from another build server
# Usage: ./download_file.sh <file_id> [destination_path]
#
# Arguments:
#   file_id          - File ID from file_registry.json
#   destination_path - Optional: where to save the file (default: current directory)
#
# Examples:
#   ./download_file.sh file_1761920500_1234
#   ./download_file.sh file_1761920500_1234 /root/configs/
#   ./download_file.sh file_1761920500_1234 /root/my_file.conf
#
# Exit Codes:
#   0 - Success
#   1 - Validation error
#   2 - Git operation failed
#   3 - File operation failed
#
# Dependencies: jq, git
################################################################################

set -euo pipefail

FILE_ID="$1"
DEST_PATH="${2:-.}"
SERVER_ID="${SERVER_ID:-$(hostname | grep -oP 'build\d+' || echo 'unknown')}"

REPO_DIR="/root/Build"

cd "$REPO_DIR"

# Pull latest
echo "Pulling latest changes from GitHub..."
git pull origin main --quiet 2>/dev/null || git pull origin main

REGISTRY_FILE="shared/file_registry.json"

if [ ! -f "$REGISTRY_FILE" ]; then
    echo "ERROR: File registry not found: $REGISTRY_FILE" >&2
    exit 1
fi

# Get file info
FILE_INFO=$(jq -c --arg id "$FILE_ID" '.files[] | select(.id == $id)' "$REGISTRY_FILE")

if [ -z "$FILE_INFO" ]; then
    echo "ERROR: File ID not found: $FILE_ID" >&2
    echo ""
    echo "Available files:"
    jq -r '.files[] | "  \(.id) - \(.filename) (\(.category)) from \(.from)"' "$REGISTRY_FILE" | tail -10
    exit 1
fi

# Extract file details
FROM=$(echo "$FILE_INFO" | jq -r '.from')
TO=$(echo "$FILE_INFO" | jq -r '.to')
CATEGORY=$(echo "$FILE_INFO" | jq -r '.category')
FILENAME=$(echo "$FILE_INFO" | jq -r '.filename')
FILE_PATH=$(echo "$FILE_INFO" | jq -r '.path')
SIZE_BYTES=$(echo "$FILE_INFO" | jq -r '.size_bytes')
DESCRIPTION=$(echo "$FILE_INFO" | jq -r '.description')
TIMESTAMP=$(echo "$FILE_INFO" | jq -r '.timestamp')

# Format size
if [ "$SIZE_BYTES" -lt 1024 ]; then
    SIZE="${SIZE_BYTES}B"
elif [ "$SIZE_BYTES" -lt $((1024 * 1024)) ]; then
    SIZE="$((SIZE_BYTES / 1024))KB"
else
    SIZE="$((SIZE_BYTES / 1024 / 1024))MB"
fi

echo "════════════════════════════════════════════════════════════"
echo "FILE INFORMATION"
echo "════════════════════════════════════════════════════════════"
echo "  File ID: $FILE_ID"
echo "  From: $FROM"
echo "  To: $TO"
echo "  Filename: $FILENAME"
echo "  Category: $CATEGORY"
echo "  Size: $SIZE"
echo "  Shared: $TIMESTAMP"
echo "  Description: $DESCRIPTION"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check if file exists in repo
if [ ! -f "$FILE_PATH" ]; then
    echo "ERROR: File not found in repository: $FILE_PATH" >&2
    echo "The file may have been removed or archived." >&2
    exit 3
fi

# Check recipient
if [ "$TO" != "all" ] && [ "$TO" != "$SERVER_ID" ]; then
    echo "WARNING: This file was shared with $TO, but you are $SERVER_ID" >&2
    echo "Proceeding anyway..." >&2
fi

# Determine destination
if [ -d "$DEST_PATH" ]; then
    # Destination is a directory
    FINAL_DEST="$DEST_PATH/$FILENAME"
elif [ "$DEST_PATH" = "." ]; then
    # Current directory
    FINAL_DEST="$FILENAME"
else
    # Destination is a file path
    FINAL_DEST="$DEST_PATH"
fi

# Check if destination exists
if [ -f "$FINAL_DEST" ]; then
    echo "WARNING: Destination file already exists: $FINAL_DEST" >&2
    echo "Overwrite? (y/N): " >&2
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Download cancelled." >&2
        exit 1
    fi
fi

# Copy file
echo "Downloading file..."
cp "$FILE_PATH" "$FINAL_DEST"

if [ ! -f "$FINAL_DEST" ]; then
    echo "ERROR: Failed to copy file to: $FINAL_DEST" >&2
    exit 3
fi

# Update registry to mark as downloaded
TMP_FILE=$(mktemp)
jq --arg id "$FILE_ID" \
   --arg server "$SERVER_ID" \
   --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '(.files[] | select(.id == $id) | .downloaded_by) += [{"server": $server, "timestamp": $ts}]' \
   "$REGISTRY_FILE" > "$TMP_FILE"
mv "$TMP_FILE" "$REGISTRY_FILE"

# Commit the download tracking
git add "$REGISTRY_FILE"
git commit -m "File downloaded: $FILENAME by $SERVER_ID" --quiet 2>/dev/null || true
git push origin main --quiet 2>/dev/null || true

echo ""
echo "[OK] File downloaded successfully!"
echo "  Location: $FINAL_DEST"
echo "  Size: $SIZE"
echo ""

# Display file info based on category
case "$CATEGORY" in
    config)
        echo "This is a configuration file. Review before using:"
        echo "  cat $FINAL_DEST"
        ;;
    log)
        echo "This is a log file. View with:"
        echo "  less $FINAL_DEST"
        echo "  tail -f $FINAL_DEST  (if actively writing)"
        ;;
    code)
        echo "This is a code file. Review before executing."
        ;;
    artifact)
        echo "This is a build artifact. Extract if compressed:"
        echo "  tar -xzf $FINAL_DEST  (if .tar.gz)"
        ;;
esac

exit 0
