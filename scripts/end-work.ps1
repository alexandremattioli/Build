param([string]$RepoPath = "K:\Projects")
$LogRoot = "C:\ProgramData\ProjectSync\GitLogs"; New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$log = Join-Path $LogRoot "end.log"; function Log($m){ "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $m" | Tee-Object -FilePath $log -Append }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git not installed." }
if (-not (Test-Path (Join-Path $RepoPath '.git'))) { throw "Not a git repo: $RepoPath" }
try {
  Log "---- End Work ----"
  git -C $RepoPath add -A | Tee-Object -FilePath $log -Append | Out-Null
  $status = git -C $RepoPath status --porcelain
  if ($status) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git -C $RepoPath commit -m "Auto-commit: $timestamp" | Tee-Object -FilePath $log -Append
    git -C $RepoPath push | Tee-Object -FilePath $log -Append
    Log "Changes committed and pushed."
  } else {
    Log "No changes to commit."
  }
  Log "End Work complete."
} catch { Log "Error: $($_.Exception.Message)"; exit 1 }
