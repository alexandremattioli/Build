#!/bin/bash
################################################################################
# Script: ack_message.sh
# Purpose: Mark a coordination message as acknowledged by a builder.
# Usage: ./scripts/ack_message.sh <message_id> <builder>
################################################################################

set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Usage: $0 <message_id> <builder>" >&2
    exit 1
fi

MSG_ID="$1"
ACK_BUILDER="$2"

if [[ ! "$ACK_BUILDER" =~ ^(build1|build2|build3|build4)$ ]]; then
    echo "ERROR: Invalid builder: $ACK_BUILDER" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

LOCK_DIR="coordination/.locks"
mkdir -p "$LOCK_DIR"
LOCK_FILE="$LOCK_DIR/messages.lock"
exec {lock_fd}>"$LOCK_FILE"
if ! flock -w "${LOCK_WAIT:-10}" "$lock_fd"; then
    echo "ERROR: Could not acquire messages lock within ${LOCK_WAIT:-10}s" >&2
    exit 2
fi
trap "flock -u $lock_fd" EXIT

git pull origin main --rebase --autostash

PYTHON_SCRIPT=$(cat <<'PY'
import json, sys, datetime
from pathlib import Path

msg_id = sys.argv[1]
ack_builder = sys.argv[2]
repo = Path(sys.argv[3])
messages_path = repo / "coordination" / "messages.json"

with messages_path.open() as fh:
    data = json.load(fh)

messages = data.get("messages", [])
target = next((m for m in messages if m.get("id") == msg_id), None)
if target is None:
    sys.stderr.write(f"ERROR: Message {msg_id} not found\n")
    sys.exit(1)

if not target.get("ack_required"):
    sys.stderr.write("ERROR: Message does not require acknowledgment\n")
    sys.exit(1)

acks = target.setdefault("acknowledged_by", [])
if ack_builder not in acks:
    acks.append(ack_builder)

target["ack_status"] = "completed" if acks else "pending"

with messages_path.open("w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
)

python3 -c "$PYTHON_SCRIPT" "$MSG_ID" "$ACK_BUILDER" "$REPO_DIR"

git add coordination/messages.json
git commit -m "Ack $MSG_ID by $ACK_BUILDER" >/dev/null 2>&1 || true

if ! git push origin main; then
    echo "ERROR: Failed to push acknowledgment" >&2
    exit 2
fi

echo "Acknowledged $MSG_ID as $ACK_BUILDER"
