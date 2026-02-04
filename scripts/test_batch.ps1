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
    $r = Invoke-Pester -Path "tests\powershell\$f" -PassThru -Quiet 2>$null
    if ($r) {
        Write-Host "$f : $($r.PassedCount)/$($r.TotalCount)" -ForegroundColor $(if ($r.FailedCount -eq 0) { 'Green' } else { 'Yellow' })
        $totalPassed += $r.PassedCount
        $totalFailed += $r.FailedCount
        $totalCount += $r.TotalCount
    }
}
Write-Host "`nBatch Total: $totalPassed/$totalCount" -ForegroundColor Cyan
