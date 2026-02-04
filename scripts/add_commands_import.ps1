# Add Commands.ps1 import to all test files that are missing it

$testDir = "P:\software\_strap\tests\powershell"
$testFiles = Get-ChildItem $testDir -Filter "*.Tests.ps1"

$fixed = 0
foreach ($file in $testFiles) {
    $content = Get-Content $file.FullName -Raw

    # Skip if already has Commands.ps1
    if ($content -match 'Commands\.ps1') {
        Write-Host "$($file.Name) - Already has Commands.ps1" -ForegroundColor Gray
        continue
    }

    # Add Commands.ps1 right after CLI.ps1
    if ($content -match '\. "\$modulesPath\\CLI\.ps1"') {
        $content = $content -replace '(\. "\$modulesPath\\CLI\.ps1")', "`$1`n        . `"`$modulesPath\Commands.ps1`""
        Set-Content -Path $file.FullName -Value $content -NoNewline
        Write-Host "$($file.Name) - Added Commands.ps1" -ForegroundColor Green
        $fixed++
    } else {
        Write-Host "$($file.Name) - No CLI.ps1 found, skipping" -ForegroundColor Yellow
    }
}

Write-Host "`nAdded Commands.ps1 to $fixed files"
