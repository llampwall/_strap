<#
.SYNOPSIS
End-to-end test for consolidate command.

.DESCRIPTION
Tests the complete consolidate workflow including command dispatch,
argument parsing, and dry-run execution.
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

$strapCmd = "P:\software\_strap\strap.cmd"
$testResults = @()

try {
  # Test 1: Command recognized (not treated as repo name)
  $testResults += Test-Step "consolidate command recognized" {
    $output = & $strapCmd consolidate 2>&1 | Out-String
    if ($output -match "Select template") {
      throw "consolidate treated as repo name (template prompt shown)"
    }
    if ($output -notmatch "--from") {
      throw "Expected --from requirement message"
    }
  }

  # Test 2: Requires --from argument
  $testResults += Test-Step "requires --from argument" {
    $output = & $strapCmd consolidate 2>&1 | Out-String
    if ($output -notmatch "--from is required") {
      throw "Expected '--from is required' error"
    }
  }

  # Test 3: Rejects non-existent --from directory
  $testResults += Test-Step "rejects non-existent --from directory" {
    $output = & $strapCmd consolidate --from "C:\NonExistentPath" 2>&1 | Out-String
    if ($output -notmatch "does not exist") {
      throw "Expected 'does not exist' error"
    }
  }

  # Test 4: Dry-run execution
  $testResults += Test-Step "dry-run executes successfully" {
    # Create temp test directory
    $testRoot = Join-Path $env:TEMP "strap-consolidate-e2e-$(Get-Random)"
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    try {
      # Create a test repo
      $testRepo = Join-Path $testRoot "e2e-test-repo"
      New-Item -ItemType Directory -Path $testRepo -Force | Out-Null
      Push-Location $testRepo
      git init | Out-Null
      git config user.email "test@test.com" | Out-Null
      git config user.name "Test User" | Out-Null
      "# Test" | Set-Content "README.md"
      git add . | Out-Null
      git commit -m "init" | Out-Null
      Pop-Location

      # Run dry-run
      $output = & $strapCmd consolidate --from $testRoot --dry-run 2>&1 | Out-String

      # Verify output
      if ($output -notmatch "DRY RUN complete") {
        throw "Expected 'DRY RUN complete' message"
      }
      if ($output -notmatch "e2e-test-repo") {
        throw "Expected test repo to be discovered"
      }
      if ($output -notmatch "Discovered 1 repositories") {
        throw "Expected 1 repo to be discovered"
      }

    } finally {
      # Cleanup
      if (Test-Path $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  }

  # Test 5: Snapshot creation
  $testResults += Test-Step "creates snapshot file" {
    $testRoot = Join-Path $env:TEMP "strap-consolidate-snapshot-$(Get-Random)"
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

    try {
      # Create a test repo
      $testRepo = Join-Path $testRoot "snapshot-test-repo"
      New-Item -ItemType Directory -Path $testRepo -Force | Out-Null
      Push-Location $testRepo
      git init | Out-Null
      git config user.email "test@test.com" | Out-Null
      git config user.name "Test User" | Out-Null
      "# Test" | Set-Content "README.md"
      git add . | Out-Null
      git commit -m "init" | Out-Null
      Pop-Location

      # Run dry-run
      $output = & $strapCmd consolidate --from $testRoot --dry-run 2>&1 | Out-String

      # Extract snapshot path
      if ($output -match "consolidate-snapshot-(\d{8}-\d{6})\.json") {
        $snapshotPattern = "consolidate-snapshot-$($matches[1]).json"
        $snapshotPath = Join-Path "P:\software\_strap\build" $snapshotPattern

        if (-not (Test-Path $snapshotPath)) {
          throw "Snapshot file not created: $snapshotPath"
        }

        # Verify snapshot content
        $snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
        if (-not $snapshot.fromPath) {
          throw "Snapshot missing fromPath"
        }
        if ($snapshot.fromPath -ne $testRoot) {
          throw "Snapshot fromPath incorrect: $($snapshot.fromPath)"
        }

        # Cleanup snapshot
        Remove-Item -LiteralPath $snapshotPath -Force -ErrorAction SilentlyContinue
      } else {
        throw "Could not find snapshot path in output"
      }

    } finally {
      # Cleanup
      if (Test-Path $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
      }
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

} catch {
  Write-Host "`n✗ Test suite failed: $_" -ForegroundColor Red
  Write-Host $_.ScriptStackTrace -ForegroundColor Red
  exit 1
}
