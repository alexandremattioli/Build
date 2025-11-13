# Install Windows Task Scheduler job for automatic status updates
# Run this script once on each Windows server to set up automated updates

param(
    [string]$ScriptPath = "$PSScriptRoot\update-status.ps1",
    [int]$IntervalSeconds = 60
)

$TaskName = "BuildServerStatusUpdater"
$TaskDescription = "Automatically updates build server status and pushes to GitHub"

# Remove existing task if present
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Output "Removed existing task: $TaskName"
}

# Create action
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`"" `
    -WorkingDirectory (Split-Path $ScriptPath -Parent | Split-Path -Parent)

# Create trigger - repeat every N seconds indefinitely
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Seconds $IntervalSeconds) -RepetitionDuration ([TimeSpan]::MaxValue)

# Create settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -MultipleInstances IgnoreNew

# Register task to run as current user
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U

Register-ScheduledTask -TaskName $TaskName `
    -Description $TaskDescription `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal

Write-Output "Successfully installed scheduled task: $TaskName"
Write-Output "Update interval: $IntervalSeconds seconds"
Write-Output "Script: $ScriptPath"
Write-Output ""
Write-Output "To verify: Get-ScheduledTask -TaskName '$TaskName'"
Write-Output "To remove: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
