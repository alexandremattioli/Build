param(
    [string]$Path = "$PSScriptRoot\\..\\.secrets\\github_token.dpapi",
    [switch]$AsSecure,
    [switch]$SetEnv
)
if (-not (Test-Path $Path)) { throw "Token file not found at $Path" }
$enc = Get-Content -Raw -Path $Path
$sec = ConvertTo-SecureString $enc
if ($SetEnv) {
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { $p = [Runtime.InteropServices.Marshal]::PtrToStringUni($b) } finally { if ($b -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) } }
    $env:GITHUB_TOKEN = $p
    Write-Output "GITHUB_TOKEN set in current session."
    return
}
if ($AsSecure) { return $sec }
$b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try { [Runtime.InteropServices.Marshal]::PtrToStringUni($b2) } finally { if ($b2 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2) } }
