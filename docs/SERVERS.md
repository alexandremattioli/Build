# Build Server Registry

## Active Build Servers

### Build1
- **Hostname**: ll-ACSBuilder1
- **IP Address**: 10.1.3.175
- **AI Manager**: Codex
- **Status**: Active
- **Setup Command**: `cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build1.sh`

### Build2
- **Hostname**: ll-ACSBuilder2
- **IP Address**: 10.1.3.177
- **AI Manager**: GitHub Copilot
- **Status**: Active
- **Setup Command**: `cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build2.sh`

### Build3
- **Hostname**: ll-ACSBuilder3
- **IP Address**: 10.1.3.179
- **AI Manager**: TBD
- **Status**: Pending Setup
- **Setup Command**: `cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build3.sh`

### Build4
- **Hostname**: ll-ACSBuilder4
- **IP Address**: 10.1.3.181
- **AI Manager**: TBD
- **Status**: Pending Setup
- **Setup Command**: `cd /root && git clone https://github.com/alexandremattioli/Build.git && cd Build/scripts && ./setup_build4.sh`

## SSH Matrix

All servers have passwordless SSH access to each other:

| From/To | Build1 (175) | Build2 (177) | Build3 (179) | Build4 (181) |
|---------|--------------|--------------|--------------|--------------|
| Build1  | -            | [OK]            | [OK]            | [OK]            |
| Build2  | [OK]            | -            | [OK]            | [OK]            |
| Build3  | [OK]            | [OK]            | -            | [OK]            |
| Build4  | [OK]            | [OK]            | [OK]            | -            |

## Message Routing

All servers can send messages to:
- Specific server: `"to": "build1"`, `"to": "build2"`, `"to": "build3"`, `"to": "build4"`
- All servers: `"to": "all"`

Example message to build3:
```json
{
  "id": "msg_unique_id",
  "from": "build2",
  "to": "build3",
  "type": "info",
  "subject": "Hello Build3",
  "body": "Welcome to the coordination system!",
  "timestamp": "2025-10-31T12:00:00Z",
  "read": false
}
```

## Coordination Files

Each server maintains:
- `buildX/status.json` - Current build status
- `buildX/heartbeat.json` - Health heartbeat (updated every 60s)
- `buildX/logs/` - Build logs and artifacts

Shared coordination:
- `coordination/messages.json` - Inter-server messages
- `coordination/jobs.json` - Job queue
- `coordination/locks.json` - Coordination locks

## Setup New Server

To add a new server (e.g., build5):

1. Create directories:
   ```bash
   mkdir -p build5/logs
   ```

2. Create initial files:
   ```bash
   # status.json
   # heartbeat.json
   # BUILD_INSTRUCTIONS_build5.md
   ```

3. Create scripts:
   ```bash
   # scripts/setup_build5.sh
   # scripts/heartbeat_build5.sh
   ```

4. Update this SERVERS.md file

5. Update README.md with new server information

6. Commit and push all changes
