Set-Location 'P:\software\_strap'
Write-Host "Running tests..." -ForegroundColor Cyan

$config = New-PesterConfiguration
$config.Run.Path = 'tests\powershell'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Minimal'

$result = Invoke-Pester -Configuration $config -ErrorAction SilentlyContinue

Write-Host "`nPassed: $($result.Passed.Count)" -ForegroundColor Green
Write-Host "Failed: $($result.Failed.Count)" -ForegroundColor Red
Write-Host "Total: $($result.TotalCount)" -ForegroundColor Yellow
$result
