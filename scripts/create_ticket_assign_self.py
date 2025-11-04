#!/usr/bin/env python3
import requests
import sys
import os

# Load config
cfg = {}
with open(os.path.expanduser('~/.config/jira/config')) as f:
    for line in f:
        if '=' in line:
            k, v = line.strip().split('=', 1)
            cfg[k] = v

with open(os.path.expanduser('~/.config/jira/api_token')) as f:
    token = f.read().strip()

base = cfg['JIRA_URL'].rstrip('/')
auth = (cfg['JIRA_EMAIL'], token)
project = cfg['JIRA_PROJECT']

summary = sys.argv[1] if len(sys.argv) > 1 else "Test - Copilot assignment check"
description = sys.argv[2] if len(sys.argv) > 2 else "Created by automation to verify assignment to current user (Copilot)."
issue_type = sys.argv[3] if len(sys.argv) > 3 else "Task"

# Get current user for accountId
me = requests.get(f"{base}/rest/api/3/myself", auth=auth)
if me.status_code != 200:
    print(f"Auth failed: {me.status_code} {me.text}")
    sys.exit(1)
account_id = me.json().get('accountId')
if not account_id:
    print("Could not determine accountId for current user")
    sys.exit(1)

issue_data = {
    "fields": {
        "project": {"key": project},
        "summary": summary,
        "description": {
            "type": "doc",
            "version": 1,
            "content": [{
                "type": "paragraph",
                "content": [{"type": "text", "text": description}]
            }]
        },
        "issuetype": {"name": issue_type},
        "assignee": {"id": account_id},
        "reporter": {"id": account_id}
    }
}

resp = requests.post(
    f"{base}/rest/api/3/issue",
    auth=auth,
    headers={"Content-Type": "application/json"},
    json=issue_data
)

if resp.status_code in (200, 201):
    key = resp.json()["key"]
    print(f"✅ Created and assigned: {key}")
    print(f"URL: {base}/browse/{key}")
else:
    # Fallback: create without assignee then assign
    if resp.status_code == 400:
        # Try creating without assignee/reporter, then assign
        issue_data_fallback = issue_data.copy()
        fields = issue_data_fallback["fields"].copy()
        fields.pop("assignee", None)
        fields.pop("reporter", None)
        issue_data_fallback["fields"] = fields
        resp2 = requests.post(
            f"{base}/rest/api/3/issue",
            auth=auth,
            headers={"Content-Type": "application/json"},
            json=issue_data_fallback
        )
        if resp2.status_code in (200, 201):
            key = resp2.json()["key"]
            # Assign
            assign = requests.put(
                f"{base}/rest/api/3/issue/{key}/assignee",
                auth=auth,
                headers={"Content-Type": "application/json"},
                json={"accountId": account_id}
            )
            if assign.status_code == 204:
                print(f"✅ Created {key} and assigned to self")
                print(f"URL: {base}/browse/{key}")
                sys.exit(0)
            else:
                print(f"Created {key} but could not assign: {assign.status_code} {assign.text}")
                print(f"URL: {base}/browse/{key}")
                sys.exit(0)
    print(f"❌ Error {resp.status_code}: {resp.text}")
    sys.exit(1)
