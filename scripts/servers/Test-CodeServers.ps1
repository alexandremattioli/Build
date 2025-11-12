param(
  [string[]]$Name
)
$servers = & "$PSScriptRoot/Get-CodeServers.ps1" -Name $Name
$results = foreach ($s in $servers) {
  $ping = Test-Connection -ComputerName $s.Host -Count 1 -Quiet -ErrorAction SilentlyContinue
  $winrm = $null; try { $null = Test-WSMan -ComputerName $s.Host -ErrorAction Stop; $winrm = $true } catch { $winrm = $false }
  $rdp = (Test-NetConnection -ComputerName $s.Host -Port 3389 -WarningAction SilentlyContinue).TcpTestSucceeded
  [pscustomobject]@{ Name=$s.Name; Host=$s.Host; Ping=$ping; WinRM=$winrm; RDP3389=$rdp }
}
$results | Format-Table -AutoSize
