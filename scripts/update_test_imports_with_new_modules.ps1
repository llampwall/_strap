# Update all test files to include new module imports

$testDir = "P:\software\_strap\tests\powershell"
$testFiles = Get-ChildItem $testDir -Filter "*.Tests.ps1"

foreach ($file in $testFiles) {
    $content = Get-Content $file.FullName -Raw

    # Check if it has module imports
    if ($content -match '\. "\$modulesPath\\Commands\.ps1"') {
        # Add new modules before Commands.ps1
        $content = $content -replace '(\. "\$modulesPath\\CLI\.ps1")', "`$1`n        . `"`$modulesPath\References.ps1`"`n        . `"`$modulesPath\Audit.ps1`"`n        . `"`$modulesPath\Consolidate.ps1`""

        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Updated $($file.Name)" -ForegroundColor Green
    } elseif ($content -match '\. "\$modulesPath\\CLI\.ps1"') {
        # Has CLI but not Commands, add all three plus Commands
        $content = $content -replace '(\. "\$modulesPath\\CLI\.ps1")', "`$1`n        . `"`$modulesPath\References.ps1`"`n        . `"`$modulesPath\Audit.ps1`"`n        . `"`$modulesPath\Consolidate.ps1`"`n        . `"`$modulesPath\Commands.ps1`""

        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "Updated $($file.Name) (added new modules + Commands)" -ForegroundColor Green
    } else {
        Write-Host "Skipped $($file.Name) - no module imports found" -ForegroundColor Yellow
    }
}

Write-Host "`nDone!"
