#!/bin/bash
# Install and enable systemd service for enhanced heartbeat on Build2
set -euo pipefail

SERVICE_NAME="build2-heartbeat.service"
SRC_UNIT="$(dirname "$0")/build2-heartbeat.service.example"
DST_UNIT="/etc/systemd/system/${SERVICE_NAME}"

if [ ! -f "$SRC_UNIT" ]; then
  echo "Missing unit template: $SRC_UNIT" >&2
  exit 1
fi

cp "$SRC_UNIT" "$DST_UNIT"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

echo "Installed and started ${SERVICE_NAME}. Logs: /var/log/enhanced_heartbeat_build2.log"
