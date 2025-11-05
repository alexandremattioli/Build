# Build Server Coordination Repository

> Quick note for operators: if you just tell the agent "follow the instructions", it will execute the exact checklist below automatically. The steps are documented here so you don't need to repeat them next time.

## SSH Access Between Builders

**Build1 (10.1.3.175)** ↔ **Build2 (10.1.3.177)**

Both builders have SSH access to each other. You can SSH anytime to check implementations, sync files, or debug:

```bash
# From Build2 to Build1
ssh root@10.1.3.175 "command"

# From Build1 to Build2  
ssh root@10.1.3.177 "command"
```

Common uses:
- Check how the other builder implemented a feature
- Compare scripts or configurations
- Trigger notifications or message checks
- Sync shared files or coordination data

## AI Development Time Estimates

**IMPORTANT:** When estimating implementation time, always base estimates on **GitHub Copilot** and **OpenAI Codex** capabilities, NOT human developer timelines.

### AI-Assisted Development Speed Reference:
- **Simple API endpoint**: 10-30 minutes
- **Database schema + DAO layer**: 1-2 hours
- **Service layer with business logic**: 2-4 hours
- **Complete plugin/module**: 1-3 days
- **Full feature with integration**: 3-7 days

**Example:** The VNF Framework plugin (3,548 lines, 28 files) was completed in 2 days with AI assistance.

### Gathering AI Model Capability Information:

To stay current with GitHub Copilot and Codex capabilities:

1. **GitHub Copilot Updates:**
   - Check: https://github.blog/changelog/label/copilot/
   - Latest features: https://docs.github.com/en/copilot/about-github-copilot
   - Release notes: https://github.com/github/copilot-docs/releases

2. **OpenAI Codex/GPT Updates:**
   - API updates: https://platform.openai.com/docs/guides/code
   - Model releases: https://openai.com/blog
   - Capabilities: https://platform.openai.com/docs/models

3. **Performance Benchmarks:**
   - HumanEval benchmark scores
   - MBPP (Mostly Basic Python Problems) results
   - Real-world completion rates in your domain

4. **Practical Testing:**
   ```bash
   # Test current model on representative task
   # Time completion of: "Implement a REST API endpoint with CRUD operations"
   # Compare against previous baseline
   ```

5. **Community Resources:**
   - r/github copilot discussions
   - Stack Overflow [github-copilot] tag
   - Twitter/X: @github, @openai announcements

**Rule of Thumb:** If a task would take a human developer 1 week, expect AI assistance to reduce it to 1-2 days. Always provide AI-based estimates, not human-only estimates.

## Work Distribution Philosophy

**IMPORTANT:** Build1 and Build2 should each do COMPLETE implementations independently. There is NO division of labor on implementation tasks.

### How Builds Work Together:

✅ **What TO Do:**
- Both builds implement the ENTIRE feature independently
- Exchange design ideas and architectural approaches
- Share implementation strategies and best practices
- Review each other's code for improvements
- Discuss technical challenges and solutions
- Compare implementations to find optimal approaches

❌ **What NOT To Do:**
- Split implementation work (e.g., "Build1 does backend, Build2 does frontend")
- Divide components (e.g., "Build1 does DAO, Build2 does Service")
- Assign layers or modules to specific builds
- Create dependencies where one build waits for another's code

### Rationale:

1. **Redundancy:** Both implementations provide backup if one has issues
2. **Quality:** Independent implementations reveal design flaws and edge cases
3. **Learning:** Each build gains complete understanding of the system
4. **Speed:** Parallel complete implementations are faster than sequential dependent work
5. **Validation:** Two implementations serve as mutual verification

### Example Workflow:

```
Day 1: Both builds design and discuss architecture
Day 2: Build1 implements complete feature (version A)
Day 2: Build2 implements complete feature (version B)
Day 3: Compare implementations, merge best approaches
Day 4: Both builds refine based on comparison
```

### Collaboration Points:

- **Design Phase:** Collaborate extensively on architecture and approach
- **Implementation Phase:** Work independently on complete implementations
- **Review Phase:** Exchange code, discuss differences, identify improvements
- **Refinement Phase:** Apply lessons learned from both implementations

**Remember:** The goal is TWO complete implementations, not ONE implementation split between two builds.

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

---

## Features Directory

The `Features/` directory contains detailed specifications and documentation for new features being developed for Apache CloudStack builds. Each feature has its own subdirectory containing:

- **Design documents** - Detailed technical specifications and architecture documentation
- **Implementation notes** - Guidelines for build servers on how to implement the feature
- **Configuration files** - Any necessary configuration or setup files
- **Test specifications** - Testing requirements and procedures

### Structure

```
Features/
├── DualSNAT/          # Dual Source NAT feature
└── VNFramework/       # VNF Framework feature
    ├── README.md      # Implementation guide
    ├── PACKAGE-SUMMARY.md
    ├── database/      # Database schema
    ├── api-specs/     # OpenAPI specifications
    ├── java-classes/  # Java interfaces and implementations
    ├── python-broker/ # VR broker service
    ├── dictionaries/  # Vendor YAML dictionaries
    ├── tests/         # Test suite
    ├── config/        # Configuration
    └── ui-specs/      # UI components and workflows
```

### For Build Servers

When implementing new features:

1. Check the `Features/` directory for the latest feature specifications
2. Each subdirectory represents a distinct feature or capability
3. Read all documentation files within the feature directory before implementation
4. Follow the specifications exactly as documented
5. Report any issues or clarifications needed via the coordination system

> **Important:** Feature directories contain authoritative documentation that build servers should reference during development and testing.

---

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

## Workflow Examples

### Starting a Build

1. Builder creates job in `coordination/jobs.json`
2. Builder acquires lock in `coordination/locks.json`
3. Builder updates own `status.json` to "building"
4. Builder writes log to `build[1|2]/logs/[timestamp].log`
5. Builder updates `status.json` on completion
6. Builder releases lock

### Checking Other Builder Status

```bash
# From Build1, check Build2 status
ssh root@10.1.3.177 'cat /root/Build/build2/status.json'

# Or via git if repo is synced
cat build2/status.json
```

### Messaging Between Builders

```bash
# Build1 sends message to Build2
./scripts/send_message.sh build1 build2 "Starting build on ExternalNew branch"

# Message appears in coordination/messages.json
```

---

## Setup Instructions

### Initial Setup (One-time)

On each builder:

```bash
cd /root
git clone https://github.com/alexandremattioli/Build.git
cd Build
git config user.name "Build[1|2] [Manager]"
git config user.email "[manager]@build[1|2].local"
```

### Regular Updates

```bash
cd /root/Build
git pull
# Make changes
git add .
git commit -m "Update from build[1|2]"
git push
```

### Automated Sync (Optional)

Add to crontab:
```bash
*/5 * * * * cd /root/Build && git pull && git add -A && git commit -m "[build1] Heartbeat $(date +\%H:\%M:\%S)" && git push
```

---

## Troubleshooting

### Git Push Conflicts

```bash
cd /root/Build
git pull --rebase
git push
```

---

## Jira Access (Copilot)

- Username (alias): `copilot@mattioli.co.uk` (alias of `alexandre@mattioli.co.uk`)
- Password file (local, not in git): `~/.config/jira/password`
  - Permissions: `600` (owner read/write only)
  - This file is created locally on Builder2 and must never be committed
- API token (preferred for automation) remains in: `~/.config/jira/api_token`
- Project key: `VNFFRAM`

Notes:
- Use the password file only where basic auth is required; otherwise prefer the API token.
- Scripts in `scripts/` read Jira config from `~/.config/jira/config` and credentials from the token/password files as needed.

### Jira curation quick links
- Board: https://mattiolihoffmann.atlassian.net/jira/software/c/projects/VNFFRAM/boards/2
- Curated tickets index (links, type, status, assignee, reporter): `docs/JIRA_CURATED_TICKETS.md`
- Summary→Key map for curated set: `docs/curated_ticket_keys.json`

### Jira scripts (automation)
- Create/assign curated tickets (idempotent via keys map):
  - `python3 scripts/create_and_assign.py`
- Verify created/updated tickets:
  - `python3 scripts/verify_created_updated.py <ISSUE_KEY> [ISSUE_KEY ...]`
- Regenerate the curated index:
  - `python3 scripts/generate_ticket_index.py`
- Move an issue to backlog (ensures To Do/Backlog status):
  - `python3 scripts/move_to_backlog.py <ISSUE_KEY>`
- Phase planning (Kanban-friendly):
  - `python3 scripts/plan_sprint.py "Phase 1 (VNFFRAM)"`
    - If the board supports sprints (Scrum), creates/adds to a sprint
    - If the board is Kanban (no sprints), creates/assigns a Fix Version instead

Dependencies for scripts: `pip3 install -r scripts/requirements.txt` (installs `requests`).

### Automatic monitoring and replies
- Heartbeat with auto-monitoring and auto-replies:
  - Run continuously: `bash scripts/enhanced_heartbeat_daemon.sh build2 300`
  - Each cycle will:
    - Update heartbeat
    - Pull new messages and log to `/var/log/build-messages-build2.log`
    - Auto-reply to unread messages using `scripts/auto_reply.py` and mark them read
  - Manual one-shot:
    - `bash scripts/enhanced_heartbeat.sh build2`
  - Convenience start/stop wrappers:
    - Start: `bash scripts/start_auto_ops.sh [build2] [interval_seconds]`
    - Stop:  `bash scripts/stop_auto_ops.sh [build2]`
  - Optional systemd service:
    - Template: `scripts/build2-heartbeat.service.example`
    - Install helper (root): `bash scripts/install_heartbeat_service.sh`
    - Then: `systemctl status build2-heartbeat.service`

#### Auto-reply rules
- Default built-in rules handle Jira space confirmation and generic requests.
- You can add custom rules in `docs/auto_reply_rules.json`:
  - Fields: `contains` (substring match on subject), optional `type` (info|warning|error|request), `action` (reply|mark)
  - `reply` object: `subject`, `body`, optional `type` (defaults to info)
  - Example provided in the file.

### Authentication rules
- API and scripts: use the API token.
  - Auth is email + API token (Basic), token file: `~/.config/jira/api_token`.
  - This is what all helper scripts use by default.
- Web UI login: use username + password.
  - Username: `copilot@mattioli.co.uk`
  - Password: stored locally in `~/.config/jira/password` (600 perms); do not commit.

### Stale Locks

If a lock is held too long:
```bash
# Manually clear lock in coordination/locks.json
# Remove the lock entry or update timestamp
```

### Missing Status Files

```bash
# Recreate status.json
cat > build1/status.json << 'EOF'
{
  "server": "build1",
  "status": "idle",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
```

---

## Best Practices

1. **Always pull before push** to avoid conflicts
2. **Update status.json** at each state change
3. **Log extensively** for debugging
4. **Use locks** for any shared resource access
5. **Heartbeat regularly** so other builders know you're alive
6. **Clean up old logs** to save space
7. **Document all jobs** in coordination/jobs.json

---

## Security Notes

- Repository is private (only accessible to authorized users)
- SSH keys required for git operations
- No sensitive credentials stored in git
- All passwords/tokens in environment variables or config files excluded from git

---

## Future Enhancements

- [ ] Automated health checks via GitHub Actions
- [ ] Web dashboard for status visualization  
- [ ] Slack/Teams integration for notifications
- [ ] Build artifact storage and distribution
- [ ] Historical metrics and performance tracking

---

**Repository:** https://github.com/alexandremattioli/Build  
**Maintainer:** Alexandre Mattioli (@alexandremattioli)  
**Last Updated:** November 4, 2025
