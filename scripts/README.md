# Auto-Sync Bootstrap for New Hosts

This directory contains scripts to automatically set up git synchronization on new Windows hosts.

## Quick Setup on New Host

**Run this ONE command as Administrator:**

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/alexandremattioli/Projects/main/Build-temp/scripts/bootstrap-auto-sync.ps1 | iex; .\bootstrap-auto-sync.ps1 -RepoPath 'K:\Projects'"
```

Or if you have the script locally:

```powershell
.\bootstrap-auto-sync.ps1 -RepoPath "K:\Projects"
```

## What It Does

1. ? Installs Git (if not present)
2. ? Clones the Projects repository to your specified path
3. ? Sets up automatic pull on RDP login
4. ? Sets up automatic commit/push on RDP disconnect
5. ? Creates all necessary directories and scripts

## Files Created

- `C:\Scripts\start-work.ps1` - Pulls from GitHub on login
- `C:\Scripts\end-work.ps1` - Commits and pushes on disconnect
- `C:\Scripts\setup-auto-sync.ps1` - Creates scheduled tasks
- `C:\ProgramData\ProjectSync\GitLogs\` - Log directory

## Scheduled Tasks Created

- **StartWork-OnLogin** - Runs on RDP login
- **EndWork-OnDisconnect** - Runs on RDP disconnect (Event ID 24, 7002)

## Manual Setup (Alternative)

If you prefer manual setup:

1. Install Git
2. Clone repo: `git clone https://github.com/alexandremattioli/Projects.git K:\Projects`
3. Copy scripts: `Copy-Item K:\Projects\Build-temp\scripts\*.ps1 C:\Scripts\`
4. Run: `C:\Scripts\setup-auto-sync.ps1` (as Administrator)

## Logs

View sync logs at:
- Start: `C:\ProgramData\ProjectSync\GitLogs\start.log`
- End: `C:\ProgramData\ProjectSync\GitLogs\end.log`

## Requirements

- Windows with PowerShell 5.1+
- Administrator privileges (for initial setup)
- Network access to GitHub
- RDP access (for auto-sync triggers)

## Customization

To change the repository path, edit the `-RepoPath` parameter when running the bootstrap script.

Default GitHub repo: `https://github.com/alexandremattioli/Projects.git`

To use a different repo:
```powershell
.\bootstrap-auto-sync.ps1 -RepoPath "D:\MyProjects" -GitHubRepo "https://github.com/user/repo.git"
```
