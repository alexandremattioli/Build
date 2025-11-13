#
# Test-NetworkConnectivity.ps1
# Check network connectivity before git operations
#

param(
    [string]$GitHubHost = "github.com",
    [int]$TimeoutSeconds = 5
)

try {
    # Test DNS resolution
    $dnsResult = Resolve-DnsName -Name $GitHubHost -ErrorAction Stop
    
    # Test HTTPS connectivity
    $testResult = Test-NetConnection -ComputerName $GitHubHost -Port 443 -WarningAction SilentlyContinue
    
    if ($testResult.TcpTestSucceeded) {
        return @{
            Success = $true
            Message = "Network connectivity OK"
            Latency = $testResult.PingReplyDetails.RoundtripTime
        }
    }
    else {
        return @{
            Success = $false
            Message = "Cannot connect to GitHub on port 443"
            Latency = -1
        }
    }
}
catch {
    return @{
        Success = $false
        Message = "Network error: $_"
        Latency = -1
    }
}
