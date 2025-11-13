#
# Start-MessageMonitor.ps1
# Automated message monitoring for Code2 Build coordination
# Checks every 60 seconds for new messages and processes them
#

param(
    [int]$IntervalSeconds = 60,
    [string]$BuildRepoPath = "K:\Projects\Build"
)

$ErrorActionPreference = "Continue"
$ServerId = if (Test-Path "$BuildRepoPath\code2\status.json") { "code2" } else { "code1" }

Write-Host "=== Code2 Message Monitor Started ===" -ForegroundColor Green
Write-Host "Server: $ServerId" -ForegroundColor Cyan
Write-Host "Interval: $IntervalSeconds seconds" -ForegroundColor Cyan
Write-Host "Repo: $BuildRepoPath" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Yellow

function Get-UnreadMessages {
    param([string]$ServerID)
    
    try {
        $messagesPath = Join-Path $BuildRepoPath "coordination\messages.json"
        $messages = Get-Content $messagesPath -Raw | ConvertFrom-Json
        
        $unread = $messages.messages | Where-Object {
            ($_.to -eq $ServerID -or $_.to -eq "all") -and
            $_.read -eq $false -and
            $_.from -ne $ServerID
        } | Sort-Object timestamp
        
        return $unread
    }
    catch {
        Write-Host "Error reading messages: $_" -ForegroundColor Red
        return @()
    }
}

function Mark-MessageRead {
    param([string]$MessageId)
    
    try {
        $messagesPath = Join-Path $BuildRepoPath "coordination\messages.json"
        $messages = Get-Content $messagesPath -Raw | ConvertFrom-Json
        
        foreach ($msg in $messages.messages) {
            if ($msg.id -eq $MessageId) {
                $msg.read = $true
                break
            }
        }
        
        $messages | ConvertTo-Json -Depth 10 | Set-Content $messagesPath
        
        # Commit the read status
        Push-Location $BuildRepoPath
        git add coordination\messages.json
        git commit -m "Code2: Mark message $MessageId as read" -q
        git push origin main -q 2>&1 | Out-Null
        Pop-Location
        
        return $true
    }
    catch {
        Write-Host "Error marking message read: $_" -ForegroundColor Red
        return $false
    }
}

function Process-Message {
    param($Message)
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "`n[$timestamp] NEW MESSAGE" -ForegroundColor Yellow
    Write-Host "From: $($Message.from) | To: $($Message.to) | Priority: $($Message.priority)" -ForegroundColor Cyan
    Write-Host "Subject: $($Message.subject)" -ForegroundColor Green
    Write-Host "Body: $($Message.body.Substring(0, [Math]::Min(200, $Message.body.Length)))..." -ForegroundColor White
    
    # Mark as read
    Mark-MessageRead -MessageId $Message.id | Out-Null
    
    # Log to local file
    $logPath = Join-Path $BuildRepoPath "$ServerId\logs\message_processing.log"
    $logEntry = "[$timestamp] PROCESSED: $($Message.id) | FROM: $($Message.from) | SUBJECT: $($Message.subject)`n"
    Add-Content -Path $logPath -Value $logEntry
    
    # Analyze if response needed
    $needsResponse = $false
    $responseType = $null
    
    # Check for questions or requests
    if ($Message.body -match "\?|\@code2|\@$ServerId|request|question|please respond") {
        $needsResponse = $true
        $responseType = "question"
    }
    
    # Check for project coordination
    if ($Message.subject -match "CCC2025|project|task|coordination" -and $Message.priority -eq "high") {
        $needsResponse = $true
        $responseType = "project"
    }
    
    # Check for initial task
    if ($Message.subject -match "Initial Task|Task Assignment") {
        $needsResponse = $true
        $responseType = "task"
    }
    
    if ($needsResponse) {
        Write-Host "→ Response needed: $responseType" -ForegroundColor Magenta
        Write-Host "→ User will be notified to review and respond" -ForegroundColor Magenta
        
        # Create notification file for user
        $notifyPath = Join-Path $BuildRepoPath "$ServerId\notifications\pending_response.txt"
        $notifyContent = @"
=== MESSAGE REQUIRES RESPONSE ===
Timestamp: $timestamp
From: $($Message.from)
To: $($Message.to)
Subject: $($Message.subject)
Type: $responseType
Priority: $($Message.priority)

Body:
$($Message.body)

---
Action Required: Review message and send appropriate response
"@
        New-Item -Path (Split-Path $notifyPath) -ItemType Directory -Force | Out-Null
        Set-Content -Path $notifyPath -Value $notifyContent
    }
}

# Main monitoring loop
$iteration = 0
$lastMessageTime = Get-Date
$lastHeartbeatTime = Get-Date

while ($true) {
    try {
        $iteration++
        
        # Pull latest changes
        Push-Location $BuildRepoPath
        $pullOutput = git pull origin main 2>&1
        Pop-Location
        
        if ($pullOutput -match "Updating|Fast-forward") {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Repository updated" -ForegroundColor Green
        }
        
        # Check for unread messages
        $unreadMessages = Get-UnreadMessages -ServerID $ServerId
        
        if ($unreadMessages -and $unreadMessages.Count -gt 0) {
            Write-Host "`n=== Found $($unreadMessages.Count) unread message(s) ===" -ForegroundColor Yellow
            
            foreach ($msg in $unreadMessages) {
                Process-Message -Message $msg
            }
            
            # Update last message time
            $lastMessageTime = Get-Date
        }
        else {
            # Check if 2 minutes have passed since last message
            $timeSinceLastMessage = (Get-Date) - $lastMessageTime
            $timeSinceLastHeartbeat = (Get-Date) - $lastHeartbeatTime
            
            if ($timeSinceLastMessage.TotalMinutes -ge 2 -and $timeSinceLastHeartbeat.TotalMinutes -ge 2) {
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] No messages for 2 minutes - sending heartbeat" -ForegroundColor Cyan
                
                # Send heartbeat
                try {
                    & "$BuildRepoPath\windows\scripts\Send-Heartbeat.ps1" -BuildRepoPath $BuildRepoPath
                    $lastHeartbeatTime = Get-Date
                    $lastMessageTime = Get-Date  # Reset to avoid immediate next heartbeat
                }
                catch {
                    Write-Host "Failed to send heartbeat: $_" -ForegroundColor Red
                }
            }
            elseif ($iteration % 10 -eq 0) {
                # Quiet status every 10 iterations (10 minutes)
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Monitoring active - no new messages (iteration $iteration)" -ForegroundColor DarkGray
            }
        }
        
        # Sleep for interval
        Start-Sleep -Seconds $IntervalSeconds
    }
    catch {
        Write-Host "Error in monitoring loop: $_" -ForegroundColor Red
        Start-Sleep -Seconds $IntervalSeconds
    }
}
