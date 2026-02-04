# Batch update all test files to use modular structure

$testFiles = Get-ChildItem "P:\software\_strap\tests\powershell" -Filter "*.Tests.ps1"
$updated = 0
$skipped = 0

# Standard BeforeAll template
$standardTemplate = @'
    BeforeAll {
        # Dot-source all strap modules
        $modulesPath = "$PSScriptRoot\..\..\modules"
        . "$modulesPath\Core.ps1"
        . "$modulesPath\Utils.ps1"
        . "$modulesPath\Path.ps1"
        . "$modulesPath\Config.ps1"
        . "$modulesPath\Chinvex.ps1"

        # Extract any functions not yet in modules
        . "$PSScriptRoot\..\TestHelpers.ps1"

        # List of functions that might need extraction
        $functionsToExtract = @(
            "Parse-GlobalFlags",
            "Show-Help",
            "Find-PathReferences",
            "Build-AuditIndex",
            "Get-ShimReferences",
            "Get-ScheduledTaskReferences",
            "Get-PathProfileReferences",
            "Invoke-Adopt",
            "Invoke-Clone",
            "Invoke-Move",
            "Invoke-Rename",
            "Invoke-Uninstall",
            "Invoke-SyncChinvex",
            "Invoke-Audit",
            "Invoke-Snapshot",
            "Invoke-ConsolidateAuditStep"
        )

        foreach ($func in $functionsToExtract) {
            try {
                Extract-StrapFunction $func
            } catch {
                # Function may already be in modules or not needed
            }
        }
'@

foreach ($file in $testFiles) {
    Write-Host "Processing $($file.Name)..." -NoNewline

    $content = Get-Content $file.FullName -Raw

    # Check if already updated (has modules path)
    if ($content -match '\$modulesPath\s*=\s*"\$PSScriptRoot\\\.\.\\\.\.\\modules"') {
        Write-Host " Already updated" -ForegroundColor Yellow
        $skipped++
        continue
    }

    # Check if uses Extract-Function pattern
    if ($content -notmatch 'function Extract-Function') {
        Write-Host " Doesn't use Extract-Function pattern" -ForegroundColor Gray
        $skipped++
        continue
    }

    # Find the BeforeAll block
    if ($content -match '(?s)(Describe[^\{]*\{)\s*(BeforeAll\s*\{.*?\n\s{4}\})') {
        $describeStart = $matches[1]
        $oldBeforeAll = $matches[2]

        # Extract the test directory setup and other non-function-extraction code
        $setupCode = ""
        if ($oldBeforeAll -match '(?s)# (Create test directory|Setup test).*') {
            $setupCode = "`n" + ($matches[0] -replace '^        ', '        ')
        }

        $newBeforeAll = $standardTemplate + $setupCode + "`n    }"

        # Replace the old BeforeAll with the new one
        $newContent = $content -replace [regex]::Escape($oldBeforeAll), $newBeforeAll

        Set-Content -Path $file.FullName -Value $newContent -NoNewline
        Write-Host " Updated!" -ForegroundColor Green
        $updated++
    } else {
        Write-Host " Could not find BeforeAll block" -ForegroundColor Red
    }
}

Write-Host "`n========================================="
Write-Host "Summary:"
Write-Host "  Updated: $updated"
Write-Host "  Skipped: $skipped"
Write-Host "  Total:   $($testFiles.Count)"
Write-Host "========================================="
