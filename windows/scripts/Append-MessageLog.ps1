# Append message to log file for Windows servers
param(
    [Parameter(Mandatory)]
    [string]$From,
    
    [Parameter(Mandatory)]
    [string]$To,
    
    [Parameter(Mandatory)]
    [string]$Type,
    
    [Parameter(Mandatory)]
    [string]$Subject,
    
    [Parameter(Mandatory)]
    [string]$Body,
    
    [string]$Timestamp
)

# Detect server
$SERVER = if ($env:COMPUTERNAME -match "Code-01|Code1") { "code1" } else { "code2" }
$LOG = "K:\Projects\Build\code$($SERVER[-1])\logs\messages.log"

# Create log if doesn't exist
if (-not (Test-Path $LOG)) {
    $logDir = Split-Path $LOG -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
}

if (-not $Timestamp) {
    $Timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

# Format message
$typeUpper = $Type.ToUpper()
$entry = @"

=== New Messages $Timestamp ===
[$typeUpper] $From -> $To
Subject: $Subject
Time: $Timestamp
$Body
---
"@

# Append to log
Add-Content -Path $LOG -Value $entry
