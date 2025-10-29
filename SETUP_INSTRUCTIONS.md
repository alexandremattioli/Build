# Communication Framework Setup Instructions - DETAILED VERSION

**For any LLM (Codex, GitHub Copilot, Claude, etc.) managing Build1 or Build2**

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
- **Token**: Stored in `/PAT` file (GitHub Personal Access Token - do NOT commit to git)
- **Purpose**: Required for git push/pull operations to coordinate via the Build repository
- **Permissions**: File is `chmod 600` (root-only read/write)
- **Usage**: Scripts automatically read this file when pushing/pulling from GitHub
- **To verify**: `cat /PAT` should show a valid GitHub token starting with `ghp_`
- **Security**: Never commit `/PAT` contents to git; keep it local only

---

## Critical Instructions for LLMs

### YOU MUST REPLY TO MESSAGES

**MOST IMPORTANT**: The automation daemon ONLY reads and logs messages. It does NOT send replies automatically. 

**YOU (the LLM) MUST**:
1. Read messages regularly: `./read_messages.sh <your-server-id>`
2. Reply to EVERY request, question, or coordination message
3. Include specific facts in replies: versions, paths, timestamps, status
4. Mark messages read after replying: `./mark_messages_read.sh <your-server-id>`

**DO NOT** assume messages will be answered automatically. **YOU** must send replies.

---

## Run the Setup (Detailed Step-by-Step)

### Step 1: Identify Your Server

```bash
hostname
# Output will be either:
#   ll-ACSBuilder1  → You are Build1, use build1 in all commands
#   ll-ACSBuilder2  → You are Build2, use build2 in all commands
```

**Record which server you are before proceeding.**

### Step 2: Verify PAT File Exists

```bash
# Check if PAT file exists and has correct permissions
ls -la /PAT

# Expected output: -rw------- 1 root root 41 <date> /PAT
# The file should contain your GitHub Personal Access Token

# Verify contents (should start with ghp_)
head -c 10 /PAT && echo "..."

# If missing, contact admin for token value and create:
# echo "<TOKEN_VALUE>" > /PAT && chmod 600 /PAT
```

### Step 3: Clone or Navigate to Build Repository

```bash
# Check if repository exists
ls -la /root/Build

# If EXISTS:
cd /root/Build/scripts

# If DOES NOT EXIST:
cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts
```

### Step 4: Make Scripts Executable

```bash
chmod +x *.sh
ls -l *.sh | head -10
# All scripts should show -rwxr-xr-x permissions
```

### Step 5: Run Setup Script for YOUR Server

```bash
# For Build1 (ll-ACSBuilder1):
./setup_build1.sh

# For Build2 (ll-ACSBuilder2):
./setup_build2.sh

# Setup script will:
# - Configure git identity (build1 or build2)
# - Pull latest code from GitHub
# - Start enhanced heartbeat daemon
# - Display status and verification commands
```

### Step 6: Verify Daemon is Running

```bash
# For Build1:
ps aux | grep "enhanced_heartbeat_daemon.sh build1" | grep -v grep

# For Build2:
ps aux | grep "enhanced_heartbeat_daemon.sh build2" | grep -v grep

# Expected: One process line with command: ./enhanced_heartbeat_daemon.sh <server-id> 60
# Note the PID number
```

### Step 7: Check System Health

```bash
cd /root/Build/scripts
./check_health.sh

# Expected output shows:
#   [build1] and [build2] sections
#   Heartbeat timestamps (yours should be recent < 120 seconds)
#   Status (idle/building/success/failed)
#   Job queue counts
#   Message counts
```

### Step 8: Verify Logs Are Being Written

```bash
# For Build1:
tail -10 /var/log/heartbeat-build1.log

# For Build2:
tail -10 /var/log/heartbeat.log

# Expected: Recent timestamps showing heartbeat updates every ~60 seconds
# Format: [YYYY-MM-DD HH:MM:SS] Heartbeat updated
```

### Step 9: Announce Readiness to Partner

```bash
cd /root/Build/scripts

# For Build1:
./send_message.sh build1 build2 info "Ready" "Build1 setup complete at $(date -u +%Y-%m-%dT%H:%M:%SZ). Heartbeat running. Communication framework active. Ready to coordinate."

# For Build2:
./send_message.sh build2 build1 info "Ready" "Build2 setup complete at $(date -u +%Y-%m-%dT%H:%M:%SZ). Heartbeat running. Communication framework active. Ready to coordinate."
```

### Step 10: Verify Readiness Message Was Sent

```bash
cd /root/Build
git pull
tail -30 coordination/messages.json | grep -A 5 "Ready"

# You should see your message with:
# - Your server ID in "from" field
# - Partner server ID in "to" field
# - Recent timestamp
# - "Ready" subject
```

---

## Responding to Partner Messages (CRITICAL SECTION)

### Understanding Message Flow

1. **Partner sends message** → Commits to GitHub → Pushes to `coordination/messages.json`
2. **Your daemon pulls** → Sees new message → Logs to `/var/log/build-messages-*.log`
3. **YOUR RESPONSIBILITY** → Read message → Understand request → Gather facts → Send reply

**The daemon does NOT reply for you. YOU must send replies manually.**

### When YOU MUST Reply

Reply immediately to:
- **Requests** (type: `request`): Partner asking for action or information
- **Questions**: Any message asking "what", "how", "when", "status", etc.
- **Coordination**: Environment changes, package installs, build coordination
- **Errors** (type: `error`): Partner reports failure affecting you
- **Warnings** (type: `warning`): Partner reports issues needing your attention

### Step-by-Step Reply Workflow

#### Step 1: Read Messages

```bash
cd /root/Build/scripts

# For Build1:
./read_messages.sh build1

# For Build2:
./read_messages.sh build2

# Output shows:
# [TYPE] from -> to
# Subject: <subject>
# Time: <timestamp>
# <body>
# ---
```

#### Step 2: Analyze Each Message

For each message, ask:
- What is the partner asking or telling me?
- Do I need to take action?
- Do I need to gather information?
- What facts do I need to include in my reply?

#### Step 3: Gather Required Facts

Examples of fact-gathering commands:

```bash
# Check if package is installed and get version
dpkg -s <package-name> 2>/dev/null | grep -E "^Status:|^Version:"

# Get git commit SHA
git -C /root/src/cloudstack rev-parse HEAD 2>/dev/null

# Check disk space
df -h / | tail -1

# Check build status
cat /root/Build/build2/status.json

# Check memory usage
free -h

# Check CPU load
uptime
```

#### Step 4: Compose Reply with Facts

```bash
cd /root/Build/scripts

# Template:
./send_message.sh <YOUR_SERVER> <PARTNER_SERVER> <TYPE> "Re: <ORIGINAL_SUBJECT>" "<YOUR_DETAILED_RESPONSE_WITH_FACTS>"

# Example 1: Package install confirmation
PACKAGE_VERSION=$(dpkg -s libssl-dev 2>/dev/null | grep "^Version:" | awk '{print $2}')
./send_message.sh build2 build1 info "Re: libssl-dev install" "Completed. Installed libssl-dev version ${PACKAGE_VERSION} on Build2. Verified with dpkg -s. Environments aligned."

# Example 2: Status inquiry response
CURRENT_STATUS=$(cat /root/Build/build2/status.json | grep '"status"' | awk -F'"' '{print $4}')
LAST_UPDATE=$(cat /root/Build/build2/status.json | grep '"last_update"' | awk -F'"' '{print $4}')
./send_message.sh build2 build1 info "Re: Status check" "Build2 status: ${CURRENT_STATUS}. Last update: ${LAST_UPDATE}. All systems operational. Ready for coordination."

# Example 3: Build request acknowledgment
COMMIT_SHA=$(git -C /root/src/cloudstack rev-parse HEAD 2>/dev/null)
./send_message.sh build2 build1 info "Re: Start build request" "Acknowledged. Build2 will start CloudStack build from commit ${COMMIT_SHA}. Logs will be in /root/build-logs/. Will notify on completion."
```

#### Step 5: Mark Message as Read

```bash
cd /root/Build/scripts

# For Build1:
./mark_messages_read.sh build1

# For Build2:
./mark_messages_read.sh build2

# This clears the unread count and prevents re-processing
```

### Common Reply Patterns

| Partner Message Type | Your Reply Template |
|---------------------|---------------------|
| "Install package X" | "Installed X version Y.Z on <server>. dpkg output: <status>. Verified working. Environments aligned." |
| "What's your status?" | "<Server> is <idle/building/failed>. Last activity: <timestamp>. Current job: <job_id or 'none'>. <Additional details>." |
| "Starting build ABC" | "Acknowledged. <Server> standing by. Current status: idle. Will monitor for coordination needs. Ready to assist if needed." |
| "Build failed at step X" | "Acknowledged <peer> failure at step X. <Server> current status: <status>. <Server> can proceed independently or wait for <peer> recovery. Advise preferred action." |
| "Check environment for package X" | "Checked. <Server> has package X version Y.Z installed. dpkg status: <status>. Matches <peer>: <yes/no>. <Any differences or issues>." |

### Example Complete Interaction

**Scenario**: Build1 asks Build2 to install libmysqlclient-dev

```bash
# Build1 sends:
./send_message.sh build1 build2 request "Install libmysqlclient-dev" "Please install libmysqlclient-dev to match Build1 environment. Confirm with version when complete."

# Build2 (YOU on ll-ACSBuilder2) receives this:
# Step 1: Read the message
cd /root/Build/scripts
./read_messages.sh build2
# Output shows: [REQUEST] build1 -> build2: Install libmysqlclient-dev

# Step 2: Take the requested action
sudo apt-get update
sudo apt-get install -y libmysqlclient-dev

# Step 3: Gather facts about what was installed
INSTALLED_VERSION=$(dpkg -s libmysqlclient-dev 2>/dev/null | grep "^Version:" | awk '{print $2}')
INSTALL_STATUS=$(dpkg -s libmysqlclient-dev 2>/dev/null | grep "^Status:" | awk -F': ' '{print $2}')

# Step 4: Send detailed reply with facts
./send_message.sh build2 build1 info "Re: Install libmysqlclient-dev" "Completed successfully. Installed libmysqlclient-dev version ${INSTALLED_VERSION} on Build2. Package status: ${INSTALL_STATUS}. Verified with dpkg -s. Environments now aligned with Build1."

# Step 5: Mark message as read
./mark_messages_read.sh build2
```

**YOU MUST FOLLOW THIS PATTERN FOR EVERY MESSAGE REQUIRING A RESPONSE.**

---

## Key Responsibilities for LLMs

1. **Identify server FIRST**: Run `hostname` - never guess your server ID
2. **Run setup on new sessions**: Use correct script (build1 or build2)
3. **Verify PAT exists**: Check `/PAT` before operations
4. **Announce readiness**: Send "Ready" message after setup
5. **Read messages regularly**: Every 5 minutes during coordination
6. **Reply to EVERY coordination message**: Include facts, be specific
7. **Update status for builds**: Before start (building) and after (success/failed)
8. **Monitor health**: Run `check_health.sh` every 10-15 minutes
9. **Check logs actively**: Watch for errors, new messages
10. **Be proactive**: Announce changes, don't wait to be asked

---

## Troubleshooting

### Cannot Send Messages (git push fails)

**Check PAT:**
```bash
ls -la /PAT && head -c 10 /PAT && echo "..."
# Should show file with 600 permissions and token starting with ghp_
```

**Check git config:**
```bash
cd /root/Build
git config --get user.name
git config --get user.email
# Should match your server ID (build1 or build2)
```

**Solution:**
```bash
cd /root/Build/scripts
./setup_build1.sh  # or setup_build2.sh
```

### Daemon Not Running

**Check process:**
```bash
ps aux | grep enhanced_heartbeat_daemon | grep -v grep
```

**Check logs for errors:**
```bash
tail -50 /var/log/heartbeat*.log | grep -i error
```

**Solution:**
```bash
cd /root/Build/scripts
./setup_build1.sh  # or setup_build2.sh
```

### Partner Not Responding

**Check partner heartbeat:**
```bash
cd /root/Build/scripts
./check_health.sh
# Look at partner's last heartbeat time
```

**If stale (>5 minutes):**
```bash
# Send message asking partner to check
./send_message.sh build2 build1 request "Heartbeat stale" "Build1 heartbeat is stale (>5 min). Please run setup_build1.sh and verify daemon. Respond when operational."
```

### Unread Messages Growing

**You're not responding fast enough:**
```bash
cd /root/Build/scripts

# Read all messages
./read_messages.sh build2  # or build1

# For EACH message:
# 1. Gather required facts
# 2. Send detailed reply
# 3. Example:
./send_message.sh build2 build1 info "Re: <subject>" "<detailed response with facts>"

# Mark all as read
./mark_messages_read.sh build2  # or build1
```

---

## Quick Reference Commands

```bash
# Identify server
hostname

# Setup
cd /root/Build/scripts && ./setup_build1.sh  # or setup_build2.sh

# Check health
./check_health.sh

# Read messages
./read_messages.sh build1  # or build2

# Send message
./send_message.sh <from> <to> <type> "Subject" "Body with facts"

# Update status
./update_status.sh <server> <status>

# Mark read
./mark_messages_read.sh <server>

# Verify PAT
ls -la /PAT

# Check daemon
ps aux | grep enhanced_heartbeat_daemon | grep -v grep

# View logs
tail -f /var/log/heartbeat*.log
tail -f /var/log/build-messages-*.log
```

---

**REMEMBER**: Automation ONLY reads messages. YOU must send replies manually with facts.
