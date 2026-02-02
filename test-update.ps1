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
$strapPs1 = "P:\software\_strap\strap.ps1"
$strapCmd = "P:\software\_strap\strap.cmd"
$registryPath = "P:\software\_strap\registry.json"

# Backup registry if it exists
$registryBackup = $null
if (Test-Path $registryPath) {
  $registryBackup = Get-Content -LiteralPath $registryPath -Raw
}

try {
  # Setup: Clone test repos
  Write-Host "`n=== SETUP ===" -ForegroundColor Cyan

  # Clone a small repo for testing
  & $strapCmd clone "https://github.com/psf/requests" --tool --name test-update-1 --yes
  if ($LASTEXITCODE -ne 0) { throw "Setup failed: clone test-update-1" }

  & $strapCmd clone "https://github.com/psf/requests" --tool --name test-update-2 --yes
  if ($LASTEXITCODE -ne 0) { throw "Setup failed: clone test-update-2" }

  Write-Host "✓ Setup complete" -ForegroundColor Green

  # Test 1: Update single repo (clean working tree)
  $testResults += Test-Step "Update single repo with clean working tree" {
    & $strapPs1 update test-update-1 --yes
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

    # Check registry was updated
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entry = $registry | Where-Object { $_.name -eq "test-update-1" }
    if (-not $entry) { throw "Registry entry not found" }
    if (-not $entry.last_pull_at) { throw "last_pull_at not set" }
    if (-not $entry.last_head) { throw "last_head not set" }

    Write-Host "  Verified: registry updated with pull metadata"
  }

  # Test 2: Dry run does not modify registry
  $testResults += Test-Step "Dry run does not modify registry" {
    # Get current updated_at
    $registryBefore = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entryBefore = $registryBefore | Where-Object { $_.name -eq "test-update-1" }
    $updatedAtBefore = $entryBefore.updated_at

    Start-Sleep -Seconds 1

    & $strapPs1 update test-update-1 --dry-run
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

    # Check registry was NOT modified
    $registryAfter = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entryAfter = $registryAfter | Where-Object { $_.name -eq "test-update-1" }
    if ($entryAfter.updated_at -ne $updatedAtBefore) { throw "Registry was modified during dry run" }

    Write-Host "  Verified: dry run preserved registry state"
  }

  # Test 3: Update with dirty working tree (should fail without --stash)
  Write-Host "`n=== Reject update with dirty working tree ===" -ForegroundColor Cyan

  # Create a dirty file
  $testFile = "P:\software\_scripts\test-update-2\test-dirty.txt"
  "test content" | Out-File -FilePath $testFile -Encoding UTF8

  # Try to update (should fail)
  pwsh -NoProfile -Command "& '$strapPs1' update test-update-2 --yes" 2>&1 | Out-Null
  $exitCode = $LASTEXITCODE

  # Clean up dirty file
  if (Test-Path $testFile) {
    Remove-Item -LiteralPath $testFile -Force
  }

  if ($exitCode -ne 0) {
    Write-Host "  Verified: update correctly rejected dirty working tree"
    Write-Host "✓ PASS" -ForegroundColor Green
    $testResults += $true
  } else {
    Write-Host "✗ FAIL: Command should have failed but succeeded" -ForegroundColor Red
    $testResults += $false
  }

  # Test 4: Update with --stash handles dirty working tree
  $testResults += Test-Step "Update with --stash handles dirty working tree" {
    # Create a dirty file
    $testFile = "P:\software\_scripts\test-update-2\test-stash.txt"
    "test content" | Out-File -FilePath $testFile -Encoding UTF8

    # Update with --stash
    & $strapPs1 update test-update-2 --yes --stash
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

    # Check file still exists (stash was popped)
    if (-not (Test-Path $testFile)) { throw "Stashed file was not restored" }

    # Clean up
    Remove-Item -LiteralPath $testFile -Force

    Write-Host "  Verified: --stash preserved dirty changes"
  }

  # Test 5: Update --all updates multiple repos
  $testResults += Test-Step "Update --all updates multiple repos" {
    & $strapPs1 update --all --tool --yes
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

    # Check both repos were updated
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entry1 = $registry | Where-Object { $_.name -eq "test-update-1" }
    $entry2 = $registry | Where-Object { $_.name -eq "test-update-2" }

    if (-not $entry1.last_pull_at) { throw "test-update-1 not updated" }
    if (-not $entry2.last_pull_at) { throw "test-update-2 not updated" }

    Write-Host "  Verified: --all updated multiple repos"
  }

  # Test 6: Update with --rebase uses rebase
  $testResults += Test-Step "Update with --rebase" {
    & $strapPs1 update test-update-1 --yes --rebase
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

    Write-Host "  Verified: --rebase completed successfully"
  }

  # Test 7: Update non-existent repo fails
  Write-Host "`n=== Update non-existent repo fails ===" -ForegroundColor Cyan
  pwsh -NoProfile -Command "& '$strapPs1' update nonexistent --yes" 2>&1 | Out-Null
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0) {
    Write-Host "  Verified: correctly failed for non-existent repo"
    Write-Host "✓ PASS" -ForegroundColor Green
    $testResults += $true
  } else {
    Write-Host "✗ FAIL: Command should have failed but succeeded" -ForegroundColor Red
    $testResults += $false
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

  # Uninstall test repos
  & $strapCmd uninstall test-update-1 --yes
  & $strapCmd uninstall test-update-2 --yes

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

    # Uninstall test repos
    & $strapCmd uninstall test-update-1 --yes 2>&1 | Out-Null
    & $strapCmd uninstall test-update-2 --yes 2>&1 | Out-Null

    # Restore registry backup
    if ($registryBackup) {
      [System.IO.File]::WriteAllText($registryPath, $registryBackup, (New-Object System.Text.UTF8Encoding($false)))
    }
  }

  exit 1
}
