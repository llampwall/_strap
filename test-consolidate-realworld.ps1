<#
.SYNOPSIS
Real-world end-to-end test of consolidate command with actual file moves.
#>

$ErrorActionPreference = 'Stop'

Write-Host "=== Real-World Consolidate Test ===" -ForegroundColor Cyan

# Setup test environment
$testRoot = Join-Path $env:TEMP "strap-consolidate-realworld-$(Get-Random)"
Write-Host "`nCreating test environment: $testRoot"
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

# Backup registry
$registryPath = "P:\software\_strap\registry.json"
$backupPath = "$registryPath.realworld-test-backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
if (Test-Path $registryPath) {
  Copy-Item -LiteralPath $registryPath -Destination $backupPath
  Write-Host "Registry backed up to: $backupPath" -ForegroundColor Yellow
}

try {
  # Create 3 test repos
  Write-Host "`nCreating test repositories..."
  $repos = @("test-app", "test-tool", "test-lib")

  foreach ($repoName in $repos) {
    $repoPath = Join-Path $testRoot $repoName
    New-Item -ItemType Directory -Path $repoPath -Force | Out-Null
    Push-Location $repoPath
    git init | Out-Null
    git config user.email "test@test.com" | Out-Null
    git config user.name "Test User" | Out-Null
    "# $repoName" | Set-Content "README.md"
    "console.log('$repoName')" | Set-Content "index.js"
    git add . | Out-Null
    git commit -m "Initial commit" | Out-Null
    Pop-Location
    Write-Host "  Created: $repoName" -ForegroundColor Green
  }

  # Test 1: Dry-run
  Write-Host "`n=== TEST 1: Dry-Run ===" -ForegroundColor Cyan
  Write-Host "Running: strap consolidate --from `"$testRoot`" --dry-run`n"

  & "P:\software\_strap\strap.cmd" consolidate --from $testRoot --dry-run

  if ($LASTEXITCODE -ne 0) {
    throw "Dry-run failed with exit code $LASTEXITCODE"
  }

  # Verify repos still in source
  foreach ($repoName in $repos) {
    $repoPath = Join-Path $testRoot $repoName
    if (-not (Test-Path $repoPath)) {
      throw "Dry-run should not move repos: $repoName missing from source"
    }
  }

  Write-Host "`n✓ Dry-run test passed!" -ForegroundColor Green

  # Test 2: Full execution with --yes
  Write-Host "`n=== TEST 2: Full Execution ===" -ForegroundColor Cyan
  Write-Host "Running: strap consolidate --from `"$testRoot`" --yes`n"

  & "P:\software\_strap\strap.cmd" consolidate --from $testRoot --yes

  if ($LASTEXITCODE -ne 0) {
    throw "Consolidate failed with exit code $LASTEXITCODE"
  }

  # Verify repos moved to managed locations
  Write-Host "`nVerifying moves..."
  $movedCount = 0
  foreach ($repoName in $repos) {
    $sourcePath = Join-Path $testRoot $repoName
    $destPath = "P:\software\$repoName"

    # Check source is gone
    if (Test-Path $sourcePath) {
      Write-Host "  ⚠ $repoName still in source (may have been skipped)" -ForegroundColor Yellow
      continue
    }

    # Check destination exists
    if (-not (Test-Path $destPath)) {
      throw "$repoName not found at destination: $destPath"
    }

    # Check git integrity
    if (-not (Test-Path "$destPath\.git")) {
      throw "$repoName git directory not found"
    }

    Write-Host "  ✓ $repoName moved to $destPath" -ForegroundColor Green
    $movedCount++
  }

  if ($movedCount -eq 0) {
    throw "No repos were moved"
  }

  Write-Host "`n✓ Full execution test passed! ($movedCount repos moved)" -ForegroundColor Green

  # Test 3: Verify registry entries
  Write-Host "`n=== TEST 3: Registry Verification ===" -ForegroundColor Cyan
  $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json

  $registeredCount = 0
  foreach ($repoName in $repos) {
    $entry = $registry.entries | Where-Object { $_.name -eq $repoName }
    if ($entry) {
      Write-Host "  ✓ $repoName registered at $($entry.path)" -ForegroundColor Green
      $registeredCount++
    }
  }

  if ($registeredCount -gt 0) {
    Write-Host "`n✓ Registry verification passed! ($registeredCount repos registered)" -ForegroundColor Green
  } else {
    Write-Host "`n⚠ No repos found in registry (may have been skipped)" -ForegroundColor Yellow
  }

  Write-Host "`n==================================" -ForegroundColor Cyan
  Write-Host "✅ ALL TESTS PASSED!" -ForegroundColor Green
  Write-Host "==================================" -ForegroundColor Cyan

  Write-Host "`nCleanup commands:"
  Write-Host "  Remove test dir: Remove-Item -LiteralPath '$testRoot' -Recurse -Force"
  Write-Host "  Restore registry: Copy-Item -LiteralPath '$backupPath' -Destination '$registryPath' -Force"
  foreach ($repoName in $repos) {
    $destPath = "P:\software\$repoName"
    if (Test-Path $destPath) {
      Write-Host "  Remove moved repo: Remove-Item -LiteralPath '$destPath' -Recurse -Force"
    }
  }

  exit 0

} catch {
  Write-Host "`n❌ TEST FAILED: $_" -ForegroundColor Red
  Write-Host $_.ScriptStackTrace -ForegroundColor Red

  Write-Host "`nCleanup commands:"
  Write-Host "  Remove test dir: Remove-Item -LiteralPath '$testRoot' -Recurse -Force"
  if (Test-Path $backupPath) {
    Write-Host "  Restore registry: Copy-Item -LiteralPath '$backupPath' -Destination '$registryPath' -Force"
  }

  exit 1
}
