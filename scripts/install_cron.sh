#!/bin/bash
# install_cron.sh - Install crontab entries for monitoring and maintenance
# Usage: ./install_cron.sh
set -euo pipefail

CRON_FILE=$(mktemp)

# Preserve existing crontab if any
crontab -l 2>/dev/null > "$CRON_FILE" || true

# Add entries (idempotent)
add_line() {
  local line="$1"
  grep -Fq "$line" "$CRON_FILE" || echo "$line" >> "$CRON_FILE"
}

# Every 5 minutes: monitor health
add_line "*/5 * * * * cd /root/Build && bash scripts/monitor_health.sh >> /var/log/monitor_health.log 2>&1"

# Daily at 01:05: archive old messages
add_line "5 1 * * * cd /root/Build && bash scripts/archive_old_messages.sh >> /var/log/archive_messages.log 2>&1"

# Hourly: collect metrics
add_line "0 * * * * cd /root/Build && bash scripts/collect_metrics.sh >> /var/log/metrics.log 2>&1"

# Apply crontab
crontab "$CRON_FILE"
rm "$CRON_FILE"

echo "Cron entries installed."
