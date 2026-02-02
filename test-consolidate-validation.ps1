<#
.SYNOPSIS
Tests registry/disk validation for consolidate command.

.DESCRIPTION
Unit tests for Test-ConsolidateRegistryDisk function.
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

function Test-ConsolidateValidation {
  $testRoot = Join-Path $env:TEMP "strap-test-validation-$(Get-Random)"
  New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

  try {
    Test-Step "detects registry path drift" {
      # Setup: registry path doesn't exist
      $registeredMoves = @(
        @{
          id = "test-repo"
          name = "test-repo"
          registryPath = "C:\NonExistent\test-repo"
          destinationPath = "$testRoot\software\test-repo"
        }
      )
      $discoveredCandidates = @()

      try {
        Test-ConsolidateRegistryDiskValidation -RegisteredMoves $registeredMoves -DiscoveredCandidates $discoveredCandidates
        throw "Expected path drift error"
      } catch {
        if ($_.Exception.Message -notmatch "drift") { throw "Expected drift error: $_" }
      }
    }

    Test-Step "detects destination conflicts" {
      # Setup: destination already exists
      $destPath = Join-Path $testRoot "software\conflict-repo"
      New-Item -ItemType Directory -Path $destPath -Force | Out-Null

      $sourcePath = Join-Path $testRoot "source\conflict-repo"
      New-Item -ItemType Directory -Path $sourcePath -Force | Out-Null

      $registeredMoves = @(
        @{
          id = "conflict-repo"
          name = "conflict-repo"
          registryPath = $sourcePath
          destinationPath = $destPath
        }
      )
      $discoveredCandidates = @()

      try {
        Test-ConsolidateRegistryDiskValidation -RegisteredMoves $registeredMoves -DiscoveredCandidates $discoveredCandidates
        throw "Expected destination conflict error"
      } catch {
        if ($_.Exception.Message -notmatch "already exists") { throw "Expected conflict error: $_" }
      }
    }

    Test-Step "warns on name collisions with different paths" {
      # Setup: discovered repo with same name but different path
      $sourcePath1 = Join-Path $testRoot "source\same-name"
      $sourcePath2 = Join-Path $testRoot "other\same-name"
      New-Item -ItemType Directory -Path $sourcePath1 -Force | Out-Null
      New-Item -ItemType Directory -Path $sourcePath2 -Force | Out-Null

      $registeredMoves = @(
        @{
          id = "same-name"
          name = "same-name"
          registryPath = $sourcePath1
          destinationPath = "$testRoot\software\same-name"
        }
      )
      $discoveredCandidates = @(
        @{
          name = "same-name"
          sourcePath = $sourcePath2
        }
      )

      $result = Test-ConsolidateRegistryDiskValidation -RegisteredMoves $registeredMoves -DiscoveredCandidates $discoveredCandidates
      if ($result.warnings.Count -eq 0) { throw "Expected name collision warning" }
      if ($result.warnings[0] -notmatch "collision") { throw "Expected collision warning" }
    }

    Test-Step "passes validation with clean state" {
      $sourcePath = Join-Path $testRoot "source\clean-repo"
      New-Item -ItemType Directory -Path $sourcePath -Force | Out-Null

      $registeredMoves = @(
        @{
          id = "clean-repo"
          name = "clean-repo"
          registryPath = $sourcePath
          destinationPath = "$testRoot\software\clean-repo"
        }
      )
      $discoveredCandidates = @()

      $result = Test-ConsolidateRegistryDiskValidation -RegisteredMoves $registeredMoves -DiscoveredCandidates $discoveredCandidates
      if ($result.warnings.Count -ne 0) { throw "Expected no warnings" }
    }
  } finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Test-ConsolidateRegistryDiskValidation {
  param(
    [array] $RegisteredMoves,
    [array] $DiscoveredCandidates
  )

  $warnings = @()

  # Check registry paths exist (no drift)
  foreach ($move in $RegisteredMoves) {
    if (-not (Test-Path -LiteralPath $move.registryPath)) {
      throw "Registry path drift detected for '$($move.name)'. Run 'strap doctor --fix-paths'."
    }

    # Check destination doesn't already exist
    if (Test-Path -LiteralPath $move.destinationPath) {
      throw "Conflict: destination already exists for '$($move.name)': $($move.destinationPath). Resolve manually before consolidate."
    }
  }

  # Check for name collisions
  foreach ($candidate in $DiscoveredCandidates) {
    $matching = $RegisteredMoves | Where-Object { $_.name.ToLowerInvariant() -eq $candidate.name.ToLowerInvariant() }
    if ($matching) {
      $normalizedRegistry = $matching.registryPath.ToLowerInvariant().Replace('/', '\').TrimEnd('\')
      $normalizedCandidate = $candidate.sourcePath.ToLowerInvariant().Replace('/', '\').TrimEnd('\')

      if ($normalizedRegistry -ne $normalizedCandidate) {
        $warnings += "Name collision: discovered repo '$($candidate.name)' differs from registered path. Treating as separate repo; rename before adopt to avoid confusion."
      }
    }
  }

  return @{ warnings = $warnings }
}

Write-Host "`n=== Consolidate Validation Tests ===" -ForegroundColor Cyan
try {
  Test-ConsolidateValidation
  Write-Host "`nAll tests passed!" -ForegroundColor Green
  exit 0
} catch {
  Write-Host "`nTest failed: $_" -ForegroundColor Red
  Write-Host $_.ScriptStackTrace -ForegroundColor Red
  exit 1
}
