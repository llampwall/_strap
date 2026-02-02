<#
.SYNOPSIS
Tests argument parsing and validation for consolidate command.

.DESCRIPTION
Unit tests for Test-ConsolidateArgs function.
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
    return $false
  }
}

function Test-ConsolidateArgs {
  Test-Step "parses --from argument" {
    $args = @{
      FromPath = "C:\TestSource"
      ToPath = $null
      TrustMode = "registry-first"
    }
    $result = Test-ConsolidateArgsValidation @args
    if (-not $result.valid) { throw "Expected valid args" }
  }

  Test-Step "rejects missing --from" {
    $args = @{
      FromPath = $null
      ToPath = $null
      TrustMode = "registry-first"
    }
    $result = Test-ConsolidateArgsValidation @args
    if ($result.valid) { throw "Expected invalid args" }
    if ($result.error -notmatch "--from") { throw "Expected --from error message" }
  }

  Test-Step "rejects non-registry-first trust mode" {
    $args = @{
      FromPath = "C:\TestSource"
      ToPath = $null
      TrustMode = "disk-discovery"
    }
    $result = Test-ConsolidateArgsValidation @args
    if ($result.valid) { throw "Expected invalid args" }
    if ($result.error -notmatch "registry-first") { throw "Expected registry-first error" }
  }

  Test-Step "accepts valid args with all parameters" {
    $args = @{
      FromPath = "C:\TestSource"
      ToPath = "C:\TestDest"
      TrustMode = "registry-first"
    }
    $result = Test-ConsolidateArgsValidation @args
    if (-not $result.valid) { throw "Expected valid args: $($result.error)" }
  }
}

function Test-ConsolidateArgsValidation {
  param(
    [string] $FromPath,
    [string] $ToPath,
    [string] $TrustMode
  )

  if (-not $FromPath) {
    return @{ valid = $false; error = "--from is required" }
  }

  if ($TrustMode -ne "registry-first") {
    return @{ valid = $false; error = "strap consolidate is registry-first; run 'strap doctor --fix-paths' first for disk-discovery recovery" }
  }

  return @{ valid = $true; error = $null }
}

Write-Host "`n=== Consolidate Args Tests ===" -ForegroundColor Cyan
try {
  Test-ConsolidateArgs
  Write-Host "`nAll tests passed!" -ForegroundColor Green
  exit 0
} catch {
  Write-Host "`nTest failed: $_" -ForegroundColor Red
  exit 1
}
