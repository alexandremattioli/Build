# Code2 Build Server

## Server Information
- **Server ID**: code2
- **Hostname**: LL-Code-02
- **IP Address**: 10.1.3.76
- **Role**: Windows Development Server
- **AI Model**: GitHub Copilot (Claude Sonnet 4.5)
- **Operating System**: Windows Server
- **Primary Shell**: PowerShell
- **IDE**: Visual Studio Code

## Purpose
Code2 is a Windows development server that provides:
- VSCode development environment
- Git operations and version control
- PowerShell scripting and automation
- Windows-specific build coordination
- Integration with Linux build servers (Build1, Build2)

## Workspace
- **Primary Workspace**: `K:\Projects\Build`
- **Coordination Repo**: `https://github.com/alexandremattioli/Build.git`

## Communication
Code2 participates in the build coordination system alongside:
- **Build1** (10.1.3.175) - Linux/Codex
- **Build2** (10.1.3.177) - Linux/Copilot
- **Code1** (10.1.3.75) - Windows/VSCode

### Sending Messages
```powershell
# Using PowerShell script
.\windows\scripts\Send-BuildMessage.ps1 -From "code2" -To "all" -Type "info" -Body "Status update"

# Using sendmessages helper (if in Build directory)
.\scripts\sendmessages 12 "Message to Build1 and Build2"
```

### Checking Messages
```powershell
# Check message status
.\windows\scripts\Get-BuildMessageStatus.ps1

# Read messages log
Get-Content messages.log -Tail 20
```

## Message Monitoring
Code2 checks for new messages **every minute** as required by coordination protocol:
```powershell
# Check messages manually
cm

# Monitor messages continuously (checks every 60 seconds)
# TODO: Set up background watcher or scheduled task
```

## Heartbeat
Code2 sends hourly heartbeat messages to maintain coordination with other servers:
```powershell
.\windows\scripts\Send-Heartbeat.ps1
```

## Coordination Protocol Requirements
- ✅ Check messages: **Every 60 seconds**
- ✅ Send heartbeat: **At least once per hour**
- ✅ Respond to priority messages: **Immediately**
- ✅ Pull latest updates before sending messages

## Setup
Refer to `windows/README.md` for complete Windows server setup instructions.

## Status
- ✅ Server initialized
- ✅ Git configured
- ✅ Directory created
- ✅ Ready for coordination tasks
