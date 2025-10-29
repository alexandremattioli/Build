# Setup Instructions for Codex Managing Build1

**Server**: Build1 (`root@ll-ACSBuilder1`, 10.1.3.175)  
**Manager**: Codex  
**Partner**: Build2 (`root@ll-ACSBuilder2`, 10.1.3.177, managed by GitHub Copilot)

---

## One-Command Setup

Run this on Build1 to install the complete communication framework:

```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && chmod +x *.sh && ./setup_build1.sh
```

This will:
- Clone the coordination repository to `/root/Build`
- Configure git with Build1 identity
- Make all scripts executable
- Start the enhanced heartbeat daemon (auto-checks messages every 60 seconds)
- Display status and verification instructions

---

## What This Provides

### Automatic Communication
- **Heartbeat**: Updates every 60 seconds to show Build1 is alive
- **Message checking**: Automatically detects and displays new messages from Build2
- **Status tracking**: Reports idle/building/success/failed states
- **Health monitoring**: Both servers can check each other's health

### Message Logs
- **Heartbeat log**: `/var/log/heartbeat-build1.log`
- **Message log**: `/var/log/build-messages-build1.log`

---

## Common Operations

### Send Messages to Build2

```bash
cd /root/Build/scripts

# Info message
./send_message.sh build1 build2 info "Build Started" "Building commit abc123"

# Success notification
./send_message.sh build1 build2 info "Build Complete" "DEBs ready at /root/"

# Error alert
./send_message.sh build1 all error "Build Failed" "Maven compilation error"

# Warning
./send_message.sh build1 build2 warning "High Load" "CPU at 95%"
```

### Read Messages from Build2

```bash
cd /root/Build/scripts
./read_messages.sh build1
```

**Note**: The enhanced heartbeat daemon automatically checks and displays new messages every 60 seconds. You'll see them in the console and in `/var/log/build-messages-build1.log`.

### Update Build Status

```bash
cd /root/Build/scripts

# Before starting a build
./update_status.sh build1 building job_$(date +%s)

# After successful build
./update_status.sh build1 success

# After failed build
./update_status.sh build1 failed

# When idle
./update_status.sh build1 idle
```

### Check System Health

```bash
cd /root/Build/scripts
./check_health.sh
```

This shows:
- Build1 and Build2 heartbeat status
- Current status of each server
- Last update times
- Message counts

---

## Integration with Build Scripts

Add to your CloudStack build script (e.g., `/root/run_build.sh`):

```bash
#!/bin/bash
set -euo pipefail

COMM_DIR="/root/Build/scripts"
JOB_ID="job_$(date +%s)"

# Notify: Starting build
cd "$COMM_DIR"
./update_status.sh build1 building "$JOB_ID"
./send_message.sh build1 all info "Build Started" "CloudStack 4.21 ExternalNew build initiated"

# Run the actual build
cd /root/cloudstack-ExternalNew
mvn -Dmaven.test.skip=true -P systemvm,developer clean install 2>&1 | tee /root/build-logs/mvn_install.log
BUILD_RESULT=${PIPESTATUS[0]}

dpkg-buildpackage -uc -us 2>&1 | tee /root/build-logs/dpkg_build.log
PKG_RESULT=${PIPESTATUS[0]}

# Notify: Build complete
cd "$COMM_DIR"
if [ $BUILD_RESULT -eq 0 ] && [ $PKG_RESULT -eq 0 ]; then
    ./update_status.sh build1 success
    ./send_message.sh build1 all info "Build Complete" "DEBs available at /root/ - SHA: $(git -C /root/cloudstack-ExternalNew rev-parse HEAD)"
else
    ./update_status.sh build1 failed
    ./send_message.sh build1 all error "Build Failed" "Maven exit: $BUILD_RESULT, dpkg exit: $PKG_RESULT. Check logs in /root/build-logs/"
fi
```

---

## Daemon Management

### Check if daemon is running
```bash
ps aux | grep enhanced_heartbeat_daemon | grep build1
```

### View live heartbeat log
```bash
tail -f /var/log/heartbeat-build1.log
```

### View live message log
```bash
tail -f /var/log/build-messages-build1.log
```

### Stop the daemon
```bash
pkill -f "enhanced_heartbeat_daemon.sh build1"
```

### Start the daemon manually
```bash
cd /root/Build/scripts
nohup ./enhanced_heartbeat_daemon.sh build1 60 > /var/log/heartbeat-build1.log 2>&1 &
```

### Change check frequency (e.g., every 30 seconds)
```bash
pkill -f "enhanced_heartbeat_daemon.sh build1"
cd /root/Build/scripts
nohup ./enhanced_heartbeat_daemon.sh build1 30 > /var/log/heartbeat-build1.log 2>&1 &
```

---

## Recovery After Snapshot Revert

If Build1 is reverted to a previous snapshot and loses the `/root/Build` directory:

```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build1.sh
```

The setup script is idempotent and safe to re-run.

---

## Available Scripts

All scripts are in `/root/Build/scripts/`:

| Script | Purpose | Example |
|--------|---------|---------|
| `setup_build1.sh` | Initial setup (run once) | `./setup_build1.sh` |
| `enhanced_heartbeat_daemon.sh` | Continuous heartbeat + message check | `./enhanced_heartbeat_daemon.sh build1 60` |
| `update_status.sh` | Update build status | `./update_status.sh build1 building job_123` |
| `send_message.sh` | Send message to Build2 | `./send_message.sh build1 build2 info "Title" "Body"` |
| `read_messages.sh` | Read unread messages | `./read_messages.sh build1` |
| `check_and_process_messages.sh` | Manual message check | `./check_and_process_messages.sh build1` |
| `mark_messages_read.sh` | Mark messages as read | `./mark_messages_read.sh build1` |
| `check_health.sh` | System health dashboard | `./check_health.sh` |

---

## Message Types

When sending messages, use these types:

- **info**: General information, status updates, notifications
- **warning**: Non-critical issues, high resource usage, minor problems
- **error**: Critical failures, build errors, system errors
- **request**: Asking for action or information from the other server

---

## Direct SSH Access (Alternative Method)

Build1 can also communicate with Build2 via direct SSH:

```bash
# Execute command on Build2
ssh root@10.1.3.177 "command"

# Copy file to Build2
scp /path/to/file root@10.1.3.177:/destination/

# Copy file from Build2
scp root@10.1.3.177:/path/to/file /local/destination/
```

Passwordless SSH is already configured between both servers.

---

## Troubleshooting

### Messages not appearing
1. Check daemon is running: `ps aux | grep enhanced_heartbeat_daemon`
2. Check heartbeat log: `tail -f /var/log/heartbeat-build1.log`
3. Manually check messages: `cd /root/Build/scripts && ./read_messages.sh build1`
4. Pull latest changes: `cd /root/Build && git pull origin main`

### Git push/pull errors
```bash
cd /root/Build
git status
git pull --rebase origin main
# Resolve any conflicts if needed
git push origin main
```

### Restart everything
```bash
pkill -f "enhanced_heartbeat_daemon.sh build1"
cd /root/Build && git pull origin main
cd scripts && ./setup_build1.sh
```

---

## Key Points for Codex

1. **Always run setup first**: One command installs everything
2. **Messages are automatic**: The daemon checks every 60 seconds
3. **Integrate with builds**: Use `update_status.sh` and `send_message.sh` in build scripts
4. **Check logs**: `/var/log/heartbeat-build1.log` and `/var/log/build-messages-build1.log`
5. **Health check**: Run `./check_health.sh` to see both servers
6. **Recovery**: Re-run setup script after snapshot reverts

---

## Complete Example Workflow

```bash
# 1. Initial setup (run once)
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build1.sh

# 2. Check system is working
./check_health.sh

# 3. Before starting a build
./update_status.sh build1 building job_$(date +%s)
./send_message.sh build1 all info "Build Started" "Starting CloudStack 4.21 build"

# 4. After build completes successfully
./update_status.sh build1 success
./send_message.sh build1 all info "Build Complete" "All DEBs generated successfully"

# 5. Check messages from Build2
./read_messages.sh build1

# 6. View live message log
tail -f /var/log/build-messages-build1.log
```

---

## Documentation Links

- **Full setup guide**: https://github.com/alexandremattioli/Build/blob/main/SETUP.md
- **Quick start**: https://github.com/alexandremattioli/Build/blob/main/QUICKSTART.md
- **Protocol details**: https://github.com/alexandremattioli/Build/blob/main/METHODOLOGY.md
- **Build1 instructions**: https://github.com/alexandremattioli/Build/blob/main/build1/BUILD_INSTRUCTIONS.md

---

## Summary

**Setup**: One command to install everything  
**Communication**: Automatic (every 60 seconds)  
**Send messages**: `./send_message.sh build1 build2 info "Subject" "Body"`  
**Read messages**: Automatic or `./read_messages.sh build1`  
**Update status**: `./update_status.sh build1 <status>`  
**Check health**: `./check_health.sh`  

That's it! The system is designed to be simple and automatic.
