#!/usr/bin/env python3
import requests
import os
import sys

if len(sys.argv) < 2:
    print("Usage: move_to_backlog.py <ISSUE_KEY>")
    sys.exit(1)

issue_key = sys.argv[1]

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

# 1) Ensure status is To Do if possible
transitions = requests.get(f"{base}/rest/api/3/issue/{issue_key}/transitions", auth=auth)
if transitions.status_code == 200:
    data = transitions.json()
    to_do = None
    for t in data.get('transitions', []):
        name = t.get('name', '').lower()
        to_status = (t.get('to') or {}).get('name', '').lower()
        if name == 'to do' or to_status == 'to do' or name == 'todo' or to_status == 'todo':
            to_do = t.get('id')
            break
    if to_do:
        r = requests.post(
            f"{base}/rest/api/3/issue/{issue_key}/transitions",
            auth=auth,
            headers={"Content-Type": "application/json"},
            json={"transition": {"id": to_do}}
        )
        if r.status_code not in (204, 200):
            print(f"Warn: transition failed: {r.status_code} {r.text}")
    else:
        pass
else:
    print(f"Warn: cannot fetch transitions: {transitions.status_code} {transitions.text}")

# 2) Move issue to backlog (Agile API)
resp = requests.post(
    f"{base}/rest/agile/1.0/backlog/issue",
    auth=auth,
    headers={"Content-Type": "application/json"},
    json={"issues": [issue_key]}
)
if resp.status_code in (204, 200):
    print(f"✅ {issue_key} moved to backlog")
else:
    print(f"❌ Move to backlog failed: {resp.status_code} {resp.text}")
    sys.exit(1)

# 3) Verify via Agile issue endpoint
check = requests.get(f"{base}/rest/agile/1.0/issue/{issue_key}", auth=auth)
if check.status_code == 200:
    fields = check.json().get('fields', {})
    sprint = fields.get('sprint')
    status = (fields.get('status') or {}).get('name')
    print(f"Status: {status}, Sprint: {sprint and sprint.get('name')}")
else:
    print(f"Warn: cannot verify via agile API: {check.status_code}")
