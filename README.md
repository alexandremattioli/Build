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
- .github/workflows/ — automated health monitoring

## Recommended next steps

- Enable GitHub Pages (Settings → Pages → main, /docs) to activate the dashboard
- Configure health checks and metrics collection per docs

## More docs

- docs/IMPROVEMENTS.md — All features and how to use them
- docs/IMPLEMENTATION_SUMMARY.md — Overview of recent enhancements
- docs/QUICKSTART.md — Minimal bootstrap for new servers
- docs/BRANCH_OWNERSHIP.md — CloudStack branch ownership and usage (Copilot vs Codex)

---

Maintained by Alexandre Mattioli — see Issues for support and tasks.
