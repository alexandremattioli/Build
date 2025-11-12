param(
  [switch]$Save,
  [string]$StorePath = "$PSScriptRoot/../../.secrets/code_pscredential.xml"
)
if ($Save) {
  if (-not (Test-Path (Split-Path -Parent $StorePath))) { New-Item -ItemType Directory (Split-Path -Parent $StorePath) | Out-Null }
  $u = Read-Host 'Username'
  $p = Read-Host 'Password' -AsSecureString
  $cred = New-Object System.Management.Automation.PSCredential($u,$p)
  $cred | Export-Clixml -Path $StorePath
  Write-Output "Saved credential to $StorePath (DPAPI user+machine bound)."
} else {
  if (-not (Test-Path $StorePath)) { throw "Credential file not found: $StorePath. Run with -Save to create it." }
  Import-Clixml -Path $StorePath
}
