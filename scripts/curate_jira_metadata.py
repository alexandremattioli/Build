#!/usr/bin/env python3
"""
Curate metadata for curated Jira tickets:
- Add labels: vnf, vnf-framework, curated
- Attach non-epic curated issues to the main epic (Epic Link) when possible
  - Fallback to adding an issue link (Relates) to the epic if Epic Link field is not available

Uses docs/curated_ticket_keys.json written by create_and_assign.py
"""
from __future__ import annotations
import os
import json
from typing import Any, Dict, List, Optional

import requests
import create_and_assign as ca

DOCS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "docs"))
KEYS_FILE = os.path.join(DOCS_DIR, "curated_ticket_keys.json")

LABELS = ["vnf", "vnf-framework", "curated"]
MAIN_EPIC_SUMMARY = "VNF Framework - Epic: Architecture & Delivery"
FIELDS = "summary,issuetype,labels,parent"


def load_keys() -> Dict[str, str]:
    with open(KEYS_FILE) as jf:
        return json.load(jf)


def get_fields(issue_key: str) -> Optional[Dict[str, Any]]:
    r = ca.session.get(f"{ca.base}/rest/api/3/issue/{issue_key}", params={"fields": FIELDS}, auth=ca.auth)
    if r.status_code != 200:
        print(f"Warn: fetch {issue_key} failed: {r.status_code} {r.text}")
        return None
    return r.json().get("fields", {})


def put_labels(issue_key: str, existing: List[str]) -> bool:
    new_labels = sorted(set(existing or []) | set(LABELS))
    r = ca.session.put(
        f"{ca.base}/rest/api/3/issue/{issue_key}",
        auth=ca.auth,
        headers={"Content-Type": "application/json"},
        json={"fields": {"labels": new_labels}},
    )
    if r.status_code != 204:
        print(f"Warn: update labels {issue_key} failed: {r.status_code} {r.text}")
        return False
    return True


def find_epic_link_field() -> Optional[str]:
    r = ca.session.get(f"{ca.base}/rest/api/3/field", auth=ca.auth)
    if r.status_code != 200:
        return None
    for fld in r.json():
        name = (fld.get("name") or "").lower()
        key = fld.get("id")
        if name == "epic link" or "epic link" in name:
            return key
    return None


def set_epic_link(issue_key: str, epic_key: str, epic_field_id: str) -> bool:
    r = ca.session.put(
        f"{ca.base}/rest/api/3/issue/{issue_key}",
        auth=ca.auth,
        headers={"Content-Type": "application/json"},
        json={"fields": {epic_field_id: epic_key}},
    )
    return r.status_code == 204


def add_issue_link(issue_key: str, epic_key: str, link_type: str = "Relates") -> bool:
    payload = {
        "type": {"name": link_type},
        "inwardIssue": {"key": issue_key},
        "outwardIssue": {"key": epic_key},
    }
    r = ca.session.post(
        f"{ca.base}/rest/api/3/issueLink",
        auth=ca.auth,
        headers={"Content-Type": "application/json"},
        json=payload,
    )
    # 201 on success
    if r.status_code not in (201, 400):
        # 400 could mean duplicate link; ignore silently
        print(f"Warn: link {issue_key}->{epic_key} failed: {r.status_code} {r.text}")
    return r.status_code in (201, 400)


def main() -> int:
    keys_map = load_keys()
    main_epic_key = keys_map.get(MAIN_EPIC_SUMMARY)
    if not main_epic_key:
        print("ERROR: Main epic key not found in curated_ticket_keys.json; run create_and_assign.py first.")
        return 1

    epic_field_id = find_epic_link_field()  # e.g., customfield_10014
    updated = 0
    linked = 0

    for summary, key in keys_map.items():
        fields = get_fields(key) or {}
        issue_type = (fields.get("issuetype") or {}).get("name", "")
        labels = fields.get("labels") or []
        # Apply labels to all curated issues
        put_labels(key, labels)
        updated += 1

        # Skip epics for epic linking
        if issue_type.lower() == "epic":
            continue
        # Set Epic Link (preferred) or add a relation link
        if epic_field_id:
            ok = set_epic_link(key, main_epic_key, epic_field_id)
            if not ok:
                # fallback to relation
                if add_issue_link(key, main_epic_key):
                    linked += 1
            else:
                linked += 1
        else:
            if add_issue_link(key, main_epic_key):
                linked += 1

    print(f"Labels updated on {updated} issues; epic associated on {linked} issues (via Epic Link or relation).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
