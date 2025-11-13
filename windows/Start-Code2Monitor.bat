@echo off
REM Start-Code2Monitor.bat
REM Startup script to launch Code2 message monitor on boot
REM Install: Place shortcut to this file in shell:startup folder

cd /d K:\Projects\Build

echo Starting Code2 Message Monitor...
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Job -Name 'Code2Monitor' -ScriptBlock { Set-Location 'K:\Projects\Build'; .\windows\scripts\Start-MessageMonitor.ps1 } | Out-Null; Write-Host 'Code2 Monitor started in background' -ForegroundColor Green; Start-Sleep -Seconds 2"

echo Monitor started. Launching health check system...
start /min powershell.exe -ExecutionPolicy Bypass -NoExit -Command "K:\Projects\Build\windows\scripts\Start-MonitorWithHealthCheck.ps1"

echo.
echo Code2 Monitor and Health Check system are now running.
echo Health check runs in minimized window for monitoring.
timeout /t 3
