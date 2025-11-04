#!/usr/bin/env python3
import requests
import sys
import os

if len(sys.argv) < 2:
    print("Usage: user_lookup.py <query/email>")
    sys.exit(1)

query = sys.argv[1]

# Load config
config = {}
with open(os.path.expanduser('~/.config/jira/config')) as f:
    for line in f:
        if '=' in line:
            k, v = line.strip().split('=', 1)
            config[k] = v

with open(os.path.expanduser('~/.config/jira/api_token')) as f:
    token = f.read().strip()

auth = (config['JIRA_EMAIL'], token)
base = config['JIRA_URL'].rstrip('/')

# Jira Cloud user search (GDPR): use /user/search with 'query'
r = requests.get(f"{base}/rest/api/3/user/search", params={"query": query}, auth=auth)
print(f"Status: {r.status_code}")
if r.status_code != 200:
    print(r.text)
    sys.exit(1)

users = r.json()
if not users:
    print("No users found")
    sys.exit(2)

for u in users:
    print(f"displayName={u.get('displayName')}")
    print(f"emailAddress={u.get('emailAddress','')}")
    print(f"accountId={u.get('accountId')}")
    print("---")
