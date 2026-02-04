Set-Location 'P:\software\_strap'
$files = @(
    'ChinvexContexts.Tests.ps1',
    'ChinvexWrapper.Tests.ps1',
    'Build-AuditIndex.Tests.ps1',
    'Get-PathProfileReferences.Tests.ps1',
    'Get-ScheduledTaskReferences.Tests.ps1',
    'Get-ShimReferences.Tests.ps1',
    'Invoke-Audit.Tests.ps1',
    'Invoke-ConsolidateAuditStep.Tests.ps1',
    'Invoke-Snapshot.Tests.ps1',
    'KillSwitch.Tests.ps1',
    'ChinvexCLIDispatch.Tests.ps1'
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
Write-Host "`nRemaining Batch: $totalPassed/$totalCount" -ForegroundColor Cyan
