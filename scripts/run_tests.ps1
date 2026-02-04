Set-Location 'P:\software\_strap'

$config = New-PesterConfiguration
$config.Run.Path = 'tests\powershell'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Minimal'

$result = Invoke-Pester -Configuration $config

Write-Host "`nPassed: $($result.Passed.Count)"
Write-Host "Failed: $($result.Failed.Count)"
Write-Host "Total: $($result.TotalCount)"
