cd "P:\software\_strap"

$config = New-PesterConfiguration
$config.Run.Path = 'tests\powershell\'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Normal'

$r = Invoke-Pester -Configuration $config

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "         REFACTORING TEST RESULTS" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests:   $($r.TotalCount)"
Write-Host "Passed:        $($r.Passed.Count)" -ForegroundColor Green
Write-Host "Failed:        $($r.Failed.Count)" -ForegroundColor $(if ($r.Failed.Count -gt 0) { 'Red' } else { 'Green' })
Write-Host "Skipped:       $($r.Skipped.Count)"
Write-Host ""
$pct = [math]::Round(100*$r.Passed.Count/$r.TotalCount)
Write-Host "Success Rate:  $pct%" -ForegroundColor $(if ($pct -ge 90) { 'Green' } elseif ($pct -ge 70) { 'Yellow' } else { 'Red' })
Write-Host "==========================================" -ForegroundColor Cyan
