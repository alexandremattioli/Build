#!/usr/bin/env python3
import requests
import os
import sys
import json
from typing import Dict, Any, List

# Load config
cfg: Dict[str, str] = {}
with open(os.path.expanduser('~/.config/jira/config')) as f:
    for line in f:
        if '=' in line:
            k, v = line.strip().split('=', 1)
            cfg[k] = v
with open(os.path.expanduser('~/.config/jira/api_token')) as f:
    token = f.read().strip()

base = cfg['JIRA_URL'].rstrip('/')
auth = (cfg['JIRA_EMAIL'], token)
project = cfg.get('JIRA_PROJECT', 'VNFFRAM')

session = requests.Session()

# Local mapping to avoid duplicates when remote search API changes
DOCS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "docs"))
os.makedirs(DOCS_DIR, exist_ok=True)
KEYS_FILE = os.path.join(DOCS_DIR, "curated_ticket_keys.json")
RUN_FILE = os.path.join(DOCS_DIR, "curated_ticket_run_LAST.json")

keys_map: Dict[str, str] = {}
if os.path.exists(KEYS_FILE):
    try:
        with open(KEYS_FILE) as jf:
            data = json.load(jf)
            if isinstance(data, dict):
                # Only keep string-to-string mappings
                keys_map = {str(k): str(v) for k, v in data.items()}
    except Exception:
        # Ignore malformed file
        keys_map = {}


def get_me() -> Dict[str, Any]:
    r = session.get(f"{base}/rest/api/3/myself", auth=auth)
    r.raise_for_status()
    return r.json()


def find_user_account_id(query: str) -> str | None:
    # Jira Cloud: GDPR-safe search; 'query' matches displayName/email if permitted
    r = session.get(f"{base}/rest/api/3/user/search", params={'query': query}, auth=auth)
    if r.status_code != 200:
        return None
    users = r.json()
    if not users:
        return None
    return users[0].get('accountId')


def search_issue_by_summary(summary: str) -> str | None:
    # First check local mapping to avoid duplicate creations if remote search is unavailable
    if summary in keys_map:
        return keys_map[summary]
    # Try legacy search endpoint (may be removed on some Jira Cloud instances)
    jql = f'project={project} AND summary ~ "\"{summary}\""'
    r = session.get(
        f"{base}/rest/api/3/search",
        params={'jql': jql, 'maxResults': 1, 'fields': 'summary'},
        auth=auth,
    )
    if r.status_code == 200:
        data = r.json()
        issues = data.get('issues', [])
        if issues:
            return issues[0].get('key')
    # Fallback: no remote search; return None to allow creation
    return None


def create_issue(summary: str, description: str, issue_type: str) -> str | None:
    payload = {
        'fields': {
            'project': {'key': project},
            'summary': summary,
            'description': {
                'type': 'doc',
                'version': 1,
                'content': [{
                    'type': 'paragraph',
                    'content': [{'type': 'text', 'text': description}]
                }]
            },
            'issuetype': {'name': issue_type},
        }
    }
    r = session.post(f"{base}/rest/api/3/issue", auth=auth, json=payload, headers={'Content-Type': 'application/json'})
    if r.status_code in (200, 201):
        return r.json().get('key')
    else:
        print(f"Create failed [{r.status_code}]: {r.text}")
        return None


def assign_issue(key: str, account_id: str) -> bool:
    r = session.put(
        f"{base}/rest/api/3/issue/{key}/assignee",
        auth=auth,
        json={'accountId': account_id},
        headers={'Content-Type': 'application/json'},
    )
    return r.status_code == 204


me = get_me()
my_id = me.get('accountId')

# Resolve Codex account id if available
codex_account = find_user_account_id('codex') or find_user_account_id('codex@mattioli.co.uk')

# Curated tickets (summary, description, type, assign_to: 'copilot'|'codex')
TICKETS: List[Dict[str, Any]] = [
    # Epics / planning
    {
        'summary': 'VNF Framework - Epic: Architecture & Delivery',
        'desc': 'Track overall VNF Framework delivery across Java plugin, Python broker, testing, and deployment.',
        'type': 'Epic', 'assign': 'copilot'
    },

    # Past work (documentation tickets for completed tasks)
    {
        'summary': 'Completed: Java Plugin Implementation',
        'desc': 'Document completion of VNF Framework Java plugin (28 files, 3,548 lines). Includes schema, DAO, services, API, Spring.',
        'type': 'Task', 'assign': 'codex'
    },
    {
        'summary': 'Completed: Python Broker Service',
        'desc': 'Document completion of Flask-based broker with JWT, HTTP proxy, SSH exec, systemd unit, tests, docs.',
        'type': 'Task', 'assign': 'copilot'
    },
    {
        'summary': 'Completed: Messaging Infrastructure between Builds',
        'desc': 'Git-based coordination with notify_build1.sh and cm helper; logs and stats in repo.',
        'type': 'Task', 'assign': 'copilot'
    },
    {
        'summary': 'Completed: Jira Integration & Scripts',
        'desc': 'API token storage, config, and helper scripts for creating/assigning Jira tickets.',
        'type': 'Task', 'assign': 'copilot'
    },

    # Present / near-term work
    {'summary': 'pfSense Lab Integration Testing', 'desc': 'Run end-to-end tests against pfSense lab: deploy, configure, SSH, parser validation, error handling.', 'type': 'Task', 'assign': 'codex'},
    {'summary': 'CloudStack Integration Tests', 'desc': 'End-to-end tests with CloudStack 4.21.7: deploy VNF via API, apply configs, monitor, teardown.', 'type': 'Task', 'assign': 'copilot'},
    {'summary': 'User Documentation', 'desc': 'Create user docs: architecture overview, API reference, deployment guide, examples, troubleshooting.', 'type': 'Task', 'assign': 'copilot'},
    {'summary': 'Developer Guide', 'desc': 'Developer docs: plugin architecture, adding VNF types, custom parsers, broker extension, testing.', 'type': 'Task', 'assign': 'codex'},

    # Enhancements
    {'summary': 'API Context Object', 'desc': 'Add context (networkId, zoneId, accountId) to API and broker client; persist provenance.', 'type': 'Story', 'assign': 'codex'},
    {'summary': 'New Error Code: VNF_RATE_LIMIT', 'desc': 'Introduce VNF_RATE_LIMIT and branch retry logic accordingly; update client and docs.', 'type': 'Story', 'assign': 'copilot'},
    {'summary': 'JWT Migration to RS256', 'desc': 'Generate RSA keypair, update broker to RS256 signing and Java client verification; plan key rotation.', 'type': 'Story', 'assign': 'copilot'},
    {'summary': 'Redis Idempotency Layer', 'desc': 'Add Redis-backed idempotency (request IDs with TTL, dedupe, cached results) including setup and config.', 'type': 'Story', 'assign': 'copilot'},
    {'summary': 'mTLS for Broker→VNF', 'desc': 'Implement mutual TLS for device comms with certificate lifecycle and validation.', 'type': 'Story', 'assign': 'codex'},

    # Ops & quality
    {'summary': 'Production Deployment of Broker', 'desc': 'Harden broker, configure mTLS, monitoring, log aggregation, backups, HA setup.', 'type': 'Task', 'assign': 'copilot'},
    {'summary': 'CI/CD Pipeline Setup', 'desc': 'Automate unit/integration tests, coverage, build, deploy with GitHub Actions.', 'type': 'Task', 'assign': 'copilot'},
    {'summary': 'Monitoring & Alerting', 'desc': 'Add metrics for deployments, latency, availability; alerts on failures and degradation.', 'type': 'Task', 'assign': 'copilot'},

    # Future
    {'summary': 'Multi-Vendor Support', 'desc': 'Add vendor abstraction, parsers, templates; initial targets: pfSense, VyOS, Fortinet.', 'type': 'Epic', 'assign': 'codex'},
    {'summary': 'Advanced Orchestration', 'desc': 'Service chaining, autoscaling, health monitoring, failover, load balancing.', 'type': 'Epic', 'assign': 'copilot'},
]


def main():
    created_or_updated: List[str] = []
    my_name = me.get('displayName')
    for t in TICKETS:
        summary = t['summary']
        desc = t['desc']
        itype = t['type']
        assign_label = t['assign']
        key = search_issue_by_summary(summary)
        if key is None:
            key = create_issue(summary, desc, itype)
            if not key:
                continue
        # Track mapping locally to avoid duplicates next run
        keys_map[summary] = key
        # Assign
        target_id = my_id if assign_label == 'copilot' or codex_account is None and assign_label == 'codex' else codex_account
        if target_id:
            assigned = assign_issue(key, target_id)
        else:
            assigned = False
        created_or_updated.append(f"{key}:{assign_label}:{'assigned' if assigned else 'unassigned'}")

    print(f"Reporter: {my_name}")
    print("Tickets created/updated:")
    for item in created_or_updated:
        print(f" - {item}")
    # Persist mapping and run report
    try:
        with open(KEYS_FILE, 'w') as jf:
            json.dump(keys_map, jf, indent=2)
    except Exception as e:
        print(f"Warning: could not write keys map: {e}")
    try:
        with open(RUN_FILE, 'w') as rf:
            json.dump({
                'reporter': my_name,
                'items': [
                    {'entry': item} for item in created_or_updated
                ]
            }, rf, indent=2)
    except Exception as e:
        print(f"Warning: could not write run report: {e}")

if __name__ == '__main__':
    main()
