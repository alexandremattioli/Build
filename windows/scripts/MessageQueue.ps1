#
# MessageQueue.ps1
# Local message queue for failed sends with retry capability
#

class MessageQueue {
    [string]$QueuePath
    
    MessageQueue([string]$BuildRepoPath) {
        $this.QueuePath = Join-Path $BuildRepoPath "code2\queue\pending_messages.json"
        $queueDir = Split-Path $this.QueuePath
        if (-not (Test-Path $queueDir)) {
            New-Item -ItemType Directory -Path $queueDir -Force | Out-Null
        }
        
        # Initialize queue file if doesn't exist
        if (-not (Test-Path $this.QueuePath)) {
            @{ messages = @() } | ConvertTo-Json | Set-Content $this.QueuePath
        }
    }
    
    [void]Enqueue([hashtable]$Message) {
        $queue = Get-Content $this.QueuePath -Raw | ConvertFrom-Json
        $Message.queuedAt = (Get-Date).ToString('o')
        $Message.attempts = 0
        $queue.messages += $Message
        $queue | ConvertTo-Json -Depth 10 | Set-Content $this.QueuePath
    }
    
    [array]GetPending() {
        $queue = Get-Content $this.QueuePath -Raw | ConvertFrom-Json
        return $queue.messages | Where-Object { $_.attempts -lt 5 }
    }
    
    [void]MarkSent([string]$MessageId) {
        $queue = Get-Content $this.QueuePath -Raw | ConvertFrom-Json
        $queue.messages = $queue.messages | Where-Object { $_.id -ne $MessageId }
        $queue | ConvertTo-Json -Depth 10 | Set-Content $this.QueuePath
    }
    
    [void]IncrementAttempts([string]$MessageId) {
        $queue = Get-Content $this.QueuePath -Raw | ConvertFrom-Json
        foreach ($msg in $queue.messages) {
            if ($msg.id -eq $MessageId) {
                $msg.attempts++
                $msg.lastAttempt = (Get-Date).ToString('o')
            }
        }
        $queue | ConvertTo-Json -Depth 10 | Set-Content $this.QueuePath
    }
}

Export-ModuleMember -Function * -Cmdlet *
