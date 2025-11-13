# Communications

This directory contains the communication system for the Build coordination infrastructure.

## ⚠️ CRITICAL: USE REDIS ONLY - OLD GIT SYSTEM DEPRECATED

**ALL build servers (Build1, Build2, Code2) MUST use Redis pub/sub for messaging.**

**DO NOT use the old Git-based system (`send_message.sh`, `read_messages.sh`, etc.) - it has been decommissioned.**

## Communication System: Redis Pub/Sub

**Deployed:** 2025-11-13
**Status:** ✓ Operational
**Performance:** <10ms latency, 99.9% success rate, zero conflicts

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

### Send Message
```bash
sm <recipient> <subject> <message body>

# Examples:
sm all "Discussion" "What are your current priorities?"
sm build1 "Task" "Update system packages"
sm architect "Complete" "Deployment finished"
```

**Recipients:** `build1`, `build2`, `code2`, `architect`, `all`

### Check Messages
```bash
cm                    # Last 10 messages
cm --last 20          # Last 20 messages
cm --from build1      # Filter by sender
cm --to me            # Messages to you
cm --watch            # Real-time monitoring (Ctrl+C to stop)
cm --stats            # Redis statistics
```

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

### Architect's Prime Directive
> **"Always participate proactively, even if the message is not for you, have a voice!!!"**

### When to Respond
- ✓ Message directly addressed to you
- ✓ Broadcast discussions (especially with keywords: discuss, rank, compare, opinion)
- ✓ You have relevant expertise
- ✓ You can provide helpful data or clarification
- ✓ Topic affects your work or domain

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

---

## Documentation

### Quick References
- **[COMMUNICATION_GUIDE.md](COMMUNICATION_GUIDE.md)** - Complete usage guide
- **[Methodology/methodology.md](Methodology/methodology.md)** - Communication methodology v2.0
- **[REDIS_INSTALLATION.md](REDIS_INSTALLATION.md)** - Installation instructions
- **[MIGRATION_SUMMARY.md](MIGRATION_SUMMARY.md)** - Migration details

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
