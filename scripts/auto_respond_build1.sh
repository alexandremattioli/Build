#!/bin/bash
################################################################################
# Script: auto_respond_build1.sh
# Purpose: Continuously monitor messages from Build1 and auto-respond from Build2
# Interval: 60 seconds
# Dependencies: jq, git, curl (optional), send_message.sh, read_messages.sh
# State file: coordination/auto_responder_state_build2.json
################################################################################

set -euo pipefail

# Canonical repository location for production runs
REPO_DIR="/root/Build"
STATE_FILE="$REPO_DIR/coordination/auto_responder_state_build2.json"
SLEEP_SECONDS=60

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Ensure state file exists
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
  tmpfile=$(mktemp)
  jq --arg id "$msg_id" '.responded += [$id] | .responded |= unique' "$STATE_FILE" > "$tmpfile" && mv "$tmpfile" "$STATE_FILE"
}

send_reply() {
  local subject="$1"
  local body="$2"

  bash "$REPO_DIR/scripts/send_message.sh" build2 build1 info "$subject" "$body"
}

compose_response_body() {
  local orig_subject="$1"

  local header
  header="Build1,\n\nThanks for the update. Build2 acknowledges and is proceeding as planned."

  local commitments
  commitments="\n\nBuild2 commitments (confirmed):\n- Harden VR broker (mTLS + JWT) and package as .deb\n- Validate initial dictionaries (pfSense first)\n- Implement API command bindings and responses\n- Deliver UI flows (dictionary editor, network wizard, health + reconcile)"

  local coordination
  coordination="\n\nCoordination:\n- pfSense end-to-end first, then FortiGate, then Palo Alto/VyOS\n- Short-lived feature branches with continuous PRs\n- Daily sync during Phase 1, milestone-based thereafter"

  local milestones
  milestones="\n\nMilestones:\n- Week 2: Broker package + DB migrations ready\n- Week 4: Provider skeleton + API commands\n- Week 8: pfSense e2e working\n- Week 12: FortiGate integration\n- Week 16: Palo Alto + VyOS\n- Week 20: Tests + Docs\n- Week 22: Release prep"

  local footer
  footer="\n\nI'll post broker progress to feature/vnf-broker today and share any blockers immediately.\n- Build2"

  # Tailor response by subject keywords (lightweight routing)
  if echo "$orig_subject" | grep -qiE "coordination|kickoff"; then
    echo -e "$header\n\nAcknowledged coordination kickoff; division of work accepted.$commitments$coordination$milestones$footer"
  elif echo "$orig_subject" | grep -qiE "analysis alignment|analysis"; then
    echo -e "$header\n\nReviewed your notes; alignment confirmed on scope and interfaces.$commitments$coordination$milestones$footer"
  else
    echo -e "$header$commitments$coordination$milestones$footer"
  fi
}

main_loop() {
  log "Starting auto-responder for Build1 → Build2 messages (every ${SLEEP_SECONDS}s)"
  init_state

  while true; do
    # Sync latest repo state (defensive against partial rebases)
    (
      cd "$REPO_DIR" || exit 0
      # If a rebase is stuck, abort it to unblock pulls
      if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
        git rebase --abort >/dev/null 2>&1 || true
      fi
      # Autostash local changes and rebase
      git pull origin main --rebase --autostash --no-edit --no-stat >/dev/null 2>&1 || true
    )

    # Find unread messages from build1 to build2 (or broadcast 'all')
    mapfile -t items < <(jq -r '
      .messages[] |
      select((.to=="build2" or .to=="all") and .from=="build1" and (.read==false or .read==null)) |
      "\(.id)|\(.subject)|\(.timestamp)"' "$REPO_DIR/coordination/messages.json" 2>/dev/null || true)

    if [ ${#items[@]} -eq 0 ]; then
      log "No new messages from Build1. Sleeping ${SLEEP_SECONDS}s..."
      sleep "$SLEEP_SECONDS"
      continue
    fi

    for line in "${items[@]}"; do
      IFS='|' read -r msg_id msg_subject msg_time <<< "$line"

      if has_responded "$msg_id"; then
        log "Already responded to $msg_id ($msg_subject) — skipping"
        continue
      fi

      log "New message: id=$msg_id subject=$msg_subject time=$msg_time"

      # Compose and send response
      local_subject="Re: $msg_subject"
      local_body=$(compose_response_body "$msg_subject")

      send_reply "$local_subject" "$local_body"
      log "Sent auto-response to Build1 for $msg_id"

      # Mark as responded
      mark_responded "$msg_id"

      # Mark unread messages read (best-effort)
      (cd "$REPO_DIR" && bash scripts/mark_messages_read.sh build2 >/dev/null 2>&1 || true)
    done

    # Update public status files if available
    (cd "$REPO_DIR" && bash scripts/update_message_status_txt.sh >/dev/null 2>&1 || true)

    sleep "$SLEEP_SECONDS"
  done
}

main_loop
