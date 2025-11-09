# Filename: CodeServer-RemoteSetup.ps1
# One-and-done remote access bootstrap for Windows Server 2019
# - Enables OpenSSH Server + firewall
# - Creates/uses a local admin user, installs your SSH public key
# - Optional WinRM over HTTPS (5986) + firewall
# - Optional RDP enable
# - Installs heartbeat scheduled task (SYSTEM, every 5 minutes)
# - Uninstall supported via -Uninstall
# Safety: Password auth stays enabled by default; flip $DisablePasswordAuthDefault to $true after you verify key login.

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [switch]$Uninstall,
  [switch]$RemoveUser
)

$ErrorActionPreference = 'Stop'

# ========= Defaults you can tweak (no parameters needed) =========
$UserNameDefault = 'buildadmin'
$PublicKeyDefault = @'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEtbG77gQtb713TkgLHno84dAtdJeRimI+44mRw28IbB alexandre@mattioli.co.uk
'@
$DisablePasswordAuthDefault = $false
$EnableWinRmHttpsDefault    = $true
$EnableRdpDefault           = $false
$BaseDirDefault             = $PSScriptRoot
# ================================================================

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw "Run this script as Administrator." }
}

function Ensure-LocalUser {
  param([string]$UserName)
  if (-not $UserName) { throw "UserName required." }
  $user = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
  if (-not $user) {
    $pw = Read-Host -AsSecureString -Prompt "Create a secure password for '$UserName'"
    New-LocalUser -Name $UserName -Password $pw -PasswordNeverExpires:$true -AccountNeverExpires:$true | Out-Null
  }
  try { Add-LocalGroupMember -Group 'Administrators' -Member $UserName -ErrorAction Stop } catch {}
}

function Ensure-OpenSSH {
  $existingSvc = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue
  if ($existingSvc) {
    Write-Host "OpenSSH Server service found. Skipping capability install."
    try { Set-Service sshd -StartupType Automatic } catch {}
    try { Start-Service sshd -ErrorAction SilentlyContinue } catch {}
    try { Set-Service ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service ssh-agent -ErrorAction SilentlyContinue } catch {}
    $fwByName = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    $fwByDisp = Get-NetFirewallRule -DisplayName 'OpenSSH Server (sshd)' -ErrorAction SilentlyContinue
    if ($fwByName -or $fwByDisp) { @($fwByName,$fwByDisp) | Where-Object { $_ } | Enable-NetFirewallRule | Out-Null }
    else { New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null }
    return
  }
  $cap = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
  if (-not $cap -or $cap.State -ne 'Installed') {
    Write-Host "Installing OpenSSH Server..."
    Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
  } else { Write-Host "OpenSSH Server already installed." }
  Start-Service sshd -ErrorAction SilentlyContinue
  Set-Service sshd -StartupType Automatic
  Set-Service ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
  Start-Service ssh-agent -ErrorAction SilentlyContinue
  $fwByName2 = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
  $fwByDisp2 = Get-NetFirewallRule -DisplayName 'OpenSSH Server (sshd)' -ErrorAction SilentlyContinue
  if ($fwByName2 -or $fwByDisp2) { @($fwByName2,$fwByDisp2) | Where-Object { $_ } | Enable-NetFirewallRule | Out-Null }
  else { New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null }
}

function Get-UserProfilePath {
  param([string]$UserName)
  $user = Get-LocalUser -Name $UserName -ErrorAction Stop
  $sid  = $user.SID.Value
  $prof = Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $sid }
  if ($prof -and $prof.LocalPath) { return $prof.LocalPath }
  $fallback = "C:\Users\$UserName"
  if (-not (Test-Path $fallback)) { try { New-Item -ItemType Directory -Path $fallback -Force | Out-Null } catch {} }
  if (Test-Path $fallback) { return $fallback }
  throw "Cannot locate or create profile folder for $UserName. Log on once interactively to initialize the profile, then rerun."
}

function Install-AuthorizedKey {
  param([string]$UserName,[string]$PublicKey)
  if (-not $PublicKey) { throw "Public key content is empty." }
  $profile = Get-UserProfilePath -UserName $UserName
  $sshDir  = Join-Path $profile '.ssh'
  $auth    = Join-Path $sshDir 'authorized_keys'
  if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }
  $pubLine = $PublicKey.Trim()
  if (Test-Path $auth) {
    $existing = Get-Content -Path $auth -ErrorAction SilentlyContinue
    if ($existing -notcontains $pubLine) { $pubLine | Out-File -FilePath $auth -Encoding ascii -Append }
  } else { $pubLine | Out-File -FilePath $auth -Encoding ascii }
  # REQUIRED PERMISSIONS: user + SYSTEM only; no inheritance; file must be ascii without BOM.
  icacls $sshDir /inheritance:r | Out-Null
  icacls $sshDir /grant "$UserName:(OI)(CI)(F)" "SYSTEM:(OI)(CI)(F)" | Out-Null
  icacls $auth  /inheritance:r | Out-Null
  icacls $auth  /grant "$UserName:(R,W)" "SYSTEM:(R,W)" | Out-Null
  Write-Host "authorized_keys installed for $UserName"
}

function Configure-SSHD {
  param([string]$UserName,[bool]$DisablePasswordAuth)
  $cfg = 'C:\ProgramData\ssh\sshd_config'
  if (-not (Test-Path $cfg)) { throw "sshd_config not found at $cfg" }
  $lines = Get-Content $cfg
  $backup = "$cfg.bak"
  if (-not (Test-Path $backup)) { Copy-Item $cfg $backup }
  function Upsert($Key,$Value){ $pattern = "^\s*#?\s*$([regex]::Escape($Key))\b.*$"; $idx = -1; for ($i=0;$i -lt $lines.Count;$i++){ if ($lines[$i] -match $pattern){ $idx=$i; break } }; if ($idx -ge 0){ $lines[$idx] = "$Key $Value" } else { $script:lines += "$Key $Value" } }
  Upsert 'PubkeyAuthentication' 'yes'
  if ($DisablePasswordAuth){ Upsert 'PasswordAuthentication' 'no' } else { if ($lines -notmatch '^\s*PasswordAuthentication\b'){ $script:lines += 'PasswordAuthentication yes' } }
  if ($lines -notmatch '^\s*AuthorizedKeysFile\b'){ $script:lines += 'AuthorizedKeysFile .ssh/authorized_keys' }
  if ($lines -notmatch '^\s*AllowUsers\b'){ $script:lines += "AllowUsers $UserName" } else { $script:lines = $script:lines -replace '^(#?\s*AllowUsers\s+.*)$', "`$1 $UserName" }
  if ($lines -notmatch '^\s*UseDNS\b'){ $script:lines += 'UseDNS no' }
  if ($lines -notmatch '^\s*GSSAPIAuthentication\b'){ $script:lines += 'GSSAPIAuthentication no' }
  Set-Content -Path $cfg -Value $lines -Encoding ascii
  Restart-Service sshd
  Write-Host "sshd_config updated. sshd restarted."
}

function Ensure-WinRM-HTTPS {
  Write-Host "Enabling PowerShell Remoting..."
  Enable-PSRemoting -Force | Out-Null
  $httpsExists = (winrm enumerate winrm/config/Listener) 2>$null | Select-String 'Transport = HTTPS'
  if ($httpsExists){ Write-Host "WinRM HTTPS listener already exists."; return }
  $hostname = (Get-CimInstance Win32_ComputerSystem).DNSHostName
  $domain   = (Get-CimInstance Win32_ComputerSystem).Domain
  $dnsName  = if ($domain -and $domain -ne $hostname){ "$hostname.$domain" } else { $hostname }
  Write-Host "Creating self-signed certificate for $dnsName ..."
  $cert = New-SelfSignedCertificate -DnsName $dnsName -CertStoreLocation Cert:\LocalMachine\My -KeyLength 2048 -HashAlgorithm sha256 -FriendlyName "WinRM HTTPS ($dnsName)"
  $thumb = $cert.Thumbprint
  Write-Host "Configuring WinRM HTTPS listener..."
  winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=\"$dnsName\"; CertificateThumbprint=\"$thumb\"}" 2>$null | Out-Null
  if (-not (Get-NetFirewallRule -DisplayName 'WinRM (HTTPS-In)' -ErrorAction SilentlyContinue)){ New-NetFirewallRule -Name 'WinRM-HTTPS-In' -DisplayName 'WinRM (HTTPS-In)' -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5986 | Out-Null }
  Write-Host "WinRM HTTPS ready on 5986."
}

function Install-Heartbeat {
  param([string]$BaseDir)
  $opsDir = Join-Path $BaseDir 'CopilotOps'; $binDir = Join-Path $opsDir 'bin'; $logDir = Join-Path $opsDir 'logs'
  New-Item -ItemType Directory -Force -Path $binDir | Out-Null
  New-Item -ItemType Directory -Force -Path $logDir | Out-Null
  $hbPath = Join-Path $binDir 'heartbeat.ps1'
  $hb = @'
$ErrorActionPreference = "SilentlyContinue"
$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$os  = Get-CimInstance Win32_OperatingSystem
$uptime = (Get-Date) - $os.LastBootUpTime
$cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1).CounterSamples.CookedValue
$memUsedGB  = "{0:N2}" -f (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/1MB)
$memTotalGB = "{0:N2}" -f ($os.TotalVisibleMemorySize/1MB)
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$ip = (Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp -ErrorAction SilentlyContinue | Where-Object {$_.IPAddress -notlike '169.*'} | Select-Object -First 1 -ExpandProperty IPAddress)
if (-not $ip){ $ip = (Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred -ErrorAction SilentlyContinue | Where-Object {$_.IPAddress -notlike '169.*'} | Select-Object -First 1 -ExpandProperty IPAddress) }
$line = [pscustomobject]@{ Timestamp=$now; Hostname=$env:COMPUTERNAME; IP=$ip; UptimeMin=[int]$uptime.TotalMinutes; CPU=[int]$cpu; MemUsedGB=$memUsedGB; MemTotGB=$memTotalGB; DiskCFreeGB = if ($disk.FreeSpace){ "{0:N2}" -f ($disk.FreeSpace/1GB) } else { $null } }
$logDir = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) '..\logs'
$log    = Join-Path $logDir ("heartbeat-"+(Get-Date -Format 'yyyyMMdd')+".log")
$line | ConvertTo-Json -Compress | Add-Content -Path $log
'@
  Set-Content -Path $hbPath -Value $hb -Encoding UTF8
  $taskName = 'CopilotHeartbeat'
  $action   = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$hbPath`""
  $trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration ([TimeSpan]::MaxValue)
  $principal= New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
  if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue){ Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal | Out-Null
  Write-Host "Heartbeat installed. Logs in: $logDir"
}

function Disable-OpenSSH { if (Get-Service sshd -ErrorAction SilentlyContinue){ Stop-Service sshd -ErrorAction SilentlyContinue; Set-Service sshd -StartupType Disabled -ErrorAction SilentlyContinue }; if (Get-NetFirewallRule -DisplayName 'OpenSSH Server (sshd)' -ErrorAction SilentlyContinue){ Get-NetFirewallRule -DisplayName 'OpenSSH Server (sshd)' | Disable-NetFirewallRule | Out-Null } }
function Remove-WinRMHttps { try { $listeners = (winrm enumerate winrm/config/Listener) 2>$null; if ($listeners){ $https = $listeners | Select-String 'Listener' -Context 0,4 | ForEach-Object { if ($_.Context.PostContext -match 'Transport = HTTPS'){ $_ } }; foreach ($entry in $https){ $line = $entry.Line; if ($line -match 'Listener\s+(\{[^\}]+\})'){ winrm delete "winrm/config/Listener?$($Matches[1])" 2>$null | Out-Null } } } } catch { Write-Host "WinRM cleanup warning: $_" -ForegroundColor Yellow }; if (Get-NetFirewallRule -DisplayName 'WinRM (HTTPS-In)' -ErrorAction SilentlyContinue){ Get-NetFirewallRule -DisplayName 'WinRM (HTTPS-In)' | Disable-NetFirewallRule | Out-Null } }
function Remove-Heartbeat { $task = Get-ScheduledTask -TaskName 'CopilotHeartbeat' -ErrorAction SilentlyContinue; if ($task){ Unregister-ScheduledTask -TaskName 'CopilotHeartbeat' -Confirm:$false }; $opsDir = Join-Path $BaseDirDefault 'CopilotOps'; if (Test-Path $opsDir){ Remove-Item -Recurse -Force $opsDir } }
function Uninstall-All { param([string]$UserName,[switch]$RemoveUser); Disable-OpenSSH; Remove-WinRMHttps; Remove-Heartbeat; if ($RemoveUser -and $UserName){ try { Remove-LocalGroupMember -Group 'Administrators' -Member $UserName -ErrorAction SilentlyContinue; Remove-LocalUser -Name $UserName -ErrorAction SilentlyContinue } catch { Write-Host "User cleanup warning: $_" -ForegroundColor Yellow } }; Write-Host 'Uninstall complete.' }

try {
  Assert-Admin
  if ($Uninstall){ Uninstall-All -UserName $UserNameDefault -RemoveUser:$RemoveUser; return }
  Ensure-LocalUser -UserName $UserNameDefault
  Ensure-OpenSSH
  Install-AuthorizedKey -UserName $UserNameDefault -PublicKey $PublicKeyDefault
  Configure-SSHD -UserName $UserNameDefault -DisablePasswordAuth:[bool]$DisablePasswordAuthDefault
  if ($EnableWinRmHttpsDefault){ Ensure-WinRM-HTTPS }
  if ($EnableRdpDefault){ Write-Host 'Enabling RDP and firewall...'; Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0; Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' | Out-Null }
  Install-Heartbeat -BaseDir $BaseDirDefault
  Write-Host "`nSUCCESS: Remote access configured."
  Write-Host ("Test SSH: ssh {0}@{1}" -f $UserNameDefault,(hostname))
  Write-Host 'To harden later, edit this script: set $DisablePasswordAuthDefault = $true and run again.'
} catch { Write-Error $_; exit 1 }
