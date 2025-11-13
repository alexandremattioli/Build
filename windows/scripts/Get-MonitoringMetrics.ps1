#
# Get-MonitoringMetrics.ps1
# Collect and display monitoring metrics
#

param(
    [string]$BuildRepoPath = "K:\Projects\Build",
    [int]$LastNHours = 24
)

$metricsPath = Join-Path $BuildRepoPath "code2\metrics"
if (-not (Test-Path $metricsPath)) {
    New-Item -ItemType Directory -Path $metricsPath -Force | Out-Null
}

$metricsFile = Join-Path $metricsPath "metrics.json"

# Initialize metrics if doesn't exist
if (-not (Test-Path $metricsFile)) {
    $initialMetrics = @{
        startTime = (Get-Date).ToString('o')
        events = @()
        stats = @{
            messagesProcessed = 0
            messagesReceived = 0
            messagesSent = 0
            autoResponses = 0
            errors = 0
            gitPullSuccesses = 0
            gitPullFailures = 0
            heartbeatsSent = 0
        }
    }
    $initialMetrics | ConvertTo-Json -Depth 10 | Set-Content $metricsFile
}

# Read current metrics
$metrics = Get-Content $metricsFile -Raw | ConvertFrom-Json

# Calculate statistics
$cutoffTime = (Get-Date).AddHours(-$LastNHours)
$recentEvents = $metrics.events | Where-Object {
    try {
        [DateTime]::Parse($_.timestamp) -gt $cutoffTime
    } catch {
        $false
    }
}

$summary = @{
    Period = "Last $LastNHours hours"
    TotalEvents = $recentEvents.Count
    MessagesSent = ($recentEvents | Where-Object { $_.type -eq 'message_sent' }).Count
    MessagesReceived = ($recentEvents | Where-Object { $_.type -eq 'message_received' }).Count
    AutoResponses = ($recentEvents | Where-Object { $_.type -eq 'auto_response' }).Count
    Errors = ($recentEvents | Where-Object { $_.type -eq 'error' }).Count
    AvgResponseTime = if ($recentEvents | Where-Object { $_.responseTime }) {
        ($recentEvents | Where-Object { $_.responseTime } | Measure-Object -Property responseTime -Average).Average
    } else { 0 }
    GitOperations = @{
        Successes = ($recentEvents | Where-Object { $_.type -eq 'git_pull_success' }).Count
        Failures = ($recentEvents | Where-Object { $_.type -eq 'git_pull_failure' }).Count
    }
}

return $summary
