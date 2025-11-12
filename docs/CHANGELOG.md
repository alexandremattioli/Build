# Build Coordination Repository Changelog

All notable changes to the Build coordination repository and build processes are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to semantic versioning for coordination protocol changes.

---

## [Unreleased]

### Added
- Jira curation helpers: `scripts/create_and_assign.py` now persists a local
  summary→key map at `docs/curated_ticket_keys.json` and a last-run report.
- Verification tooling: `scripts/verify_created_updated.py` to validate
  reporter/assignee/status for curated tickets by key or by project scan.
- Documentation index: `scripts/generate_ticket_index.py` generates
  `docs/JIRA_CURATED_TICKETS.md` with links, types, status, assignees, and reporters.
- Jira metadata curation and epic linking: `scripts/curate_jira_metadata.py` adds labels and associates to the main epic
- Phase planning automation: `scripts/plan_sprint.py` supports Scrum sprints and Kanban Fix Versions ("Phase 1 (VNFFRAM)")
- Automatic monitoring and replies: heartbeat-integrated `scripts/auto_reply.py`, daemonized via `scripts/enhanced_heartbeat_daemon.sh`
- Operational docs: Methodology expanded with collaboration policy, auto-ops rules, Jira workflow integration, and DoD
- DEB packaging helper script `scripts/build_debs.sh` to handle Ubuntu 24.04 compatibility issues
- Comprehensive build report template with detailed analysis sections
- Artifact manifest generation with SHA256 checksums
- Build status tracking with last_build metadata in status.json

### Changed
- Methodology updated to codify two-track implementation, automation-first, message semantics, and runbooks
- Updated default build workflow to include DEB packaging by default
- Enhanced status.json to include last_build with duration_seconds and artifacts array
- Improved artifact preservation to dedicated /root/artifacts directory structure

### Fixed
- Git heartbeat conflicts resolution with `--theirs` strategy
- Python 2 dependency workaround using equivs dummy packages for Ubuntu 24.04

---

## [2025-10-29] - CloudStack ExternalNew Build

### Added
- **Build2 First CloudStack Build:** Successfully built CloudStack 4.21.0.0-SNAPSHOT from ExternalNew branch
  - Commit: d8e22ab0af7881b17ddd086bcae2a42a74bfc661
  - Duration: 4:54 (294 seconds)
  - Parallelization: 32 threads (-T 1C)
  - Profiles: developer,systemvm
  
- **Artifact Management:**
  - Created `/root/artifacts/build2/` directory structure
  - Generated artifact manifests with SHA256 checksums
  - Preserved engine.war, cloud-server JAR, cloud-client-ui JAR
  
- **Build Coordination Enhancements:**
  - Implemented last_build tracking in status.json
  - Added inter-server build notifications
  - Created message_status.txt update workflow

### Changed
- **Maven Build Optimization:**
  - MAVEN_OPTS: `-Xms4g -Xmx8g -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+UseStringDeduplication`
  - Parallelism: 1 thread per core for optimal CPU utilization
  - Skipped tests and javadocs for faster builds

- **Status Tracking:**
  - status.json now includes current_job with started_at timestamp
  - last_build includes completed_at, duration_seconds, and artifacts array

### Fixed
- Repository synchronization between Build1 and Build2
- Heartbeat rebase conflicts with autostash strategy
- Build log preservation and organization

### Issues Identified
- **DEB Packaging on Ubuntu 24.04:**
  - Python 2 dependencies (python-setuptools) not available
  - dpkg-checkbuilddeps blocks with unmet dependencies
  - Requires debian/control updates or Docker-based build environment
  
- **Git Heartbeat Conflicts:**
  - Frequent merge conflicts in build2/heartbeat.json
  - Recommend using HEARTBEAT_BRANCH for separate heartbeat tracking
  
- **Build Interruption:**
  - dpkg-buildpackage interrupted with signal 130
  - Needs investigation for interactive prompts or resource constraints

---

## [2025-10-29] - Communication Framework Enhancements

### Added
- **Enhanced Heartbeat Daemon:** `scripts/enhanced_heartbeat_daemon.sh`
  - Automatic message checking every 60 seconds
  - Integrated message reading and display
  - Separate log files for heartbeat and messages
  
- **Message Statistics:**
  - `scripts/update_message_stats.sh` for aggregated metrics
  - `scripts/view_message_stats.sh` for human-readable display
  - `coordination/message_stats.json` for tracking

- **Setup Scripts:**
  - `scripts/setup_build1.sh` - Automated Build1 initialization
  - `scripts/setup_build2.sh` - Automated Build2 initialization
  - Auto-reclone option for always-latest code
  - GitHub PAT configuration via `/PAT` file

### Changed
- **Message Workflow:**
  - Mandatory message_status.txt updates after every message interaction
  - 4-line format: Build1 count/time, Build2 count/time, Last message from, Waiting on
  
- **Heartbeat Behavior:**
  - Environment variables for tuning: HEARTBEAT_PUSH_EVERY, HEARTBEAT_BRANCH
  - Batch commit support to reduce push frequency
  - Optional heartbeat branch for reduced main branch conflicts

### Fixed
- Git credential helper configuration for GitHub authentication
- Script permissions (chmod +x) applied automatically during setup
- Heartbeat daemon PID tracking and restart logic

---

## [2025-10-29] - Initial Repository Setup

### Added
- **Core Communication Files:**
  - `build1/status.json` - Build1 server status
  - `build1/heartbeat.json` - Build1 health tracking
  - `build2/status.json` - Build2 server status
  - `build2/heartbeat.json` - Build2 health tracking
  - `coordination/messages.json` - Inter-server messaging
  - `coordination/jobs.json` - Job queue management
  - `coordination/locks.json` - Coordination locks
  
- **Scripts:**
  - `scripts/heartbeat.sh` - Basic heartbeat updates
  - `scripts/heartbeat_daemon.sh` - Continuous heartbeat daemon
  - `scripts/update_status.sh` - Server status updates
  - `scripts/send_message.sh` - Send messages to partner server
  - `scripts/read_messages.sh` - Read unread messages
  - `scripts/mark_messages_read.sh` - Mark messages as read
  - `scripts/check_and_process_messages.sh` - Manual message check
  - `scripts/check_health.sh` - System health dashboard
  
- **Documentation:**
  - `README.md` - Quick start and overview
  - `SETUP_INSTRUCTIONS.md` - Comprehensive setup guide
  - `METHODOLOGY.md` - Detailed protocol specification
  - `QUICKSTART.md` - Fast setup commands

### Infrastructure
- **Git-Based Coordination:**
  - GitHub repository as central coordination hub
  - File-based message queue
  - JSON status files for structured data
  
- **Server Configuration:**
  - Build1: ll-ACSBuilder1 (10.1.3.175) managed by Codex
  - Build2: ll-ACSBuilder2 (10.1.3.177) managed by GitHub Copilot
  - Passwordless SSH between servers
  - 32 cores, 128GB RAM on each server

---

## Guidelines for Changelog Updates

### When to Add Entries
- New scripts or tools added to `scripts/`
- Changes to communication protocol or file formats
- New features in status tracking or messaging
- Build process improvements or optimizations
- Bug fixes or issue resolutions

### Categories
- **Added:** New features, scripts, or capabilities
- **Changed:** Modifications to existing functionality
- **Deprecated:** Features marked for removal (not yet removed)
- **Removed:** Features or files deleted
- **Fixed:** Bug fixes or issue resolutions
- **Security:** Security-related changes

### Entry Format
```markdown
- **Brief Title:** Detailed description
  - Sub-item 1
  - Sub-item 2
```

### Commit Message Style
- Use imperative mood: "Add feature" not "Added feature"
- Reference issue numbers when applicable
- Keep first line under 72 characters
- Provide detailed description in body if needed

---

## Version History Summary

| Date | Version | Key Changes | Build Status |
|------|---------|-------------|--------------|
| 2025-10-29 | 1.0 | Initial coordination framework | [OK] Operational |
| 2025-10-29 | 1.1 | Enhanced heartbeat and messaging | [OK] Operational |
| 2025-10-29 | 1.2 | First CloudStack build on Build2 | [OK] Maven Success, [!] DEB Issues |
| 2025-10-30 | 1.3 | Build reporting and DEB packaging improvements | 🔄 In Progress |

---

## Maintainers

- **Build1:** Managed by Codex (or assigned LLM)
- **Build2:** Managed by GitHub Copilot (or assigned LLM)
- **Repository:** https://github.com/alexandremattioli/Build

For questions or issues, check the documentation files or raise an issue in the repository.
