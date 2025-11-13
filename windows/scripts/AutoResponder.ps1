#
# AutoResponder.ps1
# Automatically acknowledge request messages and messages requiring ACK
#

param(
    [string]$BuildRepoPath = "K:\Projects\Build"
)

$ErrorActionPreference = "Stop"

try {
    Push-Location $BuildRepoPath
    
    # Determine server ID
    $ServerId = if (Test-Path "$BuildRepoPath\code2\status.json") { "code2" } else { "code1" }
    
    # Pull latest
    git pull origin main -q 2>&1 | Out-Null
    
    # Load messages
    $messagesPath = "coordination\messages.json"
    $messages = Get-Content $messagesPath -Raw | ConvertFrom-Json
    
    # Find unread messages that need ACK
    $needsAck = $messages.messages | Where-Object {
        ($_.to -eq $ServerId -or $_.to -eq "all") -and
        $_.read -eq $false -and
        $_.from -ne $ServerId -and
        ($_.type -eq "request" -or $_.ack_required -eq $true)
    }
    
    if (-not $needsAck -or $needsAck.Count -eq 0) {
        Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] No messages requiring ACK" -ForegroundColor Gray
        Pop-Location
        exit 0
    }
    
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Found $($needsAck.Count) message(s) requiring ACK" -ForegroundColor Yellow
    
    foreach ($msg in $needsAck) {
        # Generate ACK message
        $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $epochSeconds = [Math]::Floor((Get-Date).ToUniversalTime().Subtract((Get-Date '1970-01-01')).TotalSeconds)
        $ackId = "msg_${epochSeconds}_$(Get-Random -Max 9999)"
        
        $ackBody = @"
[ACK] Message received and acknowledged.

Original message:
From: $($msg.from)
Subject: $($msg.subject)
Time: $($msg.timestamp)

Status: Processing
-$ServerId (AutoResponder)
"@
        
        $ackMsg = @{
            id = $ackId
            from = $ServerId
            to = $msg.from
            type = "response"
            subject = "[ACK] Re: $($msg.subject)"
            body = $ackBody
            timestamp = $timestamp
            read = $false
            priority = "normal"
            in_reply_to = $msg.id
        }
        
        # Add ACK message
        $messages.messages += $ackMsg
        
        # Mark original as read
        foreach ($m in $messages.messages) {
            if ($m.id -eq $msg.id) {
                $m.read = $true
                break
            }
        }
        
        Write-Host "  → ACK sent for: $($msg.subject)" -ForegroundColor Green
    }
    
    # Save and commit
    $messages | ConvertTo-Json -Depth 10 | Set-Content $messagesPath
    
    git add $messagesPath | Out-Null
    git commit -m "$ServerId: Auto-ACK for $($needsAck.Count) message(s)" -q
    git push origin main -q 2>&1 | Out-Null
    
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ACK messages sent and committed" -ForegroundColor Green
    
    # Update message_status.txt
    & "$BuildRepoPath\windows\scripts\Update-MessageStatus.ps1" -BuildRepoPath $BuildRepoPath
    
    Pop-Location
    exit 0
}
catch {
    Write-Host "Error in autoresponder: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}
