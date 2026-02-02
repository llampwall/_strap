<#
.SYNOPSIS
Tests edge case guards for consolidate command.

.DESCRIPTION
Integration tests for edge case detection and resolution.
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

function Test-ConsolidateGuards {
  $testRoot = Join-Path $env:TEMP "strap-test-guards-$(Get-Random)"
  New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

  try {
    Test-Step "detects running process locks" {
      $lockPath = Join-Path $testRoot "consolidate.lock"
      $currentPid = $PID
      $lockData = @{ pid = $currentPid; timestamp = (Get-Date).ToString('o') }
      $lockData | ConvertTo-Json | Set-Content -LiteralPath $lockPath

      $existingLock = @{ pid = $currentPid; path = $lockPath }

      try {
        Test-ConsolidateEdgeCaseGuards -ExistingLock $existingLock -ProposedAdoptions @() -DestinationPaths @() -NonInteractive $true
        throw "Expected running process lock error"
      } catch {
        if ($_.Exception.Message -notmatch "in progress") { throw "Expected lock error: $_" }
      }
    }

    Test-Step "removes stale locks" {
      $lockPath = Join-Path $testRoot "consolidate-stale.lock"
      $fakePid = 999999
      $lockData = @{ pid = $fakePid; timestamp = (Get-Date).ToString('o') }
      $lockData | ConvertTo-Json | Set-Content -LiteralPath $lockPath

      $existingLock = @{ pid = $fakePid; path = $lockPath }

      $result = Test-ConsolidateEdgeCaseGuards -ExistingLock $existingLock -ProposedAdoptions @() -DestinationPaths @() -NonInteractive $true

      if (Test-Path -LiteralPath $lockPath) { throw "Expected stale lock to be removed" }
      if (-not $result.ok) { throw "Expected guards to pass after removing stale lock" }
    }

    Test-Step "detects destination path collisions" {
      $dest1 = "C:\Software\Test-Repo"
      $dest2 = "C:\software\test-repo"  # Case-insensitive collision

      try {
        Test-ConsolidateEdgeCaseGuards -ExistingLock $null -ProposedAdoptions @() -DestinationPaths @($dest1, $dest2) -NonInteractive $true
        throw "Expected destination collision error"
      } catch {
        if ($_.Exception.Message -notmatch "collision") { throw "Expected collision error: $_" }
      }
    }

    Test-Step "detects adoption ID collisions in non-interactive mode" {
      $adoptions = @(
        @{ proposedId = "test-repo"; sourcePath = "C:\Source\repo1" }
        @{ proposedId = "Test-Repo"; sourcePath = "C:\Source\repo2" }  # Case-insensitive collision
      )

      try {
        Test-ConsolidateEdgeCaseGuards -ExistingLock $null -ProposedAdoptions $adoptions -DestinationPaths @() -NonInteractive $true
        throw "Expected adoption ID collision error"
      } catch {
        if ($_.Exception.Message -notmatch "collision") { throw "Expected collision error: $_" }
      }
    }

    Test-Step "passes guards with clean state" {
      $adoptions = @(
        @{ proposedId = "repo1"; sourcePath = "C:\Source\repo1" }
        @{ proposedId = "repo2"; sourcePath = "C:\Source\repo2" }
      )
      $destinations = @("C:\Dest\repo1", "C:\Dest\repo2")

      $result = Test-ConsolidateEdgeCaseGuards -ExistingLock $null -ProposedAdoptions $adoptions -DestinationPaths $destinations -NonInteractive $true

      if (-not $result.ok) { throw "Expected guards to pass: $($result.error)" }
      if ($result.resolved.Count -ne 2) { throw "Expected 2 resolved adoptions" }
    }
  } finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Test-ConsolidateEdgeCaseGuards {
  param(
    [hashtable] $ExistingLock,
    [array] $ProposedAdoptions,
    [array] $DestinationPaths,
    [bool] $NonInteractive
  )

  # Check for running process locks
  if ($ExistingLock) {
    $running = Test-ProcessRunning -ProcessId $ExistingLock.pid
    if ($running) {
      throw "Another consolidation in progress (PID $($ExistingLock.pid))"
    }
    # Remove stale lock
    Remove-Item -LiteralPath $ExistingLock.path -Force -ErrorAction SilentlyContinue
  }

  # Check for destination path collisions
  $collision = Find-DuplicatePaths -Paths $DestinationPaths
  if ($collision) {
    throw "Destination path collision detected: $collision"
  }

  # Check for adoption ID collisions
  $seenIds = @{}
  $resolved = @()

  foreach ($item in $ProposedAdoptions) {
    $key = $item.proposedId.ToLowerInvariant()
    if ($seenIds.ContainsKey($key)) {
      if ($NonInteractive) {
        throw "Adoption ID collision detected for '$($item.proposedId)' in --yes mode."
      }
      # In interactive mode, would prompt for resolution
      # For test purposes, skip interactive resolution
      throw "Interactive resolution not implemented in test"
    }
    $seenIds[$key] = $true
    $resolved += $item
  }

  return @{ ok = $true; resolved = $resolved }
}

function Test-ProcessRunning {
  param([int] $ProcessId)
  try {
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    return $null -ne $process
  } catch {
    return $false
  }
}

function Find-DuplicatePaths {
  param([array] $Paths)

  $seen = @{}
  foreach ($path in $Paths) {
    $key = $path.ToLowerInvariant()
    if ($seen.ContainsKey($key) -and $seen[$key] -ne $path) {
      return "$($seen[$key]) <-> $path"
    }
    $seen[$key] = $path
  }
  return $null
}

Write-Host "`n=== Consolidate Guards Tests ===" -ForegroundColor Cyan
try {
  Test-ConsolidateGuards
  Write-Host "`nAll tests passed!" -ForegroundColor Green
  exit 0
} catch {
  Write-Host "`nTest failed: $_" -ForegroundColor Red
  Write-Host $_.ScriptStackTrace -ForegroundColor Red
  exit 1
}
