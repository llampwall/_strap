#!/usr/bin/env pwsh
# Test script for strap move and rename commands

$ErrorActionPreference = "Stop"

Write-Host "=== Testing strap move and rename commands ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: move command with missing arguments
Write-Host "Test 1: move without name (should fail)" -ForegroundColor Yellow
try {
  & "P:\software\_strap\strap.ps1" move --dest "P:\software\test" --dry-run
  Write-Host "❌ Expected error but command succeeded" -ForegroundColor Red
} catch {
  Write-Host "✅ Correctly failed with error" -ForegroundColor Green
}
Write-Host ""

# Test 2: move command with missing --dest
Write-Host "Test 2: move without --dest (should fail)" -ForegroundColor Yellow
try {
  & "P:\software\_strap\strap.ps1" move testname --dry-run
  Write-Host "❌ Expected error but command succeeded" -ForegroundColor Red
} catch {
  Write-Host "✅ Correctly failed with error" -ForegroundColor Green
}
Write-Host ""

# Test 3: rename command with missing arguments
Write-Host "Test 3: rename without name (should fail)" -ForegroundColor Yellow
try {
  & "P:\software\_strap\strap.ps1" rename --to newname --dry-run
  Write-Host "❌ Expected error but command succeeded" -ForegroundColor Red
} catch {
  Write-Host "✅ Correctly failed with error" -ForegroundColor Green
}
Write-Host ""

# Test 4: rename command with missing --to
Write-Host "Test 4: rename without --to (should fail)" -ForegroundColor Yellow
try {
  & "P:\software\_strap\strap.ps1" rename oldname --dry-run
  Write-Host "❌ Expected error but command succeeded" -ForegroundColor Red
} catch {
  Write-Host "✅ Correctly failed with error" -ForegroundColor Green
}
Write-Host ""

# Test 5: move command with dry-run (should fail if entry doesn't exist)
Write-Host "Test 5: move non-existent entry with dry-run" -ForegroundColor Yellow
try {
  & "P:\software\_strap\strap.ps1" move nonexistent --dest "P:\software\test" --dry-run
  Write-Host "❌ Expected error but command succeeded" -ForegroundColor Red
} catch {
  Write-Host "✅ Correctly failed with error (entry not found)" -ForegroundColor Green
}
Write-Host ""

# Test 6: rename command with dry-run (should fail if entry doesn't exist)
Write-Host "Test 6: rename non-existent entry with dry-run" -ForegroundColor Yellow
try {
  & "P:\software\_strap\strap.ps1" rename nonexistent --to newname --dry-run
  Write-Host "❌ Expected error but command succeeded" -ForegroundColor Red
} catch {
  Write-Host "✅ Correctly failed with error (entry not found)" -ForegroundColor Green
}
Write-Host ""

Write-Host "=== Basic validation tests complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "To test with actual registry entries:" -ForegroundColor Yellow
Write-Host "  strap move <existing-name> --dest P:\software\new-location --dry-run"
Write-Host "  strap rename <existing-name> --to new-name --dry-run"
Write-Host "  strap rename <existing-name> --to new-name --move-folder --dry-run"
