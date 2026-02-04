Set-Location 'P:\software\_strap'
$files = @(
    'ChinvexDocs.Tests.ps1',
    'ChinvexIdempotency.Tests.ps1',
    'ChinvexMove.Tests.ps1',
    'ChinvexRename.Tests.ps1',
    'ChinvexSync.Tests.ps1',
    'ChinvexUninstall.Tests.ps1'
)
$totalPassed = 0
$totalFailed = 0
$totalCount = 0
foreach ($f in $files) {
    $config = New-PesterConfiguration
    $config.Run.Path = "tests\powershell\$f"
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Minimal'

    $r = Invoke-Pester -Configuration $config 2>$null
    if ($r) {
        Write-Host "$f : $($r.Passed.Count)/$($r.TotalCount)" -ForegroundColor $(if ($r.Failed.Count -eq 0) { 'Green' } else { 'Yellow' })
        $totalPassed += $r.Passed.Count
        $totalFailed += $r.Failed.Count
        $totalCount += $r.TotalCount
    }
}
Write-Host "`nBatch Total: $totalPassed/$totalCount" -ForegroundColor Cyan
