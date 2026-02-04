Set-Location 'P:\software\_strap'

$config = New-PesterConfiguration
$config.Run.Path = 'tests\powershell'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'

$result = Invoke-Pester -Configuration $config

Write-Host "`n=== SUMMARY ==="
Write-Host "Passed: $($result.Passed.Count)"
Write-Host "Failed: $($result.Failed.Count)"
Write-Host "Total: $($result.TotalCount)"
