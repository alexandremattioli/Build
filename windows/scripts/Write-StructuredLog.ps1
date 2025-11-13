#
# Write-StructuredLog.ps1
# Structured JSON logging with performance metrics
#

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('DEBUG','INFO','WARNING','ERROR','CRITICAL')]
    [string]$Level,
    
    [Parameter(Mandatory=$true)]
    [string]$Message,
    
    [hashtable]$Metadata = @{},
    
    [string]$LogPath = "K:\Projects\Build\code2\logs\structured.log"
)

$logEntry = @{
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    level = $Level
    message = $Message
    server = "code2"
    metadata = $Metadata
}

$logJson = $logEntry | ConvertTo-Json -Compress

# Ensure log directory exists
$logDir = Split-Path $LogPath
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Append to log file
Add-Content -Path $LogPath -Value $logJson

# Also output to console with color
$color = switch ($Level) {
    'DEBUG' { 'DarkGray' }
    'INFO' { 'White' }
    'WARNING' { 'Yellow' }
    'ERROR' { 'Red' }
    'CRITICAL' { 'Magenta' }
}

Write-Host "[$Level] $Message" -ForegroundColor $color
