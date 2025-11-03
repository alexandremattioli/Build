# Build Coordination System

A Git-based coordination hub for distributed Apache CloudStack build servers managed by AI agents.

[![Health Monitor](https://github.com/alexandremattioli/Build/actions/workflows/health-monitor.yml/badge.svg)](https://github.com/alexandremattioli/Build/actions/workflows/health-monitor.yml)

## Quick Links

- Dashboard (GitHub Pages): https://alexandremattioli.github.io/Build/
- Actions (Health checks): https://github.com/alexandremattioli/Build/actions
- Issues (Alerts & tasks): https://github.com/alexandremattioli/Build/issues
- Messages Status (root): ./MESSAGES_STATUS.md
- All Messages Archive (root): ./MESSAGES_ALL.txt
- Scripts: ./scripts/
- Messages: ./messages/
- Coordination: ./coordination/
- Documentation: ./docs/
- **Features: ./Features/** — Feature descriptions and specifications for build servers

## What this repo is

- Single source of truth for build coordination and status
- File-based messaging, locks, job queue, and metrics
- Designed for 2–4 servers with ~30–60s coordination latency

## Get started on a server

```bash
# One-time clone
cd /root
git clone https://github.com/alexandremattioli/Build.git
cd Build

# Make tools executable
chmod +x scripts/*.sh

# Optional: set up cron (see docs/IMPROVEMENTS.md)
```

## Key components

- scripts/ — automation (queue, locks, artifacts, metrics, rollback, etc.)
- messages/ — human/agent instructions and acknowledgments
- coordination/ — jobs, locks, and other shared state
- docs/ — guides, dashboards, and detailed documentation
- **Features/ — feature descriptions organized in subdirectories (e.g., Features/VNF/, Features/Networking/)**
- .github/workflows/ — automated health monitoring

> **Note for Build Servers:** Feature specifications and implementation details can be found in subdirectories under `Features/`. Each feature has its own directory containing documentation, design specs, and related files.

## Recommended next steps

- Enable GitHub Pages (Settings → Pages → main, /docs) to activate the dashboard
- Configure health checks and metrics collection per docs

## More docs

- docs/IMPROVEMENTS.md — All features and how to use them
- docs/IMPLEMENTATION_SUMMARY.md — Overview of recent enhancements
- docs/QUICKSTART.md — Minimal bootstrap for new servers
- docs/BRANCH_OWNERSHIP.md — CloudStack branch ownership and usage (Copilot vs Codex)

## For Build3 - `root@ll-ACSBuilder3`

```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build3.sh
```

## For Build4 - `root@ll-ACSBuilder4`

```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build4.sh
```

---

Maintained by Alexandre Mattioli — see Issues for support and tasks.

## What This Repository Provides

This repository serves as a file-based communication and coordination system between:
- **Build1** (`root@ll-ACSBuilder1`, 10.1.3.175) - Managed by Codex
- **Build2** (`root@ll-ACSBuilder2`, 10.1.3.177) - Managed by GitHub Copilot
- **Build3** (`root@ll-ACSBuilder3`, 10.1.3.179) - Managed by TBD
- **Build4** (`root@ll-ACSBuilder4`, 10.1.3.181) - Managed by TBD

### Direct SSH Access
All servers have passwordless SSH configured between each other:
- Build1: `ssh root@10.1.3.175` or `ssh root@ll-ACSBuilder1`
- Build2: `ssh root@10.1.3.177` or `ssh root@ll-ACSBuilder2`
- Build3: `ssh root@10.1.3.179` or `ssh root@ll-ACSBuilder3`
- Build4: `ssh root@10.1.3.181` or `ssh root@ll-ACSBuilder4`

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
├── build3/
│   ├── status.json             # Build3 current status
│   ├── heartbeat.json          # Last update timestamp
│   └── logs/                   # Build logs and reports
│       └── [timestamp].log
├── build4/
│   ├── status.json             # Build4 current status
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
  "server": "build1|build2|build3|build4",
  "ip": "10.1.3.x",
  "manager": "Codex|GitHub Copilot|TBD",
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
  "server": "build1|build2|build3|build4",
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
      "assigned_to": "build1|build2|build3|build4|null",
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
      "locked_by": "build1|build2|build3|build4|null",
      "locked_at": "timestamp",
      "expires_at": "timestamp"
    },
    "config_update": {
      "locked_by": "build1|build2|build3|build4|null",
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
      "from": "build1|build2|build3|build4",
      "to": "build1|build2|build3|build4|all",
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
7. Execute build (Maven) and package DEBs by default
8. Update status with results and record artifacts
9. Push logs and manifests to `logs/` directory

### Default build outputs: DEB packages
- By default, every successful build MUST produce Debian packages.
- After Maven completes, run CloudStack packaging to create DEBs:
  - Preferred: `cd /root/cloudstack && ./packaging/build-deb.sh -o /root/artifacts/$(hostname)/debs/$(date -u +%Y%m%dT%H%M%SZ)`
  - Helper: `cd /root/Build/scripts && ./build_debs.sh --repo /root/cloudstack --out /root/artifacts/$(hostname)/debs/$(date -u +%Y%m%dT%H%M%SZ)`
  - On Ubuntu 24.04, a legacy build-dep (python-setuptools) may be missing. The helper script auto-installs a safe dummy using `equivs` and falls back to `dpkg-buildpackage -d` if needed.

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

## Heartbeat behavior controls

You can tune heartbeat commit behavior via environment variables (applies to both `scripts/heartbeat.sh` and `scripts/enhanced_heartbeat.sh`):

- HEARTBEAT_PUSH_EVERY: Batch commits and only push after N heartbeats. Example: `HEARTBEAT_PUSH_EVERY=5` (default if unset).
- HEARTBEAT_BRANCH: Push heartbeats to a specific remote branch without changing your local branch. Set to:
  - a branch name (e.g., `heartbeat-build2`) to push `HEAD:heartbeat-build2`, or
  - `1` or `auto` to automatically use `heartbeat-$SERVER_ID`.

When using a heartbeat branch, you can periodically squash or prune that branch on the server to keep history compact without affecting `main`.

### Squash heartbeat branch history

Use `scripts/squash_heartbeat_branch.sh` to reduce a heartbeat branch to a single commit (current snapshot) and optionally create a remote backup:

- Squash automatic branch for a server: `./scripts/squash_heartbeat_branch.sh --server build2 --backup`
- Squash specific branch: `./scripts/squash_heartbeat_branch.sh --branch heartbeat-build2 --backup`

Notes:
- Uses a force-with-lease push to update the heartbeat branch only.
- If `--backup` is set, a `backup/<branch>-<timestamp>` ref is pushed before squashing.
- Add to cron (e.g., daily) if you want continuous compaction.

### Local write locks

Writers to `coordination/messages.json` and `coordination/jobs.json` now use local `flock` locks to avoid concurrent edits on the same host. This complements git-based conflict handling across hosts and reduces transient merge churn.

