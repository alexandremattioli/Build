param(
  [string]$RepoPath = "K:\Projects",
  [string]$LogRoot = "C:\ProgramData\ProjectSync\GitLogs"
)
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$log = Join-Path $LogRoot "pull.log"
function Log($m){ "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $m" | Tee-Object -FilePath $log -Append }
if (-not (Test-Path (Join-Path $RepoPath '.git'))) { throw "Not a git repo: $RepoPath" }
$dirty = (git -C $RepoPath status --porcelain)
if ($dirty) { Log "Stashing local changes"; git -C $RepoPath stash push -u -m "scheduled-pull-$(Get-Date -Format yyyyMMdd-HHmmss)" | Out-Null }
Log "Pulling with rebase"; git -C $RepoPath pull --rebase --autostash | Tee-Object -FilePath $log -Append
if ($dirty) { Log "Attempting stash pop"; git -C $RepoPath stash pop | Tee-Object -FilePath $log -Append }
Log "Pull cycle complete"
