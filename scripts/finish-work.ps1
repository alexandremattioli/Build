param([string]$RepoPath = "K:\Projects",[string]$Message,[switch]$FullSnapshot,[int]$SnapshotRetention = 10)
$LogRoot = "C:\ProgramData\ProjectSync\GitLogs"; New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$log = Join-Path $LogRoot "finish.log"; function Log($m){ "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $m" | Tee-Object -FilePath $log -Append }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git not installed." }
if (-not (Test-Path (Join-Path $RepoPath '.git'))) { throw "Not a git repo: $RepoPath" }
if (-not $Message) { $Message = "Finish work on $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
try {
  Log "---- Finish Work ----"
  git -C $RepoPath fetch --all --prune | Tee-Object -FilePath $log -Append | Out-Null
  $branch = (git -C $RepoPath rev-parse --abbrev-ref HEAD).Trim(); if ($branch -eq "HEAD") { throw "Detached HEAD." }
  $dirty = git -C $RepoPath status --porcelain
  if ($dirty) { Log "Staging & committing"; git -C $RepoPath add -A | Out-Null; git -C $RepoPath commit -m $Message | Tee-Object -FilePath $log -Append }
  else { Log "No changes to commit." }
  if ($FullSnapshot) {
    $snapDir = Join-Path $RepoPath "snapshots"; New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"; $zipName = "snapshot-$ts-$env:COMPUTERNAME.zip"; $zipPath = Join-Path $snapDir $zipName
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $RepoPath '*') -DestinationPath $zipPath -Force
    $existing = Get-ChildItem $snapDir -Filter "snapshot-*.zip" | Sort-Object LastWriteTime -Descending
    if ($existing.Count -gt $SnapshotRetention) { $existing | Select-Object -Skip $SnapshotRetention | Remove-Item -Force }
    $giPath = Join-Path $RepoPath ".gitignore"; if (Test-Path $giPath) { $gi = Get-Content $giPath; if ($gi -notcontains "snapshots/") { Add-Content -Path $giPath -Value "snapshots/" } }
    git -C $RepoPath add -f "snapshots/$zipName" | Out-Null; git -C $RepoPath commit -m "Snapshot: $zipName" | Tee-Object -FilePath $log -Append
  }
  git -C $RepoPath pull --rebase --autostash | Tee-Object -FilePath $log -Append
  if ($LASTEXITCODE -ne 0) { Log "Rebase conflicts. Resolve then push."; exit 1 }
  git -C $RepoPath push | Tee-Object -FilePath $log -Append
  Log "Finish Work complete."
} catch { Log "Error: $($_.Exception.Message)"; exit 1 }
