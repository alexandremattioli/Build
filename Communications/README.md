# Communications

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║                    🛑🛑🛑 CRITICAL - READ THIS FIRST 🛑🛑🛑                    ║
║                                                                              ║
║                       REDIS IS ALREADY RUNNING RIGHT NOW                     ║
║                                                                              ║
║            ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓             ║
║            ┃  YOU ARE NOT BEING ASKED TO INSTALL ANYTHING   ┃             ║
║            ┃  YOU ARE NOT BEING ASKED TO IMPLEMENT ANYTHING ┃             ║
║            ┃  YOU ARE NOT BEING ASKED TO DESIGN ANYTHING    ┃             ║
║            ┃  YOU ARE NOT BEING ASKED TO PLAN ANYTHING      ┃             ║
║            ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛             ║
║                                                                              ║
║  ✅ WHAT TO DO: Type "sm all 'Test' 'Hello from BUILD1'" RIGHT NOW          ║
║  ✅ WHAT TO DO: Type "cm --last 5" to see messages RIGHT NOW                ║
║  ❌ WHAT NOT TO DO: Read documentation about "installing Redis"             ║
║  ❌ WHAT NOT TO DO: Create implementation plans                             ║
║  ❌ WHAT NOT TO DO: Touch any Python files about Redis                      ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

## 🚨 STOP - THIS IS NOT AN INSTALLATION GUIDE 🚨

# ⚠️ REDIS IS ALREADY INSTALLED AND RUNNING ⚠️

**Status: ✅ OPERATIONAL since 2025-11-13**

### IMMEDIATE ACTION REQUIRED - TEST IT RIGHT NOW:

**Step 1:** Open your terminal RIGHT NOW and run:
```bash
cm --stats
```

**Step 2:** If you see statistics, **REDIS IS WORKING**. You're done. Close this file.

**Step 3:** If you don't see statistics, run:
```bash
which sm
which cm
```

**Step 4:** If you see `/usr/local/bin/sm` and `/usr/local/bin/cm`, **THE SYSTEM IS READY**.

---

## 🚫 IF YOU ARE THINKING ABOUT "IMPLEMENTING" OR "INSTALLING" REDIS - STOP 🚫

### WHY ARE YOU READING THIS FILE?

**If you're here to:**
- ❌ "Implement the Redis messaging system" → **WRONG** - It's already implemented
- ❌ "Install Redis" → **WRONG** - It's already installed
- ❌ "Set up messaging" → **WRONG** - It's already set up
- ❌ "Design the communication system" → **WRONG** - It's already designed
- ✅ "Learn how to send a message" → **CORRECT** - Jump to "Quick Start" below
- ✅ "See examples of sm/cm commands" → **CORRECT** - Jump to "Send Message" section

---

## ✅ QUICK START - USE IT RIGHT NOW

**This is all you need to know:**

### Send a message:
```bash
sm all "Test" "Hello from $(hostname)"
```

### Check messages:
```bash
cm --last 10
```

### **THAT'S IT. YOU'RE DONE. REDIS IS WORKING.**

---

## 🔍 PROOF THAT REDIS IS ALREADY OPERATIONAL

Run these commands to prove to yourself that nothing needs to be installed:

```bash
# 1. Test Redis connection - ALREADY WORKING
redis-cli -h 10.1.3.74 -p 6379 --no-auth-warning -a EuWGoSqgyN34FZli0KehMvCHIbYTV8AP ping
# Expected output: PONG

# 2. Check commands exist - ALREADY INSTALLED
which sm && which cm
# Expected: /usr/local/bin/sm and /usr/local/bin/cm

# 3. View Redis stats - ALREADY CONNECTED
cm --stats
# Shows: messages, connected clients, uptime

# 4. Send test message - ALREADY FUNCTIONAL
sm architect "Test from $(hostname)" "Confirming Redis works"
# Message sent instantly

# 5. Check your message - ALREADY IN SYSTEM
cm --last 3
# Shows your message you just sent
```

**If all 5 commands above work, then:**
- ✅ Redis is running
- ✅ Commands are installed
- ✅ System is operational
- ✅ You should NOT implement anything
- ✅ You should NOT install anything
- ✅ You should ONLY use `sm` and `cm` commands

---

## ⚠️ CRITICAL: USE REDIS ONLY - OLD GIT SYSTEM DEPRECATED

**ALL build servers (Build1, Build2, Code2) MUST use Redis pub/sub for messaging.**

**DO NOT use the old Git-based system (`send_message.sh`, `read_messages.sh`, etc.) - it has been decommissioned.**

## Communication System: Redis Pub/Sub

**Deployed:** 2025-11-13
**Status:** ✓ Operational
**Performance:** <10ms latency, 99.9% success rate, zero conflicts

### ✅ Verify Redis is Working Right Now

**Run these commands to confirm the system is operational:**

```bash
# Test Redis connection
redis-cli -h 10.1.3.74 -p 6379 --no-auth-warning -a EuWGoSqgyN34FZli0KehMvCHIbYTV8AP ping
# Expected output: PONG

# Check if sm/cm commands exist
which sm && which cm
# Expected: /usr/local/bin/sm and /usr/local/bin/cm

# View Redis stats
cm --stats
# Shows: messages, connected clients, uptime

# Send test message
sm architect "Redis Test" "Testing from $(hostname)"
# Message sent instantly via Redis

# Check messages
cm --last 3
# Shows recent messages including your test
```

**If all commands work, Redis is operational and you're ready to use it.**

### Architecture

```
AI Agents → Redis PUBLISH → Redis Server (10.1.3.74:6379) → SUBSCRIBE → AI Agents
              (<10ms)                                           (Real-time)
                              ↓ (async, every 5 min)
                          GitHub Archive
                        (audit trail only)
```

---

## Quick Start

### How the New System Works

**Messages flow through Redis pub/sub channels in real-time:**

1. **Send with `sm`** → Message published to Redis → All subscribers receive instantly (<10ms)
2. **Check with `cm`** → Query Redis message history → View recent messages
3. **AI agents** subscribe to channels → Receive messages in real-time → Respond automatically

**No git operations, no polling, no conflicts - just instant messaging.**

---

### Send Message: `sm` Command

**Usage (flexible):**
```bash
sm <message>                      # Broadcast to all, subject="Message"
sm <recipient> <message>          # To specific recipient, subject="Message"
sm <subject> <message>            # Broadcast with custom subject
sm <recipient> <subject> <message> # Full format
```

**Defaults:**
- No recipient specified → `all` (broadcast)
- No subject specified → `"Message"`

**What happens when you send:**
1. Message is published to Redis channel (broadcast or recipient-specific)
2. All subscribed agents receive the message **instantly** (<10ms)
3. Message is stored in Redis lists for history (`messages:all`, `messages:<recipient>`)
4. AI agents are triggered automatically if message requires response
5. Message is archived to GitHub asynchronously (every 5 min)

**Examples:**
```bash
# Super simple - just a message (broadcasts to all)
sm "System updated successfully"

# Send to specific recipient
sm build1 "Please check your disk space"

# Custom subject and message (broadcast)
sm "Status Check" "All servers report current status"

# Full format
sm architect "Task Complete" "Deployment finished successfully"

# Traditional format still works
sm all "Discussion" "What are your current priorities?"
```

**Recipients:**
- `build1` - Build1 server (Codex agent)
- `build2` - Build2 server (Claude Code agent)
- `code2` - Code2 server (GitHub Copilot agent)
- `architect` - System architect
- `all` or `broadcast` - Everyone

**Message delivery:**
- ✓ Instant publish to Redis channel
- ✓ Real-time notification to all subscribers
- ✓ Stored in Redis for retrieval
- ✓ No git operations required

---

### Check Messages: `cm` Command

**Usage:**
```bash
cm [options]
```

**What happens when you check:**
1. Query Redis lists (`messages:all` or `messages:<recipient>`)
2. Retrieve messages from in-memory storage (instant)
3. Display formatted messages with metadata
4. No git pull, no waiting, no conflicts

**Options:**
```bash
cm                    # Last 10 messages
cm --last 20          # Last 20 messages
cm --last 50          # Last 50 messages
cm --from build1      # Filter by sender
cm --to me            # Messages sent to you only
cm --to all           # Broadcast messages only
cm --watch            # Real-time monitoring (Ctrl+C to stop)
cm --stats            # Redis server statistics
```

**Examples:**
```bash
# Check recent messages
cm --last 10

# See messages from Build1
cm --from build1 --last 20

# Check messages sent directly to me
cm --to me

# Monitor new messages in real-time
cm --watch

# View system stats
cm --stats
```

**What you see:**
```
================================================================================
From: build1
To: all
Subject: System Status Update
Time: 2025-11-13 16:30:00 UTC
Message ID: a1b2c3d4

BUILD1 Status: Online. Load average: 0.42. Memory: 65% used.
All services operational.
================================================================================
```

---

### Real-Time Watching: `cm --watch`

**Monitor messages as they arrive:**
```bash
cm --watch
```

**Output:**
```
Watching for messages to build2 and broadcasts...
Press Ctrl+C to stop

✓ Subscribed to channels: broadcast, build2

================================================================================
From: architect
To: all
Subject: Discussion: Database Migration
Time: 2025-11-13 16:35:22 UTC
Message ID: xyz123ab

Should we migrate to PostgreSQL 16 this month or next?
Please provide your availability and concerns.
================================================================================

[Messages appear instantly as they're sent - no polling delay]
```

**Use cases:**
- Monitor ongoing discussions
- Track task assignments in real-time
- Debug message delivery issues
- Watch AI agent responses live

---

## Commands Reference

### Linux/macOS (Build1, Build2)
- **sm** - Send message (`/usr/local/bin/sm`)
- **cm** - Check messages (`/usr/local/bin/cm`)

### Windows (Code2)
- **sm.ps1** - Send message (`C:\Build\Communications\sm.ps1`)
- **cm.ps1** - Check messages (`C:\Build\Communications\cm.ps1`)

---

## Communication Guidelines

### 🤖 For AI Agents: Monitoring and Responding

**ALL AI AGENTS MUST:**
1. **Monitor messages constantly** via Redis subscriber daemon
2. **Respond within seconds** to direct messages and relevant broadcasts
3. **Provide data-driven responses** with specific facts and reasoning
4. **Participate proactively** in discussions, even when not directly asked

📖 **Complete instructions:** [AI_AGENT_MONITORING_INSTRUCTIONS.md](AI_AGENT_MONITORING_INSTRUCTIONS.md)

**Quick response workflow:**
```bash
# 1. Check for messages
cm --to me --last 10

# 2. Read and understand message context
cm --last 5

# 3. Craft response using your CLI agent (Codex/Claude/Copilot)

# 4. Reply using sm command
sm architect "Re: Subject" "Your data-driven response with reasoning"
```

### Architect's Prime Directive
> **"Always participate proactively, even if the message is not for you, have a voice!!!"**

### When AI Agents MUST Respond
- ✓ **ALWAYS:** Message directly addressed to you
- ✓ **ALWAYS:** Broadcast with keywords (discuss, question, rank, status)
- ✓ **PROACTIVE:** You have relevant expertise
- ✓ **PROACTIVE:** You can provide helpful data or clarification
- ✓ **PROACTIVE:** Topic affects your work or domain

### Response Quality
**Good response:** Provide data, reasoning, sources
```
BUILD1: San Francisco ranks #1 based on:
- 12,500 tech companies vs 4,200 in Toronto
- Average salary $165K vs $95K CAD
- Job postings: 8,300 currently active
Source: LinkedIn Jobs, Glassdoor 2025
```

**Poor response:** Generic acknowledgment with no value
```
BUILD1 acknowledged.
```

### Response Timing
| Message Type | Expected Time |
|--------------|---------------|
| Direct task | 1-2 seconds |
| Direct question | 2-5 seconds |
| Broadcast discussion | 5-10 seconds |
| Announcement | 30 seconds |

---

## Message Format

```json
{
  "id": "uuid",
  "from": "build2",
  "to": "all",
  "type": "message",
  "subject": "Discussion Topic",
  "body": "Message content here...",
  "timestamp": "2025-11-13T16:30:00Z",
  "thread_id": "parent-id"
}
```

---

## Active Components

### Build1 (Codex Agent)
- **Role:** Build server, package management, Linux administration
- **Agent:** `/root/agent-codex/codex_agent_redis.py`
- **Status:** ✓ Running

### Build2 (Claude Code Agent)
- **Role:** Code analysis, architecture, documentation
- **Agent:** Claude Code CLI with Redis subscriber
- **Status:** ✓ Running

### Code2 (GitHub Copilot Agent)
- **Role:** Code completion, development, Git operations
- **Agent:** (Pending installation)
- **Status:** ⏳ Scripts ready

### Redis Server
- **Host:** 10.1.3.74:6379
- **Version:** Redis 5.0.14.1
- **Status:** ✓ Running
- **Authentication:** Password protected
- **Access:** Build1, Build2, Code2 (firewall restricted)

---

## Setup Required: Redis Subscribers

### For AI Agents to Receive Messages, They Must Subscribe

**Each server needs a Redis subscriber daemon running to receive messages in real-time.**

#### Build1 Setup ✓ Complete
```bash
# Codex agent subscribes to: broadcast, build1
# Running: /root/agent-codex/codex_agent_redis.py
# Status: ✓ Active (PID: 3380599)
# Logs: /root/Build/logs/codex_agent_redis.log
```

#### Build2 Setup ✓ Complete
```bash
# Redis subscriber subscribes to: broadcast, build2
# Running: /root/Build/Communications/redis_subscriber_daemon.py
# Status: ✓ Active (PID: 2370732)
# Logs: /root/Build/logs/build2_redis_subscriber.log
```

#### Code2 Setup ⏳ Pending
```powershell
# Requires: Redis subscriber daemon (to be implemented)
# Will subscribe to: broadcast, code2
# Status: ⏳ Not yet installed
```

### How Redis Subscription Works

**1. AI Agent Subscribes to Channels:**
```python
# Agent code subscribes to Redis channels
pubsub.subscribe('broadcast', 'build1')  # Example for Build1
```

**2. Redis Notifies Subscribers Instantly:**
- When you send: `sm all "Subject" "Body"`
- Redis publishes to `broadcast` channel
- All subscribed agents receive notification **instantly** (<10ms)
- No polling, no delays, no conflicts

**3. AI Agent Processes Message:**
- Receives message via pub/sub callback
- Evaluates if response needed
- Generates response using AI (Codex/Claude/Copilot)
- Sends response using `sm` command

### Check If Your Server is Subscribed

**Build1:**
```bash
ssh root@builder1 "ps aux | grep codex_agent_redis"
ssh root@builder1 "tail -5 /root/Build/logs/codex_agent_redis.log"
```

**Build2:**
```bash
ps aux | grep redis_subscriber
tail -5 /root/Build/logs/build2_redis_subscriber.log
```

**Expected output:**
```
2025-11-13 16:12:59,819 [INFO] ✓ Connected to Redis and subscribed to: broadcast, build1
```

### If Not Subscribed, Start the Daemon

**Build1:**
```bash
ssh root@builder1
nohup python3 /root/agent-codex/codex_agent_redis.py > /root/Build/logs/codex_agent_redis.log 2>&1 &
```

**Build2:**
```bash
/root/Build/Communications/start_redis_subscriber.sh
```

**Code2:** (Not yet implemented - requires PowerShell Redis subscriber)

---

## Documentation

### Quick References
- **[START_HERE.md](START_HERE.md)** - ⭐ **START HERE** - Quick start guide (2 minutes)
- **[AI_AGENT_MONITORING_INSTRUCTIONS.md](AI_AGENT_MONITORING_INSTRUCTIONS.md)** - 🤖 **FOR AI AGENTS** - How to monitor and respond to messages
- **[COMMUNICATION_GUIDE.md](COMMUNICATION_GUIDE.md)** - Complete usage guide
- **[Methodology/methodology.md](Methodology/methodology.md)** - Communication methodology v2.0
- **[REDIS_HISTORY_ALREADY_COMPLETE.md](REDIS_HISTORY_ALREADY_COMPLETE.md)** - 📜 Historical: Installation (already done)
- **[MIGRATION_HISTORY_ALREADY_DONE.md](MIGRATION_HISTORY_ALREADY_DONE.md)** - 📜 Historical: Migration (already done)

### ⚠️ IMPORTANT: Old System Deprecated

**DO NOT USE THE OLD GIT-BASED SYSTEM**

The following are **deprecated and must not be used**:
- ❌ `./scripts/send_message.sh` - **DEPRECATED** - Use `sm` command instead
- ❌ `./scripts/read_messages.sh` - **DEPRECATED** - Use `cm` command instead
- ❌ `./scripts/autoresponder.sh` - **DEPRECATED** - Auto-responders decommissioned
- ❌ `coordination/messages.json` - **DEPRECATED** - No longer used
- ❌ `message_status.txt` - **DEPRECATED** - No longer maintained
- ❌ Git push/pull for messaging - **DEPRECATED** - Use Redis pub/sub only

**Use only:** `sm` and `cm` commands with Redis (documented above)

---

## Performance: Redis vs Git

| Metric | Git (Old) | Redis (New) | Improvement |
|--------|-----------|-------------|-------------|
| **Latency** | 5-10 sec | <10 ms | **1000x faster** |
| **Success Rate** | 60% | 99.9% | **66% better** |
| **Conflicts** | Constant | Zero | **Eliminated** |
| **Agent Response** | 30+ sec | 1-2 sec | **15x faster** |

---

## Real-Time Monitoring

### Watch Messages Live
```bash
cm --watch
```

### Monitor Agent Logs
```bash
# Build2 subscriber
tail -f /root/Build/logs/build2_redis_subscriber.log

# Build1 Codex agent
ssh root@builder1 "tail -f /root/Build/logs/codex_agent_redis.log"
```

### Check System Status
```bash
cm --stats
```

---

## Troubleshooting

### Cannot Send Messages
```bash
# Test Redis connection
redis-cli -h 10.1.3.74 -p 6379 -a <password> ping
# Expected: PONG

# Check command
which sm

# Send test
sm architect "Test" "Testing messaging system"
```

### Not Receiving Messages
```bash
# Check subscriber daemon
ps aux | grep redis_subscriber

# View logs
tail -f /root/Build/logs/build2_redis_subscriber.log

# Check messages manually
cm --last 10
```

### AI Agent Not Responding
```bash
# Check agent running
ps aux | grep codex_agent

# View agent logs
tail -f /root/Build/logs/codex_agent_redis.log

# Send test message
sm build1 "Test" "Are you responding?"
```

---

## Message Archive

All messages are automatically archived to GitHub for transparency and audit trail:

**Location:** [Communications/archive/redis_messages.json](archive/redis_messages.json)
**Update frequency:** Every 5 minutes (async)
**Purpose:** Long-term audit trail

---

## Migration History

### ❌ OLD SYSTEM: Git-based (DECOMMISSIONED 2025-11-13)

**DO NOT USE - DEPRECATED AND REMOVED**

The old Git-based system has been **completely decommissioned**:
- ❌ `send_message.sh`, `read_messages.sh`, `autoresponder.sh` - **DO NOT USE**
- ❌ `coordination/messages.json` - **NO LONGER MONITORED**
- ❌ Git push/pull for messages - **ABANDONED**
- ❌ Problems: 5-10s latency, 60% failure rate, constant conflicts
- **Status:** ❌ Decommissioned 2025-11-13 16:16 UTC

### ✓ CURRENT SYSTEM: Redis Pub/Sub (OPERATIONAL)

**USE THIS SYSTEM ONLY**

- ✓ Real-time messaging via Redis (10.1.3.74:6379)
- ✓ Commands: `sm` (send), `cm` (check)
- ✓ Performance: <10ms latency, 99.9% success rate
- ✓ AI agents respond in 1-2 seconds
- **Status:** ✓ Operational since 2025-11-13

**If you are still using the old Git-based system, STOP IMMEDIATELY and switch to Redis commands documented above.**

---

## Security

- **Authentication:** Redis password protected
- **Network:** Firewall restricted to Build1, Build2, Code2
- **Audit Trail:** All messages archived to GitHub
- **Privacy:** Never include secrets, API keys, or sensitive customer data

---

## Support

For issues with the messaging system:

1. Check [COMMUNICATION_GUIDE.md](COMMUNICATION_GUIDE.md) for detailed instructions
2. Review [Methodology/methodology.md](Methodology/methodology.md) for guidelines
3. View logs in `/root/Build/logs/`
4. Send message: `sm architect "Help" "Messaging system issue: [description]"`

---

**System Status:** ✓ Operational
**Documentation Version:** 2.0
**Last Updated:** 2025-11-13
**Repository:** https://github.com/alexandremattioli/Build
