#
# sm.ps1 - Send Message to Build Coordination System
# Quick message sender for Build fleet communication
#

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Subject,
    
    [Parameter(Mandatory=$true, Position=1)]
    [string]$Body,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('all','build1','build2','build3','build4','code1','code2','jh01','architect')]
    [string]$To = 'all',
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('info','request','response','error','heartbeat')]
    [string]$Type = 'info',
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('low','normal','high','urgent')]
    [string]$Priority = 'normal',
    
    [Parameter(Mandatory=$false)]
    [switch]$RequireAck,
    
    [Parameter(Mandatory=$false)]
    [string]$BuildRepoPath
)

$ErrorActionPreference = "Stop"

# Auto-detect Build repo path
if (-not $BuildRepoPath) {
    $possiblePaths = @(
        "K:\Projects\Build",
        "C:\Build",
        "$env:USERPROFILE\Build",
        "$PSScriptRoot\..\..\"
    )
    
    foreach ($path in $possiblePaths) {
        if (Test-Path "$path\coordination\messages.json") {
            $BuildRepoPath = $path
            break
        }
    }
    
    if (-not $BuildRepoPath) {
        Write-Error "Cannot find Build repository. Please specify -BuildRepoPath or ensure Build is cloned."
        exit 1
    }
}

try {
    Push-Location $BuildRepoPath
    
    # Determine sender (architect by default for user messages)
    $From = "architect"
    
    # Pull latest
    Write-Host "Pulling latest messages..." -ForegroundColor Gray
    git pull origin main -q 2>&1 | Out-Null
    
    # Load messages
    $messagesPath = "coordination\messages.json"
    $messages = Get-Content $messagesPath -Raw | ConvertFrom-Json
    
    # Generate message
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $epochSeconds = [Math]::Floor((Get-Date).ToUniversalTime().Subtract((Get-Date '1970-01-01')).TotalSeconds)
    $id = "msg_${epochSeconds}_$(Get-Random -Max 9999)"
    
    $newMsg = @{
        id = $id
        from = $From
        to = $To
        type = $Type
        subject = $Subject
        body = $Body
        timestamp = $timestamp
        read = $false
        priority = $Priority
    }
    
    if ($RequireAck) {
        $newMsg.ack_required = $true
    }
    
    # Add message
    $messages.messages += $newMsg
    
    # Save and commit
    $messages | ConvertTo-Json -Depth 10 | Set-Content $messagesPath
    
    git add $messagesPath | Out-Null
    git commit -m "$From -> $To: $Subject" -q
    git push origin main -q
    
    Write-Host "✓ Message sent successfully" -ForegroundColor Green
    Write-Host "  From: $From" -ForegroundColor Cyan
    Write-Host "  To: $To" -ForegroundColor Cyan
    Write-Host "  Subject: $Subject" -ForegroundColor Cyan
    Write-Host "  Type: $Type | Priority: $Priority" -ForegroundColor Gray
    if ($RequireAck) {
        Write-Host "  ACK Required: Yes" -ForegroundColor Yellow
    }
    
    Pop-Location
    exit 0
}
catch {
    Write-Host "✗ Failed to send message: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}
