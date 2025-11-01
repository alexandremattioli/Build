#!/bin/bash
################################################################################
# Script: archive_logs.sh
# Purpose: Archive and compress old log files to keep repository size manageable
# Usage: ./archive_logs.sh [--days DAYS] [--cleanup-days DAYS] [--dry-run]
#
# Options:
#   --days N           Archive logs older than N days (default: 7)
#   --cleanup-days N   Delete archives older than N days (default: 30)
#   --dry-run          Show what would be done without making changes
#   --help             Show this help message
#
# Examples:
#   ./archive_logs.sh                           # Archive logs older than 7 days
#   ./archive_logs.sh --days 3                  # Archive logs older than 3 days
#   ./archive_logs.sh --cleanup-days 60         # Keep archives for 60 days
#   ./archive_logs.sh --dry-run                 # Preview actions
#
# Exit Codes:
#   0 - Success
#   1 - Error
#
# Dependencies: find, gzip, tar
################################################################################

set -euo pipefail

# Default configuration
REPO_DIR="/root/Build"
ARCHIVE_DAYS=7
CLEANUP_DAYS=30
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --days)
            ARCHIVE_DAYS="$2"
            shift 2
            ;;
        --cleanup-days)
            CLEANUP_DAYS="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            grep "^#" "$0" | grep -v "#!/bin/bash" | sed 's/^# //'
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
done

# Logging
log() {
    echo "[$(date -u +%Y-%m-%d\ %H:%M:%S)] $*"
}

log_error() {
    log "ERROR: $*" >&2
}

# Validate inputs
if [[ ! "$ARCHIVE_DAYS" =~ ^[0-9]+$ ]] || [ "$ARCHIVE_DAYS" -lt 1 ]; then
    log_error "Archive days must be a positive integer"
    exit 1
fi

if [[ ! "$CLEANUP_DAYS" =~ ^[0-9]+$ ]] || [ "$CLEANUP_DAYS" -lt 1 ]; then
    log_error "Cleanup days must be a positive integer"
    exit 1
fi

cd "$REPO_DIR"

# Statistics
ARCHIVED_COUNT=0
ARCHIVED_SIZE=0
CLEANED_COUNT=0
CLEANED_SIZE=0

log "Starting log archival process"
log "Archive logs older than: $ARCHIVE_DAYS days"
log "Delete archives older than: $CLEANUP_DAYS days"
log "Dry run: $DRY_RUN"

# Process each build server's logs
for BUILD_DIR in build1 build2 build3 build4; do
    if [ ! -d "$BUILD_DIR/logs" ]; then
        log "Skipping $BUILD_DIR/logs (does not exist)"
        continue
    fi
    
    log "Processing $BUILD_DIR/logs..."
    
    # Create archived directory if it doesn't exist
    ARCHIVE_DIR="$BUILD_DIR/logs/archived"
    if [ ! -d "$ARCHIVE_DIR" ]; then
        if [ "$DRY_RUN" = false ]; then
            mkdir -p "$ARCHIVE_DIR"
            log "Created archive directory: $ARCHIVE_DIR"
        else
            log "[DRY-RUN] Would create: $ARCHIVE_DIR"
        fi
    fi
    
    # Find and archive old log files
    while IFS= read -r -d '' logfile; do
        if [ ! -f "$logfile" ]; then
            continue
        fi
        
        FILENAME=$(basename "$logfile")
        FILESIZE=$(stat -f%z "$logfile" 2>/dev/null || stat -c%s "$logfile" 2>/dev/null || echo "0")
        
        if [ "$DRY_RUN" = false ]; then
            # Compress and move to archive
            gzip -c "$logfile" > "$ARCHIVE_DIR/${FILENAME}.gz"
            rm "$logfile"
            log "Archived: $logfile → $ARCHIVE_DIR/${FILENAME}.gz"
        else
            log "[DRY-RUN] Would archive: $logfile → $ARCHIVE_DIR/${FILENAME}.gz"
        fi
        
        ARCHIVED_COUNT=$((ARCHIVED_COUNT + 1))
        ARCHIVED_SIZE=$((ARCHIVED_SIZE + FILESIZE))
        
    done < <(find "$BUILD_DIR/logs" -maxdepth 1 -type f -name "*.log" -mtime +$ARCHIVE_DAYS -print0 2>/dev/null || true)
    
    # Find and archive old JSON summary files
    while IFS= read -r -d '' jsonfile; do
        if [ ! -f "$jsonfile" ]; then
            continue
        fi
        
        FILENAME=$(basename "$jsonfile")
        FILESIZE=$(stat -f%z "$jsonfile" 2>/dev/null || stat -c%s "$jsonfile" 2>/dev/null || echo "0")
        
        if [ "$DRY_RUN" = false ]; then
            gzip -c "$jsonfile" > "$ARCHIVE_DIR/${FILENAME}.gz"
            rm "$jsonfile"
            log "Archived: $jsonfile → $ARCHIVE_DIR/${FILENAME}.gz"
        else
            log "[DRY-RUN] Would archive: $jsonfile → $ARCHIVE_DIR/${FILENAME}.gz"
        fi
        
        ARCHIVED_COUNT=$((ARCHIVED_COUNT + 1))
        ARCHIVED_SIZE=$((ARCHIVED_SIZE + FILESIZE))
        
    done < <(find "$BUILD_DIR/logs" -maxdepth 1 -type f -name "*_summary.json" -mtime +$ARCHIVE_DAYS -print0 2>/dev/null || true)
    
    # Cleanup very old archives
    if [ -d "$ARCHIVE_DIR" ]; then
        while IFS= read -r -d '' archive; do
            if [ ! -f "$archive" ]; then
                continue
            fi
            
            FILENAME=$(basename "$archive")
            FILESIZE=$(stat -f%z "$archive" 2>/dev/null || stat -c%s "$archive" 2>/dev/null || echo "0")
            
            if [ "$DRY_RUN" = false ]; then
                rm "$archive"
                log "Deleted old archive: $archive"
            else
                log "[DRY-RUN] Would delete: $archive"
            fi
            
            CLEANED_COUNT=$((CLEANED_COUNT + 1))
            CLEANED_SIZE=$((CLEANED_SIZE + FILESIZE))
            
        done < <(find "$ARCHIVE_DIR" -type f -name "*.gz" -mtime +$CLEANUP_DAYS -print0 2>/dev/null || true)
    fi
done

# Format sizes
format_size() {
    local size=$1
    if [ "$size" -lt 1024 ]; then
        echo "${size}B"
    elif [ "$size" -lt 1048576 ]; then
        echo "$((size / 1024))KB"
    elif [ "$size" -lt 1073741824 ]; then
        echo "$((size / 1048576))MB"
    else
        echo "$((size / 1073741824))GB"
    fi
}

ARCHIVED_SIZE_FMT=$(format_size $ARCHIVED_SIZE)
CLEANED_SIZE_FMT=$(format_size $CLEANED_SIZE)

# Summary
log "════════════════════════════════════════"
log "Archival Summary"
log "════════════════════════════════════════"
log "Files archived: $ARCHIVED_COUNT ($ARCHIVED_SIZE_FMT)"
log "Archives cleaned: $CLEANED_COUNT ($CLEANED_SIZE_FMT)"
log "Total space saved: $(format_size $((ARCHIVED_SIZE + CLEANED_SIZE)))"
log "════════════════════════════════════════"

if [ "$DRY_RUN" = true ]; then
    log "This was a dry run. No changes were made."
    log "Run without --dry-run to perform actual archival."
fi

log "Log archival complete"

exit 0
