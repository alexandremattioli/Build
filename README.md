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

## Quick messaging CLI

Every setup script installs a helper so builds can send coordination messages without remembering long command lines:

- Command: `sendmessages`
- Alias: `sm` (example `sm 2 Build2 acked watcher rollout`)
- Source: `scripts/sendmessages` (wraps `scripts/send_message.sh`)

Run `sendmessages --help` for all options. Targets accept digits (`1`, `12`, `4`) or `all`; subjects are auto-derived from the first line of the body.

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
  "locks": [
    {
      "name": "job_queue",
      "owner": "build1",
      "timestamp": "2025-10-29T12:00:00Z"
    }
  ]
}
```

...
