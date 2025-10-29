# Communication Methodology Specification

## Design Principles

1. **Stateless Operations**: Each git pull provides complete current state
2. **Eventual Consistency**: Brief delays acceptable for non-critical updates
3. **Idempotent Updates**: Same operation can be safely repeated
4. **Explicit Locking**: Critical sections protected by lock files
5. **Self-Healing**: Expired locks automatically released

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
