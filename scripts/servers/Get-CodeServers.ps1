param(
  [string]$Path = "$PSScriptRoot/servers.json",
  [string[]]$Name
)
if (-not (Test-Path $Path)) { throw "Servers file not found: $Path" }
$data = Get-Content -Raw -Path $Path | ConvertFrom-Json
if ($Name) { $data | Where-Object { $_.Name -in $Name } } else { $data }
