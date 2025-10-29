# Communication Framework Setup Instructions

**For any LLM (Codex, GitHub Copilot, Claude, etc.) managing Build1 or Build2**

---

## Server Information

### Build1
- **Hostname**: `ll-ACSBuilder1`
- **IP**: 10.1.3.175
- **Access**: `root@ll-ACSBuilder1` or `ssh root@10.1.3.175`
- **Manager**: Codex (or other LLM)
- **Partner**: Build2

### Build2
- **Hostname**: `ll-ACSBuilder2`
- **IP**: 10.1.3.177
- **Access**: `root@ll-ACSBuilder2` or `ssh root@10.1.3.177`
- **Manager**: GitHub Copilot (or other LLM)
- **Partner**: Build1

---

## One-Command Setup

### If you are managing Build1:
```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && chmod +x *.sh && ./setup_build1.sh
```

### If you are managing Build2:
```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && chmod +x *.sh && ./setup_build2.sh
```

This will:
- Clone the coordination repository to `/root/Build`
- Configure git with the correct server identity
- Make all scripts executable
- Start the enhanced heartbeat daemon (auto-checks messages every 60 seconds)
- Display status and verification instructions

### Non-interactive setup and always re-clone

If `/root/Build` already exists, the setup scripts used to prompt:

"Warning: /root/Build already exists\nDo you want to re-clone? (y/N):"

You can now force a clean re-clone without any prompt by passing `--force` (or setting `FORCE_RECLONE=1`). Examples:

```bash
# Build1 - force re-clone
cd /root/Build/scripts && ./setup_build1.sh --force
# or via env var
cd /root/Build/scripts && FORCE_RECLONE=1 ./setup_build1.sh

# Build2 - force re-clone
cd /root/Build/scripts && ./setup_build2.sh --force
# or via env var
cd /root/Build/scripts && FORCE_RECLONE=1 ./setup_build2.sh
```

To explicitly keep the existing repo without a prompt, use `--skip-reclone`.

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

**Note**: Replace `build1` or `build2` with your server ID in all commands below.

### Send Messages to Partner Server

```bash
cd /root/Build/scripts

# Info message (build1 to build2 example)
./send_message.sh build1 build2 info "Build Started" "Building commit abc123"

# Send to all servers
./send_message.sh build1 all info "Build Complete" "DEBs ready at /root/"

# Error alert
./send_message.sh build2 all error "Build Failed" "Maven compilation error"

# Warning
./send_message.sh build2 build1 warning "High Load" "CPU at 95%"
```

### Read Messages from Partner Server

```bash
cd /root/Build/scripts
./read_messages.sh build1    # If you're on build1
./read_messages.sh build2    # If you're on build2
```

**Note**: The enhanced heartbeat daemon automatically checks and displays new messages every 60 seconds. You'll see them in the console and in the message log file.

### Update Build Status

```bash
cd /root/Build/scripts

# Before starting a build (replace build1 with your server)
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

Add to your CloudStack build script. **Adjust paths and server ID for your environment**:

**For Build1** (source at `/root/cloudstack-ExternalNew`):
```bash
#!/bin/bash
set -euo pipefail

COMM_DIR="/root/Build/scripts"
SERVER_ID="build1"
JOB_ID="job_$(date +%s)"

# Notify: Starting build
cd "$COMM_DIR"
./update_status.sh $SERVER_ID building "$JOB_ID"
./send_message.sh $SERVER_ID all info "Build Started" "CloudStack 4.21 ExternalNew build initiated"

# Run the actual build
cd /root/cloudstack-ExternalNew
mvn -Dmaven.test.skip=true -P systemvm,developer clean install 2>&1 | tee /root/build-logs/mvn_install.log
BUILD_RESULT=${PIPESTATUS[0]}

dpkg-buildpackage -uc -us 2>&1 | tee /root/build-logs/dpkg_build.log
PKG_RESULT=${PIPESTATUS[0]}

# Notify: Build complete
cd "$COMM_DIR"
if [ $BUILD_RESULT -eq 0 ] && [ $PKG_RESULT -eq 0 ]; then
    ./update_status.sh $SERVER_ID success
    ./send_message.sh $SERVER_ID all info "Build Complete" "DEBs available at /root/ - SHA: $(git -C /root/cloudstack-ExternalNew rev-parse HEAD)"
else
    ./update_status.sh $SERVER_ID failed
    ./send_message.sh $SERVER_ID all error "Build Failed" "Maven exit: $BUILD_RESULT, dpkg exit: $PKG_RESULT. Check logs in /root/build-logs/"
fi
```

**For Build2** (source at `/root/src/cloudstack`):
```bash
#!/bin/bash
set -euo pipefail

COMM_DIR="/root/Build/scripts"
SERVER_ID="build2"
JOB_ID="job_$(date +%s)"

# Notify: Starting build
cd "$COMM_DIR"
./update_status.sh $SERVER_ID building "$JOB_ID"
./send_message.sh $SERVER_ID all info "Build Started" "CloudStack 4.21 ExternalNew build initiated"

# Run the actual build
cd /root/src/cloudstack
mvn -Dmaven.test.skip=true -P systemvm,developer clean install 2>&1 | tee /root/build-logs/mvn_install.log
BUILD_RESULT=${PIPESTATUS[0]}

dpkg-buildpackage -uc -us 2>&1 | tee /root/build-logs/dpkg_build.log
PKG_RESULT=${PIPESTATUS[0]}

# Notify: Build complete
cd "$COMM_DIR"
if [ $BUILD_RESULT -eq 0 ] && [ $PKG_RESULT -eq 0 ]; then
    ./update_status.sh $SERVER_ID success
    ./send_message.sh $SERVER_ID all info "Build Complete" "DEBs available at /root/ - SHA: $(git -C /root/src/cloudstack rev-parse HEAD)"
else
    ./update_status.sh $SERVER_ID failed
    ./send_message.sh $SERVER_ID all error "Build Failed" "Maven exit: $BUILD_RESULT, dpkg exit: $PKG_RESULT. Check logs in /root/build-logs/"
fi
```

---

## Daemon Management

**Replace `build1` with `build2` if you're on Build2.**

### Check if daemon is running
```bash
ps aux | grep enhanced_heartbeat_daemon | grep build1  # or build2
```

### View live heartbeat log
```bash
# Build1:
tail -f /var/log/heartbeat-build1.log

# Build2:
tail -f /var/log/heartbeat.log
```

### View live message log
```bash
# Build1:
tail -f /var/log/build-messages-build1.log

# Build2:
tail -f /var/log/build-messages-build2.log
```

### Stop the daemon
```bash
pkill -f "enhanced_heartbeat_daemon.sh build1"  # or build2
```

### Start the daemon manually
```bash
cd /root/Build/scripts

# Build1:
nohup ./enhanced_heartbeat_daemon.sh build1 60 > /var/log/heartbeat-build1.log 2>&1 &

# Build2:
nohup ./enhanced_heartbeat_daemon.sh build2 60 > /var/log/heartbeat.log 2>&1 &
```

### Change check frequency (e.g., every 30 seconds)
```bash
pkill -f "enhanced_heartbeat_daemon.sh build1"  # or build2
cd /root/Build/scripts

# Build1 (30 second interval):
nohup ./enhanced_heartbeat_daemon.sh build1 30 > /var/log/heartbeat-build1.log 2>&1 &

# Build2 (30 second interval):
nohup ./enhanced_heartbeat_daemon.sh build2 30 > /var/log/heartbeat.log 2>&1 &
```

---

## Recovery After Snapshot Revert

If your server is reverted to a previous snapshot and loses the `/root/Build` directory:

**Build1:**
```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build1.sh
```

**Build2:**
```bash
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build2.sh
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
2. Check heartbeat log: `tail -f /var/log/heartbeat*.log`
3. Manually check messages: `cd /root/Build/scripts && ./read_messages.sh build1` (or `build2`)
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
# Stop daemon (use build1 or build2 as appropriate)
pkill -f "enhanced_heartbeat_daemon.sh build1"

# Pull latest
cd /root/Build && git pull origin main

# Re-run setup
cd scripts && ./setup_build1.sh  # or ./setup_build2.sh
```

---

## Key Points for Any LLM

1. **Identify your server**: Check hostname or IP to know if you're on Build1 or Build2
2. **Always run setup first**: One command installs everything (use the correct setup script for your server)
3. **Messages are automatic**: The daemon checks every 60 seconds
4. **Integrate with builds**: Use `update_status.sh` and `send_message.sh` in build scripts
5. **Check logs**: Look in `/var/log/` for heartbeat and message logs
6. **Health check**: Run `./check_health.sh` to see both servers
7. **Recovery**: Re-run setup script after snapshot reverts
8. **Use correct server ID**: Always use `build1` or `build2` matching your server

---

## Complete Example Workflow

**Determine your server first**, then follow these steps:

```bash
# 1. Identify which server you're on
hostname  # ll-ACSBuilder1 = build1, ll-ACSBuilder2 = build2

# 2. Initial setup (run once) - USE THE CORRECT COMMAND FOR YOUR SERVER
# For Build1:
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build1.sh
# For Build2:
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build2.sh

# 3. Check system is working
./check_health.sh

# 4. Before starting a build (replace build1 with build2 if needed)
./update_status.sh build1 building job_$(date +%s)
./send_message.sh build1 all info "Build Started" "Starting CloudStack 4.21 build"

# 5. After build completes successfully
./update_status.sh build1 success
./send_message.sh build1 all info "Build Complete" "All DEBs generated successfully"

# 6. Check messages from partner server
./read_messages.sh build1  # or build2

# 7. View live message log
tail -f /var/log/build-messages-build1.log  # adjust for build2 if needed
```

---

## Documentation Links

- **Full setup guide**: https://github.com/alexandremattioli/Build/blob/main/SETUP.md
- **Quick start**: https://github.com/alexandremattioli/Build/blob/main/QUICKSTART.md
- **Protocol details**: https://github.com/alexandremattioli/Build/blob/main/METHODOLOGY.md
- **Build1 instructions**: https://github.com/alexandremattioli/Build/blob/main/build1/BUILD_INSTRUCTIONS.md

---

## Summary

**First Step**: Identify your server (Build1 or Build2)  
**Setup**: One command to install everything (use correct setup script)  
**Communication**: Automatic (every 60 seconds)  
**Send messages**: `./send_message.sh <your-server> <target> <type> "Subject" "Body"`  
**Read messages**: Automatic or `./read_messages.sh <your-server>`  
**Update status**: `./update_status.sh <your-server> <status>`  
**Check health**: `./check_health.sh`  
**Logs**: `/var/log/heartbeat*.log` and `/var/log/build-messages-*.log`

That's it! The system is designed to be simple and automatic. Just make sure to use the correct server ID (build1 or build2) in all commands.
