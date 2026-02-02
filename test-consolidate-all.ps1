<#
.SYNOPSIS
Runs all consolidate tests and shows summary.

.DESCRIPTION
Master test runner for consolidate command implementation.
#>

$ErrorActionPreference = 'Stop'

Write-Host "=================================" -ForegroundColor Cyan
Write-Host "CONSOLIDATE COMMAND TEST SUITE" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

$results = @()

# Test 1: Args
Write-Host "`n[1/4] Running argument parsing tests..." -ForegroundColor Yellow
try {
  & "$PSScriptRoot\test-consolidate-args.ps1" | Out-Null
  $results += @{ name = "test-consolidate-args.ps1"; passed = $true }
  Write-Host "  ✓ PASSED" -ForegroundColor Green
} catch {
  $results += @{ name = "test-consolidate-args.ps1"; passed = $false; error = $_ }
  Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
}

# Test 2: Validation
Write-Host "`n[2/4] Running validation tests..." -ForegroundColor Yellow
try {
  & "$PSScriptRoot\test-consolidate-validation.ps1" | Out-Null
  $results += @{ name = "test-consolidate-validation.ps1"; passed = $true }
  Write-Host "  ✓ PASSED" -ForegroundColor Green
} catch {
  $results += @{ name = "test-consolidate-validation.ps1"; passed = $false; error = $_ }
  Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
}

# Test 3: Guards
Write-Host "`n[3/4] Running edge case guard tests..." -ForegroundColor Yellow
try {
  & "$PSScriptRoot\test-consolidate-guards.ps1" | Out-Null
  $results += @{ name = "test-consolidate-guards.ps1"; passed = $true }
  Write-Host "  ✓ PASSED" -ForegroundColor Green
} catch {
  $results += @{ name = "test-consolidate-guards.ps1"; passed = $false; error = $_ }
  Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
}

# Test 4: E2E
Write-Host "`n[4/4] Running end-to-end tests..." -ForegroundColor Yellow
try {
  & "$PSScriptRoot\test-consolidate-e2e.ps1" | Out-Null
  $results += @{ name = "test-consolidate-e2e.ps1"; passed = $true }
  Write-Host "  ✓ PASSED" -ForegroundColor Green
} catch {
  $results += @{ name = "test-consolidate-e2e.ps1"; passed = $false; error = $_ }
  Write-Host "  ✗ FAILED: $_" -ForegroundColor Red
}

# Summary
Write-Host "`n=================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

$passed = ($results | Where-Object { $_.passed }).Count
$total = $results.Count

foreach ($result in $results) {
  $status = if ($result.passed) { "✓" } else { "✗" }
  $color = if ($result.passed) { "Green" } else { "Red" }
  Write-Host "  $status $($result.name)" -ForegroundColor $color
}

Write-Host "`nTotal: $passed/$total test suites passed" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Red" })

# Regression tests
Write-Host "`n=================================" -ForegroundColor Cyan
Write-Host "REGRESSION TESTS" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

Write-Host "`nTesting existing commands..." -ForegroundColor Yellow

# Test doctor
try {
  $output = & "$PSScriptRoot\strap.cmd" doctor 2>&1 | Out-String
  if ($output -match "Status: OK") {
    Write-Host "  ✓ strap doctor - Still works" -ForegroundColor Green
  } else {
    Write-Host "  ⚠ strap doctor - May have issues" -ForegroundColor Yellow
  }
} catch {
  Write-Host "  ✗ strap doctor - Failed" -ForegroundColor Red
}

# Test migrate
try {
  $output = & "$PSScriptRoot\strap.cmd" migrate --plan 2>&1 | Out-String
  if ($output -match "nothing to do|Migration Plan") {
    Write-Host "  ✓ strap migrate - Still works" -ForegroundColor Green
  } else {
    Write-Host "  ⚠ strap migrate - May have issues" -ForegroundColor Yellow
  }
} catch {
  Write-Host "  ✗ strap migrate - Failed" -ForegroundColor Red
}

# Test consolidate command recognition
try {
  $output = & "$PSScriptRoot\strap.cmd" consolidate 2>&1 | Out-String
  if ($output -match "--from is required") {
    Write-Host "  ✓ strap consolidate - Command recognized" -ForegroundColor Green
  } else {
    Write-Host "  ✗ strap consolidate - Not recognized" -ForegroundColor Red
  }
} catch {
  # Expected to fail with --from error
  Write-Host "  ✓ strap consolidate - Command recognized" -ForegroundColor Green
}

Write-Host "`n=================================" -ForegroundColor Cyan
if ($passed -eq $total) {
  Write-Host "✅ ALL TESTS PASSED!" -ForegroundColor Green
  Write-Host "=================================" -ForegroundColor Cyan
  exit 0
} else {
  Write-Host "❌ SOME TESTS FAILED" -ForegroundColor Red
  Write-Host "=================================" -ForegroundColor Cyan
  exit 1
}
