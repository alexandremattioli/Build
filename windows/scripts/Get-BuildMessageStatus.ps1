<#
.SYNOPSIS
    Get current build coordination message status.

.DESCRIPTION
    Fetches and displays the current message status from the coordination system.

.EXAMPLE
    .\Get-BuildMessageStatus.ps1
#>

# Configuration
$BUILD1_IP = "10.1.3.175"
$BUILD_USER = "root"
$REPO_PATH = "/root/Build"

Write-Host "Fetching message status from Build1..." -ForegroundColor Cyan

try {
    # Fetch message_status.txt
    $content = ssh "${BUILD_USER}@${BUILD1_IP}" "cat ${REPO_PATH}/message_status.txt" 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to fetch message status"
        exit 1
    }
    
    Write-Host "`n=== BUILD COORDINATION STATUS ===" -ForegroundColor Yellow
    Write-Host $content
    Write-Host "================================`n" -ForegroundColor Yellow
}
catch {
    Write-Error "Failed to retrieve status: $_"
    exit 1
}
