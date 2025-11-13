#
# Test-AutonomousCoordination.ps1
# Test autonomous message coordination with 5-message reply chain
#

param(
    [string]$BuildRepoPath = "K:\Projects\Build",
    [int]$RequiredReplies = 5
)

$ErrorActionPreference = "Continue"

Write-Host "`n=== AUTONOMOUS COORDINATION TEST ===" -ForegroundColor Cyan
Write-Host "Goal: Send request to fleet, wait for $RequiredReplies replies, then respond to each`n" -ForegroundColor Gray

# Step 1: Send initial request to all servers
Write-Host "[1/3] Sending test request to all servers..." -ForegroundColor Yellow
& "$BuildRepoPath\windows\scripts\sm.ps1" -Body "COORDINATION TEST: Please reply with your server name and status. This is an autonomous coordination test. Include the word 'TEST-REPLY' in your response." -Subject "Coordination Test - Please Reply" -Type "request" -RequireAck -BuildRepoPath $BuildRepoPath

$testStartTime = Get-Date
$testId = "coord_test_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

Write-Host "✓ Test request sent at $($testStartTime.ToString('HH:mm:ss'))" -ForegroundColor Green
Write-Host "`n[2/3] Waiting for replies (checking every 15 seconds for 3 minutes)...`n" -ForegroundColor Yellow

$repliesReceived = @()
$maxWaitSeconds = 180
$checkInterval = 15
$elapsed = 0

while ($elapsed -lt $maxWaitSeconds -and $repliesReceived.Count -lt $RequiredReplies) {
    Start-Sleep -Seconds $checkInterval
    $elapsed += $checkInterval
    
    # Pull latest and check for replies
    Push-Location $BuildRepoPath
    git pull origin main -q 2>&1 | Out-Null
    Pop-Location
    
    $messages = Get-Content "$BuildRepoPath\coordination\messages.json" -Raw | ConvertFrom-Json
    
    # Find replies to our test (messages after test start time containing TEST-REPLY)
    $newReplies = $messages.messages | Where-Object {
        try {
            $msgTime = [DateTime]::Parse($_.timestamp)
            $msgTime -gt $testStartTime -and
            $_.body -match "TEST-REPLY" -and
            $_.from -ne "architect" -and
            $repliesReceived -notcontains $_.id
        }
        catch {
            $false
        }
    }
    
    if ($newReplies) {
        foreach ($reply in $newReplies) {
            $repliesReceived += $reply.id
            Write-Host "  [$($repliesReceived.Count)/$RequiredReplies] Reply from: $($reply.from) - $($reply.subject)" -ForegroundColor Green
        }
    }
    else {
        Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] Waiting... ($($repliesReceived.Count)/$RequiredReplies replies, ${elapsed}s elapsed)" -ForegroundColor DarkGray
    }
}

if ($repliesReceived.Count -eq 0) {
    Write-Host "`n✗ TEST FAILED: No replies received after $elapsed seconds" -ForegroundColor Red
    Write-Host "`nPossible reasons:" -ForegroundColor Yellow
    Write-Host "  - Other servers don't have monitors running" -ForegroundColor Gray
    Write-Host "  - Other servers don't have autonomous response enabled" -ForegroundColor Gray
    Write-Host "  - Network/git issues preventing message delivery" -ForegroundColor Gray
    exit 1
}

Write-Host "`n✓ Received $($repliesReceived.Count) replies!" -ForegroundColor Green

# Step 3: Respond to each reply
Write-Host "`n[3/3] Sending acknowledgment responses...`n" -ForegroundColor Yellow

$messages = Get-Content "$BuildRepoPath\coordination\messages.json" -Raw | ConvertFrom-Json
$responsesCount = 0

foreach ($replyId in $repliesReceived) {
    $reply = $messages.messages | Where-Object { $_.id -eq $replyId }
    
    if ($reply) {
        $responseBody = "Thank you for your response! Code2 acknowledges receipt from $($reply.from).`n`nTest Status: Reply $($responsesCount + 1) of $($repliesReceived.Count)`nCoordination test proceeding successfully.`n`nTest ID: $testId"
        
        try {
            & "$BuildRepoPath\windows\scripts\sm.ps1" -Body $responseBody -Subject "Re: Coordination Test Acknowledgment" -To $reply.from -BuildRepoPath $BuildRepoPath
            $responsesCount++
            Write-Host "  [$responsesCount/$($repliesReceived.Count)] Acknowledged: $($reply.from)" -ForegroundColor Green
            Start-Sleep -Seconds 2  # Avoid rapid-fire commits
        }
        catch {
            Write-Host "  ✗ Failed to acknowledge $($reply.from): $_" -ForegroundColor Red
        }
    }
}

# Summary
$testEndTime = Get-Date
$totalDuration = ($testEndTime - $testStartTime).TotalSeconds

Write-Host "`n=== TEST SUMMARY ===" -ForegroundColor Cyan
Write-Host "Test ID: $testId" -ForegroundColor White
Write-Host "Duration: $totalDuration seconds" -ForegroundColor White
Write-Host "Replies Received: $($repliesReceived.Count) / $RequiredReplies" -ForegroundColor White
Write-Host "Acknowledgments Sent: $responsesCount" -ForegroundColor White

if ($responsesCount -ge $RequiredReplies) {
    Write-Host "`n✓ TEST PASSED: Full coordination cycle completed!" -ForegroundColor Green
    Write-Host "  - Sent request to all servers" -ForegroundColor Gray
    Write-Host "  - Received $($repliesReceived.Count) autonomous replies" -ForegroundColor Gray
    Write-Host "  - Acknowledged all $responsesCount responders" -ForegroundColor Gray
    exit 0
}
elseif ($responsesCount -gt 0) {
    Write-Host "`n⚠ TEST PARTIAL: Received $($repliesReceived.Count) replies but needed $RequiredReplies" -ForegroundColor Yellow
    exit 2
}
else {
    Write-Host "`n✗ TEST FAILED: Could not complete coordination cycle" -ForegroundColor Red
    exit 1
}
