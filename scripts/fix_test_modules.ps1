# Fix test files - ensure Commands.ps1 is sourced after CLI.ps1

$testFiles = Get-ChildItem "P:\software\_strap\tests\powershell" -Filter "*.Tests.ps1"
$fixed = 0

foreach ($file in $testFiles) {
    $content = Get-Content $file.FullName -Raw

    # Skip if already has Commands.ps1
    if ($content -match 'Commands\.ps1') {
        continue
    }

    # Check if it has CLI.ps1
    if ($content -notmatch '\. "\$modulesPath\\CLI\.ps1"') {
        Write-Host "Skipping $($file.Name) - no CLI.ps1 found"
        continue
    }

    # Add Commands.ps1 right after CLI.ps1
    $content = $content -replace `
        '(\. "\$modulesPath\\CLI\.ps1")\s*\n', `
        '$1' + "`n        . `"`$modulesPath\Commands.ps1`"`n"

    Set-Content -Path $file.FullName -Value $content -NoNewline
    Write-Host "Fixed $($file.Name)"
    $fixed++
}

Write-Host "`nFixed $fixed test files"
