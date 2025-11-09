param([string]$RepoPath = "K:\Projects")
$LogRoot = "C:\ProgramData\ProjectSync\GitLogs"; New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$log = Join-Path $LogRoot "start.log"; function Log($m){ "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $m" | Tee-Object -FilePath $log -Append }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git not installed." }
if (-not (Test-Path (Join-Path $RepoPath '.git'))) { throw "Not a git repo: $RepoPath" }
try {
  Log "---- Start Work ----"
  git -C $RepoPath fetch --all --prune | Tee-Object -FilePath $log -Append | Out-Null
  git -C $RepoPath pull --rebase --autostash | Tee-Object -FilePath $log -Append
  if ($LASTEXITCODE -ne 0) { Log "Conflicts during pull. Resolve before coding."; exit 1 }
  Log "Start Work complete."
} catch { Log "Error: $($_.Exception.Message)"; exit 1 }
