#
# CircuitBreaker.ps1
# Circuit breaker pattern for git operations
#

class CircuitBreaker {
    [int]$FailureThreshold = 5
    [int]$TimeoutSeconds = 300  # 5 minutes
    [string]$State = "CLOSED"  # CLOSED, OPEN, HALF_OPEN
    [int]$FailureCount = 0
    [datetime]$LastFailureTime
    [datetime]$OpenedAt
    
    [bool]CanExecute() {
        if ($this.State -eq "CLOSED") {
            return $true
        }
        
        if ($this.State -eq "OPEN") {
            $elapsed = (Get-Date) - $this.OpenedAt
            if ($elapsed.TotalSeconds -gt $this.TimeoutSeconds) {
                $this.State = "HALF_OPEN"
                $this.FailureCount = 0
                return $true
            }
            return $false
        }
        
        # HALF_OPEN state
        return $true
    }
    
    [void]RecordSuccess() {
        $this.FailureCount = 0
        $this.State = "CLOSED"
    }
    
    [void]RecordFailure() {
        $this.FailureCount++
        $this.LastFailureTime = Get-Date
        
        if ($this.State -eq "HALF_OPEN") {
            $this.State = "OPEN"
            $this.OpenedAt = Get-Date
        }
        elseif ($this.FailureCount -ge $this.FailureThreshold) {
            $this.State = "OPEN"
            $this.OpenedAt = Get-Date
        }
    }
    
    [hashtable]GetStatus() {
        return @{
            State = $this.State
            FailureCount = $this.FailureCount
            LastFailure = if ($this.LastFailureTime) { $this.LastFailureTime.ToString('o') } else { $null }
            OpenedAt = if ($this.OpenedAt) { $this.OpenedAt.ToString('o') } else { $null }
        }
    }
}

Export-ModuleMember -Function * -Cmdlet *
