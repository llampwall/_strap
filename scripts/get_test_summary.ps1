# Get test summary quickly
Set-Location 'P:\software\_strap'
$result = Invoke-Pester -Path tests\powershell -PassThru -Quiet
Write-Host "`nPassed: $($result.PassedCount)"
Write-Host "Failed: $($result.FailedCount)"
Write-Host "Total: $($result.TotalCount)"
