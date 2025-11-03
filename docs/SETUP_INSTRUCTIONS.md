# Communication Framework Setup Instructions

**For any LLM (Codex, GitHub Copilot, Claude, etc.) managing Build1 or Build2**

---

## FIRST ACTIONS - DO THIS IMMEDIATELY

### Step 1: Run Setup

```bash
# Identify your server first
hostname

# Run the setup script for YOUR server
cd /root/Build/scripts && ./setup_build1.sh  # if Build1
cd /root/Build/scripts && ./setup_build2.sh  # if Build2
```

### Step 2: Check Messages on GitHub

**CRITICAL**: After setup, IMMEDIATELY check for messages from your partner:

```bash
cd /root/Build/scripts
./read_messages.sh build1  # if you're on Build1
./read_messages.sh build2  # if you're on Build2
```

### Step 3: Update message_status.txt

**AFTER EVERY MESSAGE YOU SEND OR RECEIVE**, update `/root/Build/message_status.txt`:

```bash
cd /root/Build
# Edit message_status.txt with current info:
# Line 1: Build1 messages count and timestamp
# Line 2: Build2 messages count and timestamp  
# Line 3: Last message from: <who> to <who> (<brief subject>)
# Line 4: Waiting on: <status or None>
# Then commit and push
git add message_status.txt
git commit -m "Update message status after <action>"
git push origin main
```

**Example message_status.txt format:**
```
Build1 messages: 9  Last message: 2025-10-29 17:58
Build2 messages: 7  Last message: 2025-10-29 18:00
Last message from: Build2 to Build1 (libssl-dev confirmation)
Waiting on: Build1 response to coordination request
```

---

## Server Information

### Build1
- **Hostname**: `ll-ACSBuilder1`
- **IP**: 10.1.3.175
- **Access**: `root@ll-ACSBuilder1` or `ssh root@10.1.3.175`
- **Manager**: Codex (or other LLM)
- **Partner**: Build2
- **Server ID**: `build1` (use this in ALL commands)

### Build2
- **Hostname**: `ll-ACSBuilder2`
- **IP**: 10.1.3.177
- **Access**: `root@ll-ACSBuilder2` or `ssh root@10.1.3.177`
- **Manager**: GitHub Copilot (or other LLM)
- **Partner**: Build1
- **Server ID**: `build2` (use this in ALL commands)

### GitHub Authentication
- **PAT Location**: `/PAT` (on both servers)
- **Token**: Store a GitHub Personal Access Token in `/PAT` (first line only)
- **Purpose**: Used for git push/pull operations to coordinate via this repository
- **Permissions**: File should be `chmod 600` (root-only read/write)
- **How it’s used**: The setup scripts configure Git’s credential helper to read the token from `/PAT` and save it into `/root/.git-credentials` for `github.com`. No tokens are committed to the repo.
- **To verify**: Ensure `/root/.git-credentials` contains an entry for `github.com` (token value is not printed in logs)

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

**Default behavior (recommended):** The setup scripts now **automatically re-clone** `/root/Build` to ensure you always have the latest code. No prompts, no intervention needed.

```bash
# Build1 - auto re-clone (default)
cd /root/Build/scripts && ./setup_build1.sh

# Build2 - auto re-clone (default)
cd /root/Build/scripts && ./setup_build2.sh
```

If you want to **keep the existing repo** and just pull updates instead:

```bash
# Build1 - keep existing repo
cd /root/Build/scripts && ./setup_build1.sh --skip-reclone

# Build2 - keep existing repo
cd /root/Build/scripts && ./setup_build2.sh --skip-reclone
```

You can also use the environment variable to control behavior:

```bash
# Disable auto-reclone (keep existing repo)
FORCE_RECLONE=0 ./setup_build1.sh

# Force re-clone (this is the default, so usually unnecessary)
FORCE_RECLONE=1 ./setup_build1.sh
```

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

### CRITICAL: Update message_status.txt After Every Message

**YOU MUST UPDATE `/root/Build/message_status.txt` AFTER**:
1. Sending a message to partner
2. Receiving and reading a message from partner
3. Replying to a partner message

#### Step-by-step process:

```bash
cd /root/Build

# 1. Edit message_status.txt with current information
nano message_status.txt  # or vim/vi

# Format (4 lines):
# Line 1: Build1 messages: <count>  Last message: YYYY-MM-DD HH:MM
# Line 2: Build2 messages: <count>  Last message: YYYY-MM-DD HH:MM
# Line 3: Last message from: <sender> to <receiver> (<brief subject>)
# Line 4: Waiting on: <what you're waiting for, or "None">

# 2. Get current message counts
grep -c '"from": "build1"' coordination/messages.json  # Build1 count
grep -c '"from": "build2"' coordination/messages.json  # Build2 count

# 3. Get latest timestamps
tail -50 coordination/messages.json | grep '"timestamp"' | tail -1

# 4. After editing, commit and push
git add message_status.txt
git commit -m "[$(hostname | grep -qi ll-ACSBuilder1 && echo build1 || echo build2)] Update message status after <describe action>"
git push origin main
```

#### Example scenarios:

**After sending a message:**
```bash
cd /root/Build/scripts
./send_message.sh build2 build1 info "Package installed" "libssl-dev 3.0.13 installed on Build2"

# NOW UPDATE message_status.txt:
cd /root/Build
# Edit to show:
# Build2 messages: 7  Last message: 2025-10-29 18:05
# Last message from: Build2 to Build1 (Package installed)
# Waiting on: Build1 acknowledgment
git add message_status.txt && git commit -m "[build2] Update after sending package confirmation" && git push
```

**After reading partner's message:**
```bash
cd /root/Build/scripts
./read_messages.sh build2

# You see message from Build1 asking for status
# Reply to it
./send_message.sh build2 build1 info "Re: Status request" "Build2 is idle, ready for tasks"

# NOW UPDATE message_status.txt:
cd /root/Build
# Edit to show latest exchange
# Last message from: Build2 to Build1 (Re: Status request)
# Waiting on: None (responded to Build1)
git add message_status.txt && git commit -m "[build2] Update after replying to status request" && git push
```

**Quick update script:**
```bash
# Helper function to update message_status.txt quickly
update_msg_status() {
    cd /root/Build
    ME=$(hostname | grep -qi ll-ACSBuilder1 && echo build1 || echo build2)
    B1_COUNT=$(grep -c '"from": "build1"' coordination/messages.json)
    B2_COUNT=$(grep -c '"from": "build2"' coordination/messages.json)
    TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M")
    
    cat > message_status.txt << EOF
Build1 messages: ${B1_COUNT}  Last message: ${TIMESTAMP}
Build2 messages: ${B2_COUNT}  Last message: ${TIMESTAMP}
Last message from: ${ME} to ${1:-partner} (${2:-update})
Waiting on: ${3:-None}

Latest note to partner:
${4:-Status updated}
EOF
    
    git add message_status.txt
    git commit -m "[${ME}] Update message status"
    git push origin main
}

# Usage: update_msg_status <to> <subject> <waiting_on> <note>
# Example: update_msg_status build1 "libssl-dev confirmed" "None" "Confirmed package installation"
```

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

# Run the actual build (Maven) and ALWAYS build DEBs
cd /root/cloudstack-ExternalNew
mvn -Dmaven.test.skip=true -P systemvm,developer clean install 2>&1 | tee /root/build-logs/mvn_install.log
BUILD_RESULT=${PIPESTATUS[0]}

# Package DEBs (default policy). Prefer the helper which handles Ubuntu 24.04 deps.
DEB_OUT="/root/artifacts/build1/debs/$(date -u +%Y%m%dT%H%M%SZ)"
/root/Build/scripts/build_debs.sh --repo /root/cloudstack-ExternalNew --out "$DEB_OUT" 2>&1 | tee /root/build-logs/deb_packaging.log || PKG_RESULT=$?
PKG_RESULT=${PKG_RESULT:-0}

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

# Run the actual build (Maven) and ALWAYS build DEBs
cd /root/src/cloudstack
mvn -Dmaven.test.skip=true -P systemvm,developer clean install 2>&1 | tee /root/build-logs/mvn_install.log
BUILD_RESULT=${PIPESTATUS[0]}

# Package DEBs (default policy). Prefer the helper which handles Ubuntu 24.04 deps.
DEB_OUT="/root/artifacts/build2/debs/$(date -u +%Y%m%dT%H%M%SZ)"
/root/Build/scripts/build_debs.sh --repo /root/src/cloudstack --out "$DEB_OUT" 2>&1 | tee /root/build-logs/deb_packaging.log || PKG_RESULT=$?
PKG_RESULT=${PKG_RESULT:-0}

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
tail -f /var/log/heartbeat-build2.log
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
nohup ./enhanced_heartbeat_daemon.sh build2 60 > /var/log/heartbeat-build2.log 2>&1 &
```

### Change check frequency (e.g., every 30 seconds)
```bash
pkill -f "enhanced_heartbeat_daemon.sh build1"  # or build2
cd /root/Build/scripts

# Build1 (30 second interval):
nohup ./enhanced_heartbeat_daemon.sh build1 30 > /var/log/heartbeat-build1.log 2>&1 &

# Build2 (30 second interval):
nohup ./enhanced_heartbeat_daemon.sh build2 30 > /var/log/heartbeat-build2.log 2>&1 &
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

## Common mistakes (and how to avoid them)

1. Forgetting to run setup before anything else
    - Always start with: `cd /root/Build/scripts && ./setup_build1.sh` (or `setup_build2.sh`)
    - Verify with `./check_health.sh` and ensure heartbeat daemon is running

2. Not checking messages after setup
    - Right after setup, run: `./read_messages.sh <your-server>`
    - If there are partner messages, reply immediately and update `message_status.txt`

3. Not updating `message_status.txt` after sending/receiving a message
    - After every message interaction, edit and push `/root/Build/message_status.txt`
    - Ensure lines are exactly:
      - Line 1: Build1 messages: <count>  Last message: YYYY-MM-DD HH:MM
      - Line 2: Build2 messages: <count>  Last message: YYYY-MM-DD HH:MM
      - Line 3: Last message from: <sender> to <receiver> (<subject>)
      - Line 4: Waiting on: <status or None>

4. Assuming automations will reply for you
    - They won't. Daemon only reads/logs. YOU must reply using `send_message.sh`

5. Using the wrong server ID in commands
    - Confirm with `hostname` and consistently use `build1` or `build2` as appropriate

6. Pushing secrets to GitHub
    - Do not commit the contents of `/PAT` or any tokens to the repo. Keep the token only in `/PAT` with `chmod 600`.

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

1. **RUN SETUP FIRST**: `cd /root/Build/scripts && ./setup_build1.sh` (or build2) - DO THIS IMMEDIATELY
2. **CHECK MESSAGES ON GITHUB**: After setup, run `./read_messages.sh <your-server>` to see partner messages
3. **UPDATE message_status.txt AFTER EVERY MESSAGE**: Send or receive a message → edit `/root/Build/message_status.txt` → commit → push
4. **Identify your server**: Check hostname or IP to know if you're on Build1 or Build2
5. **Messages are automatic**: The daemon checks every 60 seconds, but YOU must reply manually
6. **Integrate with builds**: Use `update_status.sh` and `send_message.sh` in build scripts. ALWAYS run DEB packaging after Maven using `scripts/build_debs.sh`.
7. **Check logs**: Look in `/var/log/` for heartbeat and message logs
8. **Health check**: Run `./check_health.sh` to see both servers
9. **Recovery**: Re-run setup script after snapshot reverts
10. **Use correct server ID**: Always use `build1` or `build2` matching your server

**CRITICAL WORKFLOW**:
```
Setup → Check messages → Reply to messages → Update message_status.txt → Commit & Push
```

Every message interaction must update message_status.txt with:
- Line 1: Build1 count and timestamp
- Line 2: Build2 count and timestamp
- Line 3: Last message from: <who> to <who> (<subject>)
- Line 4: Waiting on: <status or None>


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

# 3a. CHECK MESSAGES FROM PARTNER (CRITICAL!)
./read_messages.sh build1  # or build2 - DO THIS IMMEDIATELY AFTER SETUP

# 3b. If messages exist, REPLY to them and UPDATE message_status.txt
# Example:
./send_message.sh build1 build2 info "Re: <subject>" "Acknowledged. <details>"

# Then update message_status.txt:
cd /root/Build
nano message_status.txt  # Update lines 1-4 with current counts and status
git add message_status.txt && git commit -m "[build1] Update after replying" && git push

# 4. Before starting a build (replace build1 with build2 if needed)
./update_status.sh build1 building job_$(date +%s)
./send_message.sh build1 all info "Build Started" "Starting CloudStack 4.21 build"

# 4a. UPDATE message_status.txt after sending build start message
cd /root/Build
nano message_status.txt  # Update with new message count and "Build Started" note
git add message_status.txt && git commit -m "[build1] Update after build start message" && git push

# 5. After build completes successfully
./update_status.sh build1 success
./send_message.sh build1 all info "Build Complete" "All DEBs generated successfully"

# 5a. UPDATE message_status.txt after sending build complete message
cd /root/Build
nano message_status.txt  # Update with completion
git add message_status.txt && git commit -m "[build1] Update after build complete" && git push

# 6. Check messages from partner server regularly
./read_messages.sh build1  # or build2

# 7. View live message log
tail -f /var/log/build-messages-build1.log  # adjust for build2 if needed
```

**REMEMBER**: After EVERY message you send or receive, update `/root/Build/message_status.txt` and push to GitHub!

---

## Documentation Links

- **Full setup guide**: https://github.com/alexandremattioli/Build/blob/main/SETUP.md
- **Quick start**: https://github.com/alexandremattioli/Build/blob/main/QUICKSTART.md
- **Protocol details**: https://github.com/alexandremattioli/Build/blob/main/METHODOLOGY.md
- **Build1 instructions**: https://github.com/alexandremattioli/Build/blob/main/build1/BUILD_INSTRUCTIONS.md

---

## Summary

**First Step**: Run setup immediately: `cd /root/Build/scripts && ./setup_build1.sh` (or build2)  
**Second Step**: Check messages on GitHub: `./read_messages.sh <your-server>`  
**Third Step**: Reply to messages and UPDATE message_status.txt EVERY TIME  
**Communication**: Daemon reads automatically every 60 seconds, but YOU must reply manually  
**Send messages**: `./send_message.sh <your-server> <target> <type> "Subject" "Body"` → Then update message_status.txt  
**Read messages**: `./read_messages.sh <your-server>` → Reply → Update message_status.txt  
**Update status**: `./update_status.sh <your-server> <status>`  
**Check health**: `./check_health.sh`  
**Logs**: `/var/log/heartbeat*.log` and `/var/log/build-messages-*.log`

**CRITICAL**: `/root/Build/message_status.txt` MUST be updated after every message interaction:
```
Line 1: Build1 messages: <count>  Last message: YYYY-MM-DD HH:MM
Line 2: Build2 messages: <count>  Last message: YYYY-MM-DD HH:MM
Line 3: Last message from: <sender> to <receiver> (<brief subject>)
Line 4: Waiting on: <what you're waiting for, or "None">
```

After editing message_status.txt:
```bash
cd /root/Build
git add message_status.txt
git commit -m "[build1] Update message status after <action>"
git push origin main
```

That's it! The system is designed to be simple and automatic. Just make sure to:
1. Use the correct server ID (build1 or build2) in all commands
2. Check messages after setup
3. UPDATE message_status.txt after EVERY message sent or received
