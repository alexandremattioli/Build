#!/bin/bash
################################################################################
# Script: send_and_refresh.sh
# Purpose: Convenience wrapper to send a coordination message and immediately
#          refresh all derived status artifacts (message_status.txt, stats).
# Usage:   ./scripts/send_and_refresh.sh <from> <to> <type> <subject> <body> [--require-ack]
################################################################################

set -euo pipefail

if [ $# -lt 5 ]; then
    echo "Usage: $0 <from> <to> <type> <subject> <body> [--require-ack]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SEND_SCRIPT="$SCRIPT_DIR/send_message.sh"
STATUS_SCRIPT="$SCRIPT_DIR/update_message_status_txt.sh"
STATS_SCRIPT="$SCRIPT_DIR/update_message_stats.sh"

if ! "$SEND_SCRIPT" "$@"; then
    echo "ERROR: send_message.sh failed" >&2
    exit 2
fi

if ! "$STATUS_SCRIPT"; then
    echo "WARNING: update_message_status_txt.sh failed" >&2
fi

if ! "$STATS_SCRIPT"; then
    echo "WARNING: update_message_stats.sh failed" >&2
fi

echo "Message + status refresh complete."
