#!/bin/bash
################################################################################
# Script: enforce_heartbeat.sh
# Purpose: Ensure every builder has posted a heartbeat message within threshold.
#          Sends automated reminders when a builder is silent for too long.
# Usage:   ./scripts/enforce_heartbeat.sh
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

BUILDERS=(${HEARTBEAT_BUILDERS:-build1 build2 build3 build4})
THRESHOLD="${HEARTBEAT_THRESHOLD:-3600}"

python3 <<'PY' "${BUILDERS[@]}" "$THRESHOLD" "$REPO_DIR" >/tmp/heartbeat_stale.txt
import json, sys, time
from datetime import datetime, timezone
from pathlib import Path

builders = sys.argv[1:-2]
threshold = int(sys.argv[-2])
repo = Path(sys.argv[-1])
messages_path = repo / "coordination" / "messages.json"

with messages_path.open() as fh:
    data = json.load(fh)

messages = data.get("messages", [])

def parse_ts(ts: str):
    if not ts or ts.lower() == "never":
        return None
    formats = [
        "%Y-%m-%dT%H:%M:%SZ",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
    ]
    for fmt in formats:
        try:
            dt = datetime.strptime(ts, fmt)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.timestamp()
        except ValueError:
            continue
    try:
        if ts.endswith("Z"):
            ts = ts[:-1] + "+00:00"
        return datetime.fromisoformat(ts).timestamp()
    except ValueError:
        return None

now = time.time()
for builder in builders:
    sent = [m for m in messages if m.get("from") == builder]
    if not sent:
        age = float("inf")
        last_ts = "Never"
    else:
        sent.sort(key=lambda m: m.get("timestamp", ""))
        last = sent[-1]
        last_ts_str = last.get("timestamp")
        epoch = parse_ts(last_ts_str)
        if epoch is None:
            age = float("inf")
            last_ts = last_ts_str or "Unknown"
        else:
            age = now - epoch
            last_ts = last_ts_str
    if age > threshold:
        print(f"{builder}\t{int(age)}\t{last_ts}")
PY

if [ ! -s /tmp/heartbeat_stale.txt ]; then
    echo "All builders have recent heartbeats."
    rm -f /tmp/heartbeat_stale.txt
    exit 0
fi

while IFS=$'\t' read -r builder age last_ts; do
    if [ -z "$builder" ]; then
        continue
    fi
    message_subject="Heartbeat overdue for $builder"
    message_body="Automated reminder: $builder has not sent a coordination message for $age seconds (last at $last_ts UTC). Please send a heartbeat."
    "$SCRIPT_DIR/send_and_refresh.sh" system "$builder" warning "$message_subject" "$message_body" || true
done </tmp/heartbeat_stale.txt

rm -f /tmp/heartbeat_stale.txt
