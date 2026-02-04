Set-Location 'P:\software\_strap'

$config1 = New-PesterConfiguration
$config1.Run.Path = 'tests\powershell\ChinvexContexts.Tests.ps1'
$config1.Run.PassThru = $true
$config1.Output.Verbosity = 'Minimal'

$r1 = Invoke-Pester -Configuration $config1

$config2 = New-PesterConfiguration
$config2.Run.Path = 'tests\powershell\Get-PathProfileReferences.Tests.ps1'
$config2.Run.PassThru = $true
$config2.Output.Verbosity = 'Minimal'

$r2 = Invoke-Pester -Configuration $config2

Write-Host "ChinvexContexts: $($r1.Passed.Count)/$($r1.TotalCount)"
Write-Host "Get-PathProfileReferences: $($r2.Passed.Count)/$($r2.TotalCount)"
