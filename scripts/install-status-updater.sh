#!/bin/bash
# Install cron job for automatic status updates on Linux servers
# Run this script once on each Linux build server

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE_SCRIPT="$SCRIPT_DIR/update-status.sh"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Make update script executable
chmod +x "$UPDATE_SCRIPT"

# Create cron job entry (runs every minute)
CRON_ENTRY="* * * * * cd $REPO_DIR && $UPDATE_SCRIPT >> $REPO_DIR/logs/status-update.log 2>&1"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "$UPDATE_SCRIPT"; then
    echo "Cron job already exists for $UPDATE_SCRIPT"
else
    # Add to crontab
    (crontab -l 2>/dev/null || echo "") | { cat; echo "$CRON_ENTRY"; } | crontab -
    echo "Successfully installed cron job for status updates"
fi

# Create logs directory
mkdir -p "$REPO_DIR/logs"

echo "Installation complete!"
echo "Script: $UPDATE_SCRIPT"
echo "Update interval: Every 60 seconds"
echo "Log file: $REPO_DIR/logs/status-update.log"
echo ""
echo "To verify: crontab -l | grep update-status"
echo "To remove: crontab -l | grep -v update-status | crontab -"
