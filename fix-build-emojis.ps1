# PowerShell script to replace Unicode emojis with ASCII in Build repository
# Run this from the Build repository root directory

$replacements = @{
    '⚠️'  = '[!]'
    '✓'  = '[OK]'
    '✅'  = '[OK]'
    '❌'  = '[X]'
    '🔴' = '[X]'
    '📋' = '[i]'
    'ℹ️'  = '[i]'
    '📝' = '[*]'
    '⚙️'  = '[*]'
}

$files = Get-ChildItem -Path . -Recurse -Include "*.sh","*.md","*.txt" | Where-Object { 
    $_.FullName -notmatch '\\\.git\\' 
}

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $modified = $false
    
    foreach ($emoji in $replacements.Keys) {
        if ($content -match [regex]::Escape($emoji)) {
            $content = $content -replace [regex]::Escape($emoji), $replacements[$emoji]
            $modified = $true
        }
    }
    
    if ($modified) {
        Write-Host "Fixing: $($file.FullName)" -ForegroundColor Green
        Set-Content -Path $file.FullName -Value $content -Encoding UTF8 -NoNewline
    }
}

Write-Host "`nDone! Review changes with: git diff" -ForegroundColor Cyan
