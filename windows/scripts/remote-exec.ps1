<#
.SYNOPSIS
    Execute commands on Linux build servers from Windows.

.DESCRIPTION
    Run shell commands or scripts on Build1 or Build2 from Windows development servers.

.PARAMETER Target
    Target builder: "build1" or "build2"

.PARAMETER Command
    Shell command to execute

.PARAMETER ScriptPath
    Path to local script file to upload and execute

.PARAMETER ShowOutput
    Display command output (default: true)

.EXAMPLE
    .\remote-exec.ps1 -Target build1 -Command "mvn clean compile"

.EXAMPLE
    .\remote-exec.ps1 -Target build2 -Command "cd /root/Build && git pull"

.EXAMPLE
    .\remote-exec.ps1 -Target build1 -ScriptPath ".\deploy\build_vnf.sh"
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("build1", "build2")]
    [string]$Target,

    [Parameter(Mandatory=$false)]
    [string]$Command = "",

    [Parameter(Mandatory=$false)]
    [string]$ScriptPath = "",

    [switch]$ShowOutput = $true
)

# Configuration
$BUILD1_IP = "10.1.3.175"
$BUILD2_IP = "10.1.3.177"
$BUILD_USER = "root"

# Validate parameters
if ([string]::IsNullOrEmpty($Command) -and [string]::IsNullOrEmpty($ScriptPath)) {
    Write-Error "Either -Command or -ScriptPath must be specified"
    exit 1
}

if (![string]::IsNullOrEmpty($Command) -and ![string]::IsNullOrEmpty($ScriptPath)) {
    Write-Error "Specify either -Command or -ScriptPath, not both"
    exit 1
}

# Get target IP
$targetIP = if ($Target -eq "build1") { $BUILD1_IP } else { $BUILD2_IP }

Write-Host "Executing on $Target ($targetIP)..." -ForegroundColor Cyan

try {
    if (![string]::IsNullOrEmpty($Command)) {
        # Execute direct command
        Write-Host "Command: $Command" -ForegroundColor Gray
        
        if ($ShowOutput) {
            ssh "${BUILD_USER}@${targetIP}" "$Command"
        } else {
            $output = ssh "${BUILD_USER}@${targetIP}" "$Command" 2>&1
        }
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ Command completed successfully" -ForegroundColor Green
        } else {
            Write-Host "✗ Command failed with exit code $LASTEXITCODE" -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }
    else {
        # Upload and execute script
        if (!(Test-Path $ScriptPath)) {
            Write-Error "Script file not found: $ScriptPath"
            exit 1
        }
        
        $scriptName = Split-Path -Leaf $ScriptPath
        $remotePath = "/tmp/$scriptName"
        
        Write-Host "Uploading script: $scriptName" -ForegroundColor Gray
        scp "$ScriptPath" "${BUILD_USER}@${targetIP}:${remotePath}"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to upload script"
            exit 1
        }
        
        Write-Host "Executing script on $Target..." -ForegroundColor Gray
        ssh "${BUILD_USER}@${targetIP}" "chmod +x $remotePath && $remotePath"
        
        $exitCode = $LASTEXITCODE
        
        # Cleanup
        ssh "${BUILD_USER}@${targetIP}" "rm -f $remotePath" 2>&1 | Out-Null
        
        if ($exitCode -eq 0) {
            Write-Host "✓ Script executed successfully" -ForegroundColor Green
        } else {
            Write-Host "✗ Script failed with exit code $exitCode" -ForegroundColor Red
            exit $exitCode
        }
    }
}
catch {
    Write-Error "Execution failed: $_"
    exit 1
}
