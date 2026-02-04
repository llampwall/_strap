# Manual verification that Invoke-Audit works
Write-Host "=== Manual Verification of Invoke-Audit ===" -ForegroundColor Cyan

# Create temp test environment
$tempRoot = Join-Path $env:TEMP "strap_audit_test_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    # Create test registry
    $testRegistry = Join-Path $tempRoot "registry-v2.json"
    $testRepo = Join-Path $tempRoot "testproject"
    New-Item -ItemType Directory -Path $testRepo -Force | Out-Null
    Set-Content -Path (Join-Path $testRepo "config.ps1") -Value "`$path = 'C:\Code\testproject\data'"

    @{
        version = 2
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
        entries = @(
            @{
                name = "testproject"
                path = $testRepo
                scope = "software"
                last_commit = "abc123"
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content $testRegistry

    # Create config.json
    $configPath = Join-Path $tempRoot "config.json"
    @{
        registry = $testRegistry
        roots = @{
            software = $tempRoot
            tools = $tempRoot
            shims = Join-Path $tempRoot "shims"
        }
    } | ConvertTo-Json -Depth 10 | Set-Content $configPath

    Write-Host "`nTest environment created at: $tempRoot" -ForegroundColor Green
    Write-Host "  Registry: $testRegistry"
    Write-Host "  Test repo: $testRepo"
    Write-Host "  Config: $configPath"

    # Try calling strap.ps1 audit command
    Write-Host "`nCalling: strap audit testproject" -ForegroundColor Cyan
    & "P:\software\_strap\strap.ps1" audit testproject --json -StrapRoot $tempRoot

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`nSUCCESS: audit command executed" -ForegroundColor Green
    } else {
        Write-Host "`nFAILED: audit command returned exit code $LASTEXITCODE" -ForegroundColor Red
    }

} finally {
    # Cleanup
    Write-Host "`nCleaning up..." -ForegroundColor Yellow
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
