#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Prepares local VS Code (Windows) for Copilot Chat YOLO one‑click run by disabling Workspace Trust.
  YOLO itself is a Copilot Chat UI toggle; on first run, click YOLO and select
  "Always allow for this workspace" to persist consent.

.DESCRIPTION
  Updates %APPDATA%\Code\User\settings.json to set:
   - "security.workspace.trust.enabled": false
  Creates a timestamped backup before editing.

.NOTES
  Run this on your Windows desktop in a non-SSH, local VS Code workflow.
#>

$ErrorActionPreference = 'Stop'

$settingsDir = Join-Path $env:APPDATA 'Code\User'
$settingsFile = Join-Path $settingsDir 'settings.json'

if (-not (Test-Path $settingsDir)) {
  New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
}

if (-not (Test-Path $settingsFile)) {
  '{}' | Out-File -FilePath $settingsFile -Encoding UTF8 -Force
}

$backup = "$settingsFile.bak.$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
Copy-Item $settingsFile $backup -Force
Write-Host "Backup saved: $backup"

# Load/merge JSON safely without external tools
try {
  $json = Get-Content -Raw -LiteralPath $settingsFile | ConvertFrom-Json -ErrorAction Stop
} catch {
  Write-Error "settings.json is not valid JSON. Please fix and re-run."
  throw
}

if ($null -eq $json) { $json = @{} }
$json.'security.workspace.trust.enabled' = $false

($json | ConvertTo-Json -Depth 20) | Out-File -FilePath $settingsFile -Encoding UTF8 -Force

Write-Host "✓ Workspace Trust disabled in $settingsFile"
Write-Host ""
Write-Host "Next steps (once per workspace):"
Write-Host "  1) Open this repo in local VS Code (not Remote-SSH)."
Write-Host "  2) In Copilot Chat, open the ⋯ menu and enable 'Allow one-click run (YOLO)' if visible."
Write-Host "  3) Click YOLO on a simple command (e.g., git status) and choose 'Always allow for this workspace' when prompted."
Write-Host "  4) Revert by setting security.workspace.trust.enabled to true in settings."
