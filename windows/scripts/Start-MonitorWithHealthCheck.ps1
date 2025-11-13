#
# Start-MonitorWithHealthCheck.ps1
# Starts the Code2 message monitor with health checking and auto-restart
#

param(
    [string]$BuildRepoPath = "K:\Projects\Build"
)

$ErrorActionPreference = "Continue"

Write-Host "=== Code2 Monitor Health Check System ===" -ForegroundColor Cyan
Write-Host "Starting monitor with automatic restart capability`n" -ForegroundColor Gray

$monitorScript = Join-Path $BuildRepoPath "windows\scripts\Start-MessageMonitor.ps1"
$healthCheckInterval = 60  # Check every 60 seconds
$maxFailures = 3
$failureCount = 0

while ($true) {
    try {
        # Check if monitor job exists and is running
        $job = Get-Job -Name "Code2Monitor" -ErrorAction SilentlyContinue
        
        if (-not $job) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Monitor not running - starting..." -ForegroundColor Yellow
            Start-Job -Name "Code2Monitor" -ScriptBlock {
                param($path, $repo)
                Set-Location $repo
                & $path
            } -ArgumentList $monitorScript, $BuildRepoPath | Out-Null
            $failureCount = 0
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Monitor started" -ForegroundColor Green
        }
        elseif ($job.State -eq "Failed" -or $job.State -eq "Stopped") {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Monitor in $($job.State) state - restarting..." -ForegroundColor Red
            Remove-Job -Name "Code2Monitor" -Force
            Start-Job -Name "Code2Monitor" -ScriptBlock {
                param($path, $repo)
                Set-Location $repo
                & $path
            } -ArgumentList $monitorScript, $BuildRepoPath | Out-Null
            $failureCount++
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Monitor restarted (failure $failureCount/$maxFailures)" -ForegroundColor Yellow
        }
        else {
            # Monitor is running - check if it's actually working
            $lastOutput = Receive-Job -Name "Code2Monitor" -Keep | Select-Object -Last 1
            
            # Check if monitor is still producing output
            if ($lastOutput) {
                $failureCount = 0  # Reset failure count on successful check
                if ($iteration % 10 -eq 0) {  # Log health check every 10 minutes
                    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Health check OK - Monitor running" -ForegroundColor DarkGreen
                }
            }
        }
        
        # If too many failures, alert but keep trying
        if ($failureCount -ge $maxFailures) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] WARNING: Monitor has failed $failureCount times" -ForegroundColor Red
            $failureCount = 0  # Reset to continue trying
        }
        
        Start-Sleep -Seconds $healthCheckInterval
        $iteration++
    }
    catch {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Health check error: $_" -ForegroundColor Red
        Start-Sleep -Seconds $healthCheckInterval
    }
}
