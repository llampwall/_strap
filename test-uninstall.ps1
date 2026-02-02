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
  & $strapCmd clone "https://github.com/psf/requests" --tool --name test-uninstall-1
  if ($LASTEXITCODE -ne 0) { throw "Setup failed: clone test-uninstall-1" }

  & $strapCmd clone "https://github.com/pallets/flask" --name test-uninstall-2
  if ($LASTEXITCODE -ne 0) { throw "Setup failed: clone test-uninstall-2" }

  & $strapCmd clone "https://github.com/psf/requests" --tool --name test-uninstall-3
  if ($LASTEXITCODE -ne 0) { throw "Setup failed: clone test-uninstall-3" }

  Write-Host "✓ Setup complete" -ForegroundColor Green

  # Test 1: Dry run (should not delete anything)
  $testResults += Test-Step "Dry run does not delete" {
    & $strapCmd uninstall test-uninstall-1 --dry-run
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path "P:\software\_scripts\test-uninstall-1")) { throw "Folder was deleted (should be dry run)" }

    # Check registry entry still exists
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entry = $registry | Where-Object { $_.name -eq "test-uninstall-1" }
    if (-not $entry) { throw "Registry entry was removed (should be dry run)" }
    Write-Host "  Verified: folder and registry entry preserved"
  }

  # Test 2: Basic uninstall with --yes
  $testResults += Test-Step "Basic uninstall with --yes" {
    & $strapCmd uninstall test-uninstall-1 --yes
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
    if (Test-Path "P:\software\_scripts\test-uninstall-1") { throw "Folder was not deleted" }

    # Check registry entry is gone
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entry = $registry | Where-Object { $_.name -eq "test-uninstall-1" }
    if ($entry) { throw "Registry entry was not removed" }
    Write-Host "  Verified: folder and registry entry removed"
  }

  # Test 3: Uninstall with --keep-folder
  $testResults += Test-Step "Uninstall with --keep-folder" {
    & $strapCmd uninstall test-uninstall-2 --keep-folder --yes
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path "P:\software\test-uninstall-2")) { throw "Folder was deleted (should be kept)" }

    # Check registry entry is gone
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entry = $registry | Where-Object { $_.name -eq "test-uninstall-2" }
    if ($entry) { throw "Registry entry was not removed" }
    Write-Host "  Verified: folder preserved, registry entry removed"
  }

  # Test 4: Uninstall nonexistent repo (should fail)
  $testResults += Test-Step "Uninstall nonexistent repo fails" {
    & $strapCmd uninstall nonexistent-repo --yes 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { throw "Command should have failed but succeeded" }
    Write-Host "  Verified: command failed as expected"
  }

  # Test 5: Idempotency (folder already gone)
  $testResults += Test-Step "Idempotency when folder already deleted" {
    # Manually remove the folder
    Remove-Item -Recurse -Force -LiteralPath "P:\software\_scripts\test-uninstall-3"

    # Now uninstall (should succeed even though folder is gone)
    & $strapCmd uninstall test-uninstall-3 --yes
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

    # Check registry entry is gone
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entry = $registry | Where-Object { $_.name -eq "test-uninstall-3" }
    if ($entry) { throw "Registry entry was not removed" }
    Write-Host "  Verified: idempotent behavior (missing folder handled gracefully)"
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

  # Clean up any leftover folders
  $dirsToRemove = @(
    "P:\software\_scripts\test-uninstall-1",
    "P:\software\test-uninstall-2",
    "P:\software\_scripts\test-uninstall-3"
  )

  foreach ($dir in $dirsToRemove) {
    if (Test-Path $dir) {
      Write-Host "Removing $dir"
      Remove-Item -Recurse -Force -LiteralPath $dir
    }
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

    # Clean up on failure too
    $dirsToRemove = @(
      "P:\software\_scripts\test-uninstall-1",
      "P:\software\test-uninstall-2",
      "P:\software\_scripts\test-uninstall-3"
    )

    foreach ($dir in $dirsToRemove) {
      if (Test-Path $dir) {
        Remove-Item -Recurse -Force -LiteralPath $dir -ErrorAction SilentlyContinue
      }
    }

    # Restore registry backup
    if ($registryBackup) {
      [System.IO.File]::WriteAllText($registryPath, $registryBackup, (New-Object System.Text.UTF8Encoding($false)))
    }
  }

  exit 1
}
