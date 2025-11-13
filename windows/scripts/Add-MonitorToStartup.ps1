# Add-MonitorToStartup.ps1
# Adds Code2 monitor to Windows startup

$ErrorActionPreference = "Stop"

$batchFile = "K:\Projects\Build\windows\Start-Code2Monitor.bat"
$startupFolder = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupFolder "Code2-Monitor.lnk"

Write-Host "Creating startup shortcut..." -ForegroundColor Yellow

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($shortcutPath)
$Shortcut.TargetPath = $batchFile
$Shortcut.WorkingDirectory = "K:\Projects\Build"
$Shortcut.Description = "Code2 Message Monitor - Auto-start"
$Shortcut.WindowStyle = 7  # Minimized
$Shortcut.Save()

Write-Host "✓ Startup shortcut created at: $shortcutPath" -ForegroundColor Green
Write-Host "`nMonitor will start automatically on next system boot." -ForegroundColor Cyan
Write-Host "To test now, run: K:\Projects\Build\windows\Start-Code2Monitor.bat" -ForegroundColor Gray
