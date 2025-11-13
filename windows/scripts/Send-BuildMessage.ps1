<#
.SYNOPSIS
    Send coordination messages from Windows servers to the Build coordination system.

.DESCRIPTION
    PowerShell wrapper for the Linux messaging system, enabling Windows servers
    to participate in build coordination.

.PARAMETER From
    Sender identifier (e.g., "win-dev1", "win-dev2")

.PARAMETER To
    Recipient(s): "all", "build1", "build2", "build3", "build4", or comma-separated list

.PARAMETER Type
    Message type: "info", "alert", "error", "success", "question"

.PARAMETER Subject
    Message subject (will be auto-generated from body if omitted)

.PARAMETER Body
    Message body content

.PARAMETER RequireAck
    If specified, message requires acknowledgment

.EXAMPLE
    .\Send-BuildMessage.ps1 -From "win-dev1" -To "all" -Type "info" -Subject "Status" -Body "Development in progress"

.EXAMPLE
    .\Send-BuildMessage.ps1 -From "win-dev2" -To "build1,build2" -Type "alert" -Body "Checkstyle fixes completed" -RequireAck
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$From,

    [Parameter(Mandatory=$true)]
    [string]$To,

    [Parameter(Mandatory=$true)]
    [ValidateSet("info", "alert", "error", "success", "question")]
    [string]$Type,

    [Parameter(Mandatory=$false)]
    [string]$Subject = "",

    [Parameter(Mandatory=$true)]
    [string]$Body,

    [switch]$RequireAck
)

# Configuration
$BUILD1_IP = "10.1.3.175"
$BUILD2_IP = "10.1.3.177"
$BUILD_USER = "root"
$REPO_PATH = "/root/Build"

# Function to execute command on Linux builder
function Invoke-BuilderCommand {
    param(
        [string]$Target,
        [string]$Command
    )

    $targetIP = if ($Target -eq "build1") { $BUILD1_IP } else { $BUILD2_IP }
    
    try {
        # Use SSH to execute command on Linux builder
        $result = ssh "${BUILD_USER}@${targetIP}" "$Command" 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Command failed on $Target with exit code $LASTEXITCODE"
            Write-Warning "Output: $result"
            return $false
        }
        
        return $true
    }
    catch {
        Write-Error "Failed to connect to ${Target}: $_"
        return $false
    }
}

# Auto-generate subject from first line of body if not provided
if ([string]::IsNullOrEmpty($Subject)) {
    $Subject = ($Body -split "`n")[0].Substring(0, [Math]::Min(50, $Body.Length))
}

# Escape special characters for bash
$escapedSubject = $Subject -replace '"', '\"' -replace '`', '\`' -replace '$', '\$'
$escapedBody = $Body -replace '"', '\"' -replace '`', '\`' -replace '$', '\$'

# Build command
$ackFlag = if ($RequireAck) { " --require-ack" } else { "" }
$command = "cd $REPO_PATH && ./scripts/send_and_refresh.sh `"$From`" `"$To`" `"$Type`" `"$escapedSubject`" `"$escapedBody`"$ackFlag"
    # Log message locally
    . $PSScriptRoot\Append-MessageLog.ps1 -From $From -To $To -Type $Type -Subject $subject -Body $Body


Write-Host "Sending message from $From to $To..." -ForegroundColor Cyan

# Send via Build1 (primary messaging hub)
$success = Invoke-BuilderCommand -Target "build1" -Command $command

if ($success) {
    Write-Host "✓ Message sent successfully" -ForegroundColor Green
    Write-Host "  From: $From" -ForegroundColor Gray
    Write-Host "  To: $To" -ForegroundColor Gray
    Write-Host "  Type: $Type" -ForegroundColor Gray
    Write-Host "  Subject: $Subject" -ForegroundColor Gray
} else {
    Write-Host "✗ Failed to send message" -ForegroundColor Red
    
    # Try Build2 as fallback
    Write-Host "Attempting fallback to Build2..." -ForegroundColor Yellow
    $success = Invoke-BuilderCommand -Target "build2" -Command $command
    
    if ($success) {
        Write-Host "✓ Message sent via Build2" -ForegroundColor Green
    } else {
        Write-Error "Failed to send message via both builders"
        exit 1
    }
}

