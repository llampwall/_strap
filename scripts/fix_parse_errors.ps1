# Fix parse errors in test files - remove malformed try-catch blocks

$brokenFiles = @(
    "Invoke-Snapshot.Tests.ps1",
    "Invoke-Audit.Tests.ps1",
    "ChinvexCLIDispatch.Tests.ps1",
    "ChinvexContexts.Tests.ps1",
    "ChinvexIdempotency.Tests.ps1",
    "ChinvexMove.Tests.ps1",
    "ChinvexRename.Tests.ps1",
    "ChinvexSync.Tests.ps1",
    "ChinvexUninstall.Tests.ps1"
)

$testDir = "P:\software\_strap\tests\powershell"

foreach ($fileName in $brokenFiles) {
    $filePath = Join-Path $testDir $fileName
    if (-not (Test-Path $filePath)) {
        Write-Host "File not found: $fileName" -ForegroundColor Yellow
        continue
    }

    Write-Host "Fixing $fileName..."
    $content = Get-Content $filePath -Raw

    # Remove the malformed catch block pattern
    # Pattern: . "$modulesPath\CLI.ps1" catch { ... }
    $content = $content -replace '(\. "\$modulesPath\\CLI\.ps1")\s*catch\s*\{[^}]*\}', '$1'

    # Ensure Commands.ps1 is imported if CLI.ps1 is present
    if ($content -match '\. "\$modulesPath\\CLI\.ps1"' -and
        $content -notmatch '\. "\$modulesPath\\Commands\.ps1"') {
        $content = $content -replace '(\. "\$modulesPath\\CLI\.ps1")', '$1' + "`n        . `"`$modulesPath\Commands.ps1`""
    }

    Set-Content -Path $filePath -Value $content -NoNewline
    Write-Host "  Fixed!" -ForegroundColor Green
}

Write-Host "`nDone!"
