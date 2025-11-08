<#
.SYNOPSIS
    Send hourly heartbeat from Windows development server.

.DESCRIPTION
    Sends a heartbeat message to the coordination system to indicate the Windows
    server is online and active.

.EXAMPLE
    .\Send-Heartbeat.ps1
#>

# Get hostname
$hostname = $env:COMPUTERNAME.ToLower()
$from = "win-$hostname"

# Determine which Windows server this is
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -match '^10\.1\.3\.' }).IPAddress

if (!$ip) {
    $ip = "unknown"
}

# Get system info
$cpu = Get-Counter '\Processor(_Total)\% Processor Time' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue
$mem = Get-Counter '\Memory\% Committed Bytes In Use' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue
$disk = Get-PSDrive C | Select-Object -ExpandProperty Used
$diskFree = Get-PSDrive C | Select-Object -ExpandProperty Free

# Format heartbeat message
$body = @"
Windows Development Server Heartbeat
IP: $ip
CPU: $([Math]::Round($cpu, 1))%
Memory: $([Math]::Round($mem, 1))%
Disk Used: $([Math]::Round($disk / 1GB, 1)) GB
Disk Free: $([Math]::Round($diskFree / 1GB, 1)) GB
Timestamp: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

# Send heartbeat
try {
    & "$PSScriptRoot\Send-BuildMessage.ps1" -From $from -To "all" -Type "info" -Subject "Hourly heartbeat" -Body $body
    Write-Host "Heartbeat sent successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to send heartbeat: $_"
    exit 1
}
