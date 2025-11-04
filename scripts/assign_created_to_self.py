#!/usr/bin/env python3
import requests
import os
import sys

def load_cfg():
    cfg = {}
    with open(os.path.expanduser('~/.config/jira/config')) as f:
        for line in f:
            if '=' in line:
                k, v = line.strip().split('=', 1)
                cfg[k] = v
    with open(os.path.expanduser('~/.config/jira/api_token')) as f:
        cfg['JIRA_TOKEN'] = f.read().strip()
    return cfg


def get_me(base, auth):
    r = requests.get(f"{base}/rest/api/3/myself", auth=auth)
    r.raise_for_status()
    return r.json()


def search_issues(base, auth, jql):
    all_issues = []
    start_at = 0
    max_results = 100
    while True:
        r = requests.get(
            f"{base}/rest/api/3/search",
            params={
                'jql': jql,
                'startAt': start_at,
                'maxResults': max_results,
                'fields': 'summary,assignee,reporter,status'
            },
            auth=auth,
        )
        r.raise_for_status()
        data = r.json()
        issues = data.get('issues', [])
        all_issues.extend(issues)
        if len(issues) < max_results:
            break
        start_at += max_results
    return all_issues


def assign_issue(base, auth, key, account_id):
    r = requests.put(
        f"{base}/rest/api/3/issue/{key}/assignee",
        auth=auth,
        headers={'Content-Type': 'application/json'},
        json={'accountId': account_id}
    )
    return r.status_code


def main():
    cfg = load_cfg()
    base = cfg['JIRA_URL'].rstrip('/')
    auth = (cfg['JIRA_EMAIL'], cfg['JIRA_TOKEN'])
    project = cfg.get('JIRA_PROJECT', 'VNFFRAM')

    me = get_me(base, auth)
    my_id = me.get('accountId')
    my_name = me.get('displayName')

    # Find issues reported by current user that are unassigned or assigned to others
    jql = f"project={project} AND reporter = currentUser()"
    issues = search_issues(base, auth, jql)

    assigned = []
    skipped = []
    for it in issues:
        key = it.get('key')
        fields = it.get('fields', {})
        assignee = fields.get('assignee')
        assignee_id = assignee and assignee.get('accountId')
        if assignee_id == my_id:
            skipped.append((key, 'already-assigned'))
            continue
        code = assign_issue(base, auth, key, my_id)
        if code == 204:
            assigned.append(key)
        else:
            skipped.append((key, f'assign-failed:{code}'))

    print(f"User: {my_name}")
    print(f"Assigned to self: {len(assigned)} -> {', '.join(assigned) if assigned else '-'}")
    if skipped:
        print("Skipped:")
        for key, reason in skipped[:20]:
            print(f"  - {key}: {reason}")
        if len(skipped) > 20:
            print(f"  ... and {len(skipped)-20} more")

if __name__ == '__main__':
    main()
