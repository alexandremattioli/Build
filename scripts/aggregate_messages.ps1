$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$MsgDir = Join-Path $Root 'messages'
$CoordFile = Join-Path $Root 'coordination/messages.json'
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
$coordMessages = @()
if (Test-Path $CoordFile) {
  $coordData = Get-Content -Raw -Path $CoordFile | ConvertFrom-Json
  if ($null -ne $coordData.messages) {
    $coordMessages = $coordData.messages | Sort-Object { $_.timestamp }
  }
}

# Build status markdown
$lines = @()
$lines += '# Messages Status'
$lines += ''
$lines += 'Generated: ' + (Get-Date).ToUniversalTime().ToString('s') + 'Z'
$lines += ''
$lines += ('Text message files: ' + ($files | Measure-Object | Select-Object -ExpandProperty Count))
if ($coordMessages.Count -gt 0) {
  $lines += ('Coordination messages: ' + $coordMessages.Count)
}
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
if ($coordMessages.Count -gt 0) {
  $lines += ''
  $lines += '## Coordination Thread (coordination/messages.json)'
  $lines += ''
  $unread = @{
    build1 = ($coordMessages | Where-Object { (($_.to -eq 'build1') -or ($_.to -eq 'all')) -and ($_.read -ne $true) }).Count
    build2 = ($coordMessages | Where-Object { (($_.to -eq 'build2') -or ($_.to -eq 'all')) -and ($_.read -ne $true) }).Count
    build3 = ($coordMessages | Where-Object { (($_.to -eq 'build3') -or ($_.to -eq 'all')) -and ($_.read -ne $true) }).Count
    build4 = ($coordMessages | Where-Object { (($_.to -eq 'build4') -or ($_.to -eq 'all')) -and ($_.read -ne $true) }).Count
  }
  $lines += ('Total messages: ' + $coordMessages.Count)
  $lines += ("Unread: build1={0} build2={1} build3={2} build4={3}" -f $unread.build1, $unread.build2, $unread.build3, $unread.build4)
  $lines += ''
  $lines += '| ID | FROM | TO | TYPE | PRIORITY | TIMESTAMP | SUBJECT | READ |'
  $lines += '|----|------|----|------|----------|-----------|---------|------|'
  foreach ($msg in $coordMessages) {
    $priority = if ($null -ne $msg.priority -and $msg.priority -ne '') { $msg.priority } else { 'normal' }
    $subject = if ($null -ne $msg.subject) { $msg.subject -replace '\|', '\|' } else { '' }
    $readFlag = if ($msg.read) { 'yes' } else { 'no' }
    $lines += "| $($msg.id) | $($msg.from) | $($msg.to) | $($msg.type) | $priority | $($msg.timestamp) | $subject | $readFlag |"
  }
}
Set-Content -Path $StatusFile -Value $lines -NoNewline:$false -Encoding UTF8

# Build concatenated messages
$out = @()
$out += ('===== ALL MESSAGES (Generated ' + (Get-Date).ToUniversalTime().ToString('s') + 'Z UTC) =====')
$out += ''
$out += '--- TEXT FILES (messages/*.txt) ---'
$out += ''
foreach ($f in $files) {
  $out += ('----- FILE: ' + $f.Name + ' -----')
  $out += (Get-Content -Raw -Path $f.FullName)
  $out += ''
}
if ($coordMessages.Count -gt 0) {
  $out += '--- COORDINATION THREAD (coordination/messages.json) ---'
  $out += ''
  foreach ($msg in $coordMessages) {
    $priority = if ($null -ne $msg.priority -and $msg.priority -ne '') { $msg.priority } else { 'normal' }
    $readFlag = if ($msg.read) { 'yes' } else { 'no' }
    $out += ('----- MESSAGE: ' + $msg.id + ' -----')
    $out += ('FROM: ' + $msg.from)
    $out += ('TO: ' + $msg.to)
    $out += ('TYPE: ' + $msg.type)
    $out += ('PRIORITY: ' + $priority)
    $out += ('TIMESTAMP: ' + $msg.timestamp)
    $out += ('READ: ' + $readFlag)
    $out += ''
    $out += ('SUBJECT: ' + ($msg.subject))
    $out += ''
    if ([string]::IsNullOrWhiteSpace($msg.body)) {
      $out += 'BODY: (empty)'
    } else {
      $out += 'BODY:'
      $out += ($msg.body -split "`r?`n")
    }
    $out += ''
  }
}
Set-Content -Path $AllFile -Value $out -NoNewline:$false -Encoding UTF8

Write-Output "Wrote $StatusFile"
Write-Output "Wrote $AllFile"
