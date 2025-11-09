param(
  [string]$RepoPath = "K:\Projects",
  [string]$LogRoot = "C:\ProgramData\ProjectSync\GitLogs",
  [string]$CommitMessage
)
New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
$log = Join-Path $LogRoot "push.log"
function Log($m){ "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $m" | Tee-Object -FilePath $log -Append }

if (-not (Test-Path (Join-Path $RepoPath '.git'))) { throw "Not a git repo: $RepoPath" }

$git = "git"
try {
  $status = & $git -C $RepoPath status --porcelain
  if (-not $status) { Log "No changes to commit"; exit 0 }

  $u = & $git -C $RepoPath config user.name
  $e = & $git -C $RepoPath config user.email
  if (-not $u) { & $git -C $RepoPath config user.name ("$env:USERNAME on $env:COMPUTERNAME") | Out-Null }
  if (-not $e) { & $git -C $RepoPath config user.email ("$env:USERNAME@$env:COMPUTERNAME.local") | Out-Null }

  & $git -C $RepoPath add -A | Out-Null
  if (-not $CommitMessage) { $CommitMessage = "autosave: $env:COMPUTERNAME $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
  Log ("Committing: '" + $CommitMessage + "'")
  & $git -C $RepoPath commit -m $CommitMessage | Tee-Object -FilePath $log -Append | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "git commit failed" }

  Log "Rebasing onto remote"
  & $git -C $RepoPath pull --rebase --autostash | Tee-Object -FilePath $log -Append | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "git pull --rebase failed; resolve conflicts manually" }

  Log "Pushing"
  & $git -C $RepoPath push | Tee-Object -FilePath $log -Append | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "git push failed" }
  Log "Push complete"
} catch {
  Log ("Error: " + $_.Exception.Message)
  exit 1
}
