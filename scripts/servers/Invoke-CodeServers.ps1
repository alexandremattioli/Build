[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [scriptblock]$ScriptBlock,
  [string[]]$Name,
  [switch]$UseSSL,
  [int]$Port,
  [System.Management.Automation.PSCredential]$Credential
)
$servers = & "$PSScriptRoot/Get-CodeServers.ps1" -Name $Name
$cred = $Credential
if (-not $cred) { $cred = & "$PSScriptRoot/Get-CodeCredential.ps1" }
$results = @()
foreach ($s in $servers) {
  $opts = @{ ComputerName=$s.Host; Credential=$cred; ErrorAction='Stop' }
  if ($UseSSL) { $opts['UseSSL'] = $true }
  if ($Port) { $opts['Port'] = $Port }
  try {
    $res = Invoke-Command @opts -ScriptBlock $ScriptBlock
    $results += [pscustomobject]@{ Name=$s.Name; Host=$s.Host; Success=$true; Result=$res }
  } catch {
    $results += [pscustomobject]@{ Name=$s.Name; Host=$s.Host; Success=$false; Error=$_.Exception.Message }
  }
}
$results
