Set-Location 'P:\software\_strap'
$r1 = Invoke-Pester -Path tests\powershell\ChinvexContexts.Tests.ps1 -PassThru -Quiet
$r2 = Invoke-Pester -Path tests\powershell\Get-PathProfileReferences.Tests.ps1 -PassThru -Quiet
Write-Host "ChinvexContexts: $($r1.PassedCount)/$($r1.TotalCount)"
Write-Host "Get-PathProfileReferences: $($r2.PassedCount)/$($r2.TotalCount)"
