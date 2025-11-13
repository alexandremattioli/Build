#!/usr/bin/env bash
# enable_yolo_local.sh - Prep local VS Code for Copilot Chat YOLO (one‑click run)
# This script disables Workspace Trust in the desktop VS Code user settings
# so Copilot Chat can run commands with fewer prompts. The YOLO toggle itself
# is a Copilot Chat UI control; on first run, click YOLO and choose
# "Always allow for this workspace" to persist consent.

set -euo pipefail

USER_SETTINGS_DIR="$HOME/.config/Code/User"
USER_SETTINGS_FILE="$USER_SETTINGS_DIR/settings.json"
BACKUP_FILE="$USER_SETTINGS_FILE.bak.$(date +%s)"

mkdir -p "$USER_SETTINGS_DIR"

# Ensure settings.json exists
if [ ! -f "$USER_SETTINGS_FILE" ]; then
  echo '{}' > "$USER_SETTINGS_FILE"
fi

# Backup
cp "$USER_SETTINGS_FILE" "$BACKUP_FILE"
echo "Backup saved: $BACKUP_FILE"

# Require jq
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required. Install jq (e.g., sudo apt-get install -y jq) and re-run." >&2
  exit 1
fi

# Merge desired settings
TMP=$(mktemp)
jq '. + {"security.workspace.trust.enabled": false}' "$USER_SETTINGS_FILE" > "$TMP"
mv "$TMP" "$USER_SETTINGS_FILE"

echo "✓ Workspace Trust disabled in $USER_SETTINGS_FILE"

echo "Next steps (once per workspace):"
echo "1) Open this repo in local VS Code (not Remote-SSH)."
echo "2) In Copilot Chat, open the ⋯ menu and enable \"Allow one-click run (YOLO)\" if visible."
echo "3) Click YOLO on a simple command (e.g., git status) and choose \"Always allow for this workspace\" when prompted."
echo "4) You can revert by setting security.workspace.trust.enabled to true in settings."
