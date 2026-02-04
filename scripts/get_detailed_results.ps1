Set-Location 'P:\software\_strap'
$result = Invoke-Pester -Path tests\powershell -PassThru
Write-Host "`n=== SUMMARY ==="
Write-Host "Passed: $($result.PassedCount)"
Write-Host "Failed: $($result.FailedCount)"
Write-Host "Total: $($result.TotalCount)"
