#!/bin/bash
################################################################################
# Script: autoresponder.sh
# Purpose: Send automated acknowledgements for fresh messages addressed to
#          the local server, ensuring coordination threads stay up to date.
# Usage: ./autoresponder.sh [--interval SECONDS] [--once]
# Dependencies: jq, git, scripts/send_message.sh, scripts/mark_messages_read.sh,
#               scripts/update_message_status_txt.sh, scripts/server_id.sh
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_ID="$("$SCRIPT_DIR/server_id.sh")"
STATE_FILE="$REPO_DIR/coordination/auto_responder_state_${SERVER_ID}.json"
INTERVAL=60
ONCE=false

usage() {
  echo "Usage: $0 [--interval seconds] [--once]"
  exit 1
}

while (( "$#" )); do
  case "$1" in
    --interval)
      shift
      INTERVAL="$1"
      ;;
    --once)
      ONCE=true
      ;;
    -h|--help)
      usage
      ;;
    *)
      usage
      ;;
  esac
  shift
done

init_state() {
  if [ ! -f "$STATE_FILE" ]; then
    mkdir -p "$(dirname "$STATE_FILE")"
    echo '{"responded":[]}' > "$STATE_FILE"
  fi
}

has_responded() {
  local msg_id="$1"
  jq -e --arg id "$msg_id" '.responded[]? | select(. == $id)' "$STATE_FILE" >/dev/null 2>&1
}

mark_responded() {
  local msg_id="$1"
  local tmp
  tmp=$(mktemp)
  jq --arg id "$msg_id" '.responded += [$id] | .responded |= unique' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

compose_body() {
  local from="$1"
  local subject="$2"
  cat <<EOF
${SERVER_ID} Auto Responder here.

Acknowledging receipt of your message "${subject}" sent from ${from}.
I will process it shortly and post any updates via the shared inbox.

Let me know if anything in particular needs urgent attention.
EOF
}

detect_new_messages() {
  jq -c --arg server "$SERVER_ID" '.messages[] |
    select((.to == $server or .to == "all") and (.read == false or .read == null) and (.type == "request" or .ack_required == true))' \
    "$REPO_DIR/coordination/messages.json" || true
}

send_ack() {
  local msg_from="$1"
  local msg_id="$2"
  local msg_subject="$3"
  local reply_subject="Re: $msg_subject"
  local reply_body
  reply_body=$(compose_body "$msg_from" "$msg_subject")
  bash "$REPO_DIR/scripts/send_message.sh" "$SERVER_ID" "$msg_from" info "$reply_subject" "$reply_body"
}

main_loop() {
  init_state

  while true; do
    (
      cd "$REPO_DIR"
      git pull origin main --rebase --autostash >/dev/null 2>&1 || true
    )
    local new_messages
    mapfile -t new_messages < <(detect_new_messages)

    if [ "${#new_messages[@]}" -eq 0 ]; then
      if [ "$ONCE" = true ]; then
        break
      fi
      sleep "$INTERVAL"
      continue
    fi

    for entry in "${new_messages[@]}"; do
      local msg_id msg_from msg_subject
      msg_id="$(echo "$entry" | jq -r '.id')"
      msg_from="$(echo "$entry" | jq -r '.from')"
      msg_subject="$(echo "$entry" | jq -r '.subject')"

      if has_responded "$msg_id"; then
        continue
      fi

      send_ack "$msg_from" "$msg_id" "$msg_subject"
      mark_responded "$msg_id"

      bash "$REPO_DIR/scripts/mark_messages_read.sh" "$SERVER_ID" >/dev/null 2>&1 || true
      bash "$REPO_DIR/scripts/update_message_status_txt.sh" >/dev/null 2>&1 || true
    done

    if [ "$ONCE" = true ]; then
      break
    fi
    sleep "$INTERVAL"
  done
}

main_loop
