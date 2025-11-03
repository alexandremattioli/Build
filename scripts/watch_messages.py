#!/usr/bin/env python3
"""
Shared message watcher for Build coordination.

- Polls the repository's coordination/messages.json at a fixed interval
- Prints any newly observed messages addressed to this server (or 'all')
- Appends a compact single-line log entry to a local log file
- Tracks seen message ids to avoid duplicates across runs

Usage examples:
  python3 scripts/watch_messages.py --target auto --interval 10 --log /root/Build/messages.log
  python3 scripts/watch_messages.py --target build1 --interval 10 --log /root/Build/messages.log

Notes:
- When --target=auto, the watcher will use scripts/server_id.sh to resolve the server id
- Messages addressed to 'all' are always printed/logged
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request
from urllib.error import URLError, HTTPError

MESSAGES_URL = "https://raw.githubusercontent.com/alexandremattioli/Build/main/coordination/messages.json"
DEFAULT_LOG = "/root/Build/messages.log"
DEFAULT_STATE = "/root/Build/.watch_messages_state.json"


def resolve_server_id_auto() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    sid_path = os.path.join(here, "server_id.sh")
    try:
        res = subprocess.run([sid_path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=5)
        sid = (res.stdout or "").strip()
        if sid in {"build1", "build2"}:
            return sid
        return "unknown"
    except Exception:
        return "unknown"


def load_state(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return set(data.get("seen_ids", []))
    except FileNotFoundError:
        return set()
    except Exception as e:
        print(f"WARN: Failed to load state from {path}: {e}", file=sys.stderr)
        return set()


def save_state(path: str, seen_ids: set):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"seen_ids": sorted(list(seen_ids))}, f, indent=2)
    except Exception as e:
        print(f"WARN: Failed to save state into {path}: {e}", file=sys.stderr)


def fetch_messages(url: str):
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            if resp.status != 200:
                raise HTTPError(url, resp.status, "Non-200 response", hdrs=resp.headers, fp=None)
            raw = resp.read().decode("utf-8")
        payload = json.loads(raw)
        return payload
    except (URLError, HTTPError) as e:
        print(f"ERROR: Network error fetching messages: {e}", file=sys.stderr)
        return None
    except json.JSONDecodeError as e:
        print(f"ERROR: Failed to parse JSON from messages: {e}", file=sys.stderr)
        return None


def should_deliver(msg: dict, target: str) -> bool:
    to = msg.get("to")
    if not to:
        return False
    if to == "all":
        return True
    if target in {"build1", "build2"} and to == target:
        return True
    return False


def append_log(log_path: str, direction: str, m: dict):
    try:
        os.makedirs(os.path.dirname(log_path), exist_ok=True)
    except Exception:
        pass
    ts = m.get("timestamp", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    mid = m.get("id", "")
    frm = m.get("from", "")
    to = m.get("to", "")
    subj = (m.get("subject", "") or "").replace("\n", " ")
    body = (m.get("body", "") or "").strip().replace("\n", " ")
    line = f"{ts} [READ] id={mid} from={frm} to={to} subject=\"{subj}\" body=\"{body[:400]}\"\n"
    try:
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception as e:
        print(f"WARN: Failed to append to log {log_path}: {e}", file=sys.stderr)


def print_messages(msgs):
    for m in msgs:
        ts = m.get("timestamp", "")
        mid = m.get("id", "")
        frm = m.get("from", "")
        to = m.get("to", "")
        subj = m.get("subject", "")
        body = m.get("body", "")
        print("\n" + "="*80)
        print(f"[{ts}] {mid}")
        print(f"From: {frm}  To: {to}  Type: {m.get('type','')}")
        print(f"Subject: {subj}")
        print("-"*80)
        print((body or "").strip())
        print("="*80 + "\n")


def main():
    parser = argparse.ArgumentParser(description="Watch Build coordination messages")
    parser.add_argument("--target", default="auto", choices=["auto", "build1", "build2", "all"], help="Message target to watch (default auto via server_id.sh)")
    parser.add_argument("--interval", type=int, default=10, help="Polling interval in seconds (default 10)")
    parser.add_argument("--once", action="store_true", help="Fetch once and exit")
    parser.add_argument("--log", default=DEFAULT_LOG, help=f"Path to append read messages (default {DEFAULT_LOG})")
    parser.add_argument("--state", default=DEFAULT_STATE, help=f"Path to store seen ids (default {DEFAULT_STATE})")
    args = parser.parse_args()

    target = args.target
    if target == "auto":
        target = resolve_server_id_auto()
        print(f"[watcher] auto-detected target: {target}")

    seen_ids = load_state(args.state)

    def tick():
        payload = fetch_messages(MESSAGES_URL)
        if not payload:
            return
        messages = payload.get("messages", [])
        new_msgs = []
        for m in messages:
            mid = m.get("id")
            if not mid or mid in seen_ids:
                continue
            if target == "all":
                deliver = (m.get("to") in {"build1", "build2", "all"})
            else:
                deliver = should_deliver(m, target)
            if deliver:
                new_msgs.append(m)
        if new_msgs:
            print_messages(new_msgs)
            for m in new_msgs:
                mid = m.get("id")
                if mid:
                    seen_ids.add(mid)
                append_log(args.log, "READ", m)
            save_state(args.state, seen_ids)
        else:
            print("[watcher] No new messages for target")

    if args.once:
        tick()
        return

    try:
        while True:
            tick()
            time.sleep(max(5, args.interval))
    except KeyboardInterrupt:
        print("Watcher stopped by user.")


if __name__ == "__main__":
    main()
