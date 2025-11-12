# 🚀 Automated Setup Guide

## One-Command Setup (For AI Assistants)

This repository contains a complete communication framework for Build1 (Codex) and Build2 (GitHub Copilot).

---

## [i] Quick Setup

### For Build1 (10.1.3.175 - Codex)

```bash
cd /root && \
git clone https://github.com/alexandremattioli/Build.git && \
cd Build/scripts && \
chmod +x *.sh && \
./setup_build1.sh
```

**Or use the automated setup script:**
```bash
bash <(curl -s https://raw.githubusercontent.com/alexandremattioli/Build/main/scripts/setup_build1.sh)
```

### For Build2 (10.1.3.177 - GitHub Copilot)

```bash
cd /root && \
git clone https://github.com/alexandremattioli/Build.git && \
cd Build/scripts && \
chmod +x *.sh && \
./setup_build2.sh
```

**Or use the automated setup script:**
```bash
bash <(curl -s https://raw.githubusercontent.com/alexandremattioli/Build/main/scripts/setup_build2.sh)
```

---

## 🤖 Instructions for AI Assistants

### For Codex (Managing Build1)

When given this repository link: https://github.com/alexandremattioli/Build

**Execute these steps:**

1. Clone the repository to `/root/Build`
2. Run the setup script: `/root/Build/scripts/setup_build1.sh`
3. Verify setup: `/root/Build/scripts/check_health.sh`

**The setup script will:**
- Clone the repository
- Configure git with Build1 identity
- Make all scripts executable
- Start the enhanced heartbeat daemon (auto-checks messages every 60s)
- Report status

### For GitHub Copilot (Managing Build2)

When given this repository link: https://github.com/alexandremattioli/Build

**Execute these steps:**

1. Clone the repository to `/root/Build`
2. Run the setup script: `/root/Build/scripts/setup_build2.sh`
3. Verify setup: `/root/Build/scripts/check_health.sh`

**The setup script will:**
- Clone the repository
- Configure git with Build2 identity
- Make all scripts executable
- Start the enhanced heartbeat daemon (auto-checks messages every 60s)
- Report status

---

## 📁 What This Repository Provides

### Communication Framework
- **Status tracking** for both servers
- **Heartbeat monitoring** (health checks)
- **Job queue** for coordinated builds
- **Message passing** between servers
- **Lock mechanism** to prevent conflicts

### Helper Scripts
All located in `scripts/`:
- `setup_build1.sh` / `setup_build2.sh` - One-command setup
- `update_status.sh` - Update server status
- `heartbeat.sh` / `enhanced_heartbeat.sh` - Send heartbeat
- `heartbeat_daemon.sh` / `enhanced_heartbeat_daemon.sh` - Continuous monitoring
- `check_health.sh` - Monitor all servers
- `send_message.sh` - Send messages between servers
- `read_messages.sh` - Read unread messages
- `check_and_process_messages.sh` - Auto-check and display messages
- `mark_messages_read.sh` - Mark messages as read

### Documentation
- `README.md` - Overview and protocol
- `METHODOLOGY.md` - Detailed technical specification
- `QUICKSTART.md` - Manual setup guide
- `SETUP.md` - This file (automated setup)
- `SNAPSHOT_RECOVERY.txt` - Recovery procedures

---

## [OK] Post-Setup Verification

After running the setup script, verify with:

```bash
cd /root/Build/scripts
./check_health.sh
```

You should see:
- Heartbeat status for both servers
- Server status (idle/building/etc)
- Job queue status
- Message count

---

## 🔄 Communication Flow

Once both servers are set up:

1. **Automatic Heartbeat**: Every 60 seconds, each server:
   - Updates its heartbeat (health signal)
   - Checks for new messages
   - Updates status

2. **Sending Messages**:
   ```bash
   cd /root/Build/scripts
   ./send_message.sh build1 build2 info "Subject" "Message body"
   ```

3. **Reading Messages**:
   - Messages are **automatically detected** during heartbeat cycles
   - Messages are displayed on console
   - Messages are logged to `/var/log/build-messages-<server>.log`

4. **Updating Status**:
   ```bash
   cd /root/Build/scripts
   ./update_status.sh build1 building job_123
   ./update_status.sh build1 success
   ```

---

## 🔧 Integration with Build Scripts

### Example: Integrate with CloudStack Build

Add to your build script (e.g., `/root/run_build_local.sh`):

```bash
#!/bin/bash
set -euo pipefail

COMM_DIR="/root/Build"
SERVER_ID="build2"  # or build1
JOB_ID="job_$(date +%s)"

# Start: Update status
cd $COMM_DIR/scripts
./update_status.sh $SERVER_ID building $JOB_ID
./send_message.sh $SERVER_ID all info "Build Started" "ACS 4.21 build initiated"

# ... your build commands ...

# End: Update status based on result
cd $COMM_DIR/scripts
if [ $? -eq 0 ]; then
    ./update_status.sh $SERVER_ID success
    ./send_message.sh $SERVER_ID all info "Build Success" "Build completed"
else
    ./update_status.sh $SERVER_ID failed
    ./send_message.sh $SERVER_ID all error "Build Failed" "Check logs"
fi
```

---

## 🛠️ Recovery After Snapshot Revert

If a server is reverted to a previous snapshot:

### For Build1:
```bash
cd /root/Build/scripts && ./setup_build1.sh
```

### For Build2:
```bash
cd /root/Build/scripts && ./setup_build2.sh
```

**Or if the repository was also lost:**
```bash
cd /root && \
git clone https://github.com/alexandremattioli/Build.git && \
cd Build/scripts && \
./setup_build1.sh  # or setup_build2.sh
```

See `SNAPSHOT_RECOVERY.txt` for detailed recovery procedures.

---

## 📊 Repository Structure

```
alexandremattioli/Build/
├── README.md                    # Protocol overview
├── METHODOLOGY.md               # Technical specification
├── QUICKSTART.md                # Manual setup guide
├── SETUP.md                     # This file (automated setup)
├── SNAPSHOT_RECOVERY.txt        # Recovery procedures
├── .gitignore
│
├── build1/                      # Build1 files
│   ├── status.json
│   ├── heartbeat.json
│   └── logs/
│
├── build2/                      # Build2 files
│   ├── status.json
│   ├── heartbeat.json
│   └── logs/
│
├── coordination/                # Shared coordination
│   ├── jobs.json
│   ├── locks.json
│   └── messages.json
│
├── shared/                      # Shared configuration
│   ├── build_config.json
│   └── health_dashboard.json
│
└── scripts/                     # All helper scripts
    ├── setup_build1.sh         ⭐ SETUP SCRIPT FOR BUILD1
    ├── setup_build2.sh         ⭐ SETUP SCRIPT FOR BUILD2
    ├── update_status.sh
    ├── heartbeat.sh
    ├── enhanced_heartbeat.sh
    ├── heartbeat_daemon.sh
    ├── enhanced_heartbeat_daemon.sh
    ├── check_health.sh
    ├── send_message.sh
    ├── read_messages.sh
    ├── check_and_process_messages.sh
    └── mark_messages_read.sh
```

---

## 🎯 Key Features

- [OK] **No external dependencies** (just Git and standard tools)
- [OK] **Automatic message detection** (no polling needed)
- [OK] **Built-in recovery** from snapshot reverts
- [OK] **Complete audit trail** (Git history)
- [OK] **Self-healing** (expired locks auto-cleanup)
- [OK] **AI-friendly** (scripts designed for AI execution)

---

## 📞 Support

- **Repository**: https://github.com/alexandremattioli/Build
- **Build1**: 10.1.3.175 (Codex)
- **Build2**: 10.1.3.177 (GitHub Copilot)

---

## 🚀 Ready to Start?

**Just run the appropriate setup script for your server!**

Build1 (Codex):
```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build1.sh
```

Build2 (Copilot):
```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build2.sh
```

That's it! The framework will be fully operational in ~2 minutes.
