# Convert old test files to use module imports instead of function extraction

$testDir = "P:\software\_strap\tests\powershell"

$oldStyleFiles = @(
    "Build-AuditIndex.Tests.ps1",
    "ChinvexClone.Tests.ps1",
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

foreach ($fileName in $oldStyleFiles) {
    $filePath = Join-Path $testDir $fileName
    if (-not (Test-Path $filePath)) {
        Write-Host "$fileName - Not found" -ForegroundColor Yellow
        continue
    }

    Write-Host "Converting $fileName..."
    $content = Get-Content $filePath -Raw

    # Find the BeforeAll block start
    if ($content -notmatch '(?s)(BeforeAll\s*\{)') {
        Write-Host "  No BeforeAll block found" -ForegroundColor Yellow
        continue
    }

    # Strategy: Replace everything from BeforeAll { up to the first It/Context block
    # with BeforeAll { <standard imports>
    # This preserves the test logic

    # Find where BeforeAll ends (at first It or Context statement)
    if ($content -match '(?s)(BeforeAll\s*\{)(.*?)(^\s*(It|Context)\s)') {
        # Extract the old setup code in case there are test-specific setups we need to keep
        $oldSetup = $matches[2]

        # Check if there's test-specific setup after function extraction (like mock functions)
        # Look for anything that's not function extraction or strap.ps1 reading
        $testSpecificSetup = ""
        $lines = $oldSetup -split "`n"
        $keepLines = @()

        $inExtraction = $false
        foreach ($line in $lines) {
            # Skip extraction-related lines
            if ($line -match '(Extract|strap\.ps1|function.*Extract|strapContent|braceCount|IndexOf)') {
                $inExtraction = $true
                continue
            }
            # Skip Invoke-Expression lines
            if ($line -match 'Invoke-Expression') {
                continue
            }
            # Keep other setup lines (mocks, test data, etc.)
            if ($line.Trim() -and -not $inExtraction) {
                $keepLines += $line
            }
            # If we see a blank line after extraction code, we're probably past it
            if ($inExtraction -and $line.Trim() -eq '') {
                $inExtraction = $false
            }
        }

        if ($keepLines.Count -gt 0) {
            $testSpecificSetup = "`n`n" + ($keepLines -join "`n")
        }

        # Replace with standard imports + any test-specific setup
        $newBeforeAll = "BeforeAll {`n$standardImports$testSpecificSetup`n    }`n`n    "
        $content = $content -replace '(?s)(BeforeAll\s*\{)(.*?)(^\s*(It|Context)\s)', "$newBeforeAll`$3"

        Set-Content -Path $filePath -Value $content -NoNewline
        Write-Host "  Converted!" -ForegroundColor Green
    } else {
        Write-Host "  Could not find It/Context block" -ForegroundColor Yellow
    }
}

Write-Host "`nDone!"
