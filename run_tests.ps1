$config = New-PesterConfiguration
$config.Run.Path = 'tests\powershell\Invoke-Audit.Tests.ps1'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Minimal'

$result = Invoke-Pester -Configuration $config

Write-Host '---SUMMARY---'
Write-Host "Passed: $($result.Passed.Count)"
Write-Host "Failed: $($result.Failed.Count)"
if ($result.Failed.Count -gt 0) {
    Write-Host 'TESTS FAILED' -ForegroundColor Red
    exit 1
} else {
    Write-Host 'TESTS PASSED' -ForegroundColor Green
    exit 0
}
