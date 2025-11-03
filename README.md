# Build Server Coordination Repository

> Quick note for operators: if you just tell the agent “follow the instructions”, it will execute the exact checklist below automatically. The steps are documented here so you don’t need to repeat them next time.

## For Build1 (Codex) - `root@ll-ACSBuilder1`

```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build1.sh
```

## For Build2 (GitHub Copilot) - `root@ll-ACSBuilder2`

```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build2.sh
```

## Builder1 Workspace Quick Reference

- The Codex session that backs this workspace runs on **Builder1 / Build1** (`ll-ACSBuilder1`, `10.1.3.175`), the primary host used to build Apache CloudStack artifacts.
- Builder1 is permanently managed by Codex; assume Codex automation is active on this host for all build coordination.
- CloudStack source checkouts typically live under `/root` (for example `/root/cloudstack`, `/root/cloudstack_VNFCopilot`).

### Check Which Repositories Are Mounted

```bash
find /root -maxdepth 2 -type d -name .git -print | sort
```

This lists every Git working tree currently available on Builder1. Use `git -C <repo-path> status -sb` to inspect each checkout.

### Locate Build Outputs

- Maven build logs and coordination metadata: `/root/Build/build1/logs/`
- Packaged artifacts (DEBs, manifests, etc.): `/root/artifacts/ll-ACSBuilder1/`
  - Example DEB run folder: `/root/artifacts/ll-ACSBuilder1/debs/<timestamp>/`
- Recent job metadata and artifact manifests are also referenced from `/root/Build/build1/status.json`

## Builder2 Workspace Quick Reference

- GitHub Copilot sessions run on **Builder2 / Build2** (`ll-ACSBuilder2`, `10.1.3.177`), providing redundant capacity for Apache CloudStack builds.
- Builder2 is permanently managed by GitHub Copilot automation.

### Check Which Repositories Are Mounted

```bash
find /root -maxdepth 2 -type d -name .git -print | sort
```

Use `git -C <repo-path> status -sb` to inspect each checkout on Build2.

### Locate Build Outputs

- Build logs and coordination metadata: `/root/Build/build2/logs/`
- Packaged artifacts (DEBs, manifests, etc.): `/root/artifacts/ll-ACSBuilder2/`
  - Example DEB run folder: `/root/artifacts/ll-ACSBuilder2/debs/<timestamp>/`
- Build status records: `/root/Build/build2/status.json`

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

## Hands‑free bootstrap and daily ops (Build2)

The Copilot agent on Build2 will perform these actions when asked to “follow the instructions”. You can also run them manually.

### 0) Identity and repo state

```bash
# Ensure identity (one of the three options below)
echo "build2" > /root/Build/.build_server_id 2>/dev/null || true
# Or:
# echo "build2" > /etc/build_server_id
# export SERVER_ID=build2

# If repository already exists, make local changes safe before pulling
cd /root/Build 2>/dev/null && git stash --include-untracked || true

# Get latest code or clone fresh
[ -d /root/Build/.git ] && git -C /root/Build pull origin main || (cd /root && git clone https://github.com/alexandremattioli/Build.git)

# Ensure scripts are executable
chmod +x /root/Build/scripts/*.sh || true

# Verify identity helper
/root/Build/scripts/server_id.sh || true
```

### 1) One-shot setup/recovery

```bash
cd /root/Build/scripts && ./setup_build2.sh
```

This will: clone/refresh the repo (unless already up-to-date), set permissions, read the recent conversation, start the heartbeat daemon, and check messages each cycle.

### 2) Background processes (verify or start)

```bash
# Start/verify heartbeat daemon (60s interval)
nohup /root/Build/scripts/enhanced_heartbeat_daemon.sh build2 60 > /var/log/heartbeat-build2.out 2>&1 &

# (Optional) Classic heartbeat instead of the daemon
# nohup /root/Build/scripts/heartbeat_daemon.sh build2 60 > /var/log/heartbeat-build2.out 2>&1 &

# Check processes
ps aux | grep -E "(heartbeat|watch_messages)" | grep -v grep
```

### 3) Messages and coordination

```bash
# Check unread
cd /root/Build/scripts && ./check_unread_messages.sh build2

# Read the recent conversation thread
./read_conversation_thread.sh build2

# Update message status summary files
./update_message_status_txt.sh

# Send an ACK/status to Build1
./send_message.sh build2 build1 info "Build2 online and monitoring" "Setup completed; heartbeat active; ready for jobs."
```

### 4) Health and jobs

```bash
# Overall health (heartbeats, queue summary, unread counts)
./check_health.sh

# Job queue is kept in coordination/jobs.json; assignment is performed under locks.
# (If you maintain jobs from this host, always pull first and respect locks.)
git -C /root/Build pull --ff-only || true
```

### 5) Logs and status locations

- Heartbeat log: `/var/log/heartbeat-build2.log` (or `/var/log/heartbeat-build2.out` if started via nohup)
- Message summaries: `/root/Build/MESSAGES_STATUS.md` and `/root/Build/MESSAGES_ALL.txt`
- Build2 status JSON: `/root/Build/build2/status.json`
- Build2 logs: `/root/Build/build2/logs/`
- Message watcher logs (if enabled by the setup): `/root/Build/messages.log`

### Conflict handling (safe defaults)

When a pull is blocked by local edits, the agent will:

```bash
cd /root/Build && git stash && git pull --ff-only && git stash pop || true
```

If merges are required repeatedly, changes will be logged to `coordination/messages.json` using `send_message.sh` for operator visibility.

 

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

## Identity persistence and convention

- GitHub Copilot is ALWAYS `build2`.
- Codex is ALWAYS `build1`.

To make identity explicit on each host without polluting git history:

- Keep a local, untracked marker in the repo root:
  - Copy `.build_server_id.example` to `.build_server_id` and set to `build1` or `build2`.
  - `.gitignore` already excludes `.build_server_id`.
- Or set a system-wide marker: `/etc/build_server_id` with `build1` or `build2`.
- Or export an environment variable per shell/session: `export SERVER_ID=build2` (or `build1`).

Use the helper to resolve identity with clear precedence:
```bash
cd /root/Build/scripts
./server_id.sh   # prints build1 or build2
```

Precedence order: `$SERVER_ID` > `/etc/build_server_id` > `./.build_server_id` > hostname/IP heuristic > `unknown`.

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
