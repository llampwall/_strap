# Fix stray closing braces in test files

$testPath = "P:\software\_strap\tests\powershell"

# Define files with stray closing braces and the lines to check
$filesToFix = @(
    @{ File = "ChinvexContexts.Tests.ps1"; Line = 276 },
    @{ File = "ChinvexIdempotency.Tests.ps1"; Line = 337 },
    @{ File = "ChinvexMove.Tests.ps1"; Line = 379 },
    @{ File = "ChinvexRename.Tests.ps1"; Line = 310 },
    @{ File = "ChinvexUninstall.Tests.ps1"; Line = 305 },
    @{ File = "Invoke-Audit.Tests.ps1"; Line = 50 },
    @{ File = "Invoke-Audit.Tests.ps1"; Line = 158 },
    @{ File = "Invoke-Snapshot.Tests.ps1"; Line = 54 },
    @{ File = "Invoke-Snapshot.Tests.ps1"; Line = 147 }
)

foreach ($item in $filesToFix) {
    $filePath = Join-Path $testPath $item.File
    $lines = Get-Content $filePath

    # Check if the line is just whitespace + closing brace
    $lineIndex = $item.Line - 1  # Convert to 0-based index
    if ($lineIndex -lt $lines.Count) {
        $line = $lines[$lineIndex]

        # If line is just whitespace and a closing brace, check context
        if ($line -match '^\s*}\s*$') {
            Write-Host "Checking $($item.File):$($item.Line) - '$line'" -ForegroundColor Cyan

            # Get surrounding lines for context
            $before = if ($lineIndex -gt 0) { $lines[$lineIndex - 1] } else { "" }
            $after = if ($lineIndex + 1 -lt $lines.Count) { $lines[$lineIndex + 1] } else { "" }

            Write-Host "  Before: $before" -ForegroundColor Gray
            Write-Host "  Line:   $line" -ForegroundColor Yellow
            Write-Host "  After:  $after" -ForegroundColor Gray

            # If the line before is also a closing brace, or line after is blank/comment,
            # this is likely a stray brace
            if ($before -match '^\s*}\s*$' -or $after -match '^\s*$' -or $after -match '^\s*#') {
                Write-Host "  ACTION: Removing stray brace" -ForegroundColor Red
                # Remove the line
                $lines = $lines[0..($lineIndex-1)] + $lines[($lineIndex+1)..($lines.Count-1)]
                Set-Content -Path $filePath -Value $lines
                Write-Host "  FIXED: $($item.File):$($item.Line)" -ForegroundColor Green
            } else {
                Write-Host "  SKIP: Context unclear, manual review needed" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Line $($item.Line) in $($item.File) is not a simple closing brace" -ForegroundColor Magenta
        }
    }
}

Write-Host "`nDone. Re-run parse error checker to verify." -ForegroundColor Cyan
