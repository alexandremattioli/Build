#!/usr/bin/env python3
import requests
import os

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

r = requests.get(f"{base}/rest/api/3/project/search", params={"expand":"lead"}, auth=auth)
if r.status_code != 200:
    print(f"Error: {r.status_code} {r.text}")
    raise SystemExit(1)

data = r.json()
print(f"Total projects: {data.get('total')}")
for p in data.get('values', []):
    print(f"- {p.get('key')}: {p.get('name')} (id={p.get('id')})")
