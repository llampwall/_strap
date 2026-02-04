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
Write-Host "`nRemaining Batch: $totalPassed/$totalCount" -ForegroundColor Cyan
