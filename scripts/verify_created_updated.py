#!/usr/bin/env python3
"""
Verify reporter and assignee for curated VNF Framework tickets.

This reuses the curated ticket list and helpers from create_and_assign.py to
find each issue by summary, then fetches reporter/assignee/status/type fields
for confirmation.
"""
from __future__ import annotations
import sys
from typing import Any, Dict

# Reuse config/session/helpers and curated TICKETS
import create_and_assign as ca

FIELDS = "summary,issuetype,status,assignee,reporter"


def get_issue_fields(issue_key: str) -> Dict[str, Any] | None:
    r = ca.session.get(
        f"{ca.base}/rest/api/3/issue/{issue_key}",
        params={"fields": FIELDS},
        auth=ca.auth,
    )
    if r.status_code != 200:
        print(f"Failed to fetch {issue_key}: {r.status_code} {r.text}")
        return None
    return r.json().get("fields", {})


def fetch_project_issues() -> list[dict]:
    """Fetch all issues in the configured project with select fields."""
    issues: list[dict] = []
    start_at = 0
    max_results = 100
    jql = f"project={ca.project} ORDER BY created ASC"
    while True:
        r = ca.session.get(
            f"{ca.base}/rest/api/3/search",
            params={
                "jql": jql,
                "startAt": start_at,
                "maxResults": max_results,
                "fields": FIELDS,
            },
            auth=ca.auth,
        )
        if r.status_code != 200:
            print(f"Search error: {r.status_code} {r.text}")
            break
        data = r.json()
        batch = data.get("issues", [])
        issues.extend(batch)
        if len(batch) < max_results:
            break
        start_at += max_results
    return issues


def fmt_user(u: Dict[str, Any] | None) -> str:
    if not u:
        return "(none)"
    dn = u.get("displayName") or ""
    email = u.get("emailAddress") or ""
    if email:
        return f"{dn} <{email}>"
    return dn


def main() -> int:
    print(f"Reporter (expected self): {ca.me.get('displayName')}")
    args = sys.argv[1:]
    verified = 0
    missing = 0

    if args:
        # Treat args as explicit issue keys
        for key in args:
            fields = get_issue_fields(key)
            if not fields:
                print(f"- MISSING: {key}")
                missing += 1
                continue
            assignee = fmt_user(fields.get("assignee"))
            reporter = fmt_user(fields.get("reporter"))
            status = (fields.get("status") or {}).get("name", "")
            itype = (fields.get("issuetype") or {}).get("name", "")
            summary = fields.get("summary", "")
            print(f"- {key}: [{itype} | {status}] Assignee={assignee} Reporter={reporter} :: {summary}")
            verified += 1
        print(f"Verified {verified} tickets; {missing} missing")
        return 0

    # No args provided: fall back to project-wide fetch and match by summary
    issues = fetch_project_issues()
    by_summary: dict[str, dict] = {}
    for i in issues:
        fields = i.get("fields", {})
        s = fields.get("summary") or ""
        if s and s not in by_summary:
            by_summary[s] = i

    for t in ca.TICKETS:
        summary = t["summary"]
        i = by_summary.get(summary)
        if not i:
            print(f"- MISSING: {summary}")
            missing += 1
            continue
        fields = i.get("fields", {})
        assignee = fmt_user(fields.get("assignee"))
        reporter = fmt_user(fields.get("reporter"))
        status = (fields.get("status") or {}).get("name", "")
        itype = (fields.get("issuetype") or {}).get("name", "")
        print(f"- {i.get('key')}: [{itype} | {status}] Assignee={assignee} Reporter={reporter} :: {summary}")
        verified += 1
    print(f"Verified {verified} tickets; {missing} missing")
    return 0


if __name__ == "__main__":
    sys.exit(main())
