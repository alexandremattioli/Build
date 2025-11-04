#!/usr/bin/env python3
import requests
import os
import sys

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
key = cfg.get('JIRA_PROJECT') or (sys.argv[1] if len(sys.argv) > 1 else None)
if not key:
    print('Provide project key or set JIRA_PROJECT in config')
    sys.exit(1)

auth = (cfg['JIRA_EMAIL'], token)

# Get project details
pr = requests.get(f"{base}/rest/api/3/project/{key}", auth=auth)
if pr.status_code != 200:
    print(f"Project fetch failed: {pr.status_code} {pr.text}")
    sys.exit(2)
proj = pr.json()
print("Project:")
print(f"  name: {proj.get('name')}")
print(f"  key: {proj.get('key')}")
print(f"  id: {proj.get('id')}")
lead = (proj.get('lead') or {})
print(f"  lead: {lead.get('displayName','')} <{lead.get('emailAddress','')}>" )

# Get boards for the project (Agile API)
br = requests.get(f"{base}/rest/agile/1.0/board", params={"projectKeyOrId": proj.get('id')}, auth=auth)
if br.status_code != 200:
    print(f"Boards fetch failed: {br.status_code} {br.text}")
    sys.exit(3)
boards = br.json().get('values', [])
print("Boards:")
for b in boards:
    print(f"  - id: {b.get('id')}, name: {b.get('name')}, type: {b.get('type')}")
    print(f"    url: {base}/jira/software/c/projects/{key}/boards/{b.get('id')}")

# Heuristic pick: board with smallest id, or one named like the project
chosen = None
if boards:
    by_name = [b for b in boards if key in (b.get('name') or '') or (proj.get('name') or '') in (b.get('name') or '')]
    chosen = (by_name[0] if by_name else sorted(boards, key=lambda x: x.get('id'))[0])
    print("Chosen board:")
    print(f"  id: {chosen.get('id')}")
    print(f"  name: {chosen.get('name')}")
    print(f"  url: {base}/jira/software/c/projects/{key}/boards/{chosen.get('id')}")
else:
    print("No boards found for this project.")
