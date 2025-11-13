#
# Send-Message.ps1
# Easy command to send messages to Build coordination system
#

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$To,
    
    [Parameter(Mandatory=$true, Position=1)]
    [string]$Subject,
    
    [Parameter(Mandatory=$true, Position=2)]
    [string]$Body,
    
    [ValidateSet('info','request','response','heartbeat','error')]
    [string]$Type = 'info',
    
    [ValidateSet('low','normal','high','urgent')]
    [string]$Priority = 'normal',
    
    [switch]$RequireAck
)

$BuildRepoPath = "K:\Projects\Build"
$ErrorActionPreference = "Stop"

try {
    Push-Location $BuildRepoPath
    
    # Determine sender
    $ServerId = if (Test-Path "$BuildRepoPath\code2\status.json") { "code2" } else { "code1" }
    
    # Validate recipient
    $validRecipients = @('all','build1','build2','build3','build4','code1','code2','jh01','architect')
    if ($To -notin $validRecipients) {
        Write-Host "Error: Invalid recipient '$To'" -ForegroundColor Red
        Write-Host "Valid recipients: $($validRecipients -join ', ')" -ForegroundColor Yellow
        Pop-Location
        exit 1
    }
    
    # Pull latest
    Write-Host "Pulling latest changes..." -ForegroundColor Gray
    git pull origin main -q 2>&1 | Out-Null
    
    # Load messages
    $messagesPath = "coordination\messages.json"
    $messages = Get-Content $messagesPath -Raw | ConvertFrom-Json
    
    # Generate message ID and timestamp
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $epochSeconds = [Math]::Floor((Get-Date).ToUniversalTime().Subtract((Get-Date '1970-01-01')).TotalSeconds)
    $id = "msg_${epochSeconds}_$(Get-Random -Max 9999)"
    
    # Create new message
    $newMsg = @{
        id = $id
        from = $ServerId
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
    
    Write-Host "Sending message..." -ForegroundColor Gray
    git add $messagesPath | Out-Null
    git commit -m "$ServerId: $Subject" -q
    git push origin main -q 2>&1 | Out-Null
    
    # Update status
    Write-Host "Updating message_status.txt..." -ForegroundColor Gray
    & "$BuildRepoPath\windows\scripts\Update-MessageStatus.ps1" -BuildRepoPath $BuildRepoPath
    
    Write-Host "`n✅ Message sent successfully!" -ForegroundColor Green
    Write-Host "  From: $ServerId" -ForegroundColor Cyan
    Write-Host "  To: $To" -ForegroundColor Cyan
    Write-Host "  Subject: $Subject" -ForegroundColor Cyan
    Write-Host "  Type: $Type | Priority: $Priority" -ForegroundColor Cyan
    if ($RequireAck) {
        Write-Host "  ACK Required: YES" -ForegroundColor Yellow
    }
    
    Pop-Location
    exit 0
}
catch {
    Write-Host "Error sending message: $_" -ForegroundColor Red
    Pop-Location
    exit 1
}
