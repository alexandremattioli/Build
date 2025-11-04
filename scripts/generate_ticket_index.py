#!/usr/bin/env python3
"""
Generate a markdown index of curated Jira tickets with links, type, status,
assignee, and reporter, using the locally persisted keys map.
"""
from __future__ import annotations
import os
import json
from typing import Any, Dict

import create_and_assign as ca

DOCS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "docs"))
KEYS_FILE = os.path.join(DOCS_DIR, "curated_ticket_keys.json")
OUT_FILE = os.path.join(DOCS_DIR, "JIRA_CURATED_TICKETS.md")

FIELDS = "summary,issuetype,status,assignee,reporter,labels,parent"


def fmt_user(u: Dict[str, Any] | None) -> str:
    if not u:
        return "(none)"
    dn = u.get("displayName") or ""
    email = u.get("emailAddress") or ""
    if email:
        return f"{dn} <{email}>"
    return dn


def main() -> int:
    if not os.path.exists(KEYS_FILE):
        print(f"Missing keys map: {KEYS_FILE}. Run create_and_assign.py first.")
        return 1
    with open(KEYS_FILE) as jf:
        keys_map: Dict[str, str] = json.load(jf)

    rows = []
    for summary in ca.TICKETS:
        s = summary["summary"]
        key = keys_map.get(s)
        if not key:
            rows.append(("(missing)", s, "", "", "", "", "", ""))
            continue
        r = ca.session.get(
            f"{ca.base}/rest/api/3/issue/{key}",
            params={"fields": FIELDS},
            auth=ca.auth,
        )
        if r.status_code != 200:
            rows.append((key, s, "(error)", "", "", "", "", ""))
            continue
        fields = r.json().get("fields", {})
        itype = (fields.get("issuetype") or {}).get("name", "")
        status = (fields.get("status") or {}).get("name", "")
        assignee = fmt_user(fields.get("assignee"))
        reporter = fmt_user(fields.get("reporter"))
        labels = ",".join((fields.get("labels") or []))
        # 'parent' is present for sub-tasks or for stories linked under epic in some Jira configs; Epic Link may not surface as parent
        parent = fields.get("parent", {})
        parent_key = parent.get("key", "")
        rows.append((key, s, itype, status, assignee, reporter, labels, parent_key))

    base_url = ca.base.rstrip("/")
    lines = []
    lines.append("# Curated Jira Tickets Index\n")
    lines.append(f"Project: {ca.project}  ")
    lines.append("\n")
    lines.append("| Key | Summary | Type | Status | Assignee | Reporter | Labels | Parent |\n")
    lines.append("|-----|---------|------|--------|----------|----------|--------|--------|\n")
    for key, s, itype, status, assignee, reporter, labels, parent_key in rows:
        if key.startswith("("):
            link = key
        else:
            link = f"[{key}]({base_url}/browse/{key})"
        # Escape vertical bars in summary
        s2 = s.replace("|", "\\|")
        lines.append(f"| {link} | {s2} | {itype} | {status} | {assignee} | {reporter} | {labels} | {parent_key} |\n")

    with open(OUT_FILE, "w") as f:
        f.writelines(lines)
    print(f"Wrote index: {OUT_FILE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
