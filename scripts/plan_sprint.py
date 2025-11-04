#!/usr/bin/env python3
"""
Plan a sprint (if supported) or a Fix Version for VNFFRAM on the primary board.
- Detect Board ID for VNFFRAM (fallback to 2)
- Try to find/create a sprint and add issues
- If the board does not support sprints (Kanban), create/find a Fix Version and set it on issues

Usage:
  python3 scripts/plan_sprint.py "Phase 1 (VNFFRAM)"  # uses default issue set
  python3 scripts/plan_sprint.py "Custom Sprint" VNFFRAM-111 VNFFRAM-112 ...

Requires: docs/curated_ticket_keys.json and Jira token config (as other scripts)
"""
from __future__ import annotations
import os
import sys
import json
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Any

import requests
import create_and_assign as ca

DOCS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "docs"))
KEYS_FILE = os.path.join(DOCS_DIR, "curated_ticket_keys.json")

DEFAULT_SUMMARIES = [
    "pfSense Lab Integration Testing",
    "CloudStack Integration Tests",
    "New Error Code: VNF_RATE_LIMIT",
    "JWT Migration to RS256",
    "Redis Idempotency Layer",
    "CI/CD Pipeline Setup",
    "Monitoring & Alerting",
    "User Documentation",
]


def load_keys() -> Dict[str, str]:
    with open(KEYS_FILE) as jf:
        return json.load(jf)


def board_id_for_project(project_key: str) -> int:
    # Try agile boards search
    r = ca.session.get(f"{ca.base}/rest/agile/1.0/board", params={"projectKeyOrId": project_key}, auth=ca.auth)
    if r.status_code == 200:
        vals = r.json().get("values", [])
        for b in vals:
            if b.get("type") in ("scrum", "kanban"):
                return b.get("id", 2)
    # Fallback to known board id
    return 2


def find_or_create_sprint(board_id: int, name: str) -> int:
    # List active/future sprints and match by name
    r = ca.session.get(f"{ca.base}/rest/agile/1.0/board/{board_id}/sprint", params={"state": "active,future"}, auth=ca.auth)
    if r.status_code == 200:
        for s in r.json().get("values", []):
            if s.get("name") == name:
                return s.get("id")
    # Create new sprint
    start = datetime.now(timezone.utc)
    end = start + timedelta(days=7)
    payload = {
        "name": name,
        "originBoardId": board_id,
    "startDate": start.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
    "endDate": end.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        # state omitted => created as future sprint
    }
    r = ca.session.post(f"{ca.base}/rest/agile/1.0/sprint", auth=ca.auth, json=payload, headers={"Content-Type": "application/json"})
    if r.status_code in (200, 201):
        return r.json().get("id")
    else:
        print(f"ERROR: sprint create failed: {r.status_code} {r.text}")
        return -1


def add_issues_to_sprint(sprint_id: int, issue_keys: List[str]) -> None:
    if not issue_keys:
        print("No issues to add")
        return
    r = ca.session.post(
        f"{ca.base}/rest/agile/1.0/sprint/{sprint_id}/issue",
        auth=ca.auth,
        headers={"Content-Type": "application/json"},
        json={"issues": issue_keys},
    )
    if r.status_code not in (204, 200):
        print(f"ERROR: add issues failed: {r.status_code} {r.text}")
        raise SystemExit(1)


def get_project_id(project_key: str) -> int:
    r = ca.session.get(f"{ca.base}/rest/api/3/project/{project_key}", auth=ca.auth)
    r.raise_for_status()
    return int(r.json().get("id"))


def find_or_create_version(project_id: int, name: str) -> Dict[str, Any]:
    # List existing versions
    r = ca.session.get(f"{ca.base}/rest/api/3/project/{project_id}/versions", auth=ca.auth)
    if r.status_code == 200:
        for v in r.json():
            if v.get("name") == name:
                return v
    # Create version
    payload = {"name": name, "projectId": project_id}
    r = ca.session.post(f"{ca.base}/rest/api/3/version", auth=ca.auth, json=payload, headers={"Content-Type": "application/json"})
    if r.status_code in (200, 201):
        return r.json()
    print(f"ERROR: version create failed: {r.status_code} {r.text}")
    raise SystemExit(1)


def set_fix_versions(issue_key: str, version_id: int) -> bool:
    payload = {"fields": {"fixVersions": [{"id": str(version_id)}]}}
    r = ca.session.put(f"{ca.base}/rest/api/3/issue/{issue_key}", auth=ca.auth, json=payload, headers={"Content-Type": "application/json"})
    return r.status_code == 204


def main() -> int:
    if not os.path.exists(KEYS_FILE):
        print("Missing keys map; run create_and_assign.py first")
        return 1
    keys_map = load_keys()

    if len(sys.argv) < 2:
        sprint_name = "Phase 1 (VNFFRAM)"
        target_summaries = DEFAULT_SUMMARIES
    else:
        sprint_name = sys.argv[1]
        if len(sys.argv) > 2:
            target_keys = sys.argv[2:]
        else:
            target_keys = [keys_map[s] for s in DEFAULT_SUMMARIES if s in keys_map]

    board_id = board_id_for_project(ca.project)
    sprint_id = find_or_create_sprint(board_id, sprint_name)

    # Build issue keys list
    if len(sys.argv) > 2:
        issue_keys = target_keys
    else:
        issue_keys = [keys_map[s] for s in DEFAULT_SUMMARIES if s in keys_map]

    if sprint_id and sprint_id > 0:
        add_issues_to_sprint(sprint_id, issue_keys)
        # Verify placements via Agile API
        placed: List[str] = []
        for k in issue_keys:
            r = ca.session.get(f"{ca.base}/rest/agile/1.0/issue/{k}", auth=ca.auth)
            if r.status_code == 200:
                fields = r.json().get("fields", {})
                sprint = fields.get("sprint")
                if sprint and sprint.get("id") == sprint_id:
                    placed.append(k)
        print(f"Sprint '{sprint_name}' (id={sprint_id}) now contains {len(placed)}/{len(issue_keys)} issues: {', '.join(placed)}")
    else:
        # Fallback to Fix Version grouping
        project_id = get_project_id(ca.project)
        version = find_or_create_version(project_id, sprint_name)
        vid = int(version.get("id"))
        updated = 0
        for k in issue_keys:
            if set_fix_versions(k, vid):
                updated += 1
        print(f"Board does not support sprints. Applied Fix Version '{sprint_name}' (id={vid}) to {updated}/{len(issue_keys)} issues: {', '.join(issue_keys)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
