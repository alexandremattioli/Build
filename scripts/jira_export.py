#!/usr/bin/env python3
"""
Export Jira issues for a project to a JSON (full) and CSV (summary) file.

Reads Jira config from ~/.config/jira/config and API token from ~/.config/jira/api_token
Requirements: requests
"""
import os
import sys
import json
import csv
from datetime import datetime

import requests


def load_config():
    cfg = {}
    cfg_path = os.path.expanduser("~/.config/jira/config")
    if not os.path.exists(cfg_path):
        print(f"Missing config: {cfg_path}")
        sys.exit(1)
    with open(cfg_path) as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                cfg[k] = v
    token_path = os.path.expanduser("~/.config/jira/api_token")
    if not os.path.exists(token_path):
        print(f"Missing API token: {token_path}")
        sys.exit(1)
    with open(token_path) as f:
        cfg["JIRA_TOKEN"] = f.read().strip()
    return cfg


def fetch_all_issues(base_url, auth, project_key):
    issues = []
    start_at = 0
    max_results = 100
    session = requests.Session()
    jql = f"project={project_key} ORDER BY created ASC"
    while True:
        r = session.get(
            f"{base_url}/rest/api/3/search",
            params={
                "jql": jql,
                "startAt": start_at,
                "maxResults": max_results,
                # Include key fields; description is ADF by default in v3
                "fields": "summary,description,issuetype,status,assignee,reporter,labels,created,updated,parent,priority"
            },
            auth=auth,
        )
        if r.status_code != 200:
            print(f"Error fetching issues: {r.status_code} {r.text}")
            sys.exit(2)
        data = r.json()
        batch = data.get("issues", [])
        issues.extend(batch)
        if len(batch) < max_results:
            break
        start_at += max_results
    return issues


def write_outputs(issues, project_key):
    out_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "docs"))
    os.makedirs(out_dir, exist_ok=True)
    ts = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    json_path = os.path.join(out_dir, f"{project_key}_issues_{ts}.json")
    csv_path = os.path.join(out_dir, f"{project_key}_issues_{ts}.csv")

    with open(json_path, "w") as jf:
        json.dump({"issues": issues}, jf, indent=2)

    with open(csv_path, "w", newline="") as cf:
        writer = csv.writer(cf)
        writer.writerow(["key", "summary", "type", "status", "assignee", "reporter", "created", "updated", "labels"])
        for i in issues:
            fields = i.get("fields", {})
            writer.writerow([
                i.get("key"),
                (fields.get("summary") or "").replace("\n", " ").strip(),
                (fields.get("issuetype", {}) or {}).get("name"),
                (fields.get("status", {}) or {}).get("name"),
                (fields.get("assignee", {}) or {}).get("emailAddress", ""),
                (fields.get("reporter", {}) or {}).get("emailAddress", ""),
                fields.get("created"),
                fields.get("updated"),
                ",".join(fields.get("labels", []) or []),
            ])

    return json_path, csv_path


def main():
    cfg = load_config()
    base_url = cfg["JIRA_URL"].rstrip("/")
    auth = (cfg["JIRA_EMAIL"], cfg["JIRA_TOKEN"])
    project_key = cfg.get("JIRA_PROJECT") or (sys.argv[1] if len(sys.argv) > 1 else None)
    if not project_key:
        print("Usage: jira_export.py [PROJECT_KEY]  # or set JIRA_PROJECT in config")
        sys.exit(1)

    print(f"Exporting issues for project {project_key}...")
    issues = fetch_all_issues(base_url, auth, project_key)
    print(f"Fetched {len(issues)} issues")
    json_path, csv_path = write_outputs(issues, project_key)
    print(f"Wrote JSON: {json_path}")
    print(f"Wrote CSV:  {csv_path}")


if __name__ == "__main__":
    main()
