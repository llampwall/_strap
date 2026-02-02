<#
.SYNOPSIS
Tests consolidate move execution and transaction logic.
#>

$ErrorActionPreference = 'Stop'

function Test-Step {
  param([string] $Name, [scriptblock] $Action)
  Write-Host "`n=== $Name ===" -ForegroundColor Cyan
  try {
    & $Action
    Write-Host "✓ PASS" -ForegroundColor Green
    return $true
  } catch {
    Write-Host "✗ FAIL: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    return $false
  }
}

$testResults = @()

# Test 1: Execute move creates directory and moves files
$testResults += Test-Step "executeMove creates destination and moves repo" {
  $testRoot = Join-Path $env:TEMP "strap-consolidate-move-$(Get-Random)"
  New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

  try {
    # Create source repo
    $sourcePath = Join-Path $testRoot "source\test-repo"
    New-Item -ItemType Directory -Path $sourcePath -Force | Out-Null
    Push-Location $sourcePath
    git init | Out-Null
    git config user.email "test@test.com" | Out-Null
    git config user.name "Test User" | Out-Null
    "# Test" | Set-Content "README.md"
    git add . | Out-Null
    git commit -m "init" | Out-Null
    Pop-Location

    # Execute move
    $destPath = Join-Path $testRoot "dest\test-repo"
    . "$PSScriptRoot\strap.ps1" -RepoName "__test__" 2>&1 | Out-Null
    Invoke-ConsolidateExecuteMove -Name "test-repo" -FromPath $sourcePath -ToPath $destPath

    # Verify
    if (Test-Path $sourcePath) { throw "Source still exists" }
    if (-not (Test-Path $destPath)) { throw "Destination not created" }
    if (-not (Test-Path "$destPath\.git")) { throw "Git directory not moved" }
    if (-not (Test-Path "$destPath\README.md")) { throw "Files not moved" }

  } finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# Test 2: Rollback move restores original location
$testResults += Test-Step "rollbackMove restores repo to original location" {
  $testRoot = Join-Path $env:TEMP "strap-consolidate-rollback-$(Get-Random)"
  New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

  try {
    # Create and move repo
    $sourcePath = Join-Path $testRoot "source\test-repo"
    $destPath = Join-Path $testRoot "dest\test-repo"
    New-Item -ItemType Directory -Path $sourcePath -Force | Out-Null
    Push-Location $sourcePath
    git init | Out-Null
    git config user.email "test@test.com" | Out-Null
    git config user.name "Test User" | Out-Null
    "# Test" | Set-Content "README.md"
    git add . | Out-Null
    git commit -m "init" | Out-Null
    Pop-Location

    . "$PSScriptRoot\strap.ps1" -RepoName "__test__" 2>&1 | Out-Null
    Invoke-ConsolidateExecuteMove -Name "test-repo" -FromPath $sourcePath -ToPath $destPath

    # Rollback
    Invoke-ConsolidateRollbackMove -Name "test-repo" -FromPath $sourcePath -ToPath $destPath

    # Verify
    if (-not (Test-Path $sourcePath)) { throw "Source not restored" }
    if (Test-Path $destPath) { throw "Destination still exists" }
    if (-not (Test-Path "$sourcePath\.git")) { throw "Git directory not restored" }

  } finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# Test 3: Transaction rolls back on failure
$testResults += Test-Step "transaction rolls back completed moves when one fails" {
  $testRoot = Join-Path $env:TEMP "strap-consolidate-txn-$(Get-Random)"
  New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

  try {
    # Create repos
    $repo1Path = Join-Path $testRoot "source\repo1"
    $repo2Path = Join-Path $testRoot "source\repo2"

    foreach ($path in @($repo1Path, $repo2Path)) {
      New-Item -ItemType Directory -Path $path -Force | Out-Null
      Push-Location $path
      git init | Out-Null
      git config user.email "test@test.com" | Out-Null
      git config user.name "Test User" | Out-Null
      "# Test" | Set-Content "README.md"
      git add . | Out-Null
      git commit -m "init" | Out-Null
      Pop-Location
    }

    # Create blocker at destination for repo2
    $dest2 = Join-Path $testRoot "dest\repo2"
    New-Item -ItemType Directory -Path $dest2 -Force | Out-Null

    # Setup mock config/registry
    $config = @{
      software_root = Join-Path $testRoot "dest"
      tools_root = Join-Path $testRoot "dest\_scripts"
      registry = Join-Path $testRoot "registry.json"
    }
    @{ registry_version = 1; entries = @() } | ConvertTo-Json | Set-Content $config.registry

    # Try transaction (should fail on repo2)
    $plans = @(
      @{ name = "repo1"; fromPath = $repo1Path; toPath = (Join-Path $testRoot "dest\repo1"); scope = "software" }
      @{ name = "repo2"; fromPath = $repo2Path; toPath = $dest2; scope = "software" }
    )

    . "$PSScriptRoot\strap.ps1" -RepoName "__test__" 2>&1 | Out-Null

    try {
      Invoke-ConsolidateTransaction -Plans $plans -Config $config -Registry @() -StrapRootPath $testRoot
      throw "Transaction should have failed"
    } catch {
      if ($_.Exception.Message -notmatch "already exists") {
        throw "Expected 'already exists' error: $_"
      }
    }

    # Verify rollback
    if (-not (Test-Path $repo1Path)) { throw "repo1 not rolled back" }
    if (Test-Path (Join-Path $testRoot "dest\repo1")) { throw "repo1 destination still exists" }

  } finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# Summary
Write-Host "`n==================================" -ForegroundColor Cyan
$passed = ($testResults | Where-Object { $_ -eq $true }).Count
$total = $testResults.Count
Write-Host "Results: $passed/$total tests passed" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Red" })

if ($passed -eq $total) {
  Write-Host "`nAll tests passed!" -ForegroundColor Green
  exit 0
} else {
  Write-Host "`nSome tests failed" -ForegroundColor Red
  exit 1
}
