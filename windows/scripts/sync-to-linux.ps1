<#
.SYNOPSIS
    Synchronize files between Windows and Linux build servers.

.DESCRIPTION
    Uses rsync over SSH to sync CloudStack source code and other files
    between Windows development servers and Linux builders.

.PARAMETER Target
    Target builder: "build1" or "build2"

.PARAMETER Direction
    Sync direction: "push" (Windows -> Linux) or "pull" (Linux -> Windows)

.PARAMETER Path
    Local path to sync (default: C:\src\cloudstack)

.PARAMETER RemotePath
    Remote path on Linux builder (default: /root/src/cloudstack)

.PARAMETER DryRun
    Perform a dry run without actually transferring files

.PARAMETER Exclude
    Patterns to exclude (default: .git, target, *.class)

.EXAMPLE
    .\sync-to-linux.ps1 -Target build1 -Direction push

.EXAMPLE
    .\sync-to-linux.ps1 -Target build2 -Direction pull -DryRun

.EXAMPLE
    .\sync-to-linux.ps1 -Target build1 -Direction push -Path "C:\src\cloudstack\plugins\vnf-framework"
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("build1", "build2")]
    [string]$Target,

    [Parameter(Mandatory=$true)]
    [ValidateSet("push", "pull")]
    [string]$Direction,

    [Parameter(Mandatory=$false)]
    [string]$Path = "C:\src\cloudstack",

    [Parameter(Mandatory=$false)]
    [string]$RemotePath = "/root/src/cloudstack",

    [switch]$DryRun,

    [Parameter(Mandatory=$false)]
    [string[]]$Exclude = @(".git", "target", "*.class", "*.log", ".idea", ".vscode")
)

# Configuration
$BUILD1_IP = "10.1.3.175"
$BUILD2_IP = "10.1.3.177"
$BUILD_USER = "root"

# Check if rsync is available (via WSL, Cygwin, or Git Bash)
$rsyncPath = Get-Command rsync -ErrorAction SilentlyContinue

if (!$rsyncPath) {
    Write-Error @"
rsync not found. Please install one of:
1. WSL2: wsl --install
2. Git for Windows (includes rsync in Git Bash)
3. Cygwin with rsync package
"@
    exit 1
}

# Get target IP
$targetIP = if ($Target -eq "build1") { $BUILD1_IP } else { $BUILD2_IP }

# Convert Windows path to WSL/Cygwin path if needed
$localPath = $Path
if ($rsyncPath.Source -match "wsl") {
    # Convert C:\path to /mnt/c/path for WSL
    $localPath = $Path -replace '^([A-Z]):', { "/mnt/$($_.Groups[1].Value.ToLower())" } -replace '\\', '/'
}

# Build exclude options
$excludeOpts = $Exclude | ForEach-Object { "--exclude=`"$_`"" }

# Build rsync command
$dryRunFlag = if ($DryRun) { "--dry-run" } else { "" }

if ($Direction -eq "push") {
    $source = "$localPath/"
    $destination = "${BUILD_USER}@${targetIP}:${RemotePath}/"
    $verb = "Pushing"
} else {
    $source = "${BUILD_USER}@${targetIP}:${RemotePath}/"
    $destination = "$localPath/"
    $verb = "Pulling"
}

Write-Host "$verb files $Direction $Target ($targetIP)..." -ForegroundColor Cyan
Write-Host "Source: $source" -ForegroundColor Gray
Write-Host "Destination: $destination" -ForegroundColor Gray

if ($DryRun) {
    Write-Host "[DRY RUN - No files will be transferred]" -ForegroundColor Yellow
}

# Execute rsync
$rsyncCmd = "rsync -avz --progress $dryRunFlag $excludeOpts `"$source`" `"$destination`""

Write-Host "Executing: $rsyncCmd" -ForegroundColor Gray
Write-Host ""

try {
    Invoke-Expression $rsyncCmd
    
    if ($LASTEXITCODE -eq 0) {
        if ($DryRun) {
            Write-Host "`n✓ Dry run completed" -ForegroundColor Green
        } else {
            Write-Host "`n✓ Sync completed successfully" -ForegroundColor Green
        }
    } else {
        Write-Host "`n✗ Sync failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}
catch {
    Write-Error "Sync failed: $_"
    exit 1
}

# Optional: Trigger message notification
if (!$DryRun -and $Direction -eq "push") {
    $msg = "Code synchronized from Windows to $Target"
    Write-Host "`nSending coordination message..." -ForegroundColor Cyan
    
    $hostname = $env:COMPUTERNAME.ToLower()
    & "$PSScriptRoot\Send-BuildMessage.ps1" -From "win-$hostname" -To $Target -Type "info" -Body $msg
}
