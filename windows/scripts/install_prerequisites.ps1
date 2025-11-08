<#
.SYNOPSIS
    Install prerequisites for Windows development servers.

.DESCRIPTION
    Installs required software for CloudStack development on Windows:
    - Git for Windows
    - Java JDK 17
    - Maven
    - Python 3.11+
    - VSCode (if not present)
    - OpenSSH Client

.PARAMETER SkipVSCode
    Skip VSCode installation (if already installed)

.EXAMPLE
    .\install_prerequisites.ps1

.EXAMPLE
    .\install_prerequisites.ps1 -SkipVSCode
#>

param(
    [switch]$SkipVSCode
)

# Requires Administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

Write-Host "=== Windows Development Server Prerequisites Installation ===" -ForegroundColor Cyan
Write-Host ""

# Function to download file
function Download-File {
    param(
        [string]$Url,
        [string]$Output
    )
    
    Write-Host "Downloading: $Url" -ForegroundColor Gray
    Invoke-WebRequest -Uri $Url -OutFile $Output -UseBasicParsing
}

# Function to check if software is installed
function Test-Installed {
    param([string]$Name)
    
    $installed = Get-Command $Name -ErrorAction SilentlyContinue
    return $null -ne $installed
}

$tempDir = "$env:TEMP\build-setup"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

# 1. Install Git for Windows
if (Test-Installed "git") {
    Write-Host "✓ Git already installed" -ForegroundColor Green
} else {
    Write-Host "Installing Git for Windows..." -ForegroundColor Yellow
    $gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe"
    $gitInstaller = "$tempDir\git-installer.exe"
    
    Download-File -Url $gitUrl -Output $gitInstaller
    Start-Process -FilePath $gitInstaller -Args "/VERYSILENT /NORESTART" -Wait
    
    Write-Host "✓ Git installed" -ForegroundColor Green
}

# 2. Install OpenSSH Client
$sshClient = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'
if ($sshClient.State -eq "Installed") {
    Write-Host "✓ OpenSSH Client already installed" -ForegroundColor Green
} else {
    Write-Host "Installing OpenSSH Client..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
    Write-Host "✓ OpenSSH Client installed" -ForegroundColor Green
}

# 3. Install Java JDK 17
if (Test-Path "C:\Program Files\Java\jdk-17") {
    Write-Host "✓ Java JDK 17 already installed" -ForegroundColor Green
} else {
    Write-Host "Installing Java JDK 17..." -ForegroundColor Yellow
    Write-Host "Please download and install manually from:" -ForegroundColor Yellow
    Write-Host "https://www.oracle.com/java/technologies/downloads/#java17" -ForegroundColor Cyan
    Write-Host "Or use: winget install Oracle.JDK.17" -ForegroundColor Cyan
    
    # Try winget if available
    if (Test-Installed "winget") {
        winget install -e --id Oracle.JDK.17 --silent --accept-source-agreements --accept-package-agreements
    }
}

# Set JAVA_HOME
$javaHome = "C:\Program Files\Java\jdk-17"
if (Test-Path $javaHome) {
    [Environment]::SetEnvironmentVariable("JAVA_HOME", $javaHome, "Machine")
    $env:JAVA_HOME = $javaHome
    Write-Host "✓ JAVA_HOME set to $javaHome" -ForegroundColor Green
}

# 4. Install Maven
if (Test-Path "C:\Program Files\Apache\Maven") {
    Write-Host "✓ Maven already installed" -ForegroundColor Green
} else {
    Write-Host "Installing Maven 3.8.7..." -ForegroundColor Yellow
    $mavenUrl = "https://archive.apache.org/dist/maven/maven-3/3.8.7/binaries/apache-maven-3.8.7-bin.zip"
    $mavenZip = "$tempDir\maven.zip"
    $mavenDir = "C:\Program Files\Apache\Maven"
    
    Download-File -Url $mavenUrl -Output $mavenZip
    Expand-Archive -Path $mavenZip -DestinationPath "C:\Program Files\Apache" -Force
    Rename-Item -Path "C:\Program Files\Apache\apache-maven-3.8.7" -NewName "Maven"
    
    # Add to PATH
    $path = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($path -notlike "*$mavenDir\bin*") {
        [Environment]::SetEnvironmentVariable("Path", "$path;$mavenDir\bin", "Machine")
        $env:Path += ";$mavenDir\bin"
    }
    
    Write-Host "✓ Maven installed" -ForegroundColor Green
}

# 5. Install Python 3.11
if (Test-Installed "python") {
    $pythonVersion = python --version
    Write-Host "✓ Python already installed: $pythonVersion" -ForegroundColor Green
} else {
    Write-Host "Installing Python 3.11..." -ForegroundColor Yellow
    if (Test-Installed "winget") {
        winget install -e --id Python.Python.3.11 --silent --accept-source-agreements --accept-package-agreements
    } else {
        Write-Host "Please install Python manually from: https://www.python.org/downloads/" -ForegroundColor Yellow
    }
}

# 6. Install VSCode
if ($SkipVSCode) {
    Write-Host "⊘ Skipping VSCode installation" -ForegroundColor Gray
} elseif (Test-Installed "code") {
    Write-Host "✓ VSCode already installed" -ForegroundColor Green
} else {
    Write-Host "Installing Visual Studio Code..." -ForegroundColor Yellow
    if (Test-Installed "winget") {
        winget install -e --id Microsoft.VisualStudioCode --silent --accept-source-agreements --accept-package-agreements
    } else {
        Write-Host "Please install VSCode manually from: https://code.visualstudio.com/" -ForegroundColor Yellow
    }
}

# Cleanup
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Close and reopen your terminal to refresh environment variables" -ForegroundColor White
Write-Host "2. Run: git clone https://github.com/alexandremattioli/Build.git C:\Build" -ForegroundColor White
Write-Host "3. Run: cd C:\Build\windows && .\setup_windows.ps1" -ForegroundColor White
Write-Host ""
