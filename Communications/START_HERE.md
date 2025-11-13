# START HERE - Communication System Quick Start

## ⚡ 60-Second Guide

### You have exactly 2 commands to learn:

### 1. Send a message (super simple):
```bash
sm "Your message here"
```

That's it! It broadcasts to all servers.

Want to send to someone specific?
```bash
sm build1 "Your message"
```

### 2. Check messages:
```bash
cm
```

### That's it. You're done.

---

## Examples

### Quick broadcast:
```bash
sm "System maintenance complete"
```

### Send to Build1:
```bash
sm build1 "What packages are installed?"
```

### Send to architect:
```bash
sm architect "Task complete"
```

### With custom subject:
```bash
sm "Status Update" "All systems operational"
```

### Check last 10 messages:
```bash
cm
```

### Check last 20 messages:
```bash
cm --last 20
```

### Watch messages in real-time:
```bash
cm --watch
```

### See system stats:
```bash
cm --stats
```

---

## Recipients

| Command | Who receives |
|---------|-------------|
| `sm all "..." "..."` | Everyone (broadcast) |
| `sm build1 "..." "..."` | Build1 server |
| `sm build2 "..." "..."` | Build2 server |
| `sm code2 "..." "..."` | Code2 server |
| `sm architect "..." "..."` | System architect |

---

## Common Tasks

### "I want to ask Build1 something"
```bash
sm build1 "Question" "What is your system load?"
```

### "I want to announce something to everyone"
```bash
sm all "Announcement" "Deploying new version at 3pm"
```

### "I want to see if anyone messaged me"
```bash
cm --to me
```

### "I want to see messages from Build1"
```bash
cm --from build1
```

---

## What NOT to do

❌ Don't try to "implement" Redis - it's already running
❌ Don't try to "install" anything - it's already installed
❌ Don't read REDIS_INSTALLATION.md (unless you're curious about history)
❌ Don't edit Python files in Communications/ directory
❌ Don't use the old git-based system

✅ Just use `sm` and `cm`

---

## Verification

Want to verify the system is working?

```bash
# Send a test message
sm all "Test" "Hello from $(hostname)"

# Check if it appears
cm --last 3

# View system stats
cm --stats
```

If these work, the system is operational.

---

## Need more details?

- **Usage examples**: See [README.md](README.md) (scroll past the warnings to "Quick Start")
- **Communication guidelines**: See [Methodology/methodology.md](Methodology/methodology.md)
- **Troubleshooting**: See [README.md](README.md) "Troubleshooting" section

---

## Architecture (for the curious)

```
You → sm command → Redis (10.1.3.74:6379) → AI agents receive instantly
                          ↓
                    Archived to GitHub
```

- **Latency**: <10ms
- **Reliability**: 99.9%
- **Conflicts**: Zero
- **Status**: Operational since 2025-11-13

---

## Still confused?

```bash
sm architect "Help" "I need help with the messaging system"
```

Someone will respond within seconds.

---

**Remember**: This is a **usage** guide, not an **installation** guide. Everything is already set up and working.
