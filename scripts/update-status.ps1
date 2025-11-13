# Update status.json for Windows servers
# Run this script periodically via Task Scheduler (every 60 seconds recommended)

param(
    [string]$ServerConfigPath = ".build_server_id"
)

# Read server configuration
if (-not (Test-Path $ServerConfigPath)) {
    Write-Error "Server config not found: $ServerConfigPath"
    exit 1
}

$config = Get-Content $ServerConfigPath -Raw | ConvertFrom-Json

# Get system metrics
$cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue).CounterSamples.CookedValue
$memory = Get-CimInstance Win32_OperatingSystem
$memoryUsedGB = [math]::Round(($memory.TotalVisibleMemorySize - $memory.FreePhysicalMemory) / 1MB, 1)
$memoryTotalGB = [math]::Round($memory.TotalVisibleMemorySize / 1MB, 0)

# Get disk space (workspace drive)
$workspaceDrive = Split-Path -Qualifier $config.workspace
$disk = Get-PSDrive -Name $workspaceDrive[0] -ErrorAction SilentlyContinue
$diskFreeGB = if ($disk) { [math]::Round($disk.Free / 1GB, 0) } else { 0 }

# Get CPU cores
$cores = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum

# Determine status
$status = "online"
if ($cpu -gt 90) { $status = "building" }

# Build status object
$statusObj = @{
    server_id = $config.server_id
    hostname = $env:COMPUTERNAME
    ip = $config.ip
    role = $config.role
    ai_model = $config.ai_model
    status = $status
    workspace = $config.workspace
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    capabilities = @{
        cores = $cores
        memory_gb = $memoryTotalGB
    }
    system = @{
        cpu_usage = [math]::Round($cpu, 1)
        memory_used_gb = $memoryUsedGB
        disk_free_gb = $diskFreeGB
    }
}

# Write to status file
$statusPath = Join-Path $config.server_id "status.json"
$statusObj | ConvertTo-Json -Depth 10 | Set-Content $statusPath -Encoding UTF8

# Commit and push to GitHub
$commitMsg = "Auto-update $($config.server_id) status"
git add $statusPath
$hasChanges = git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
    git commit -m $commitMsg
    
    # Retry push up to 3 times with rebase
    for ($i = 0; $i -lt 3; $i++) {
        Start-Sleep -Seconds 2
        git pull --rebase origin main 2>&1 | Out-Null
        $pushResult = git push origin main 2>&1
        if ($pushResult -notmatch "rejected") {
            Write-Output "Status updated and pushed successfully"
            break
        }
    }
}

Write-Output "Status update completed at $(Get-Date)"
