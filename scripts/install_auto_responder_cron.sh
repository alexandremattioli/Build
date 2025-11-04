#!/bin/bash
################################################################################
# Script: install_auto_responder_cron.sh
# Purpose: Install cron entries to supervise Build1 auto-responder continuously
# Requires: crontab
################################################################################
set -euo pipefail

CRON_FILE=$(mktemp)

# Preserve existing crontab if any
crontab -l 2>/dev/null > "$CRON_FILE" || true

add_line() {
  local line="$1"
  grep -Fq "$line" "$CRON_FILE" || echo "$line" >> "$CRON_FILE"
}

# Ensure supervisor runs at reboot and every minute
add_line "@reboot cd /root/Build && bash scripts/ensure_auto_responder.sh >> /var/log/auto_responder_supervisor.log 2>&1"
add_line "* * * * * cd /root/Build && bash scripts/ensure_auto_responder.sh >> /var/log/auto_responder_supervisor.log 2>&1"

crontab "$CRON_FILE"
rm "$CRON_FILE"

echo "Auto-responder cron installed."
