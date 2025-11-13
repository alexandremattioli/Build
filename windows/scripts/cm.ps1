#!/usr/bin/env pwsh
# cm.ps1 - Check Messages (Windows version)

param(
    [switch]$Verbose,
    [switch]$Follow,
    [int]$Lines = 20
)

# Detect server
$SERVER = if (Test-Path "K:\Projects\Build") {
    if ($env:COMPUTERNAME -match "Code-01|Code1") { "code1" }
    elseif ($env:COMPUTERNAME -match "Code-02|Code2") { "code2" }
    else { "code2" }
} else {
    "code2"
}

$LOG = "K:\Projects\Build\code$($SERVER[-1])\logs\messages.log"

# Create log if doesn't exist
if (-not (Test-Path $LOG)) {
    $logDir = Split-Path $LOG -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    "=== Message log for $SERVER ===" | Set-Content $LOG
}

# Format timestamps
function Format-Timestamp {
    param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        $_ -replace '(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2}:\d{2})Z', '$1 @ $2 '
    }
}

# Condense to headers only
function Get-CondensedView {
    param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        if ($_ -match '^===|^\[INFO\]|^\[WARN\]|^\[ERROR\]|^Subject:|^Time:|^---') {
            $_
        }
    }
}

# Execute
if ($Follow) {
    if ($Verbose) {
        Write-Host "Following messages for $SERVER in VERBOSE mode (Ctrl+C to stop)..." -ForegroundColor Cyan
        Write-Host "--- Recent messages ---" -ForegroundColor Gray
        Get-Content $LOG -Tail 20 | Format-Timestamp
        Write-Host "`n--- Following new messages ---" -ForegroundColor Gray
        Get-Content $LOG -Wait -Tail 0 | Format-Timestamp
    } else {
        Write-Host "Following messages for $SERVER (Ctrl+C to stop)..." -ForegroundColor Cyan
        Write-Host "--- Recent messages ---" -ForegroundColor Gray
        Get-Content $LOG -Tail 20 | Format-Timestamp | Get-CondensedView
        Write-Host "`n--- Following new messages ---" -ForegroundColor Gray
        Get-Content $LOG -Wait -Tail 0 | Format-Timestamp | Get-CondensedView
    }
} elseif ($Verbose) {
    Get-Content $LOG -Tail $Lines | Format-Timestamp
} else {
    Write-Host "Messages for $SERVER (condensed - use 'cm -Verbose' for full):" -ForegroundColor Cyan
    Write-Host "---" -ForegroundColor Gray
    Get-Content $LOG -Tail $Lines | Format-Timestamp | Get-CondensedView
    Write-Host "---" -ForegroundColor Gray
}
