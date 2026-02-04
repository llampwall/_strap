# Update all test files to source modules directly

$testFiles = Get-ChildItem "P:\software\_strap\tests\powershell" -Filter "*.Tests.ps1"

# Standard module imports block
$moduleImports = @'
        # Dot-source all strap modules
        $modulesPath = "$PSScriptRoot\..\..\modules"
        . "$modulesPath\Core.ps1"
        . "$modulesPath\Utils.ps1"
        . "$modulesPath\Path.ps1"
        . "$modulesPath\Config.ps1"
        . "$modulesPath\Chinvex.ps1"
        . "$modulesPath\CLI.ps1"
'@

foreach ($file in $testFiles) {
    $content = Get-Content $file.FullName -Raw

    # Skip if already updated (has CLI.ps1)
    if ($content -match 'CLI\.ps1') {
        Write-Host "Skipping $($file.Name) - already updated"
        continue
    }

    # Skip if doesn't have BeforeAll
    if ($content -notmatch 'BeforeAll') {
        Write-Host "Skipping $($file.Name) - no BeforeAll block"
        continue
    }

    Write-Host "Updating $($file.Name)..."

    # Replace function extraction code with module imports
    $content = $content -replace '(?s)(\s+BeforeAll \{\s+)# Extract.*?from strap\.ps1.*?Invoke-Expression \$funcCode\s+\}', "`$1$moduleImports"

    Set-Content -Path $file.FullName -Value $content -NoNewline
}

Write-Host "`nDone!"
