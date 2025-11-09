<#
.SYNOPSIS
    Bootstrap script to set up automatic git sync on a new host
.DESCRIPTION
    This script will:
    1. Install Git if not present
    2. Clone the Projects repository
    3. Set up automatic pull on login and push on disconnect
.PARAMETER RepoPath
    The local path where the Projects repo should be cloned (e.g., "K:\Projects")
.PARAMETER GitHubRepo
    The GitHub repository URL (e.g., "https://github.com/alexandremattioli/Projects.git")
.EXAMPLE
    .\bootstrap-auto-sync.ps1 -RepoPath "K:\Projects" -GitHubRepo "https://github.com/alexandremattioli/Projects.git"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$RepoPath,
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubRepo = "https://github.com/alexandremattioli/Projects.git"
)

$ErrorActionPreference = "Stop"

function Log($message) {
    Write-Host "[$(Get-Date -Format ''HH:mm:ss'')] $message" -ForegroundColor Cyan
}

function Check-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This script must be run as Administrator. Please restart PowerShell as Administrator."
    }
}

# Check for admin rights
Check-Admin

Log "Starting bootstrap process..."
Log "Target repo path: $RepoPath"
Log "GitHub repo: $GitHubRepo"

# Step 1: Check/Install Git
Log "Checking for Git installation..."
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Log "Git not found. Installing Git..."
    
    # Download Git installer
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe"
    $gitInstaller = "$env:TEMP\git-installer.exe"
    
    Log "Downloading Git installer..."
    Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
    
    Log "Installing Git (this may take a few minutes)..."
    Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS=`"icons,ext\reg\shellhere,assoc,assoc_sh`"" -Wait
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    Log "Git installed successfully."
} else {
    Log "Git is already installed: $(git --version)"
}

# Step 2: Clone or update repository
if (Test-Path (Join-Path $RepoPath ".git")) {
    Log "Repository already exists at $RepoPath"
    Log "Pulling latest changes..."
    git -C $RepoPath pull
} else {
    Log "Cloning repository to $RepoPath..."
    
    # Create parent directory if needed
    $parentDir = Split-Path $RepoPath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    git clone $GitHubRepo $RepoPath
    Log "Repository cloned successfully."
}

# Step 3: Create C:\Scripts directory
Log "Creating C:\Scripts directory..."
New-Item -ItemType Directory -Path "C:\Scripts" -Force | Out-Null

# Step 4: Copy sync scripts from repo (if they exist) or create them
$scriptsInRepo = Join-Path $RepoPath "Build-temp\scripts"

if (Test-Path $scriptsInRepo) {
    Log "Copying scripts from repository..."
    Copy-Item "$scriptsInRepo\start-work.ps1" -Destination "C:\Scripts\" -Force -ErrorAction SilentlyContinue
    Copy-Item "$scriptsInRepo\end-work.ps1" -Destination "C:\Scripts\" -Force -ErrorAction SilentlyContinue
    Copy-Item "$scriptsInRepo\setup-auto-sync.ps1" -Destination "C:\Scripts\" -Force -ErrorAction SilentlyContinue
}

# Step 5: Create start-work.ps1 if it doesn''t exist
if (-not (Test-Path "C:\Scripts\start-work.ps1")) {
    Log "Creating start-work.ps1..."
    @"
param([string]`$RepoPath = "$RepoPath")
`$LogRoot = "C:\ProgramData\ProjectSync\GitLogs"; New-Item -ItemType Directory -Path `$LogRoot -Force | Out-Null
`$log = Join-Path `$LogRoot "start.log"; function Log(`$m){ "`$((Get-Date).ToString(''yyyy-MM-dd HH:mm:ss'')) `$m" | Tee-Object -FilePath `$log -Append }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git not installed." }
if (-not (Test-Path (Join-Path `$RepoPath ''.git''))) { throw "Not a git repo: `$RepoPath" }
try {
  Log "---- Start Work ----"
  git -C `$RepoPath fetch --all --prune | Tee-Object -FilePath `$log -Append | Out-Null
  git -C `$RepoPath pull --rebase --autostash | Tee-Object -FilePath `$log -Append
  if (`$LASTEXITCODE -ne 0) { Log "Conflicts during pull. Resolve before coding."; exit 1 }
  Log "Start Work complete."
} catch { Log "Error: `$(`$_.Exception.Message)"; exit 1 }
"@ | Set-Content "C:\Scripts\start-work.ps1"
}

# Step 6: Create end-work.ps1 if it doesn''t exist
if (-not (Test-Path "C:\Scripts\end-work.ps1")) {
    Log "Creating end-work.ps1..."
    @"
param([string]`$RepoPath = "$RepoPath")
`$LogRoot = "C:\ProgramData\ProjectSync\GitLogs"; New-Item -ItemType Directory -Path `$LogRoot -Force | Out-Null
`$log = Join-Path `$LogRoot "end.log"; function Log(`$m){ "`$((Get-Date).ToString(''yyyy-MM-dd HH:mm:ss'')) `$m" | Tee-Object -FilePath `$log -Append }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git not installed." }
if (-not (Test-Path (Join-Path `$RepoPath ''.git''))) { throw "Not a git repo: `$RepoPath" }
try {
  Log "---- End Work ----"
  git -C `$RepoPath add -A | Tee-Object -FilePath `$log -Append | Out-Null
  `$status = git -C `$RepoPath status --porcelain
  if (`$status) {
    `$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git -C `$RepoPath commit -m "Auto-commit: `$timestamp" | Tee-Object -FilePath `$log -Append
    git -C `$RepoPath push | Tee-Object -FilePath `$log -Append
    Log "Changes committed and pushed."
  } else {
    Log "No changes to commit."
  }
  Log "End Work complete."
} catch { Log "Error: `$(`$_.Exception.Message)"; exit 1 }
"@ | Set-Content "C:\Scripts\end-work.ps1"
}

# Step 7: Create setup-auto-sync.ps1 if it doesn''t exist
if (-not (Test-Path "C:\Scripts\setup-auto-sync.ps1")) {
    Log "Creating setup-auto-sync.ps1..."
    @"
# Run this script as Administrator to set up automatic git sync

# Task 1: Pull on Login
`$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File ```"C:\Scripts\start-work.ps1```""
`$trigger = New-ScheduledTaskTrigger -AtLogOn
`$principal = New-ScheduledTaskPrincipal -UserId `$env:USERNAME -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName "StartWork-OnLogin" -Action `$action -Trigger `$trigger -Principal `$principal -Description "Pull from GitHub on RDP login" -Force

# Task 2: Commit/Push on Disconnect - Using XML for event trigger
`$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"&gt;&lt;Select Path="Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"&gt;*[System[EventID=24]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[EventID=7002]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal>
      <UserId>`$env:USERNAME</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT1H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Scripts\end-work.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

Register-ScheduledTask -TaskName "EndWork-OnDisconnect" -Xml `$xml -Force

Write-Host "Tasks created successfully!" -ForegroundColor Green
Write-Host "- StartWork-OnLogin: Pulls on RDP login" -ForegroundColor Cyan
Write-Host "- EndWork-OnDisconnect: Commits and pushes on RDP disconnect (Event ID 24, 7002)" -ForegroundColor Cyan
"@ | Set-Content "C:\Scripts\setup-auto-sync.ps1"
}

# Step 8: Run the setup script to create scheduled tasks
Log "Setting up scheduled tasks..."
& "C:\Scripts\setup-auto-sync.ps1"

Log ""
Log "========================================" -ForegroundColor Green
Log "Bootstrap complete!" -ForegroundColor Green
Log "========================================" -ForegroundColor Green
Log ""
Log "Configuration:"
Log "  - Repository: $RepoPath"
Log "  - Scripts: C:\Scripts\"
Log "  - Logs: C:\ProgramData\ProjectSync\GitLogs\"
Log ""
Log "Scheduled Tasks:"
Log "  - StartWork-OnLogin: Pulls on RDP login"
Log "  - EndWork-OnDisconnect: Commits/pushes on RDP disconnect"
Log ""
Log "Next: Configure your Git credentials if needed:"
Log "  git config --global user.name `"Your Name`""
Log "  git config --global user.email `"your.email@example.com`""
Log ""
