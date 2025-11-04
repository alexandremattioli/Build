#!/usr/bin/env python3
import requests
import sys
import os

if len(sys.argv) < 3:
    print("Usage: create_ticket_with_assignment.py <summary> <description> <type> <assignee>")
    print("Assignee: 'builder2', 'codex', or 'unassigned'")
    sys.exit(1)

# Load config
config = {}
with open(os.path.expanduser('~/.config/jira/config')) as f:
    for line in f:
        if '=' in line:
            key, value = line.strip().split('=', 1)
            config[key] = value

auth = (config['JIRA_EMAIL'], config['JIRA_PASSWORD'])
base_url = config['JIRA_URL'].rstrip('/')

summary = sys.argv[1]
description = sys.argv[2]
issue_type = sys.argv[3] if len(sys.argv) > 3 else "Task"
assignee = sys.argv[4] if len(sys.argv) > 4 else "unassigned"

# Map assignee names to account IDs (need to lookup first time)
assignee_map = {
    'builder2': 'alexandre@mattioli.co.uk',
    'codex': 'codex@mattioli.co.uk',
    'copilot': 'copilot@mattioli.co.uk'
}

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

# Create the ticket
response = requests.post(
    f"{base_url}/rest/api/3/issue",
    auth=auth,
    headers={"Content-Type": "application/json"},
    json=issue_data
)

if response.status_code in [200, 201]:
    result = response.json()
    ticket_key = result['key']
    print(f"✅ Ticket created: {ticket_key}")
    
    # Try to assign if not unassigned
    if assignee != 'unassigned' and assignee in assignee_map:
        assign_response = requests.put(
            f"{base_url}/rest/api/3/issue/{ticket_key}/assignee",
            auth=auth,
            headers={"Content-Type": "application/json"},
            json={"accountId": assignee_map.get(assignee.lower())}
        )
        if assign_response.status_code == 204:
            print(f"   Assigned to: {assignee}")
        else:
            print(f"   ⚠️  Could not assign (will be unassigned)")
    
    print(f"URL: {base_url}/browse/{ticket_key}")
else:
    print(f"❌ Error {response.status_code}: {response.text}")
    sys.exit(1)
