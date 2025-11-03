#!/bin/bash
# Message Management Script
# Mark messages as read and archive old messages

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MESSAGES_FILE="$REPO_ROOT/coordination/messages.json"
ARCHIVE_DIR="$REPO_ROOT/coordination/archive"

# Archive messages older than N days (default: 30)
ARCHIVE_DAYS=${ARCHIVE_DAYS:-30}

log() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"
}

mark_message_read() {
    local message_id="$1"
    
    if [ -z "$message_id" ]; then
        echo "Usage: $0 mark-read <message_id>"
        return 1
    fi
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    # Use flock to prevent concurrent modifications
    exec 200>"$MESSAGES_FILE.flock"
    flock -n 200 || {
        log "Another process is modifying messages, please try again..."
        return 1
    }
    
    local temp_file=$(mktemp)
    
    # Mark message as read
    jq --arg id "$message_id" \
       '(.messages[] | select(.id == $id) | .read) = true' \
       "$MESSAGES_FILE" > "$temp_file"
    
    if cmp -s "$MESSAGES_FILE" "$temp_file"; then
        log "Message $message_id was already marked as read or not found"
        rm "$temp_file"
        flock -u 200
        return 0
    fi
    
    mv "$temp_file" "$MESSAGES_FILE"
    flock -u 200
    
    git add "$MESSAGES_FILE"
    git commit -m "Mark message $message_id as read"
    git push origin main
    
    log "Message $message_id marked as read"
}

mark_all_read() {
    local target="$1"  # Optional: "all", "build1", "build2", or empty for all
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    exec 200>"$MESSAGES_FILE.flock"
    flock -n 200 || {
        log "Another process is modifying messages, please try again..."
        return 1
    }
    
    local temp_file=$(mktemp)
    
    if [ -z "$target" ] || [ "$target" = "all" ]; then
        # Mark all messages as read
        jq '.messages[].read = true' "$MESSAGES_FILE" > "$temp_file"
        log "Marking all messages as read..."
    else
        # Mark messages to/from specific server as read
        jq --arg to "$target" --arg from "$target" \
           '(.messages[] | select(.to == $to or .from == $from or .to == "all") | .read) = true' \
           "$MESSAGES_FILE" > "$temp_file"
        log "Marking messages for $target as read..."
    fi
    
    mv "$temp_file" "$MESSAGES_FILE"
    flock -u 200
    
    git add "$MESSAGES_FILE"
    git commit -m "Mark messages as read [$(date -u +%Y-%m-%dT%H:%M:%SZ)]"
    git push origin main
    
    log "Messages marked as read"
}

archive_old_messages() {
    log "Archiving messages older than $ARCHIVE_DAYS days..."
    
    cd "$REPO_ROOT"
    git pull origin main --quiet
    
    mkdir -p "$ARCHIVE_DIR"
    
    exec 200>"$MESSAGES_FILE.flock"
    flock -n 200 || {
        log "Another process is modifying messages, please try again..."
        return 1
    }
    
    local cutoff_date=$(date -u -d "$ARCHIVE_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ)
    local cutoff_epoch=$(date -d "$cutoff_date" +%s)
    
    local temp_file=$(mktemp)
    local archive_file="$ARCHIVE_DIR/messages_$(date -u +%Y%m).json"
    
    # Extract old read messages
    jq --arg cutoff "$cutoff_date" \
       '[.messages[] | select(.read == true and .timestamp < $cutoff)]' \
       "$MESSAGES_FILE" > "$temp_file"
    
    local old_count=$(jq 'length' "$temp_file")
    
    if [ "$old_count" -gt 0 ]; then
        log "Found $old_count old messages to archive"
        
        # Append to archive file
        if [ -f "$archive_file" ]; then
            # Merge with existing archive
            jq -s '.[0] + .[1]' "$archive_file" "$temp_file" > "${archive_file}.tmp"
            mv "${archive_file}.tmp" "$archive_file"
        else
            mv "$temp_file" "$archive_file"
        fi
        
        # Remove archived messages from main file
        jq --arg cutoff "$cutoff_date" \
           '.messages = [.messages[] | select(.read == false or .timestamp >= $cutoff)]' \
           "$MESSAGES_FILE" > "${MESSAGES_FILE}.tmp"
        mv "${MESSAGES_FILE}.tmp" "$MESSAGES_FILE"
        
        flock -u 200
        
        git add "$MESSAGES_FILE" "$archive_file"
        git commit -m "Archive $old_count old messages [$(date -u +%Y-%m-%dT%H:%M:%SZ)]"
        git push origin main
        
        log "Archived $old_count messages to $archive_file"
    else
        log "No old messages to archive"
        rm "$temp_file"
        flock -u 200
    fi
}

list_unread() {
    local target="$1"  # Optional: filter by "to" field
    
    if [ -z "$target" ]; then
        jq -r '.messages[] | select(.read == false) | "\(.id): [\(.from) → \(.to)] \(.subject)"' \
            "$MESSAGES_FILE"
    else
        jq -r --arg to "$target" \
           '.messages[] | select(.read == false and (.to == $to or .to == "all")) | "\(.id): [\(.from) → \(.to)] \(.subject)"' \
           "$MESSAGES_FILE"
    fi
}

show_stats() {
    log "Message Statistics:"
    
    local total=$(jq '.messages | length' "$MESSAGES_FILE")
    local unread=$(jq '[.messages[] | select(.read == false)] | length' "$MESSAGES_FILE")
    local read=$(jq '[.messages[] | select(.read == true)] | length' "$MESSAGES_FILE")
    
    echo "  Total messages: $total"
    echo "  Unread: $unread"
    echo "  Read: $read"
    
    echo ""
    echo "Messages by type:"
    jq -r '.messages | group_by(.type) | .[] | "\(.  [0].type): \(length)"' "$MESSAGES_FILE"
    
    if [ -d "$ARCHIVE_DIR" ]; then
        local archive_count=$(find "$ARCHIVE_DIR" -name "messages_*.json" -exec jq 'length' {} \; | awk '{s+=$1} END {print s}')
        echo ""
        echo "  Archived messages: ${archive_count:-0}"
    fi
}

# Main command dispatcher
case "${1:-help}" in
    mark-read)
        mark_message_read "$2"
        ;;
    mark-all-read)
        mark_all_read "$2"
        ;;
    archive)
        archive_old_messages
        ;;
    list-unread)
        list_unread "$2"
        ;;
    stats)
        show_stats
        ;;
    help|*)
        cat <<EOF
Message Management Script

Usage:
  $0 mark-read <message_id>        Mark a specific message as read
  $0 mark-all-read [target]        Mark all messages as read (optionally filter by build1/build2)
  $0 archive                       Archive old read messages (older than $ARCHIVE_DAYS days)
  $0 list-unread [target]          List unread messages (optionally filter by target)
  $0 stats                         Show message statistics
  $0 help                          Show this help message

Environment Variables:
  ARCHIVE_DAYS                     Number of days before archiving (default: 30)

Examples:
  $0 mark-read msg_1234567890_5678
  $0 mark-all-read build2
  $0 list-unread build1
  $0 archive

EOF
        ;;
esac
