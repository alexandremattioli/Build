Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = "K:\Projects\Build"
$impl = Join-Path $repo "Communications\Implementation"
$python = Join-Path $impl ".venv\Scripts\python.exe"
if (-not (Test-Path $python)) { py -3 -m venv (Join-Path $impl ".venv") }
& $python -m pip install --disable-pip-version-check -r (Join-Path $impl "requirements.txt")
$logs = Join-Path $repo "logs"
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$watchHb = Join-Path $logs "watch_messages.heartbeat"
$autoHb = Join-Path $logs "autoresponder_code2.heartbeat"
$stdout = Join-Path $logs "watch_messages.out"
while ($true) {
  try {
    & $python (Join-Path $impl "message_monitor.py") --repo $repo --server "code2" --interval 10 --watch-heartbeat $watchHb --autoresponder-heartbeat $autoHb 2>&1 | Tee-Object -FilePath $stdout -Append
  } catch {
    Add-Content -Path $stdout -Value ("[{0}] monitor crashed: {1}" -f (Get-Date), $_)
  }
  Start-Sleep -Seconds 5
}
