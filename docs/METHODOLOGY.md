# Communication Methodology Specification

## Design Principles

1. **Stateless Operations**: Each git pull provides complete current state
2. **Eventual Consistency**: Brief delays acceptable for non-critical updates
3. **Idempotent Updates**: Same operation can be safely repeated
4. **Explicit Locking**: Critical sections protected by lock files
5. **Self-Healing**: Expired locks automatically released
6. **Two-Track Implementation**: Build1 and Build2 each deliver complete implementations independently (no split ownership)
7. **Automation-First**: Prefer scripts and daemons over manual steps; everything repeatable and idempotent
8. **Minimal Human Protocol**: Requests/agreements use short, typed messages with machine-readable fields where feasible

## Collaboration Policy (Build1 ↔ Build2)

- Both builds implement the entire feature; do not divide by layers or modules.
- Share approaches and review each other’s work; use messages for milestones/decisions.
- Keep work observable: status.json, logs/, build reports, and concise messages.
- Prefer converging artifacts: compare, then synthesize the best of both.

Rationale: redundancy, quality via divergence, full-system understanding, speed via parallel completeness.

## Detailed Protocol Specifications

### Lock Acquisition Protocol

```python
def acquire_lock(lock_name, server_id, timeout_seconds=30):
    """
    Acquire a named lock with automatic expiration
    """
    max_retries = 5
    for attempt in range(max_retries):
        # Pull latest state
        git_pull()
        
        # Read current locks
        locks = read_json('coordination/locks.json')
        
        # Check if lock is available or expired
        if lock_name not in locks['locks']:
            locks['locks'][lock_name] = {}
            
        current_lock = locks['locks'][lock_name]
        now = current_timestamp()
        
        # Lock available if not held or expired
        if not current_lock.get('locked_by') or \
           current_lock.get('expires_at', 0) < now:
            # Attempt to acquire
            current_lock['locked_by'] = server_id
            current_lock['locked_at'] = now
            current_lock['expires_at'] = now + timeout_seconds
            
            write_json('coordination/locks.json', locks)
            
            if git_commit_and_push(f'Lock {lock_name} acquired by {server_id}'):
                return True
            else:
                # Push failed, retry
                sleep(random(1, 5))
                continue
        else:
            # Lock held by another server, wait and retry
            wait_time = min(5, timeout_seconds / 10)
            sleep(wait_time)
    
    return False

def release_lock(lock_name, server_id):
    """
    Release a lock only if we hold it
    """
    git_pull()
    locks = read_json('coordination/locks.json')
    
    if locks['locks'].get(lock_name, {}).get('locked_by') == server_id:
        locks['locks'][lock_name] = {
            'locked_by': None,
            'locked_at': None,
            'expires_at': None
        }
        write_json('coordination/locks.json', locks)
        git_commit_and_push(f'Lock {lock_name} released by {server_id}')
```

### Job Assignment Protocol

```python
def claim_next_job(server_id):
    """
    Atomically claim the next available job
    """
    if not acquire_lock('job_assignment', server_id):
        return None
    
    try:
        git_pull()
        jobs = read_json('coordination/jobs.json')
        
        # Find highest priority queued job
        available = [j for j in jobs['jobs'] 
                     if j['status'] == 'queued' and j['assigned_to'] is None]
        
        if not available:
            return None
        
        # Sort by priority (lower number = higher priority), then by created_at
        available.sort(key=lambda j: (j['priority'], j['created_at']))
        next_job = available[0]
        
        # Claim the job
        next_job['assigned_to'] = server_id
        next_job['status'] = 'running'
        next_job['started_at'] = current_timestamp()
        
        write_json('coordination/jobs.json', jobs)
        git_commit_and_push(f'Job {next_job["id"]} claimed by {server_id}')
        
        return next_job
    finally:
        release_lock('job_assignment', server_id)
```

### Status Update Protocol

```python
def update_status(server_id, status_data):
    """
    Update server status (no lock needed - each server owns its status)
    """
    git_pull()
    
    status_file = f'{server_id}/status.json'
    status_data['timestamp'] = current_timestamp()
    
    write_json(status_file, status_data)
    git_commit_and_push(f'{server_id} status: {status_data["status"]}')
```

### Message Protocol

```python
def send_message(from_server, to_server, msg_type, subject, body):
    """
    Send a message to another server or broadcast
    """
    if not acquire_lock('message_queue', from_server, timeout_seconds=10):
        log_error('Failed to acquire message lock')
        return False
    
    try:
        git_pull()
        messages = read_json('coordination/messages.json')
        
        new_message = {
            'id': generate_uuid(),
            'from': from_server,
            'to': to_server,  # or 'all' for broadcast
            'type': msg_type,
            'subject': subject,
            'body': body,
            'timestamp': current_timestamp(),
            'read': False
        }
        
        messages['messages'].append(new_message)
        write_json('coordination/messages.json', messages)
        git_commit_and_push(f'Message from {from_server} to {to_server}')
        
        return True
    finally:
        release_lock('message_queue', from_server)

def read_messages(server_id):
    """
    Read messages for this server
    """
    git_pull()
    messages = read_json('coordination/messages.json')
    
    # Filter for messages to this server or 'all'
    my_messages = [m for m in messages['messages']
                   if (m['to'] == server_id or m['to'] == 'all') 
                   and not m['read']]
    
    return my_messages

def mark_message_read(message_id, server_id):
    """
    Mark a message as read
    """
    git_pull()
    messages = read_json('coordination/messages.json')
    
    for msg in messages['messages']:
        if msg['id'] == message_id:
            msg['read'] = True
            break
    
    write_json('coordination/messages.json', messages)
    git_commit_and_push(f'Message {message_id} marked read by {server_id}')
```

### Automatic Message Handling and Replies

Build2 continuously monitors and optionally replies to messages according to rules:

- Daemon: enhanced heartbeat invokes message checker and `auto_reply.py` each cycle
- Rules: `docs/auto_reply_rules.json` supports subject "contains" matching, optional type filter, and actions:
    - `reply`: send a templated response (subject/body/type)
    - `mark`: mark-as-read without reply (to avoid noise)
- Safety: self-originated messages are ignored to prevent loops; all processed messages are marked read

Default semantics:
- `request`: acknowledge and proceed; confirm key decisions (e.g., Jira board, auth rules)
- `info`: mark as read unless actionable
- `warning`/`error`: surface in logs and mark read; follow local runbooks

Outputs:
- Message log: `/var/log/build-messages-build2.log`
- Auto-reply log: `/var/log/build-auto-replies-build2.log`

## Error Handling

### Git Push Conflicts

```bash
# Auto-resolve strategy for status updates
git pull origin main --rebase --autostash
if [ $? -ne 0 ]; then
    # Conflict in our own status file - ours wins
    git checkout --ours build2/status.json
    git add build2/status.json
    git rebase --continue
fi
git push origin main
```

### Orphaned Locks

Locks automatically expire. A cleanup script can run periodically:

```python
def cleanup_expired_locks():
    """
    Release any expired locks
    """
    git_pull()
    locks = read_json('coordination/locks.json')
    now = current_timestamp()
    changed = False
    
    for lock_name, lock_data in locks['locks'].items():
        if lock_data.get('expires_at') and lock_data['expires_at'] < now:
            locks['locks'][lock_name] = {
                'locked_by': None,
                'locked_at': None,
                'expires_at': None
            }
            changed = True
    
    if changed:
        write_json('coordination/locks.json', locks)
        git_commit_and_push('Cleanup expired locks')
```

### Dead Server Detection

```python
def check_server_health(server_id, max_age_seconds=300):
    """
    Check if a server's heartbeat is recent
    """
    git_pull()
    heartbeat = read_json(f'{server_id}/heartbeat.json')
    
    last_beat = parse_timestamp(heartbeat['timestamp'])
    age = current_timestamp() - last_beat
    
    return age < max_age_seconds
```

## Optimization Strategies

### Batched Updates

For non-critical updates, batch multiple changes:

```python
def batched_log_upload(server_id):
    """
    Upload multiple log entries in one commit
    """
    pending_logs = get_pending_logs()
    
    git_pull()
    
    for log in pending_logs:
        write_file(f'{server_id}/logs/{log.filename}', log.content)
        git_add(f'{server_id}/logs/{log.filename}')
    
    git_commit(f'{server_id}: Upload {len(pending_logs)} log files')
    git_push()
```

### Reduced Heartbeat Frequency

During idle periods, reduce heartbeat frequency to minimize commits:

```python
def adaptive_heartbeat(server_id):
    """
    Adjust heartbeat frequency based on activity
    """
    status = read_json(f'{server_id}/status.json')
    
    if status['status'] == 'building':
        interval = 30  # 30 seconds during builds
    elif has_pending_jobs():
        interval = 60  # 1 minute when jobs available
    else:
        interval = 300  # 5 minutes when idle
    
    return interval
```

## Security Considerations

1. **Repository Access**: Use SSH keys with read/write access
2. **Commit Signing**: Optional GPG signing for audit trail
3. **Secrets**: Never store credentials in this repository
    - Jira API token in `~/.config/jira/api_token` (600)
    - Jira password (UI) in `~/.config/jira/password` (600)
    - Codex credentials remain on Build1 only; no replication via git
4. **Network**: VPN or private network recommended
5. **Authentication**: GitHub personal access tokens with repo scope

## Monitoring and Alerting

### Health Check Script

```bash
#!/bin/bash
# check_health.sh - Run periodically to monitor system

cd /path/to/Build
git pull origin main

# Check heartbeats
for server in build1 build2; do
    last_beat=$(jq -r '.timestamp' $server/heartbeat.json)
    age=$(($(date +%s) - $(date -d "$last_beat" +%s)))
    
    if [ $age -gt 300 ]; then
        echo "WARNING: $server heartbeat is $age seconds old"
        # Send alert
    fi
done

# Check for stuck jobs
stuck_jobs=$(jq '[.jobs[] | select(.status == "running" and 
    (now - (.started_at | fromdate)) > 3600)] | length' coordination/jobs.json)

if [ $stuck_jobs -gt 0 ]; then
    echo "WARNING: $stuck_jobs jobs running for over 1 hour"
    # Send alert
fi
```

## Migration Path

### Phase 1: Initial Setup (Day 1)
- Create repository structure
- Initialize status files
- Deploy heartbeat scripts

### Phase 2: Monitoring (Days 2-3)
- Test heartbeat reliability
- Monitor git repository performance
- Verify status updates

### Phase 3: Job Coordination (Days 4-7)
- Implement job queue
- Test lock mechanisms
- Validate job assignment

### Phase 4: Full Production (Week 2+)
- Enable automated builds
- Implement message queue
- Set up monitoring alerts

## Performance Characteristics

- **Latency**: 1-5 seconds for status updates (git push time)
- **Throughput**: 10-20 updates per minute sustainable
- **Storage**: ~1MB per day with log rotation
- **Scalability**: Supports 2-10 servers effectively

## Troubleshooting

### High Conflict Rate
- Increase retry delays
- Reduce update frequency
- Use file-level locking (different files per server)

### Repository Growth
- Enable git LFS for large files
- Implement log rotation
- Archive old branches

### Git Push Failures
- Check network connectivity
- Verify credentials
- Check repository permissions
- Review git push logs

## Jira Workflow Integration

This repository standardizes Jira operations via scripts (token auth):

- Backlog curation: `scripts/create_and_assign.py`
    - Creates or updates curated tickets; assigns to Copilot/Codex; persists `docs/curated_ticket_keys.json`
- Verification: `scripts/verify_created_updated.py [KEY ...]`
    - Confirms reporter/assignee/status for curated items by key
- Index generation: `scripts/generate_ticket_index.py`
    - Produces `docs/JIRA_CURATED_TICKETS.md` with links, types, status, assignee, reporter, labels, parent
- Metadata curation: `scripts/curate_jira_metadata.py`
    - Adds labels (vnf, vnf-framework, curated) and associates non-epics to the main epic (Epic Link or relation)
- Backlog placement: `scripts/move_to_backlog.py KEY`
    - Ensures To Do status and moves issue to backlog
- Phase planning (Scrum or Kanban): `scripts/plan_sprint.py "Phase 1 (VNFFRAM)" [KEY ...]`
    - Scrum: creates/uses a sprint and adds issues
    - Kanban: creates/uses a Fix Version and assigns issues

Jira board: VNFFRAM / Board 2  
Auth rules: API token for automation; UI uses username+password (stored locally; not in git).

## Quality Gates & Definition of Done (DoD)

Quality gates must be explicitly tracked and reported as PASS/FAIL per change:

- Build/Run: scripts execute without errors and produce expected artifacts/logs
- Lint/Typecheck: no syntax/type errors in changed files (note: third-party import warnings are acceptable if dependencies are installed at runtime)
- Tests: verification scripts pass; where applicable, unit/integration tests report green
- Docs: README or feature docs updated to reflect new automation and ops steps

Definition of Done for automation changes:

- Idempotent scripts with persisted state where necessary (e.g., keys map)
- Minimal operator steps; default safe behavior with clear logging
- Reproducible: dependencies captured (e.g., `scripts/requirements.txt`)
- Observability: output paths and logs documented

## Operational Runbooks

### Keep Work Moving (Hands-Free)

- Start continuous operations: `bash scripts/start_auto_ops.sh build2 300`
- Stop: `bash scripts/stop_auto_ops.sh build2`
- As systemd service on Build2:
    - `bash scripts/install_heartbeat_service.sh`
    - `systemctl status build2-heartbeat.service`

### Responding to Messages

- Add or adjust rules in `docs/auto_reply_rules.json` to tune replies/mark-only behavior
- Use message types consistently: `info`, `warning`, `error`, `request`
- For manual responses, prefer `scripts/send_message.sh` with succinct subjects and bodies

### Jira Backlog Lifecycle

1) Seed or update curated backlog: `python3 scripts/create_and_assign.py`

2) Curate metadata: `python3 scripts/curate_jira_metadata.py`

3) Plan phase:
     - Scrum board → sprint via `plan_sprint.py`
     - Kanban board → Fix Version via `plan_sprint.py`

4) Verify and publish index: `python3 scripts/generate_ticket_index.py`

5) Move specific issues to backlog when needed: `python3 scripts/move_to_backlog.py KEY`

### Incident and Recovery

- Conflicting pushes: rerun with backoff; for non-critical JSONs, prefer last-writer-wins with rebase and autostash
- Broken JSON: validate with `scripts/validate_json.sh` (if present); repair using temp-file pattern as in scripts
- Lost mapping: regenerate `docs/curated_ticket_keys.json` by re-running `create_and_assign.py` (idempotent)
