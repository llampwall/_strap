# Find and report parse errors in test files
$testFiles = @(
    "ChinvexCLI.Tests.ps1",
    "ChinvexCLIDispatch.Tests.ps1",
    "ChinvexClone.Tests.ps1",
    "ChinvexConfig.Tests.ps1",
    "ChinvexContexts.Tests.ps1",
    "ChinvexDocs.Tests.ps1",
    "ChinvexHelpers.Tests.ps1",
    "ChinvexIdempotency.Tests.ps1",
    "ChinvexMove.Tests.ps1",
    "ChinvexRename.Tests.ps1",
    "ChinvexSync.Tests.ps1",
    "ChinvexUninstall.Tests.ps1",
    "ChinvexWrapper.Tests.ps1",
    "Get-PathProfileReferences.Tests.ps1",
    "Get-ScheduledTaskReferences.Tests.ps1",
    "Get-ShimReferences.Tests.ps1",
    "Invoke-Audit.Tests.ps1",
    "Invoke-ConsolidateAuditStep.Tests.ps1",
    "Invoke-Snapshot.Tests.ps1",
    "KillSwitch.Tests.ps1"
)

$testPath = "P:\software\_strap\tests\powershell"

foreach ($testFile in $testFiles) {
    $filePath = Join-Path $testPath $testFile
    Write-Host "`nChecking $testFile..." -ForegroundColor Cyan

    # Try to parse the file
    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($filePath, [ref]$tokens, [ref]$errors)

    if ($errors.Count -gt 0) {
        Write-Host "  PARSE ERRORS FOUND:" -ForegroundColor Red
        foreach ($err in $errors) {
            Write-Host "    Line $($err.Extent.StartLineNumber): $($err.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  OK" -ForegroundColor Green
    }
}
