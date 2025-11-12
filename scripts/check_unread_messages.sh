#!/bin/bash
################################################################################
# Script: check_unread_messages.sh
# Purpose: Check for unread messages and display status for all servers
# Usage: ./check_unread_messages.sh [server_id]
#
# Arguments:
#   server_id - Optional: build1, build2, build3, build4, or "all" (default: current server or all)
#
# Exit Codes:
#   0 - Success
#   1 - Has unread messages
#   2 - Error
#
# Dependencies: jq, git
################################################################################

set -euo pipefail

REPO_DIR="/root/Build"
SERVER_ID="${1:-all}"

cd "$REPO_DIR"

# Pull latest
git pull origin main --quiet 2>/dev/null || {
    echo "Warning: Git pull failed" >&2
}

MESSAGES_FILE="coordination/messages.json"
UNREAD_STATUS_FILE="coordination/unread_messages_status.json"

# Function to count unread messages for a server
count_unread() {
    local server="$1"
    jq --arg server "$server" '[.messages[] | select((.to == $server or .to == "all") and .read == false)] | length' "$MESSAGES_FILE"
}

# Function to get unread message details for a server
get_unread_messages() {
    local server="$1"
    jq --arg server "$server" '[.messages[] | select((.to == $server or .to == "all") and .read == false)] | sort_by(.timestamp)' "$MESSAGES_FILE"
}

# Generate unread status for all servers
generate_unread_status() {
    local now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Count unread for each server
    local build1_unread=$(count_unread "build1")
    local build2_unread=$(count_unread "build2")
    local build3_unread=$(count_unread "build3")
    local build4_unread=$(count_unread "build4")
    
    # Get first unread message for each server (if any)
    local build1_first_unread=$(jq --arg server "build1" -c '[.messages[] | select((.to == $server or .to == "all") and .read == false)] | sort_by(.timestamp) | first // null' "$MESSAGES_FILE")
    local build2_first_unread=$(jq --arg server "build2" -c '[.messages[] | select((.to == $server or .to == "all") and .read == false)] | sort_by(.timestamp) | first // null' "$MESSAGES_FILE")
    local build3_first_unread=$(jq --arg server "build3" -c '[.messages[] | select((.to == $server or .to == "all") and .read == false)] | sort_by(.timestamp) | first // null' "$MESSAGES_FILE")
    local build4_first_unread=$(jq --arg server "build4" -c '[.messages[] | select((.to == $server or .to == "all") and .read == false)] | sort_by(.timestamp) | first // null' "$MESSAGES_FILE")
    
    # Create status JSON
    jq -n \
      --arg now "$now" \
      --argjson build1_unread "$build1_unread" \
      --argjson build2_unread "$build2_unread" \
      --argjson build3_unread "$build3_unread" \
      --argjson build4_unread "$build4_unread" \
      --argjson build1_first "$build1_first_unread" \
      --argjson build2_first "$build2_first_unread" \
      --argjson build3_first "$build3_first_unread" \
      --argjson build4_first "$build4_first_unread" \
      '{
        last_checked: $now,
        servers: {
          build1: {
            unread_count: $build1_unread,
            has_unread: ($build1_unread > 0),
            first_unread_message: $build1_first
          },
          build2: {
            unread_count: $build2_unread,
            has_unread: ($build2_unread > 0),
            first_unread_message: $build2_first
          },
          build3: {
            unread_count: $build3_unread,
            has_unread: ($build3_unread > 0),
            first_unread_message: $build3_first
          },
          build4: {
            unread_count: $build4_unread,
            has_unread: ($build4_unread > 0),
            first_unread_message: $build4_first
          }
        }
      }' > "$UNREAD_STATUS_FILE"
}

# Display unread status
display_unread_status() {
    local server="$1"
    
    if [ "$server" = "all" ]; then
        echo "======================================"
        echo "UNREAD MESSAGES STATUS - ALL SERVERS"
        echo "======================================"
        echo ""
        
        for srv in build1 build2 build3 build4; do
            local unread=$(jq -r ".servers.$srv.unread_count" "$UNREAD_STATUS_FILE")
            local has_unread=$(jq -r ".servers.$srv.has_unread" "$UNREAD_STATUS_FILE")
            
            echo "[$srv]"
            if [ "$has_unread" = "true" ]; then
                echo "  Status: [!]  HAS UNREAD MESSAGES"
                echo "  Unread Count: $unread"
                
                # Show first unread message
                local first_unread=$(jq -r ".servers.$srv.first_unread_message" "$UNREAD_STATUS_FILE")
                if [ "$first_unread" != "null" ]; then
                    local from=$(echo "$first_unread" | jq -r '.from')
                    local subject=$(echo "$first_unread" | jq -r '.subject')
                    local timestamp=$(echo "$first_unread" | jq -r '.timestamp')
                    echo "  First Unread: From $from at $timestamp"
                    echo "  Subject: $subject"
                fi
            else
                echo "  Status: [OK] No unread messages"
            fi
            echo ""
        done
    else
        local unread=$(jq -r ".servers.$server.unread_count" "$UNREAD_STATUS_FILE")
        local has_unread=$(jq -r ".servers.$server.has_unread" "$UNREAD_STATUS_FILE")
        
        echo "======================================"
        echo "UNREAD MESSAGES STATUS - $server"
        echo "======================================"
        echo ""
        
        if [ "$has_unread" = "true" ]; then
            echo "[!]  YOU HAVE $unread UNREAD MESSAGE(S)"
            echo ""
            
            # Show all unread messages
            get_unread_messages "$server" | jq -r '.[] | "[\(.type | ascii_upcase)] From: \(.from) | Time: \(.timestamp)\nSubject: \(.subject)\nID: \(.id)\n\(.body)\n" + "─" * 70'
        else
            echo "[OK] No unread messages"
        fi
    fi
}

# Generate status
generate_unread_status

# Display status
display_unread_status "$SERVER_ID"

# Commit and push status file
git add "$UNREAD_STATUS_FILE" 2>/dev/null || true
git commit -m "Update unread messages status: $(date -u +%H:%M:%S)" >/dev/null 2>&1 || true
git push origin main --quiet 2>/dev/null || true

# Exit with code 1 if current server has unread messages
if [ "$SERVER_ID" != "all" ]; then
    HAS_UNREAD=$(jq -r ".servers.$SERVER_ID.has_unread" "$UNREAD_STATUS_FILE")
    if [ "$HAS_UNREAD" = "true" ]; then
        exit 1
    fi
fi

exit 0
