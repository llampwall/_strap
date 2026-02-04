# Update test files to use dot-sourced modules instead of function extraction

$testFiles = Get-ChildItem "P:\software\_strap\tests\powershell\*.Tests.ps1"

foreach ($file in $testFiles) {
    Write-Host "Processing $($file.Name)..."

    $content = Get-Content $file.FullName -Raw

    # Check if this file uses Extract-Function
    if ($content -notmatch 'function Extract-Function') {
        Write-Host "  Skipping (doesn't use Extract-Function)"
        continue
    }

    # Replace the Extract-Function BeforeAll block with module imports
    $newContent = $content -replace `
        '(?s)# Extract.*?from strap\.ps1\s+\$strapContent = Get-Content.*?Invoke-Expression \$funcCode\s+\}',
        '# Dot-source modules (automatically loads all functions)
        $modulesPath = "$PSScriptRoot\..\..\modules"
        . "$modulesPath\Core.ps1"
        . "$modulesPath\Utils.ps1"
        . "$modulesPath\Path.ps1"
        . "$modulesPath\Config.ps1"
        . "$modulesPath\Chinvex.ps1"'

    # If replacement happened, save the file
    if ($newContent -ne $content) {
        Set-Content -Path $file.FullName -Value $newContent -NoNewline
        Write-Host "  Updated!"
    } else {
        Write-Host "  No changes needed"
    }
}

Write-Host "`nDone updating test files."
