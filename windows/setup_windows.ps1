<#
.SYNOPSIS
    Setup Windows development server for Build coordination.

.DESCRIPTION
    Configures Windows server to participate in the Build coordination system.

.EXAMPLE
    .\setup_windows.ps1
#>

# Requires Administrator for scheduled task creation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

Write-Host "=== Windows Development Server Setup ===" -ForegroundColor Cyan
Write-Host ""

# 1. Verify prerequisites
Write-Host "[1/6] Verifying prerequisites..." -ForegroundColor Yellow

$checks = @{
    "Git" = { git --version }
    "SSH" = { ssh -V }
    "Java" = { java -version }
    "Maven" = { mvn --version }
    "Python" = { python --version }
}

foreach ($check in $checks.GetEnumerator()) {
    try {
        $null = & $check.Value 2>&1
        Write-Host "  ✓ $($check.Key) installed" -ForegroundColor Green
    }
    catch {
        Write-Warning "  ✗ $($check.Key) not found - run install_prerequisites.ps1"
    }
}

# 2. Configure Git
Write-Host "`n[2/6] Configuring Git..." -ForegroundColor Yellow
git config --global core.autocrlf true
git config --global user.name "Alexandre Mattioli"
git config --global user.email "alexandre@shapeblue.com"
Write-Host "  ✓ Git configured" -ForegroundColor Green

# 3. Setup SSH keys for Linux builders
Write-Host "`n[3/6] Setting up SSH access..." -ForegroundColor Yellow

$sshDir = "$env:USERPROFILE\.ssh"
if (!(Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir | Out-Null
}

$keyPath = "$sshDir\id_ed25519"
if (!(Test-Path $keyPath)) {
    Write-Host "  Generating SSH key..." -ForegroundColor Gray
    ssh-keygen -t ed25519 -f $keyPath -N '""' -C "windows-dev-server"
    Write-Host "  ✓ SSH key generated" -ForegroundColor Green
    
    Write-Host "`n  To enable passwordless SSH, copy your public key to Linux builders:" -ForegroundColor Cyan
    Write-Host "  Get-Content $keyPath.pub | ssh root@10.1.3.175 'cat >> ~/.ssh/authorized_keys'" -ForegroundColor White
    Write-Host "  Get-Content $keyPath.pub | ssh root@10.1.3.177 'cat >> ~/.ssh/authorized_keys'" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "  ✓ SSH key already exists" -ForegroundColor Green
}

# 4. Clone CloudStack repository
Write-Host "`n[4/6] Setting up CloudStack repository..." -ForegroundColor Yellow

$cloudstackPath = "C:\src\cloudstack"
if (!(Test-Path $cloudstackPath)) {
    New-Item -ItemType Directory -Path "C:\src" -Force | Out-Null
    Write-Host "  Cloning CloudStack repository..." -ForegroundColor Gray
    git clone https://github.com/alexandremattioli/cloudstack.git $cloudstackPath
    
    Push-Location $cloudstackPath
    git checkout VNFCopilot
    Pop-Location
    
    Write-Host "  ✓ CloudStack repository cloned (VNFCopilot branch)" -ForegroundColor Green
} else {
    Write-Host "  ✓ CloudStack repository already exists" -ForegroundColor Green
}

# 5. Install VSCode extensions
Write-Host "`n[5/6] Installing VSCode extensions..." -ForegroundColor Yellow

if (Get-Command code -ErrorAction SilentlyContinue) {
    $extensions = @(
        "vscjava.vscode-java-pack",
        "ms-python.python",
        "eamodio.gitlens",
        "github.copilot",
        "ms-vscode-remote.remote-ssh",
        "ms-vscode.powershell"
    )
    
    foreach ($ext in $extensions) {
        Write-Host "  Installing $ext..." -ForegroundColor Gray
        code --install-extension $ext --force 2>&1 | Out-Null
    }
    
    Write-Host "  ✓ VSCode extensions installed" -ForegroundColor Green
} else {
    Write-Warning "  VSCode not found - skipping extension installation"
}

# 6. Setup scheduled heartbeat task
Write-Host "`n[6/6] Setting up heartbeat task..." -ForegroundColor Yellow

if ($isAdmin) {
    $taskName = "BuildHeartbeat"
    $existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if ($existingTask) {
        Write-Host "  Removing existing task..." -ForegroundColor Gray
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\scripts\Send-Heartbeat.ps1`""
    
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Hours 1) `
        -RepetitionDuration ([TimeSpan]::MaxValue)
    
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
    
    Register-ScheduledTask -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Principal $principal `
        -Description "Hourly coordination heartbeat for Build system" | Out-Null
    
    Write-Host "  ✓ Heartbeat task configured (runs hourly)" -ForegroundColor Green
} else {
    Write-Warning "  Run as Administrator to setup heartbeat task"
    Write-Host "  Manual setup: Task Scheduler -> Create Task" -ForegroundColor Gray
    Write-Host "  Trigger: Hourly" -ForegroundColor Gray
    Write-Host "  Action: PowerShell.exe -File `"$PSScriptRoot\scripts\Send-Heartbeat.ps1`"" -ForegroundColor Gray
}

# Summary
Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Copy SSH key to Linux builders (if not already done)" -ForegroundColor White
Write-Host "2. Test connectivity:" -ForegroundColor White
Write-Host "   ssh root@10.1.3.175" -ForegroundColor Gray
Write-Host "   ssh root@10.1.3.177" -ForegroundColor Gray
Write-Host "3. Send test message:" -ForegroundColor White
Write-Host "   .\scripts\Send-BuildMessage.ps1 -From 'win-dev1' -To 'all' -Type 'info' -Body 'Windows setup complete'" -ForegroundColor Gray
Write-Host "4. Open VSCode and start developing!" -ForegroundColor White
Write-Host ""
Write-Host "Available scripts in .\scripts\:" -ForegroundColor Cyan
Write-Host "  Send-BuildMessage.ps1  - Send coordination messages" -ForegroundColor White
Write-Host "  Send-Heartbeat.ps1     - Send heartbeat (runs hourly)" -ForegroundColor White
Write-Host "  Get-BuildMessageStatus.ps1 - View message status" -ForegroundColor White
Write-Host "  remote-exec.ps1        - Execute commands on Linux builders" -ForegroundColor White
Write-Host "  sync-to-linux.ps1      - Sync files with Linux builders" -ForegroundColor White
Write-Host ""
