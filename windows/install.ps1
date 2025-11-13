#
# install.ps1 - Install Build Coordination Tools for Windows
# Supports Windows 10/11/Server 2016+
#

#Requires -Version 5.1

param(
    [Parameter(Mandatory=$false)]
    [string]$BuildRepoPath,
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipGitCheck
)

$ErrorActionPreference = "Stop"

Write-Host "`n=== Build Coordination Tools Installer ===" -ForegroundColor Cyan
Write-Host "Windows version: $([System.Environment]::OSVersion.VersionString)`n" -ForegroundColor Gray

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

# Check PowerShell version
$psVersion = $PSVersionTable.PSVersion
if ($psVersion.Major -lt 5) {
    Write-Host "✗ PowerShell 5.1+ required (current: $psVersion)" -ForegroundColor Red
    exit 1
}
Write-Host "✓ PowerShell $psVersion" -ForegroundColor Green

# Check Git
if (-not $SkipGitCheck) {
    try {
        $gitVersion = git --version 2>&1
        Write-Host "✓ Git installed: $gitVersion" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Git not found. Please install Git for Windows from https://git-scm.com/download/win" -ForegroundColor Red
        exit 1
    }
}

# Find or clone Build repository
if (-not $BuildRepoPath) {
    $defaultPath = "C:\Build"
    $BuildRepoPath = Read-Host "Enter Build repository path (default: $defaultPath)"
    if (-not $BuildRepoPath) {
        $BuildRepoPath = $defaultPath
    }
}

if (-not (Test-Path $BuildRepoPath)) {
    Write-Host "`nBuild repository not found at: $BuildRepoPath" -ForegroundColor Yellow
    $clone = Read-Host "Clone from GitHub? (y/n)"
    if ($clone -eq 'y') {
        Write-Host "Cloning repository..." -ForegroundColor Gray
        git clone https://github.com/alexandremattioli/Build.git $BuildRepoPath
        Write-Host "✓ Repository cloned" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Cannot proceed without Build repository" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "✓ Build repository found at: $BuildRepoPath" -ForegroundColor Green
}

# Create PowerShell profile if it doesn't exist
$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) {
    Write-Host "`nCreating PowerShell profile directory..." -ForegroundColor Gray
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

# Add aliases to profile
Write-Host "`nConfiguring PowerShell aliases..." -ForegroundColor Yellow

$aliasConfig = @"

# Build Coordination Tools
`$env:BUILD_REPO_PATH = "$BuildRepoPath"
Set-Alias -Name cm -Value "$BuildRepoPath\windows\scripts\cm.ps1"
Set-Alias -Name sm -Value "$BuildRepoPath\windows\scripts\sm.ps1"

function Send-BuildMessage {
    param([string]`$Subject, [string]`$Body, [string]`$To = "all")
    sm `$Subject `$Body -To `$To
}
"@

$profileContent = ""
if (Test-Path $PROFILE) {
    $profileContent = Get-Content $PROFILE -Raw
}

if ($profileContent -notmatch "Build Coordination Tools") {
    Add-Content -Path $PROFILE -Value $aliasConfig
    Write-Host "✓ Aliases added to PowerShell profile" -ForegroundColor Green
}
else {
    Write-Host "✓ Aliases already configured" -ForegroundColor Green
}

# Test commands
Write-Host "`nTesting commands..." -ForegroundColor Yellow

try {
    . $PROFILE
    Write-Host "✓ Profile loaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "⚠ Profile load failed, aliases will work in new sessions" -ForegroundColor Yellow
}

# Show usage
Write-Host "`n=== Installation Complete ===" -ForegroundColor Green
Write-Host "`nAvailable commands:" -ForegroundColor Cyan
Write-Host "  cm              - Check messages (condensed view)" -ForegroundColor White
Write-Host "  cm -Verbose     - Check messages (full view)" -ForegroundColor White
Write-Host "  cm -Follow      - Follow messages in real-time" -ForegroundColor White
Write-Host "  cm -Lines 20    - Show last 20 lines" -ForegroundColor White
Write-Host "`n  sm 'Subject' 'Body'              - Send message to all servers" -ForegroundColor White
Write-Host "  sm 'Subject' 'Body' -To build1   - Send to specific server" -ForegroundColor White
Write-Host "  sm 'Subject' 'Body' -RequireAck  - Require acknowledgment" -ForegroundColor White
Write-Host "  sm 'Subject' 'Body' -Type request -Priority high" -ForegroundColor White

Write-Host "`nTo use commands in THIS session, run: " -ForegroundColor Yellow -NoNewline
Write-Host ". `$PROFILE" -ForegroundColor Cyan

Write-Host "`nDocumentation: $BuildRepoPath\Communications\README.md" -ForegroundColor Gray
Write-Host ""
