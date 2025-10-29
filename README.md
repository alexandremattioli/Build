# Build Server Coordination Repository

## For Build1 (Codex) - `root@ll-ACSBuilder1`

```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build1.sh
```

## For Build2 (GitHub Copilot) - `root@ll-ACSBuilder2`

```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build2.sh
```

---

## What This Repository Provides

This repository serves as a file-based communication and coordination system between:
- **Build1** (`root@ll-ACSBuilder1`, 10.1.3.175) - Managed by Codex
- **Build2** (`root@ll-ACSBuilder2`, 10.1.3.177) - Managed by GitHub Copilot

### Direct SSH Access
Both servers have passwordless SSH configured:
- Build1 can SSH to Build2: `ssh root@10.1.3.177` or `ssh root@ll-ACSBuilder2`
- Build2 can SSH to Build1: `ssh root@10.1.3.175` or `ssh root@ll-ACSBuilder1`

This enables direct file access, remote command execution, and real-time coordination beyond git-based communication.

## Communication Protocol

### File Structure
```
/
├── README.md                    # This file
├── METHODOLOGY.md               # Detailed protocol specification
├── build1/
│   ├── status.json             # Build1 current status
│   ├── heartbeat.json          # Last update timestamp
│   └── logs/                   # Build logs and reports
│       └── [timestamp].log
├── build2/
│   ├── status.json             # Build2 current status
│   ├── heartbeat.json          # Last update timestamp
│   └── logs/                   # Build logs and reports
│       └── [timestamp].log
├── coordination/
│   ├── jobs.json               # Job queue
│   ├── locks.json              # Coordination locks
│   └── messages.json           # Inter-server messages
└── shared/
    ├── build_config.json       # Shared build configuration
    └── health_dashboard.json   # Aggregate health status
```

### Status File Format

Each server maintains a `status.json` file:
```json
{
  "server": "build1|build2",
  "ip": "10.1.3.x",
  "manager": "Codex|GitHub Copilot",
  "timestamp": "2025-10-29T12:00:00Z",
  "status": "idle|building|failed|success",
  "current_job": {
    "id": "job_uuid",
    "branch": "ExternalNew",
    "commit": "sha",
    "started_at": "timestamp"
  },
  "last_build": {
    "id": "job_uuid",
    "status": "success|failed",
    "completed_at": "timestamp",
    "duration_seconds": 1234,
    "artifacts": ["cloudstack_4.21.0.0_amd64.deb"]
  },
  "system": {
    "cpu_usage": 45.2,
    "memory_used_gb": 32.1,
    "disk_free_gb": 450.0
  }
}
```

### Heartbeat File Format

Each server updates `heartbeat.json` every minute:
```json
{
  "server": "build1|build2",
  "timestamp": "2025-10-29T12:00:00Z",
  "uptime_seconds": 86400,
  "healthy": true
}
```

### Job Queue Format

The `coordination/jobs.json` file manages work distribution:
```json
{
  "jobs": [
    {
      "id": "job_uuid",
      "type": "build|test|deploy",
      "priority": 1,
      "branch": "ExternalNew",
      "commit": "sha",
      "assigned_to": "build1|build2|null",
      "status": "queued|running|completed|failed",
      "created_at": "timestamp",
      "started_at": "timestamp",
      "completed_at": "timestamp"
    }
  ]
}
```

### Lock Mechanism

The `coordination/locks.json` file prevents race conditions:
```json
{
  "locks": {
    "job_assignment": {
      "locked_by": "build1|build2|null",
      "locked_at": "timestamp",
      "expires_at": "timestamp"
    },
    "config_update": {
      "locked_by": "build1|build2|null",
      "locked_at": "timestamp",
      "expires_at": "timestamp"
    }
  }
}
```

### Message Queue Format

The `coordination/messages.json` enables inter-server communication:
```json
{
  "messages": [
    {
      "id": "msg_uuid",
      "from": "build1|build2",
      "to": "build1|build2|all",
      "type": "info|warning|error|request",
      "subject": "Brief description",
      "body": "Detailed message",
      "timestamp": "2025-10-29T12:00:00Z",
      "read": false
    }
  ]
}
```

## Usage Workflow

### 1. Server Startup
Each server should:
1. Pull latest from this repository
2. Update its `heartbeat.json`
3. Update its `status.json` with "idle" status
4. Push changes back

### 2. Heartbeat Updates
Every 60 seconds:
1. Pull latest changes
2. Update `heartbeat.json`
3. Push changes

### 3. Job Processing
When checking for work:
1. Pull latest changes
2. Acquire lock in `locks.json`
3. Check `jobs.json` for queued jobs
4. Assign job to self if available
5. Update status to "building"
6. Push changes and release lock
7. Execute build
8. Update status with results
9. Push logs to `logs/` directory

### 4. Monitoring
Both servers can:
- Read each other's status files
- Check heartbeats for health
- View job queue
- Read messages

## Implementation Scripts

### Update Status Script
```bash
#!/bin/bash
cd /path/to/Build
git pull origin main
# Update status.json
jq '.timestamp = now | .status = "idle"' build2/status.json > tmp.json
mv tmp.json build2/status.json
git add build2/status.json
git commit -m "Update build2 status: $(date -u)"
git push origin main
```

### Heartbeat Script
```bash
#!/bin/bash
while true; do
  cd /path/to/Build
  git pull origin main
  jq ".timestamp = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" | .healthy = true" \
    build2/heartbeat.json > tmp.json
  mv tmp.json build2/heartbeat.json
  git add build2/heartbeat.json
  git commit -m "Heartbeat: build2 $(date -u +%H:%M:%S)"
  git push origin main
  sleep 60
done
```

## Conflict Resolution

If git push fails due to conflicts:
1. Pull and merge automatically
2. Retry push
3. If repeated failures, log to messages.json
4. Alert operator

## Best Practices

1. **Always pull before push**: Ensure you have the latest state
2. **Use atomic commits**: One file change per commit when possible
3. **Include timestamps**: All updates should include ISO 8601 timestamps
4. **Lock sensitive operations**: Use locks for job assignments
5. **Keep logs organized**: Use timestamp-based log filenames
6. **Monitor health**: Check heartbeats to detect failures
7. **Clean old logs**: Periodically archive logs older than 7 days

## Advantages

- **Simple**: No complex middleware or message brokers
- **Auditable**: Full git history of all communications
- **Resilient**: Works even if one server is down
- **Transparent**: Easy to inspect state manually
- **Version controlled**: Built-in rollback capability

## Maintenance

- Archive old logs weekly
- Monitor repository size
- Consider git LFS for large artifacts
- Review and clean completed jobs monthly
