#!/bin/bash
################################################################################
# Script: enable_auto_approve.sh
# Purpose: Enable non-interactive agent actions in VS Code Server by:
#  - Disabling workspace trust sandbox
#  - Setting Claude Code approval policy to "auto"
# Usage: ./enable_auto_approve.sh
# Notes: Idempotent. Creates a timestamped backup of settings.json before editing.
################################################################################
set -euo pipefail

SETTINGS_DIR="$HOME/.vscode-server/data/Machine"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
BACKUP_FILE="$SETTINGS_FILE.bak.$(date +%s)"

mkdir -p "$SETTINGS_DIR"

# Ensure a JSON file exists
if [ ! -f "$SETTINGS_FILE" ]; then
  echo "{}" > "$SETTINGS_FILE"
fi

# Backup existing settings
cp "$SETTINGS_FILE" "$BACKUP_FILE"
echo "Backup saved: $BACKUP_FILE"

# Apply settings (requires jq)
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install jq and re-run." >&2
  exit 1
fi

TMP=$(mktemp)
# Merge desired keys into settings
jq '. + {
  "security.workspace.trust.enabled": false,
  "claude-code.approvalPolicy": "auto"
}' "$SETTINGS_FILE" > "$TMP"

mv "$TMP" "$SETTINGS_FILE"

# Show confirmation
if grep -q '"claude-code.approvalPolicy"' "$SETTINGS_FILE"; then
  echo "claude-code.approvalPolicy set to auto"
fi
if grep -q '"security.workspace.trust.enabled"' "$SETTINGS_FILE"; then
  echo "security.workspace.trust.enabled set to false"
fi

echo "Auto-approve enabled for this host."
