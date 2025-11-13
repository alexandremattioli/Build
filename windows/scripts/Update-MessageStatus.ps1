#
# Update-MessageStatus.ps1
# Update message_status.txt with current coordination statistics
#

param(
    [string]$BuildRepoPath = "K:\Projects\Build"
)

$ErrorActionPreference = "Stop"

try {
    Push-Location $BuildRepoPath
    
    # Load messages
    $messages = Get-Content "coordination\messages.json" -Raw | ConvertFrom-Json
    
    # All known servers
    $allServers = @('build1','build2','build3','build4','code1','code2','jh01','architect')
    
    $statusLines = @()
    $statusLines += "=== BUILD COORDINATION MESSAGE STATUS ==="
    $statusLines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $statusLines += ""
    $statusLines += "MESSAGE COUNTS BY SERVER:"
    
    foreach ($srv in $allServers) {
        $count = ($messages.messages | Where-Object { $_.from -eq $srv }).Count
        $lastMsg = $messages.messages | Where-Object { $_.from -eq $srv } | Select-Object -Last 1
        $lastTime = if ($lastMsg) { $lastMsg.timestamp } else { "never" }
        $statusLines += "  $srv messages: $count  Last: $lastTime"
    }
    
    $statusLines += ""
    $totalCount = $messages.messages.Count
    $statusLines += "TOTAL MESSAGES: $totalCount"
    $statusLines += ""
    
    $lastMsg = $messages.messages | Select-Object -Last 1
    $statusLines += "LAST MESSAGE:"
    $statusLines += "  From: $($lastMsg.from)"
    $statusLines += "  To: $($lastMsg.to)"
    $statusLines += "  Subject: $($lastMsg.subject)"
    $statusLines += "  Time: $($lastMsg.timestamp)"
    $statusLines += ""
    $statusLines += "Body:"
    $statusLines += $lastMsg.body
    
    $statusLines | Set-Content "message_status.txt"
    
    git add message_status.txt | Out-Null
    git commit -m "Auto-update message_status.txt" -q 2>&1 | Out-Null
    git push origin main -q 2>&1 | Out-Null
    
    Pop-Location
    exit 0
}
catch {
    Write-Host "Warning: Could not update message_status.txt: $_" -ForegroundColor Yellow
    Pop-Location
    exit 1
}
