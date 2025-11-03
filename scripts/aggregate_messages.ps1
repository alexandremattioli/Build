$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$MsgDir = Join-Path $Root 'messages'
$StatusFile = Join-Path $Root 'MESSAGES_STATUS.md'
$AllFile = Join-Path $Root 'MESSAGES_ALL.txt'

if (-not (Test-Path $MsgDir)) {
  Write-Error "messages directory not found: $MsgDir"
}

function Get-Field {
  param(
    [string]$Content,
    [string]$Key
  )
  ($Content -split "`n" | Where-Object { $_ -match "^$Key\s*:\s*" } | Select-Object -First 1 | ForEach-Object { ($_ -replace "^$Key\s*:\s*", '') -replace "\r$", '' })
}

$files = Get-ChildItem -Path $MsgDir -File -Filter *.txt | Sort-Object Name

# Build status markdown
$lines = @()
$lines += '# Messages Status'
$lines += ''
$lines += 'Generated: ' + (Get-Date).ToUniversalTime().ToString('s') + 'Z'
$lines += ''
$lines += ('Total messages: ' + ($files | Measure-Object | Select-Object -ExpandProperty Count))
$lines += ''
$lines += '| File | TO | FROM | PRIORITY | TYPE | TIMESTAMP | SUBJECT |'
$lines += '|------|----|------|----------|------|-----------|---------|'
foreach ($f in $files) {
  $c = Get-Content -Raw -Path $f.FullName
  $to = Get-Field -Content $c -Key 'TO'
  $from = Get-Field -Content $c -Key 'FROM'
  $prio = Get-Field -Content $c -Key 'PRIORITY'
  $type = Get-Field -Content $c -Key 'TYPE'
  $ts = Get-Field -Content $c -Key 'TIMESTAMP'
  $subj = Get-Field -Content $c -Key 'SUBJECT'
  if ($null -ne $subj) { $subj = $subj -replace '\|', '\|' }
  $lines += "| $($f.Name) | $to | $from | $prio | $type | $ts | $subj |"
}
Set-Content -Path $StatusFile -Value $lines -NoNewline:$false -Encoding UTF8

# Build concatenated messages
$out = @()
$out += ('===== ALL MESSAGES (Generated ' + (Get-Date).ToUniversalTime().ToString('s') + 'Z UTC) =====')
$out += ''
foreach ($f in $files) {
  $out += ('----- FILE: ' + $f.Name + ' -----')
  $out += (Get-Content -Raw -Path $f.FullName)
  $out += ''
}
Set-Content -Path $AllFile -Value $out -NoNewline:$false -Encoding UTF8

Write-Output "Wrote $StatusFile"
Write-Output "Wrote $AllFile"
