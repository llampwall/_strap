Set-Location 'P:\software\_strap'
Write-Host "Running tests..." -ForegroundColor Cyan
$result = Invoke-Pester -Path tests\powershell -PassThru -Quiet -ErrorAction SilentlyContinue
Write-Host "`nPassed: $($result.PassedCount)" -ForegroundColor Green
Write-Host "Failed: $($result.FailedCount)" -ForegroundColor Red
Write-Host "Total: $($result.TotalCount)" -ForegroundColor Yellow
$result
