param(
  [int]$Port = 8000
)

$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Clear()
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host "Static server running at $prefix (root: $PSScriptRoot)" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkYellow

function Get-ContentType([string]$path) {
  switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
    ".html" { return "text/html; charset=utf-8" }
    ".htm"  { return "text/html; charset=utf-8" }
    ".css"  { return "text/css" }
    ".js"   { return "application/javascript" }
    ".json" { return "application/json" }
    ".png"  { return "image/png" }
    ".jpg"  { return "image/jpeg" }
    ".jpeg" { return "image/jpeg" }
    default { return "application/octet-stream" }
  }
}

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    $relPath = [Uri]::UnescapeDataString($request.Url.AbsolutePath.TrimStart('/'))
    if ([string]::IsNullOrWhiteSpace($relPath)) { $relPath = 'index.html' }

    $filePath = Join-Path -Path $PSScriptRoot -ChildPath $relPath

    if (Test-Path -Path $filePath -PathType Leaf) {
      try {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $response.ContentType = Get-ContentType $filePath
        $response.ContentLength64 = $bytes.Length
        $response.StatusCode = 200
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
      } catch {
        $response.StatusCode = 500
        $msg = [Text.Encoding]::UTF8.GetBytes("Internal Server Error")
        $response.OutputStream.Write($msg, 0, $msg.Length)
      }
    } else {
      $response.StatusCode = 404
      $msg = [Text.Encoding]::UTF8.GetBytes("Not Found")
      $response.OutputStream.Write($msg, 0, $msg.Length)
    }

    $response.Close()
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
