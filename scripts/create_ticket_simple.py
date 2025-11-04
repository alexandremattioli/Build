#!/usr/bin/env python3
import requests
import sys
import os

if len(sys.argv) < 3:
    print("Usage: create_ticket_simple.py <summary> <description> <type>")
    sys.exit(1)

# Load config
config = {}
with open(os.path.expanduser('~/.config/jira/config')) as f:
    for line in f:
        if '=' in line:
            key, value = line.strip().split('=', 1)
            config[key] = value

# Use API token
with open(os.path.expanduser('~/.config/jira/api_token')) as f:
    token = f.read().strip()

auth = (config['JIRA_EMAIL'], token)
base_url = config['JIRA_URL'].rstrip('/')

summary = sys.argv[1]
description = sys.argv[2]
issue_type = sys.argv[3] if len(sys.argv) > 3 else "Task"

issue_data = {
    "fields": {
        "project": {"key": config['JIRA_PROJECT']},
        "summary": summary,
        "description": {
            "type": "doc",
            "version": 1,
            "content": [{
                "type": "paragraph",
                "content": [{
                    "type": "text",
                    "text": description
                }]
            }]
        },
        "issuetype": {"name": issue_type}
    }
}

response = requests.post(
    f"{base_url}/rest/api/3/issue",
    auth=auth,
    headers={"Content-Type": "application/json"},
    json=issue_data
)

if response.status_code in [200, 201]:
    result = response.json()
    print(f"✅ {result['key']}")
else:
    print(f"❌ Error {response.status_code}")
    sys.exit(1)
