# Fix all test file module imports

$testDir = "P:\software\_strap\tests\powershell"
$testFiles = Get-ChildItem $testDir -Filter "*.Tests.ps1"

$standardImports = @"
        # Dot-source all strap modules
        `$modulesPath = "`$PSScriptRoot\..\..\modules"
        . "`$modulesPath\Core.ps1"
        . "`$modulesPath\Utils.ps1"
        . "`$modulesPath\Path.ps1"
        . "`$modulesPath\Config.ps1"
        . "`$modulesPath\Chinvex.ps1"
        . "`$modulesPath\CLI.ps1"
        . "`$modulesPath\Commands.ps1"
"@

foreach ($file in $testFiles) {
    Write-Host "Processing $($file.Name)..."
    $content = Get-Content $file.FullName -Raw

    # Find the BeforeAll block
    if ($content -notmatch '(?s)BeforeAll\s*\{') {
        Write-Host "  No BeforeAll block found, skipping" -ForegroundColor Yellow
        continue
    }

    # Pattern to match the module imports section (with or without malformed try-catch)
    $pattern = '(?s)(BeforeAll\s*\{\s*)(?:# Dot-source.*?\.ps1"(?:\s*catch\s*\{[^}]*\})*)*'

    # Replace with standard imports
    $newContent = $content -replace $pattern, "`$1$standardImports`n"

    # Write back
    Set-Content -Path $file.FullName -Value $newContent -NoNewline
    Write-Host "  Fixed $($file.Name)" -ForegroundColor Green
}

Write-Host "`nDone! Fixed $($testFiles.Count) test files."
