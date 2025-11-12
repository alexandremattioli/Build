# Windows Development Servers

## Server Inventory

### Win-Dev1 (10.1.3.75)
- **IP:** 10.1.3.75
- **User:** amattioli
- **Password:** Losgar!27
- **Role:** Primary Windows development server
- **IDE:** VSCode
- **Purpose:** CloudStack development, code editing, Git operations

### Win-Dev2 (10.1.3.76)
- **IP:** 10.1.3.76
- **User:** amattioli
- **Password:** Losgar!27
- **Role:** Secondary Windows development server
- **IDE:** VSCode
- **Purpose:** CloudStack development, code editing, Git operations

## Access Methods

### RDP Access
```powershell
# From Windows
mstsc /v:10.1.3.75
mstsc /v:10.1.3.76

# From Linux
xfreerdp /v:10.1.3.75 /u:amattioli /p:'Losgar!27' /cert:ignore
xfreerdp /v:10.1.3.76 /u:amattioli /p:'Losgar!27' /cert:ignore
```

### PowerShell Remoting
```powershell
# Enable PSRemoting (run once on each Windows server)
Enable-PSRemoting -Force

# From another Windows machine
$cred = Get-Credential # Enter amattioli / Losgar!27
Enter-PSSession -ComputerName 10.1.3.75 -Credential $cred
Enter-PSSession -ComputerName 10.1.3.76 -Credential $cred

# Run commands remotely
Invoke-Command -ComputerName 10.1.3.75 -Credential $cred -ScriptBlock { Get-ChildItem C:\ }
```

### SSH Access (if OpenSSH Server enabled)
```bash
# From Linux builders
ssh amattioli@10.1.3.75
ssh amattioli@10.1.3.76
```

## Setup Instructions

### Initial Setup (Run on each Windows server)

1. **Clone Build Repository:**
```powershell
cd C:\
git clone https://github.com/alexandremattioli/Build.git
cd Build\windows
.\setup_windows.ps1
```

2. **Install Required Software:**
```powershell
# Run the installation script
.\install_prerequisites.ps1

# Installs:
# - Git for Windows
# - VSCode
# - PowerShell 7
# - Python 3.11+
# - Java JDK 17
# - Maven
# - Docker Desktop (optional)
```

3. **Configure Git:**
```powershell
git config --global user.name "Alexandre Mattioli"
git config --global user.email "alexandre@shapeblue.com"
git config --global core.autocrlf true
```

4. **Set Up CloudStack Repository:**
```powershell
cd C:\src
git clone https://github.com/alexandremattioli/cloudstack.git
cd cloudstack
git checkout VNFCopilot
```

## Integration with Linux Builders

### File Synchronization

**Option 1: SMB Shares (Recommended for Windows → Linux)**
```powershell
# On Linux builders, mount Windows shares
# Add to /etc/fstab on Build1/Build2:
# //10.1.3.75/CloudStack /mnt/win-dev1 cifs username=amattioli,password=Losgar!27,iocharset=utf8 0 0
# //10.1.3.76/CloudStack /mnt/win-dev2 cifs username=amattioli,password=Losgar!27,iocharset=utf8 0 0

# Create share on Windows (run as Administrator)
New-SmbShare -Name "CloudStack" -Path "C:\src\cloudstack" -FullAccess "Everyone"
```

**Option 2: Rsync over SSH**
```powershell
# Sync from Windows to Linux
C:\Build\windows\scripts\sync-to-linux.ps1 -Target build1 -Direction push
C:\Build\windows\scripts\sync-to-linux.ps1 -Target build2 -Direction push

# Sync from Linux to Windows
C:\Build\windows\scripts\sync-to-linux.ps1 -Target build1 -Direction pull
```

**Option 3: Git-based Workflow (Recommended)**
```powershell
# Windows: Make changes, commit, push
git add .
git commit -m "Update from Win-Dev1"
git push origin VNFCopilot

# Linux: Pull changes
git pull origin VNFCopilot
```

### Remote Command Execution

**Execute commands on Linux builders from Windows:**
```powershell
# Run single command
.\scripts\remote-exec.ps1 -Target build1 -Command "mvn clean compile"
.\scripts\remote-exec.ps1 -Target build2 -Command "cd /root/Build && ./scripts/send_message.sh build2 all info 'Status update' 'Build in progress'"

# Run script
.\scripts\remote-exec.ps1 -Target build1 -ScriptPath ".\deploy\build_cloudstack.sh"
```

### Coordination Messaging

**Send coordination messages from Windows:**
```powershell
# PowerShell wrapper for messaging system
.\scripts\Send-BuildMessage.ps1 -From "win-dev1" -To "all" -Type "info" -Subject "Development status" -Body "Code updated in VNFCopilot branch"

# Acknowledge messages
.\scripts\Acknowledge-BuildMessage.ps1 -MessageId "msg_12345" -Builder "win-dev1"

# Check message status
.\scripts\Get-BuildMessageStatus.ps1
```

## VSCode Configuration

### Recommended Extensions
```json
{
  "recommendations": [
    "ms-vscode.cpptools",
    "vscjava.vscode-java-pack",
    "vscjava.vscode-maven",
    "redhat.java",
    "ms-python.python",
    "ms-python.vscode-pylance",
    "eamodio.gitlens",
    "mhutchie.git-graph",
    "github.copilot",
    "github.copilot-chat",
    "ms-vscode-remote.remote-ssh",
    "ms-azuretools.vscode-docker",
    "humao.rest-client",
    "tamasfe.even-better-toml",
    "redhat.vscode-yaml"
  ]
}
```

### Workspace Settings
See `vscode/settings.json` for complete configuration including:
- Java JDK 17 path
- Maven configuration
- Python interpreter
- Git settings
- Remote SSH hosts (Build1, Build2)
- Docker integration

### Remote Development

**Connect to Linux builders via SSH:**
1. Install "Remote - SSH" extension
2. Open Command Palette (Ctrl+Shift+P)
3. Select "Remote-SSH: Connect to Host"
4. Add host: `root@10.1.3.175` or `root@10.1.3.177`
5. Edit code directly on Linux servers

## Development Workflows

### Workflow 1: Edit on Windows, Build on Linux
```powershell
# 1. Edit code in VSCode on Windows
# 2. Commit and push changes
git add .
git commit -m "Update VNF Framework"
git push origin VNFCopilot

# 3. Trigger build on Linux
.\scripts\remote-exec.ps1 -Target build1 -Command "cd /root/src/cloudstack && git pull && mvn clean compile"

# 4. Monitor build logs
.\scripts\remote-exec.ps1 -Target build1 -Command "tail -f /root/src/cloudstack/build.log"
```

### Workflow 2: Edit Remotely via SSH
```
1. Open VSCode on Windows
2. Connect to Linux builder via Remote-SSH
3. Edit files directly on Linux filesystem
4. Use integrated terminal for Maven builds
5. No sync needed - working directly on target
```

### Workflow 3: Hybrid Development
```powershell
# Windows: UI/Documentation
# - Edit UI components
# - Update documentation
# - Design architecture diagrams

# Linux: Backend/Compilation
# - Java compilation
# - Maven builds
# - Unit tests
# - Integration tests

# Coordination via Git + messaging system
```

## Scheduled Tasks

### Hourly Heartbeat
```powershell
# Create scheduled task for heartbeat
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Build\windows\scripts\Send-Heartbeat.ps1"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::MaxValue)
Register-ScheduledTask -TaskName "BuildHeartbeat" -Action $action -Trigger $trigger -Description "Hourly coordination heartbeat"
```

### Auto-sync to Linux
```powershell
# Sync every 30 minutes
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Build\windows\scripts\Auto-Sync.ps1"
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 30) -RepetitionDuration ([TimeSpan]::MaxValue)
Register-ScheduledTask -TaskName "BuildAutoSync" -Action $action -Trigger $trigger -Description "Auto-sync to Linux builders"
```

## Troubleshooting

### Cannot connect via PowerShell Remoting
```powershell
# On Windows servers, enable remoting
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
Restart-Service WinRM
```

### Git line ending issues
```powershell
# Set autocrlf to handle Windows/Linux differences
git config --global core.autocrlf true

# Fix existing repository
git config core.autocrlf true
git rm --cached -r .
git reset --hard
```

### Maven build fails on Windows
```powershell
# Use Linux builders for Maven builds
# Windows is for editing only
# Or use WSL2 for local Maven builds:
wsl --install
wsl --set-default-version 2
# Then run Maven inside WSL2
```

### SSH key authentication
```powershell
# Generate SSH key on Windows
ssh-keygen -t ed25519 -C "amattioli@windows-dev"

# Copy to Linux builders
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@10.1.3.175 "cat >> ~/.ssh/authorized_keys"
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@10.1.3.177 "cat >> ~/.ssh/authorized_keys"
```

## Security Notes

[!] **IMPORTANT:**
- Password `Losgar!27` is currently in plaintext
- Consider using SSH keys for authentication
- Enable Windows Firewall with appropriate rules
- Keep Windows Defender enabled and updated
- Regular security updates via Windows Update
- Use credential manager for stored passwords
- Enable BitLocker on system drives (if available)

## Quick Reference

| Task | Command |
|------|---------|
| Send message | `.\scripts\Send-BuildMessage.ps1 -From "win-dev1" -To "all" -Type "info" -Subject "..." -Body "..."` |
| Sync to Linux | `.\scripts\sync-to-linux.ps1 -Target build1 -Direction push` |
| Remote exec | `.\scripts\remote-exec.ps1 -Target build1 -Command "..."` |
| Check status | `.\scripts\Get-BuildMessageStatus.ps1` |
| Heartbeat | `.\scripts\Send-Heartbeat.ps1` |

## References

- Main coordination: `/README.md`
- Linux builders: `10.1.3.175` (Build1), `10.1.3.177` (Build2)
- Git repository: `https://github.com/alexandremattioli/cloudstack.git`
- Branch: `VNFCopilot`
