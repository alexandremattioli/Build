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
    
    # Message counts by server
    foreach ($srv in $allServers) {
        $fromCount = ($messages.messages | Where-Object { $_.from -eq $srv }).Count
        $toCount = ($messages.messages | Where-Object { $_.to -eq $srv -or $_.to -eq 'all' }).Count
        $lastMsg = $messages.messages | Where-Object { $_.from -eq $srv } | Select-Object -Last 1
        $lastTime = if ($lastMsg) { 
            try { [DateTime]::Parse($lastMsg.timestamp).ToString('yyyy-MM-dd HH:mm') } 
            catch { $lastMsg.timestamp }
        } else { 
            "never" 
        }
        $statusLines += "${srv} messages: $fromCount  Last message: $lastTime"
    }
    
    $statusLines += ""
    
    # Latest message summary
    $lastMsg = $messages.messages | Select-Object -Last 1
    $lastTime = try { [DateTime]::Parse($lastMsg.timestamp).ToString('yyyy-MM-dd HH:mm') } catch { $lastMsg.timestamp }
    $statusLines += "Last message from: $($lastMsg.from) to $($lastMsg.to) ($($lastMsg.subject))"
    
    # Unread count
    $unreadByServer = @{}
    foreach ($srv in $allServers) {
        $unread = ($messages.messages | Where-Object { ($_.to -eq $srv -or $_.to -eq 'all') -and $_.read -eq $false }).Count
        if ($unread -gt 0) {
            $unreadByServer[$srv] = $unread
        }
    }
    
    if ($unreadByServer.Count -gt 0) {
        $waitingOn = ($unreadByServer.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Name
        $waitingCount = $unreadByServer[$waitingOn]
        $statusLines += "Waiting on: $waitingOn ($waitingCount unread)"
    }
    
    # ACK pending count
    $ackPending = ($messages.messages | Where-Object { $_.ack_required -eq $true -and -not $_.ack_by }).Count
    if ($ackPending -gt 0) {
        $statusLines += "Ack pending: $ackPending"
    }
    
    # Total messages
    $totalCount = $messages.messages.Count
    $statusLines += "Total messages: $totalCount"
    $statusLines += ""
    $statusLines += "Latest message body:"
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
