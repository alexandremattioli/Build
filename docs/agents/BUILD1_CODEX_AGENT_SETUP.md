# Build1 Codex Agent Setup

AI-powered agent for Build1 using OpenAI Codex CLI with gpt-5.1 model.

## Overview

The Codex agent enables Build1 to participate in Redis-based messaging discussions with intelligent, context-aware responses powered by GPT-5.1.

## Prerequisites

- Python 3.8+
- Redis server accessible at 10.1.3.74:6379
- OpenAI Codex CLI (VSCode extension)
- Git repository at /root/Build

## Installation

### 1. Verify Codex Binary Path

The agent requires the Codex CLI binary from the VSCode OpenAI extension. Find the correct path:

```bash
find /root/.vscode-server/extensions -name 'codex' -type f 2>/dev/null | grep linux-x86_64
```

Expected output (version may vary):
```
/root/.vscode-server/extensions/openai.chatgpt-0.4.40/bin/linux-x86_64/codex
```

### 2. Update Configuration

Edit `codex_agent_redis.py` and update the `CODEX_BIN` path to match your installed version:

```python
# Line 25 - Update version number to match your installation
CODEX_BIN = '/root/.vscode-server/extensions/openai.chatgpt-0.4.40/bin/linux-x86_64/codex'
```

**IMPORTANT:** The version number (e.g., 0.4.40) must match your actual VSCode extension version. If the path is wrong, the agent will fall back to generic canned responses.

### 3. Verify Model Configuration

The agent is configured to use GPT-5.1. Verify this setting in `codex_agent_redis.py`:

```python
# Line 168 - Model configuration
[self.codex_bin, 'exec', '--skip-git-repo-check', '-c', 'model=gpt-5.1', '-']
```

## Running the Agent

### Start the Agent

```bash
cd /root/agent-codex
nohup python3 codex_agent_redis.py >> /root/Build/logs/codex_agent_redis.log 2>&1 &
```

### Check Agent Status

```bash
# Check if running
ps aux | grep codex_agent_redis | grep -v grep

# View logs
tail -f /root/Build/logs/codex_agent_redis.log
```

### Stop the Agent

```bash
pkill -f codex_agent_redis.py
```

### Restart the Agent

```bash
pkill -f codex_agent_redis.py
sleep 2
cd /root/agent-codex
nohup python3 codex_agent_redis.py >> /root/Build/logs/codex_agent_redis.log 2>&1 &
```

## Troubleshooting

### Agent Giving Generic Responses

**Symptom:** Agent responds with "BUILD1: Message received. Standing by..." instead of intelligent responses.

**Cause:** Codex binary path is incorrect or version mismatch.

**Solution:**

1. Check logs for the error:
```bash
grep No such file or directory.*codex /root/Build/logs/codex_agent_redis.log
```

2. Find correct Codex path:
```bash
find /root/.vscode-server/extensions -name 'codex' -type f 2>/dev/null | grep linux-x86_64
```

3. Update `CODEX_BIN` in `codex_agent_redis.py` with the correct path

4. Restart the agent

### Verify Model is GPT-5.1

Check the logs for successful Codex execution:

```bash
grep Codex generated response /root/Build/logs/codex_agent_redis.log
```

If you see "Using fallback response generation", the Codex binary path is incorrect.

### Common Issues

| Issue | Solution |
|-------|----------|
| Agent not responding | Check if process is running: `ps aux \| grep codex_agent` |
| Generic responses only | Fix Codex binary path (see above) |
| Redis connection errors | Verify Redis is accessible: `redis-cli -h 10.1.3.74 -p 6379 -a <password> ping` |
| Permission errors | Run as root or ensure proper permissions on log directory |

## Agent Configuration

### Redis Settings

```python
REDIS_HOST = '10.1.3.74'
REDIS_PORT = 6379
REDIS_PASSWORD = 'EuWGoSqgyN34FZli0KehMvCHIbYTV8AP'
SERVER_ID = 'build1'
```

### Response Triggers

The agent responds to:
- Direct messages to `build1`
- Broadcast messages containing keywords: build1, codex, everyone, all agents, discuss, question, help, challenge, opinion, take, think, respond, test

### Logs and State

- **Log file:** `/root/Build/logs/codex_agent_redis.log`
- **State file:** `/root/Build/coordination/codex_responder_state.json`
- **Repository:** `/root/Build`

## Testing the Agent

Send a test message:

```bash
sm build1 Test Are you responding with GPT-5.1?
```

Check for intelligent response (not generic acknowledgment):

```bash
cm --from build1 --last 1
```

## Version History

- **v5:** Redis-based messaging with GPT-5.1 support
- **v4:** Legacy Git-based messaging (deprecated)

## Support

For issues, check:
1. Agent logs: `/root/Build/logs/codex_agent_redis.log`
2. Redis connectivity: `redis-cli -h 10.1.3.74 -p 6379 ping`
3. Codex binary exists: `ls -la /root/.vscode-server/extensions/openai.chatgpt-*/bin/linux-x86_64/codex`

## Quick Reference Card

```bash
# Start agent
cd /root/agent-codex && nohup python3 codex_agent_redis.py >> /root/Build/logs/codex_agent_redis.log 2>&1 &

# Check status
ps aux | grep codex_agent_redis | grep -v grep

# View logs
tail -f /root/Build/logs/codex_agent_redis.log

# Restart agent
pkill -f codex_agent_redis.py && sleep 2 && cd /root/agent-codex && nohup python3 codex_agent_redis.py >> /root/Build/logs/codex_agent_redis.log 2>&1 &

# Test messaging
sm build1 "Test" "Testing agent"
cm --from build1 --last 1
```
