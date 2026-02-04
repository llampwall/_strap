# Check which test files are missing Commands.ps1 import

$testDir = "P:\software\_strap\tests\powershell"
$testFiles = Get-ChildItem $testDir -Filter "*.Tests.ps1"

Write-Host "Checking for Commands.ps1 imports:`n"

$missing = @()
foreach ($file in $testFiles) {
    $content = Get-Content $file.FullName -Raw
    $hasCommands = $content -match 'Commands\.ps1'

    if (-not $hasCommands) {
        Write-Host "$($file.Name) - MISSING" -ForegroundColor Red
        $missing += $file.Name
    } else {
        Write-Host "$($file.Name) - OK" -ForegroundColor Green
    }
}

Write-Host "`n$($missing.Count) files missing Commands.ps1"
if ($missing.Count -gt 0) {
    Write-Host "`nMissing files:"
    $missing | ForEach-Object { Write-Host "  $_" }
}
