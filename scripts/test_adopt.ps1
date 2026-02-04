Set-Location 'P:\software\_strap'

$config = New-PesterConfiguration
$config.Run.Path = 'tests\powershell\ChinvexAdopt.Tests.ps1'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Minimal'

$r = Invoke-Pester -Configuration $config
Write-Host "Passed: $($r.Passed.Count) / $($r.TotalCount)"
