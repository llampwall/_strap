cd "P:\software\_strap"
$r = Invoke-Pester tests\powershell\ -PassThru

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "         REFACTORING TEST RESULTS" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests:   $($r.TotalCount)"
Write-Host "Passed:        $($r.PassedCount)" -ForegroundColor Green
Write-Host "Failed:        $($r.FailedCount)" -ForegroundColor $(if ($r.FailedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Skipped:       $($r.SkippedCount)"
Write-Host ""
$pct = [math]::Round(100*$r.PassedCount/$r.TotalCount)
Write-Host "Success Rate:  $pct%" -ForegroundColor $(if ($pct -ge 90) { 'Green' } elseif ($pct -ge 70) { 'Yellow' } else { 'Red' })
Write-Host "==========================================" -ForegroundColor Cyan
