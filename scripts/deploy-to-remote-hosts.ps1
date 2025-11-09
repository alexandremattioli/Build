<#
.SYNOPSIS
    Deploy auto-sync setup to remote hosts
.DESCRIPTION
    This script deploys the bootstrap setup to one or more remote Windows hosts via PowerShell remoting
.PARAMETER RemoteHosts
    Array of remote host IPs or hostnames
.PARAMETER RepoPath
    The local path where the Projects repo should be cloned on remote hosts
.PARAMETER Credential
    PSCredential object for authentication (optional, will prompt if not provided)
.EXAMPLE
    .\deploy-to-remote-hosts.ps1 -RemoteHosts @("10.1.3.175", "10.1.3.177") -RepoPath "K:\Projects"
#>

param(
    [Parameter(Mandatory=$true)]
    [string[]]$RemoteHosts,
    
    [Parameter(Mandatory=$false)]
    [string]$RepoPath = "K:\Projects",
    
    [Parameter(Mandatory=$false)]
    [string]$GitHubRepo = "https://github.com/alexandremattioli/Projects.git",
    
    [Parameter(Mandatory=$false)]
    [PSCredential]$Credential,

    [switch]$UseCurrentUser
)

$ErrorActionPreference = "Continue"

function Log($message, $color = "Cyan") {
    Write-Host "[$(Get-Date -Format ''HH:mm:ss'')] $message" -ForegroundColor $color
}

# Get credentials if not provided and not using current user
if (-not $UseCurrentUser) {
    if (-not $Credential) {
        Log "Enter credentials for remote hosts (or rerun with -UseCurrentUser to skip prompt):" "Yellow"
        $Credential = Get-Credential
    }
}

# Read the bootstrap script
$bootstrapPath = Join-Path $PSScriptRoot "bootstrap-auto-sync.ps1"
if (-not (Test-Path $bootstrapPath)) {
    throw "Bootstrap script not found at: $bootstrapPath"
}

$bootstrapContent = Get-Content $bootstrapPath -Raw

Log "Starting deployment to $($RemoteHosts.Count) host(s)..." "Green"
Log "Target repo path: $RepoPath"
Log "GitHub repo: $GitHubRepo"
Log ""

foreach ($host in $RemoteHosts) {
    Log "========================================" "Magenta"
    Log "Deploying to: $host" "Magenta"
    Log "========================================" "Magenta"
    
    try {
        # Test connection
        Log "Testing connection to $host..."
        if (-not (Test-Connection -ComputerName $host -Count 1 -Quiet)) {
            Log "Cannot reach $host - skipping" "Red"
            continue
        }
        
        # Create PSSession
        Log "Creating remote session..."
        if ($UseCurrentUser) {
            $session = New-PSSession -ComputerName $host -ErrorAction Stop
        } else {
            $session = New-PSSession -ComputerName $host -Credential $Credential -ErrorAction Stop
        }
        
        # Copy bootstrap script to remote host
        Log "Copying bootstrap script..."
        Invoke-Command -Session $session -ScriptBlock {
            param($content, $repoPath, $gitRepo)
            
            # Create temp directory
            $tempDir = Join-Path $env:TEMP "bootstrap-setup"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            # Save bootstrap script
            $scriptPath = Join-Path $tempDir "bootstrap-auto-sync.ps1"
            Set-Content -Path $scriptPath -Value $content
            
            # Run bootstrap
            Write-Host "Running bootstrap script..." -ForegroundColor Cyan
            & $scriptPath -RepoPath $repoPath -GitHubRepo $gitRepo
            
        } -ArgumentList $bootstrapContent, $RepoPath, $GitHubRepo
        
        Log "Deployment to $host completed successfully!" "Green"
        
        # Close session
        Remove-PSSession -Session $session
        
    } catch {
        Log "Error deploying to $host : $($_.Exception.Message)" "Red"
    }
    
    Log ""
}

Log "========================================" "Green"
Log "Deployment complete!" "Green"
Log "========================================" "Green"
