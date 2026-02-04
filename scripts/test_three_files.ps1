Set-Location 'P:\software\_strap'
$files = @('ChinvexConfig.Tests.ps1', 'ChinvexCLI.Tests.ps1', 'ChinvexAdopt.Tests.ps1')
foreach ($f in $files) {
    Write-Host "`n=== $f ===" -ForegroundColor Cyan
    $r = Invoke-Pester -Path "tests\powershell\$f" -PassThru -Quiet
    Write-Host "Passed: $($r.PassedCount) Failed: $($r.FailedCount)"
}
