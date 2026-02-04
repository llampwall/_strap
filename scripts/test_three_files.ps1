Set-Location 'P:\software\_strap'
$files = @('ChinvexConfig.Tests.ps1', 'ChinvexCLI.Tests.ps1', 'ChinvexAdopt.Tests.ps1')
foreach ($f in $files) {
    Write-Host "`n=== $f ===" -ForegroundColor Cyan

    $config = New-PesterConfiguration
    $config.Run.Path = "tests\powershell\$f"
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Minimal'

    $r = Invoke-Pester -Configuration $config
    Write-Host "Passed: $($r.Passed.Count) Failed: $($r.Failed.Count)"
}
