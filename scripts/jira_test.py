#!/usr/bin/env python3
import requests
import json
import os

# Load config
config = {}
with open(os.path.expanduser('~/.config/jira/config')) as f:
    for line in f:
        key, value = line.strip().split('=', 1)
        config[key] = value

with open(os.path.expanduser('~/.config/jira/api_token')) as f:
    token = f.read().strip()

# Jira credentials
auth = (config['JIRA_EMAIL'], token)
base_url = config['JIRA_URL'].rstrip('/')

# Test connection first
print("Testing Jira connection...")
response = requests.get(f"{base_url}/rest/api/3/myself", auth=auth)
print(f"Auth test: {response.status_code}")
if response.status_code == 200:
    user = response.json()
    print(f"Authenticated as: {user['displayName']} ({user['emailAddress']})")

# Create test ticket
print("\nCreating test ticket...")
issue_data = {
    "fields": {
        "project": {"key": config['JIRA_PROJECT']},
        "summary": "VNF Framework Integration Test",
        "description": {
            "type": "doc",
            "version": 1,
            "content": [{
                "type": "paragraph",
                "content": [{
                    "type": "text",
                    "text": "Testing Jira API integration from Build2. VNF Framework implementation is complete with Java plugin and Python broker."
                }]
            }]
        },
        "issuetype": {"name": "Task"}
    }
}

response = requests.post(
    f"{base_url}/rest/api/3/issue",
    auth=auth,
    headers={"Content-Type": "application/json"},
    json=issue_data
)

print(f"Create ticket: {response.status_code}")
if response.status_code in [200, 201]:
    result = response.json()
    print(f"✅ Ticket created: {result['key']}")
    print(f"URL: {base_url}/browse/{result['key']}")
else:
    print(f"❌ Error: {response.text}")
