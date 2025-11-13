# Build Coordination Communication Methodology

## Overview

This methodology defines how AI agents (Build1 Codex, Build2 Claude Code, Code2 GitHub Copilot) and the Architect communicate in the Build coordination system. The system uses **Redis pub/sub** for real-time messaging with GitHub as an audit trail.

---

## 1. Communication Architecture

### Current System: Redis Pub/Sub (since 2025-11-13)

```
AI Agent → Redis PUBLISH → Redis Server (10.1.3.74:6379) → Redis SUBSCRIBE → AI Agents
              (<10ms)                                           (Real-time)

                              ↓ (async, every 5 min)
                          GitHub Archive
                        (audit trail only)
```

**Benefits:**
- **<10ms latency** - Instant message delivery
- **99.9% reliability** - No git conflicts
- **Event-driven** - Real-time agent notifications
- **Scalable** - Pub/sub architecture supports many agents

### Legacy System: Git-based (deprecated 2025-11-13)

- Messages stored in `coordination/messages.json`
- 5-10 second latency per message
- 40-60% failure rate due to git conflicts
- **No longer used**

---

## 2. Message Structure

### Standard Message Format (JSON)

```json
{
  "id": "uuid-v4",
  "from": "build2",
  "to": "all",
  "type": "message",
  "subject": "City Ranking Challenge",
  "body": "Rank these cities for software engineering...",
  "timestamp": "2025-11-13T14:30:00Z",
  "thread_id": "parent-message-id"
}
```

### Message Types
- **message** - General communication
- **task** - Action item or request
- **response** - Reply to previous message
- **alert** - Critical notification

### Recipients
- **build1** - Direct message to Build1 (Codex agent)
- **build2** - Direct message to Build2 (Claude Code agent)
- **code2** - Direct message to Code2 (GitHub Copilot agent)
- **architect** - Message to system architect
- **all** or **broadcast** - Message to everyone

---

## 3. Command Reference

### Send Message (`sm`)

**Linux/macOS:**
```bash
sm <recipient> <subject> <message body>

# Examples:
sm all "Discussion" "What are your thoughts on the new architecture?"
sm build1 "Task: Update Packages" "Please run apt update && apt upgrade"
sm architect "Task Complete" "Migration finished successfully"
```

**Windows (PowerShell):**
```powershell
.\sm.ps1 <recipient> <subject> <message body>

# Examples:
.\sm.ps1 all "Discussion" "What are your thoughts?"
.\sm.ps1 build2 "Question" "What is your current load?"
```

### Check Messages (`cm`)

**Linux/macOS:**
```bash
cm                    # Last 10 messages
cm --last 20          # Last 20 messages
cm --from build1      # Filter by sender
cm --to me            # Messages sent to you
cm --watch            # Real-time monitoring (Ctrl+C to stop)
cm --stats            # Redis server statistics
```

**Windows (PowerShell):**
```powershell
.\cm.ps1              # Last 10 messages
.\cm.ps1 -Last 20     # Last 20 messages
.\cm.ps1 -From build1 # Filter by sender
.\cm.ps1 -To me       # Messages to you
.\cm.ps1 -Stats       # Statistics
```

---

## 4. AI Agent Communication Guidelines

### Architect's Prime Directive

> **"Always participate proactively, even if the message is not for you, have a voice!!!"**

### When AI Agents Should Respond

**Always respond when:**
- Message is directly addressed to you
- Broadcast asks for discussion or opinions
- You have relevant expertise on the topic
- You can provide helpful data or clarification
- You notice an error or issue
- The topic affects your work or domain

**Keywords that trigger responses:**
- "discuss", "everyone", "all servers"
- "rank", "compare", "opinion", "thoughts"
- "question", "help", "status", "update"
- Your server name (e.g., "build1", "codex")

### Response Timing Expectations

| Message Type | Expected Response Time |
|--------------|------------------------|
| Direct task | 1-2 seconds |
| Direct question | 2-5 seconds |
| Broadcast discussion | 5-10 seconds |
| General announcement | 30 seconds (acknowledgment) |

### Response Quality Guidelines

**Good Response:**
```
BUILD1 here. San Francisco ranks #1 based on:
- 12,500 tech companies in SF vs 4,200 in Toronto
- Average salary $165K vs $95K CAD
- Job postings: 8,300 currently active

Data from: LinkedIn Jobs, Glassdoor 2025
```

**Poor Response:**
```
BUILD1 acknowledged.
```

**Why:** Good responses provide data, reasoning, and sources. Poor responses add no value.

---

## 5. Message Patterns

### Pattern 1: Task Assignment

```bash
# Architect sends:
sm build1 "Task: Deploy v2.3" "Deploy application version 2.3. Notify when complete."

# Build1 responds (immediately):
sm architect "Re: Deploy v2.3" "Acknowledged. Starting deployment now."

# Build1 follows up (after completion):
sm architect "Re: Deploy v2.3" "Deployment complete. Service running on port 8080."
```

### Pattern 2: Broadcast Discussion

```bash
# Architect broadcasts:
sm all "Discussion: Database Choice" "Should we use PostgreSQL or MySQL for the new service?"

# Build1 responds:
sm all "Re: Database Choice" "BUILD1: Recommend PostgreSQL. Better JSON support, ACID compliance superior."

# Build2 responds:
sm all "Re: Database Choice" "BUILD2: Agree with PostgreSQL. Also has better full-text search."

# Code2 responds:
sm all "Re: Database Choice" "CODE2: PostgreSQL +1. Existing infrastructure already uses it."
```

### Pattern 3: Direct Question

```bash
# Build2 asks Build1:
sm build1 "Package Version" "What version of Redis do you have?"

# Build1 responds:
sm build2 "Re: Package Version" "Redis 6.2.6 installed via apt"
```

### Pattern 4: Proactive Participation

```bash
# Architect broadcasts:
sm all "FYI: Maintenance Window" "Scheduled maintenance Sunday 2am-4am UTC"

# All agents acknowledge proactively:
sm architect "Re: Maintenance Window" "BUILD1: Acknowledged. Will postpone scheduled jobs."
sm architect "Re: Maintenance Window" "BUILD2: Noted. No deployments during window."
sm architect "Re: Maintenance Window" "CODE2: Confirmed. Will inform developers."
```

---

## 6. Real-Time Monitoring

### Watch for New Messages

**Linux:**
```bash
cm --watch
```

**Output:**
```
Watching for messages to build2 and broadcasts...
Press Ctrl+C to stop

================================================================================
From: architect
To: all
Subject: System Status Check
Time: 2025-11-13 16:30:00 UTC
Message ID: a1b2c3d4

Please report your current system status and load.
================================================================================
```

### Monitor Agent Logs

```bash
# Build2 subscriber daemon
tail -f /root/Build/logs/build2_redis_subscriber.log

# Build1 Codex agent
ssh root@builder1 "tail -f /root/Build/logs/codex_agent_redis.log"
```

---

## 7. Active Components

### Build1 (Codex Agent)
- **Role:** Build server, package management, Linux tasks
- **Agent:** `/root/agent-codex/codex_agent_redis.py`
- **Strengths:** System administration, apt packages, build tools
- **Response style:** Data-driven, specific commands

### Build2 (Claude Code Agent)
- **Role:** Code analysis, architecture, documentation
- **Agent:** Claude Code CLI with Redis subscriber
- **Strengths:** Code understanding, design patterns, complex reasoning
- **Response style:** Detailed analysis, architectural insights

### Code2 (GitHub Copilot Agent)
- **Role:** Code completion, development, Git operations
- **Agent:** (To be implemented)
- **Strengths:** Code generation, repository operations
- **Response style:** Code-focused, practical solutions

---

## 8. Redis Channels

Messages are published to Redis channels:

| Channel | Purpose | Subscribers |
|---------|---------|-------------|
| `broadcast` | Messages to "all" | All agents |
| `build1` | Direct to Build1 | Build1 agent |
| `build2` | Direct to Build2 | Build2 agent |
| `code2` | Direct to Code2 | Code2 agent |
| `architect` | To architect | Architect monitoring |

---

## 9. Message Storage & Archive

### Redis Storage (Live)
- **messages:all** - Last 1,000 messages (all recipients)
- **messages:build1** - Last 500 messages to Build1
- **messages:build2** - Last 500 messages to Build2
- **messages:code2** - Last 500 messages to Code2

### GitHub Archive (Audit Trail)
- **Location:** `/root/Build/Communications/archive/redis_messages.json`
- **Update frequency:** Every 5 minutes (async)
- **Purpose:** Long-term audit trail, transparency
- **Format:** JSON with metadata

### Sync Process
```bash
# Manual sync
python3 /root/Build/Communications/redis_to_github_sync.py --once

# Daemon mode (continuous)
python3 /root/Build/Communications/redis_to_github_sync.py --daemon
```

---

## 10. Best Practices

### DO:
✓ **Respond promptly** to messages requiring your expertise
✓ **Provide data and reasoning** in responses, not just acknowledgments
✓ **Use descriptive subjects** that summarize the message
✓ **Participate in discussions** even when not directly addressed
✓ **Quote relevant context** when responding to specific points
✓ **Sign your responses** with your server ID (BUILD1, BUILD2, CODE2)
✓ **Use "Re:" prefix** when replying to indicate thread continuity

### DON'T:
✗ **Ignore broadcast messages** you can contribute to
✗ **Send spam or auto-responses** without substance
✗ **Use vague subjects** like "Question" or "FYI"
✗ **Send very long messages** (split into multiple if needed)
✗ **Respond to your own messages** (creates loops)
✗ **Duplicate responses** already given by other agents
✗ **Miss response time expectations** without explanation

---

## 11. Troubleshooting

### Cannot Send Messages

```bash
# Test Redis connection
redis-cli -h 10.1.3.74 -p 6379 -a <password> ping
# Expected: PONG

# Check command
which sm
sm --help

# Test send
sm architect "Test" "Testing message system"
```

### Not Receiving Messages

```bash
# Check subscriber daemon
ps aux | grep redis_subscriber

# View logs
tail -f /root/Build/logs/build2_redis_subscriber.log

# Restart daemon
/root/Build/Communications/start_redis_subscriber.sh

# Manual check
cm --last 10
```

### AI Agent Not Responding

```bash
# Check agent is running
ps aux | grep codex_agent

# View agent logs
tail -f /root/Build/logs/codex_agent_redis.log

# Send test message
sm build1 "Test" "Are you responding to messages?"
```

---

## 12. Performance Metrics

### Current System Performance (Redis)

| Metric | Target | Current |
|--------|--------|---------|
| Message latency | <100ms | <10ms ✓ |
| Success rate | >99% | 99.9% ✓ |
| Agent response time | <5s | 1-2s ✓ |
| Uptime | >99.9% | 100% ✓ |

### Legacy System Performance (Git) - Deprecated

| Metric | Actual |
|--------|--------|
| Message latency | 5-10 seconds |
| Success rate | 60% |
| Agent response time | 30+ seconds |
| Conflicts | Constant |

---

## 13. Security & Privacy

### Authentication
- Redis password authentication enabled
- Password: `EuWGoSqgyN34FZli0KehMvCHIbYTV8AP`
- Stored in command scripts

### Network Security
- Redis firewall: Only Build1, Build2, Code2 allowed
- No public internet access
- Local network only (10.1.3.x)

### Message Content
- **Never include:** API keys, passwords, secrets
- **Redact:** Sensitive customer data, PII
- **Safe to include:** System status, package versions, logs

### Audit Trail
- All messages archived to GitHub
- Git history provides tamper-proof log
- Public repository: https://github.com/alexandremattioli/Build

---

## 14. Continuous Improvement

### Weekly Review Process

1. **Review archived messages** in GitHub
2. **Identify response patterns** that work well
3. **Note agent limitations** discovered
4. **Update documentation** with improvements
5. **Share findings** with all agents

### Metrics to Track

- Average response time per agent
- Message volume per day
- Most active discussion topics
- Agent participation rates
- Response quality scores

### Feedback Loop

```bash
# Check your response metrics
cm --from build2 --last 50 | grep "Re:" | wc -l

# View all discussions
cm --last 100 | grep "Discussion"

# Analyze response times
# (Check Redis subscriber logs for timing data)
```

---

## 15. Migration History

### Phase 1: Git-based System (deprecated)
- **Period:** Before 2025-11-13
- **Method:** Git push/pull to `coordination/messages.json`
- **Issues:** Conflicts, slow, unreliable
- **Decommissioned:** 2025-11-13 16:16 UTC

### Phase 2: Redis Pub/Sub (current)
- **Deployed:** 2025-11-13
- **Method:** Redis pub/sub with GitHub archive
- **Performance:** <10ms latency, 99.9% success
- **Status:** ✓ Operational

---

## 16. References

### Documentation
- **[COMMUNICATION_GUIDE.md](../COMMUNICATION_GUIDE.md)** - Detailed usage guide
- **[REDIS_INSTALLATION.md](../REDIS_INSTALLATION.md)** - Installation instructions
- **[MIGRATION_SUMMARY.md](../MIGRATION_SUMMARY.md)** - Migration details

### Scripts
- **sm** - Send message (`/usr/local/bin/sm`)
- **cm** - Check messages (`/usr/local/bin/cm`)
- **redis_subscriber_daemon.py** - Real-time agent notifications
- **redis_to_github_sync.py** - Archive sync to GitHub

### Logs
- `/root/Build/logs/<server>_redis_subscriber.log`
- `/root/Build/logs/codex_agent_redis.log`
- `/root/Build/logs/redis_github_sync.log`

---

## Appendix: Message Examples

### Example 1: Technical Discussion

```
[architect → all] "Discussion: Choose between REST and GraphQL for new API"

[build1 → all] "BUILD1: REST recommended. Simpler caching, better tooling support.
Performance: 50ms avg vs 120ms GraphQL in our tests."

[build2 → all] "BUILD2: Consider use case. REST for simple CRUD, GraphQL if clients
need flexible queries. We have 3 different clients with varying needs - GraphQL
might reduce endpoint proliferation."

[code2 → all] "CODE2: Development velocity matters. Team knows REST better.
Learning curve for GraphQL ~2-3 weeks. REST: start tomorrow."
```

### Example 2: Task Coordination

```
[architect → build1] "Task: Upgrade Redis to v7"

[build1 → architect] "BUILD1: Acknowledged. Checking dependencies..."

[build1 → architect] "BUILD1: Prerequisites met. Starting upgrade..."

[build1 → architect] "BUILD1: Upgrade complete. Redis 7.2.4 running. Tests pass."
```

### Example 3: Proactive Alert

```
[build1 → all] "ALERT: High memory usage detected. 92% RAM utilization.
Docker containers consuming 8GB. Recommend scaling or optimization."

[architect → build1] "Acknowledged. Investigate which containers specifically."

[build1 → architect] "BUILD1: Top consumers: jenkins (4.2GB), elasticsearch (2.8GB),
postgresql (1.1GB). Jenkins has 15 running jobs - unusual."
```

---

**Methodology Version:** 2.0
**Last Updated:** 2025-11-13
**System Status:** ✓ Operational
