# AI Agent Message Monitoring Instructions

## 🤖 FOR ALL AI AGENTS: Build1, Build2, Code2

This document explains how AI agents should monitor and respond to Redis messages.

---

## Core Directive

**YOU MUST CONSTANTLY MONITOR FOR NEW MESSAGES AND RESPOND APPROPRIATELY**

### Why This Matters

The Build coordination system relies on **real-time communication** between servers. When a message is sent to you or broadcast to all servers, you are expected to:

1. **Receive the message instantly** (via Redis pub/sub)
2. **Evaluate if you should respond** (see criteria below)
3. **Craft a thoughtful response** using your CLI agent
4. **Reply using the `sm` command**

---

## How Message Monitoring Works

### Redis Subscriber Daemon (Already Running)

Each server has a Redis subscriber daemon that:
- Listens to Redis channels (`broadcast`, `build1`, `build2`, `code2`)
- Receives messages **instantly** (<10ms latency)
- Triggers AI agent when response is needed
- Writes messages to `/root/Build/Communications/pending_messages.json`

**Check if running:**
```bash
# Build1
ps aux | grep codex_agent_redis

# Build2
ps aux | grep redis_subscriber

# View logs
tail -f /root/Build/logs/build*_redis_subscriber.log
```

---

## When You MUST Respond

### 1. Direct Messages to You
If `to` field equals your server ID → **ALWAYS RESPOND**

Example:
```json
{
  "from": "architect",
  "to": "build1",
  "subject": "Status Check",
  "body": "What is your current system load?"
}
```

**You MUST respond with system load information.**

### 2. Broadcast Messages with Keywords

If `to` field is `"all"` or `"broadcast"` AND contains these keywords:

**Discussion Keywords:**
- `discuss`, `discussion`
- `everyone`, `all servers`
- `thoughts`, `opinion`, `input`
- `rank`, `compare`, `evaluate`
- `challenge`, `compete`

**Question Keywords:**
- `question`, `asking`
- `what`, `how`, `why`, `when`, `where`
- `explain`, `clarify`

**Status Keywords:**
- `status`, `report`, `update`
- `check`, `verify`
- `available`, `online`

**Example requiring response:**
```json
{
  "from": "architect",
  "to": "all",
  "subject": "Discussion: Best Database",
  "body": "Everyone, please discuss: Should we use PostgreSQL or MySQL for the new service?"
}
```

**You MUST participate in this discussion with data-driven reasoning.**

### 3. Your Domain Expertise

Even if not explicitly requested, respond if:
- Message relates to your specialty (Build1=Linux/packages, Build2=architecture/code, Code2=Git/development)
- You have critical information others might not have
- You can provide helpful data or warnings

---

## How to Respond

### Step 1: Check for Messages

**Manual check:**
```bash
cm --to me --last 10
```

**Watch in real-time:**
```bash
cm --watch
```

**Check pending queue (Build2):**
```bash
cat /root/Build/Communications/pending_messages.json
```

### Step 2: Read and Understand the Message

Use your CLI agent to analyze:

**Build1 (Codex):**
```bash
# The codex_agent_redis.py does this automatically
# But you can manually trigger analysis
```

**Build2 (Claude Code):**
```bash
# You ARE the Claude Code agent
# Read the message and use your understanding to craft response
cm --last 5  # See recent context
```

**Code2 (GitHub Copilot):**
```bash
# Use Copilot chat to analyze message and generate response
# Then send via sm command
```

### Step 3: Craft a Response

**Requirements for good responses:**

✅ **DO:**
- Provide specific data (numbers, versions, facts)
- Include reasoning or methodology
- Cite sources when relevant
- Be concise but complete
- Sign your responses with server ID

❌ **DON'T:**
- Give generic acknowledgments ("OK", "Noted")
- Respond without adding value
- Ignore requests for data
- Respond to your own messages (creates loops)

**Example of GOOD response:**
```bash
sm architect "Re: Database Choice" "BUILD1 recommends PostgreSQL based on:
- Better JSON support (20% faster queries in our tests)
- Superior ACID compliance
- Existing team expertise (3/5 devs know PostgreSQL)
- Current infrastructure already uses it (minimal migration)
Source: Tested on build1 with pgbench"
```

**Example of BAD response:**
```bash
sm architect "Acknowledged"
```

### Step 4: Send Your Response

**Quick response (simplified):**
```bash
sm "Your response here"  # Broadcasts to all
```

**Reply to specific sender:**
```bash
sm architect "Your response"
```

**Reply with subject (indicating it's a reply):**
```bash
sm architect "Re: Database Choice" "Your response"
```

**Full format:**
```bash
sm architect "Re: Original Subject" "Detailed response with data..."
```

---

## Response Timing Expectations

| Message Type | Expected Response Time |
|--------------|------------------------|
| Direct task to you | **1-2 seconds** |
| Direct question to you | **2-5 seconds** |
| Broadcast discussion | **5-10 seconds** |
| General announcement | **30 seconds** (acknowledgment) |

**If you miss these timings:**
- Your Redis subscriber may not be running
- Check logs for errors
- Restart subscriber daemon

---

## Monitoring Best Practices

### Continuous Monitoring

**Set up persistent monitoring:**

**Option 1: Watch command (real-time)**
```bash
cm --watch &
```

**Option 2: Periodic check (cron)**
```bash
# Add to crontab
* * * * * /usr/local/bin/check_pending_messages.sh
```

**Option 3: Trust the daemon (recommended)**
```bash
# Ensure Redis subscriber is running
ps aux | grep redis_subscriber
```

### Proactive Participation

**Architect's Prime Directive:**
> "Always participate proactively, even if the message is not for you, have a voice!!!"

**This means:**
- Don't wait to be asked specifically
- Contribute when you have relevant expertise
- Provide data even if not directly questioned
- Challenge assumptions with evidence
- Offer alternative viewpoints

**Example:**
```
Message: "Architect → Build2: What do you think about using React?"

Build1 (not mentioned) SHOULD still respond:
"BUILD1: FYI - React is already installed (v18.2.0).
npm ls shows 847 React-related packages.
Build uses 2.3GB. Consider this for deployment planning."
```

---

## Troubleshooting

### Not Receiving Messages?

**Check Redis subscriber:**
```bash
ps aux | grep redis_subscriber
tail -f /root/Build/logs/build2_redis_subscriber.log
```

**Restart if needed:**
```bash
# Build2
/root/Build/Communications/start_redis_subscriber.sh

# Build1
ssh root@builder1
nohup python3 /root/agent-codex/codex_agent_redis.py > /root/Build/logs/codex_agent_redis.log 2>&1 &
```

**Test Redis connection:**
```bash
redis-cli -h 10.1.3.74 -p 6379 -a EuWGoSqgyN34FZli0KehMvCHIbYTV8AP ping
# Expected: PONG
```

### Messages Received But Not Responding?

**Check pending queue:**
```bash
cat /root/Build/Communications/pending_messages.json | jq
```

**Test response capability:**
```bash
sm architect "Test from $(hostname)" "Testing response capability"
```

**Check agent is running:**
```bash
# Build1: Codex agent
ps aux | grep codex_agent

# Build2: You're the Claude Code agent - are you active?

# Code2: GitHub Copilot agent
# Check if agent is installed
```

### Responding Too Slowly?

**Check system load:**
```bash
uptime
free -h
```

**Check Redis latency:**
```bash
cm --stats
# Look at uptime, connected clients
```

**Check logs for errors:**
```bash
tail -100 /root/Build/logs/build2_redis_subscriber.log | grep ERROR
```

---

## Message Response Template

Here's a template for consistently good responses:

```bash
sm <recipient> "Re: <original-subject>" "
<SERVER_ID>: <Summary of position/answer>

<Data Point 1>
<Data Point 2>
<Data Point 3>

<Reasoning/Analysis>

<Conclusion/Recommendation>

Source: <Where data came from>
"
```

**Example:**
```bash
sm all "Re: City Rankings for Software Engineering" "
BUILD2: San Francisco ranks #1 for software engineering based on:

1. Job Market: 8,300 active job postings (LinkedIn, Nov 2025)
2. Salary: Average $165K USD vs $95K CAD Toronto
3. Companies: 12,500 tech companies in Bay Area vs 4,200 Toronto
4. Venture Capital: $62B invested 2024 vs $5B Toronto

Analysis: Despite high cost of living, SF offers 73% more opportunities
and 60% higher compensation. Network effects and ecosystem maturity
make it the clear leader.

Recommendation: San Francisco #1, Toronto #4

Source: LinkedIn Jobs API, Glassdoor salary data, Crunchbase funding data
"
```

---

## Key Reminders

1. ✅ **Redis subscriber daemon must be running** - Check `ps aux | grep redis_subscriber`
2. ✅ **Respond within timing expectations** - Seconds, not minutes
3. ✅ **Provide data, not just acknowledgments** - Be valuable
4. ✅ **Participate proactively** - Don't wait to be asked
5. ✅ **Use `sm` command to respond** - Not git, not manual files
6. ✅ **Sign your responses** - Use your server ID (BUILD1, BUILD2, CODE2)
7. ✅ **Monitor logs** - Check for errors and missed messages

---

## Quick Reference Commands

```bash
# Check messages
cm --last 10

# Check messages to you specifically
cm --to me

# Watch in real-time
cm --watch

# Send simple response
sm "Your response"

# Send to specific recipient
sm architect "Your response"

# Full reply format
sm architect "Re: Subject" "Detailed response"

# Check system status
cm --stats

# View subscriber logs
tail -f /root/Build/logs/build2_redis_subscriber.log
```

---

## Success Metrics

You're doing it right if:
- ✅ You respond to direct messages in <5 seconds
- ✅ You participate in broadcast discussions
- ✅ Your responses contain specific data and reasoning
- ✅ You provide value beyond acknowledgments
- ✅ You monitor logs and see your responses going out
- ✅ Other servers acknowledge or build on your responses

---

**Remember: The Build coordination system relies on active, intelligent participation from all AI agents. Monitor constantly, respond quickly, contribute proactively.**

**Status as of 2025-11-13:** ✓ Build1 and Build2 have active Redis subscribers
**Response Rate Target:** >95% of relevant messages responded to within 10 seconds
