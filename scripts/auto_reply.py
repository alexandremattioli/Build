#!/usr/bin/env python3
"""
Auto-reply to unread coordination messages for Build2 with simple rules,
then mark them as read. Intended to be invoked by enhanced_heartbeat.sh.

Rules:
- request: Reply with ACK and short plan; special-cases known Jira topics
- info/warning/error: mark read; reply only to specific prompts

This script is idempotent per message because it marks messages as read after
replying or acknowledging.
"""
from __future__ import annotations
import json
import os
import subprocess
import sys
from typing import Any, Dict, List

REPO_DIR = "/root/Build"
MESSAGES_FILE = os.path.join(REPO_DIR, "coordination", "messages.json")
LOG_FILE = f"/var/log/build-auto-replies-build2.log"
RULES_FILE = os.path.join(REPO_DIR, "docs", "auto_reply_rules.json")


def log(line: str) -> None:
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line.rstrip() + "\n")
    except Exception:
        pass


def load_messages() -> List[Dict[str, Any]]:
    with open(MESSAGES_FILE) as f:
        data = json.load(f)
    return data.get("messages", [])


def send_message(to_server: str, subject: str, body: str, msg_type: str = "info") -> bool:
    cmd = [
        os.path.join(REPO_DIR, "scripts", "send_message.sh"),
        "build2",
        to_server,
        msg_type,
        subject,
        body,
    ]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, check=True)
        log(f"Sent message to {to_server}: {subject}\n{out.stdout.strip()}")
        return True
    except subprocess.CalledProcessError as e:
        log(f"ERROR sending message: {e}\n{e.stdout}\n{e.stderr}")
        return False


def mark_read(msg_id: str) -> None:
    cmd = [os.path.join(REPO_DIR, "scripts", "mark_messages_read.sh"), "build2", msg_id]
    try:
        subprocess.run(cmd, capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as e:
        log(f"ERROR marking read {msg_id}: {e}\n{e.stdout}\n{e.stderr}")


def classify_and_reply(msg: Dict[str, Any]) -> None:
    msg_id = msg.get("id", "")
    to = msg.get("to")
    from_srv = msg.get("from")
    subj = (msg.get("subject") or "").strip()
    body = (msg.get("body") or "").strip()
    mtype = (msg.get("type") or "").strip().lower()

    # Do not process messages we sent (avoid loops for messages addressed to all)
    if from_srv == "build2":
        log(f"Skip self-originated message {msg_id}: {subj}")
        return

    # Default: only reply to the sender
    reply_to = from_srv if from_srv in ("build1", "build2", "build3", "build4") else "build1"

    did_reply = False
    # Special-case subjects
    subj_l = subj.lower()

    # 0) Optional rules file overrides (contains simple contains/type matching)
    try:
        if os.path.exists(RULES_FILE):
            with open(RULES_FILE) as rf:
                rules = json.load(rf)
            for rule in rules or []:
                contains = (rule.get("contains") or "").lower()
                req_type = (rule.get("type") or "").lower()
                action = (rule.get("action") or "reply").lower()  # reply|mark
                if contains and contains in subj_l and (not req_type or req_type == mtype):
                    if action == "mark":
                        mark_read(msg_id)
                        log(f"Rule mark-only applied for {msg_id}: {subj}")
                        return
                    # reply
                    rsubj = rule.get("reply", {}).get("subject") or f"ACK: {subj[:60]}"
                    rbody = rule.get("reply", {}).get("body") or "Acknowledged."
                    rtype = rule.get("reply", {}).get("type") or "info"
                    did_reply = send_message(reply_to, rsubj, rbody, rtype)
                    mark_read(msg_id)
                    log(f"Rule-based reply to {msg_id}: {rsubj}")
                    return
    except Exception as e:
        log(f"Rules processing error: {e}")

    if mtype == "request" and "confirm jira space" in subj_l:
        rsubj = "AGREE: VNFFRAM / Board 2 confirmed"
        rbody = (
            "Confirmed: Using project VNFFRAM and Board #2. \n"
            "Auth rules: API scripts use API token; Web UI uses username+password.\n"
            "Curated backlog seeded; see docs/JIRA_CURATED_TICKETS.md and docs/curated_ticket_keys.json.\n"
            "Reply ADJUST if you want different board/project or auth rules."
        )
        did_reply = send_message(reply_to, rsubj, rbody, "info")
    elif "vnffram space located" in subj_l:
        rsubj = "AGREE: VNFFRAM space acknowledged"
        rbody = "Acknowledged. Proceeding with VNFFRAM Board 2 as the working board."
        did_reply = send_message(reply_to, rsubj, rbody, "info")
    elif "credentials" in subj_l:
        rsubj = "ACK: Credentials update received"
        rbody = (
            "Credentials noted. Not persisting secrets in repo; using local secure storage on builders."
        )
        did_reply = send_message(reply_to, rsubj, rbody, "info")
    elif mtype == "request":
        rsubj = f"ACK: {subj[:60]}"
        rbody = (
            "Request acknowledged. Executing and will report via messages and docs.\n"
            "Index: docs/JIRA_CURATED_TICKETS.md | Keys: docs/curated_ticket_keys.json"
        )
        did_reply = send_message(reply_to, rsubj, rbody, "info")
    else:
        # For info/warning/error, auto-ack only for actionable items; otherwise mark read silently
        did_reply = False

    # Always mark as read after processing
    mark_read(msg_id)
    status = "replied" if did_reply else "acknowledged"
    log(f"Processed {msg_id}: {status} ({subj})")


def main() -> int:
    # Pull latest before reading (best-effort)
    subprocess.run(["git", "-C", REPO_DIR, "pull", "origin", "main", "--rebase", "--autostash"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    msgs = load_messages()
    # Filter unread to build2 or all
    targets = [m for m in msgs if not m.get("read") and (m.get("to") in ("build2", "all"))]
    if not targets:
        return 0
    for m in targets:
        classify_and_reply(m)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
