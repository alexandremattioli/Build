#
# Send-Heartbeat.ps1
# Send hourly heartbeat message to Build coordination system
#

param(
    [string]$BuildRepoPath = "K:\Projects\Build"
)

$ErrorActionPreference = "Stop"

try {
    Push-Location $BuildRepoPath
    
    # Determine server ID
    $ServerId = if (Test-Path "$BuildRepoPath\code2\status.json") { "code2" } else { "code1" }
    
    # Pull latest first
    git pull origin main -q 2>&1 | Out-Null
    
    # Load current messages
    $messagesPath = "coordination\messages.json"
    $messages = Get-Content $messagesPath -Raw | ConvertFrom-Json
    
    # Generate message ID and timestamp
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $epochSeconds = [Math]::Floor((Get-Date).ToUniversalTime().Subtract((Get-Date "1970-01-01")).TotalSeconds)
    $id = "msg_${epochSeconds}_$(Get-Random -Max 9999)"
    
    # Get system info
    $cpuUsage = (Get-Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 1).CounterSamples.CookedValue
    $memoryUsage = (Get-Counter "\Memory\% Committed Bytes In Use" -SampleInterval 1 -MaxSamples 1).CounterSamples.CookedValue
    $hostname = $env:COMPUTERNAME
    
    # Count unread messages
    $unreadCount = ($messages.messages | Where-Object { 
        ($_.to -eq $ServerId -or $_.to -eq "all") -and 
        $_.read -eq $false -and 
        $_.from -ne $ServerId 
    }).Count
    
    # Create heartbeat body
    $body = @"
Heartbeat from $ServerId ($hostname)
Status: ONLINE
Unread Messages: $unreadCount
CPU Usage: $([Math]::Round($cpuUsage, 1))%
Memory Usage: $([Math]::Round($memoryUsage, 1))%
Monitoring: ACTIVE (60s polling)
Last Beat: $timestamp
"@
    
    # Create new message
    $newMsg = @{
        id = $id
        from = $ServerId
        to = "all"
        type = "heartbeat"
        subject = "Hourly Heartbeat - $ServerId"
        body = $body
        timestamp = $timestamp
        read = $false
        priority = "low"
    }
    
    # Add message
    $messages.messages += $newMsg
    
    # Save and commit
    $messages | ConvertTo-Json -Depth 10 | Set-Content $messagesPath
    
    git add $messagesPath | Out-Null
    git commit -m "$ServerId automated heartbeat" -q
    git push origin main -q 2>&1 | Out-Null
    
    # Update heartbeat.json
    $heartbeatPath = "$ServerId\heartbeat.json"
    $heartbeatData = @{
        server_id = $ServerId
        last_heartbeat = $timestamp
        status = "online"
        unread_messages = $unreadCount
        cpu_usage = [Math]::Round($cpuUsage, 1)
        memory_usage = [Math]::Round($memoryUsage, 1)
    }
    
    $heartbeatData | ConvertTo-Json -Depth 10 | Set-Content $heartbeatPath
    git add $heartbeatPath | Out-Null
    git commit -m "$ServerId heartbeat status update" -q
    git push origin main -q 2>&1 | Out-Null
    
    Write-Host "[$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")] Heartbeat sent successfully" -ForegroundColor Green
    
    Pop-Location
    exit 0
}
catch {
    Write-Host "Error sending heartbeat: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}
