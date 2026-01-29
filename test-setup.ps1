param([switch] $KeepOnFailure)

$ErrorActionPreference = "Stop"

function Test-Step {
  param([string] $Name, [scriptblock] $Action)
  Write-Host "`n=== $Name ===" -ForegroundColor Cyan
  try {
    & $Action
    Write-Host "✓ PASS" -ForegroundColor Green
    return $true
  } catch {
    Write-Host "✗ FAIL: $_" -ForegroundColor Red
    return $false
  }
}

$testResults = @()
$strapPs1 = "P:\software\_strap\build\strap.ps1"
$strapCmd = "P:\software\_strap\build\strap.cmd"
$registryPath = "P:\software\_strap\build\registry.json"

# Backup registry if it exists
$registryBackup = $null
if (Test-Path $registryPath) {
  $registryBackup = Get-Content -LiteralPath $registryPath -Raw
}

try {
  # Clean up any existing test artifacts first
  Write-Host "`n=== PRE-CLEANUP ===" -ForegroundColor Cyan

  $pythonTestPath = "P:\software\test-setup-python"
  $nodeTestPath = "P:\software\test-setup-node"

  if (Test-Path $pythonTestPath) {
    Remove-Item -LiteralPath $pythonTestPath -Recurse -Force
  }
  if (Test-Path $nodeTestPath) {
    Remove-Item -LiteralPath $nodeTestPath -Recurse -Force
  }

  # Setup: Create test repos for different stacks
  Write-Host "`n=== SETUP ===" -ForegroundColor Cyan

  # Create Python test repo
  if (-not (Test-Path $pythonTestPath)) {
    New-Item -ItemType Directory -Path $pythonTestPath | Out-Null
  }
  Push-Location $pythonTestPath
  "# test" | Out-File -FilePath "README.md" -Encoding UTF8
  @"
[project]
name = "test-setup-python"
version = "0.1.0"
description = "Test project"
dependencies = []
"@ | Out-File -FilePath "pyproject.toml" -Encoding UTF8
  git init | Out-Null
  git add . | Out-Null
  git commit -m "init" | Out-Null
  Pop-Location

  # Create Node test repo
  if (-not (Test-Path $nodeTestPath)) {
    New-Item -ItemType Directory -Path $nodeTestPath | Out-Null
  }
  Push-Location $nodeTestPath
  "# test" | Out-File -FilePath "README.md" -Encoding UTF8
  @"
{
  "name": "test-setup-node",
  "version": "1.0.0",
  "dependencies": {
    "ms": "^2.1.3"
  }
}
"@ | Out-File -FilePath "package.json" -Encoding UTF8
  git init | Out-Null
  git add . | Out-Null
  git commit -m "init" | Out-Null
  Pop-Location

  # Manually register repos in registry
  $registry = if (Test-Path $registryPath) {
    Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
  } else {
    @()
  }

  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

  $pythonEntry = [PSCustomObject]@{
    id         = "test-setup-python"
    name       = "test-setup-python"
    scope      = "software"
    path       = $pythonTestPath
    url        = $null
    shims      = @()
    created_at = $timestamp
    updated_at = $timestamp
  }

  $nodeEntry = [PSCustomObject]@{
    id         = "test-setup-node"
    name       = "test-setup-node"
    scope      = "software"
    path       = $nodeTestPath
    url        = $null
    shims      = @()
    created_at = $timestamp
    updated_at = $timestamp
  }

  $registry = @($pythonEntry, $nodeEntry)
  $registryJson = ($registry | ConvertTo-Json -Depth 10)
  [System.IO.File]::WriteAllText($registryPath, $registryJson, (New-Object System.Text.UTF8Encoding($false)))

  Write-Host "✓ Setup complete" -ForegroundColor Green

  # Test 1: Setup Python repo with detection
  $testResults += Test-Step "Setup Python repo (auto-detect)" {
    Push-Location $pythonTestPath
    try {
      # Dry run first
      & $strapPs1 setup --dry-run
      if ($LASTEXITCODE -ne 0) { throw "Dry run failed" }

      # Actual setup
      & $strapPs1 setup --yes
      if ($LASTEXITCODE -ne 0) { throw "Setup failed" }

      # Verify venv was created
      $venvPython = Join-Path $pythonTestPath ".venv\Scripts\python.exe"
      if (-not (Test-Path $venvPython)) { throw "Venv not created" }

      # Verify registry was updated
      $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
      $entry = $registry | Where-Object { $_.name -eq "test-setup-python" }
      if (-not $entry) { throw "Registry entry not found" }
      if ($entry.stack_detected -ne "python") { throw "Stack not recorded" }
      if (-not $entry.setup_last_run_at) { throw "setup_last_run_at not set" }
      if ($entry.setup_status -ne "success") { throw "setup_status not set" }

      Write-Host "  Verified: Python setup completed, venv created, registry updated"
    } finally {
      Pop-Location
    }
  }

  # Test 2: Setup Node repo with forced stack
  $testResults += Test-Step "Setup Node repo (forced stack)" {
    Push-Location $nodeTestPath
    try {
      & $strapPs1 setup --yes --stack node --pm npm
      if ($LASTEXITCODE -ne 0) { throw "Setup failed" }

      # Verify node_modules was created
      $nodeModules = Join-Path $nodeTestPath "node_modules"
      if (-not (Test-Path $nodeModules)) { throw "node_modules not created" }

      # Verify registry was updated
      $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
      $entry = $registry | Where-Object { $_.name -eq "test-setup-node" }
      if (-not $entry) { throw "Registry entry not found" }
      if ($entry.stack_detected -ne "node") { throw "Stack not recorded" }

      Write-Host "  Verified: Node setup completed, node_modules created"
    } finally {
      Pop-Location
    }
  }

  # Test 3: Setup by registry name (--repo flag)
  $testResults += Test-Step "Setup by registry name" {
    # Clean up venv first
    $venvPath = Join-Path $pythonTestPath ".venv"
    if (Test-Path $venvPath) {
      Remove-Item -LiteralPath $venvPath -Recurse -Force
    }

    # Setup using --repo flag from different directory
    Push-Location "P:\software"
    try {
      & $strapPs1 setup --repo test-setup-python --yes
      if ($LASTEXITCODE -ne 0) { throw "Setup failed" }

      # Verify venv was created
      $venvPython = Join-Path $pythonTestPath ".venv\Scripts\python.exe"
      if (-not (Test-Path $venvPython)) { throw "Venv not created" }

      Write-Host "  Verified: Setup via --repo flag works"
    } finally {
      Pop-Location
    }
  }

  # Test 4: Fail on ambiguous stack (multi-stack detection)
  $testResults += Test-Step "Fail on ambiguous stack" {
    $multiStackPath = "P:\software\test-setup-multi"
    if (-not (Test-Path $multiStackPath)) {
      New-Item -ItemType Directory -Path $multiStackPath | Out-Null
    }

    Push-Location $multiStackPath
    try {
      # Create both Python and Node files
      "# test" | Out-File -FilePath "pyproject.toml" -Encoding UTF8
      "{}" | Out-File -FilePath "package.json" -Encoding UTF8

      # Should fail without --stack
      pwsh -NoProfile -Command "& '$strapPs1' setup --yes" 2>&1 | Out-Null
      $exitCode = $LASTEXITCODE

      if ($exitCode -ne 0) {
        Write-Host "  Verified: Correctly failed on multi-stack detection"
      } else {
        throw "Should have failed on multi-stack detection"
      }
    } finally {
      Pop-Location
      if (Test-Path $multiStackPath) {
        Remove-Item -LiteralPath $multiStackPath -Recurse -Force
      }
    }
  }

  # Test 5: Dry run does not modify registry
  $testResults += Test-Step "Dry run does not modify registry" {
    # Get current timestamp
    $registryBefore = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entryBefore = $registryBefore | Where-Object { $_.name -eq "test-setup-python" }
    $updatedAtBefore = $entryBefore.updated_at

    Start-Sleep -Seconds 1

    Push-Location $pythonTestPath
    try {
      & $strapPs1 setup --dry-run
      if ($LASTEXITCODE -ne 0) { throw "Dry run failed" }

      # Check registry was NOT modified
      $registryAfter = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
      $entryAfter = $registryAfter | Where-Object { $_.name -eq "test-setup-python" }
      if ($entryAfter.updated_at -ne $updatedAtBefore) { throw "Registry was modified during dry run" }

      Write-Host "  Verified: Dry run preserved registry state"
    } finally {
      Pop-Location
    }
  }

  # Summary
  Write-Host "`n=== TEST SUMMARY ===" -ForegroundColor Cyan
  $passed = ($testResults | Where-Object { $_ -eq $true }).Count
  $failed = ($testResults | Where-Object { $_ -eq $false }).Count
  Write-Host "Passed: $passed / $($testResults.Count)" -ForegroundColor Green
  if ($failed -gt 0) {
    Write-Host "Failed: $failed / $($testResults.Count)" -ForegroundColor Red
    throw "Some tests failed"
  }

  Write-Host "`n=== CLEANUP ===" -ForegroundColor Cyan

  # Remove test directories
  if (Test-Path $pythonTestPath) {
    Remove-Item -LiteralPath $pythonTestPath -Recurse -Force
  }
  if (Test-Path $nodeTestPath) {
    Remove-Item -LiteralPath $nodeTestPath -Recurse -Force
  }

  # Restore registry backup
  if ($registryBackup) {
    Write-Host "Restoring registry backup"
    [System.IO.File]::WriteAllText($registryPath, $registryBackup, (New-Object System.Text.UTF8Encoding($false)))
  } else {
    Write-Host "Clearing registry (no backup existed)"
    "[]" | Set-Content -LiteralPath $registryPath -NoNewline
  }

  Write-Host "`n✓ ALL TESTS PASSED" -ForegroundColor Green

} catch {
  Write-Host "`n✗ TEST SUITE FAILED: $_" -ForegroundColor Red

  if (-not $KeepOnFailure) {
    Write-Host "`nCleaning up (use -KeepOnFailure to preserve test artifacts)..." -ForegroundColor Yellow

    # Remove test directories
    if (Test-Path "P:\software\test-setup-python") {
      Remove-Item -LiteralPath "P:\software\test-setup-python" -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path "P:\software\test-setup-node") {
      Remove-Item -LiteralPath "P:\software\test-setup-node" -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path "P:\software\test-setup-multi") {
      Remove-Item -LiteralPath "P:\software\test-setup-multi" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Restore registry backup
    if ($registryBackup) {
      [System.IO.File]::WriteAllText($registryPath, $registryBackup, (New-Object System.Text.UTF8Encoding($false)))
    }
  }

  exit 1
}
