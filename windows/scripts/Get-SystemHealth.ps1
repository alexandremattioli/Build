#
# Get-SystemHealth.ps1
# Monitor system health (disk space, memory, git repo)
#

param(
    [string]$BuildRepoPath = "K:\Projects\Build"
)

$health = @{
    Timestamp = Get-Date -Format 'o'
    Checks = @{}
    Overall = "HEALTHY"
}

# Check disk space
try {
    $drive = (Get-Item $BuildRepoPath).PSDrive
    $freeGB = [math]::Round($drive.Free / 1GB, 2)
    $totalGB = [math]::Round(($drive.Free + $drive.Used) / 1GB, 2)
    $percentFree = [math]::Round(($drive.Free / ($drive.Free + $drive.Used)) * 100, 1)
    
    $diskStatus = "OK"
    if ($freeGB -lt 0.5) {
        $diskStatus = "CRITICAL"
        $health.Overall = "CRITICAL"
    }
    elseif ($freeGB -lt 1) {
        $diskStatus = "WARNING"
        if ($health.Overall -ne "CRITICAL") { $health.Overall = "WARNING" }
    }
    
    $health.Checks.DiskSpace = @{
        Status = $diskStatus
        FreeGB = $freeGB
        TotalGB = $totalGB
        PercentFree = $percentFree
    }
}
catch {
    $health.Checks.DiskSpace = @{ Status = "ERROR"; Message = $_ }
    $health.Overall = "ERROR"
}

# Check memory
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $usedPercent = [math]::Round((1 - ($os.FreePhysicalMemory / $os.TotalVisibleMemorySize)) * 100, 1)
    
    $memStatus = "OK"
    if ($usedPercent -gt 95) {
        $memStatus = "WARNING"
        if ($health.Overall -eq "HEALTHY") { $health.Overall = "WARNING" }
    }
    
    $health.Checks.Memory = @{
        Status = $memStatus
        FreeGB = $freeMemoryGB
        TotalGB = $totalMemoryGB
        UsedPercent = $usedPercent
    }
}
catch {
    $health.Checks.Memory = @{ Status = "ERROR"; Message = $_ }
}

# Check git repository
try {
    Push-Location $BuildRepoPath
    $gitStatus = git status --porcelain 2>&1
    $gitLog = git log -1 --pretty=format:"%h %s" 2>&1
    Pop-Location
    
    $repoStatus = "OK"
    if ($gitStatus -match "fatal|error") {
        $repoStatus = "ERROR"
        $health.Overall = "ERROR"
    }
    
    $health.Checks.GitRepo = @{
        Status = $repoStatus
        LastCommit = $gitLog
        UncommittedChanges = ($gitStatus | Measure-Object -Line).Lines
    }
}
catch {
    $health.Checks.GitRepo = @{ Status = "ERROR"; Message = $_ }
    Pop-Location
}

# Check monitor process
try {
    $job = Get-Job -Name "Code2Monitor" -ErrorAction SilentlyContinue
    $monitorStatus = if ($job -and $job.State -eq "Running") { "OK" } else { "WARNING" }
    
    if ($monitorStatus -ne "OK" -and $health.Overall -eq "HEALTHY") {
        $health.Overall = "WARNING"
    }
    
    $health.Checks.Monitor = @{
        Status = $monitorStatus
        JobState = if ($job) { $job.State } else { "Not Running" }
        HasMoreData = if ($job) { $job.HasMoreData } else { $false }
    }
}
catch {
    $health.Checks.Monitor = @{ Status = "ERROR"; Message = $_ }
}

return $health
