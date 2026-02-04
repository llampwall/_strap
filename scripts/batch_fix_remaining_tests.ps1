# Batch fix remaining test files with old-style function extraction

$testDir = "P:\software\_strap\tests\powershell"

# Files that still need fixing (excluding the 2 we just did manually)
$filesToFix = @(
    "ChinvexConfig.Tests.ps1",
    "ChinvexDocs.Tests.ps1",
    "ChinvexHelpers.Tests.ps1",
    "ChinvexWrapper.Tests.ps1",
    "Get-PathProfileReferences.Tests.ps1",
    "Get-ScheduledTaskReferences.Tests.ps1",
    "Get-ShimReferences.Tests.ps1",
    "KillSwitch.Tests.ps1"
)

$standardImports = @'
        # Dot-source all strap modules
        $modulesPath = "$PSScriptRoot\..\..\modules"
        . "$modulesPath\Core.ps1"
        . "$modulesPath\Utils.ps1"
        . "$modulesPath\Path.ps1"
        . "$modulesPath\Config.ps1"
        . "$modulesPath\Chinvex.ps1"
        . "$modulesPath\CLI.ps1"
        . "$modulesPath\Commands.ps1"
'@

foreach ($fileName in $filesToFix) {
    $filePath = Join-Path $testDir $fileName
    if (-not (Test-Path $filePath)) {
        Write-Host "$fileName - Not found" -ForegroundColor Yellow
        continue
    }

    Write-Host "Processing $fileName..."
    $lines = Get-Content $filePath

    $newLines = @()
    $inBeforeAll = $false
    $inExtraction = $false
    $importsAdded = $false
    $braceDepth = 0

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # Check if we're entering BeforeAll
        if ($line -match '^\s*BeforeAll\s*\{') {
            $inBeforeAll = $true
            $braceDepth = 1
            $newLines += $line
            continue
        }

        # If in BeforeAll, track braces
        if ($inBeforeAll) {
            # Count braces to know when BeforeAll ends
            $openBraces = ($line -split '\{').Count - 1
            $closeBraces = ($line -split '\}').Count - 1
            $braceDepth += ($openBraces - $closeBraces)

            # Skip function extraction code
            if (-not $importsAdded -and (
                $line -match 'Extract' -or
                $line -match 'strap\.ps1' -or
                $line -match 'strapContent' -or
                $line -match 'Invoke-Expression' -or
                $line -match '\$funcName' -or
                $line -match 'function.*Extract-Function' -or
                $line -match 'braceCount' -or
                $line -match 'IndexOf\(' -or
                $line -match 'foreach.*\$funcName'
            )) {
                $inExtraction = $true
                continue
            }

            # When we hit the first non-extraction, non-comment, non-blank line, add imports
            if (-not $importsAdded -and $line.Trim() -and
                $line -notmatch '^\s*#' -and
                $line -notmatch 'Extract' -and
                $line -notmatch 'strap\.ps1') {
                # Add imports before this line
                $importLines = $standardImports -split "`n"
                $newLines += $importLines
                $newLines += ""
                $importsAdded = $true
                $inExtraction = $false
            }

            # End of BeforeAll
            if ($braceDepth -eq 0) {
                $inBeforeAll = $false
                $importsAdded = $false
            }
        }

        # Add the line if we're not skipping extraction code
        if (-not $inExtraction -or $inBeforeAll -eq $false) {
            $newLines += $line
        }

        # Reset extraction flag after we add imports
        if ($importsAdded) {
            $inExtraction = $false
        }
    }

    # Write back
    $newLines | Set-Content -Path $filePath
    Write-Host "  Fixed!" -ForegroundColor Green
}

Write-Host "`nDone!"
