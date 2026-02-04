Set-Location 'P:\software\_strap'
$r = Invoke-Pester -Path tests\powershell\ChinvexClone.Tests.ps1 -PassThru -Quiet
Write-Host "Passed: $($r.PassedCount) / $($r.TotalCount)"
