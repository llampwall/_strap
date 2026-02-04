# Add Commands.ps1 to all test files

$testFiles = Get-ChildItem "P:\software\_strap\tests\powershell" -Filter "*.Tests.ps1"

foreach ($file in $testFiles) {
    $content = Get-Content $file.FullName -Raw

    # Skip if already has Commands.ps1
    if ($content -match 'Commands\.ps1') {
        continue
    }

    # Add Commands.ps1 after CLI.ps1
    $content = $content -replace '(\. "\$modulesPath\\CLI\.ps1")', '$1' + "`n        . `"`$modulesPath\Commands.ps1`""

    Set-Content -Path $file.FullName -Value $content -NoNewline
    Write-Host "Updated $($file.Name)"
}

Write-Host "`nDone!"
