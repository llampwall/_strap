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
$strapPs1 = "P:\software\_strap\build\strap.ps1"
$registryPath = "P:\software\_strap\build\registry.json"

# Backup registry if it exists
$registryBackup = $null
if (Test-Path $registryPath) {
  $registryBackup = Get-Content -LiteralPath $registryPath -Raw
}

try {
  # Test 1: Migrate from V0 (bare array) to V1
  $testResults += Test-Step "Migrate from V0 array to V1" {
    # Create V0 registry (bare array)
    $v0Registry = @(
      [PSCustomObject]@{
        name = "test-migrate-1"
        scope = "software"
        path = "P:\software\test-migrate-1"
        shims = @()
        updated_at = "2024-01-01T00:00:00Z"
      }
      [PSCustomObject]@{
        name = "test-migrate-2"
        scope = "tool"
        path = "P:\software\_scripts\test-migrate-2"
        shims = @()
        # Missing created_at, updated_at (should be backfilled)
      }
    )
    $json = $v0Registry | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($registryPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    # Run migrate
    & $strapPs1 migrate --yes
    if ($LASTEXITCODE -ne 0) { throw "Migration failed with exit code $LASTEXITCODE" }

    # Verify result
    $content = Get-Content -LiteralPath $registryPath -Raw
    $migrated = $content | ConvertFrom-Json

    # Check structure
    if (-not $migrated.PSObject.Properties['registry_version']) { throw "Missing registry_version" }
    if ($migrated.registry_version -ne 1) { throw "Version not set to 1" }
    if (-not $migrated.PSObject.Properties['entries']) { throw "Missing entries" }
    if (-not $migrated.PSObject.Properties['updated_at']) { throw "Missing updated_at" }

    # Check entries
    $entries = $migrated.entries
    if ($entries.Count -ne 2) { throw "Expected 2 entries, got $($entries.Count)" }

    # Check first entry
    $entry1 = $entries | Where-Object { $_.name -eq "test-migrate-1" }
    if (-not $entry1) { throw "Entry test-migrate-1 not found" }
    if (-not $entry1.PSObject.Properties['id']) { throw "Missing id field" }
    if (-not $entry1.PSObject.Properties['created_at']) { throw "Missing created_at field" }

    # Check second entry (should have backfilled fields)
    $entry2 = $entries | Where-Object { $_.name -eq "test-migrate-2" }
    if (-not $entry2) { throw "Entry test-migrate-2 not found" }
    if (-not $entry2.PSObject.Properties['id']) { throw "Missing id field" }
    if (-not $entry2.PSObject.Properties['created_at']) { throw "Missing created_at field (should be backfilled)" }
    if (-not $entry2.PSObject.Properties['updated_at']) { throw "Missing updated_at field (should be backfilled)" }

    Write-Host "  Verified: V0 array migrated to V1 with backfilled fields"
  }

  # Test 2: Migrate already at target version (no-op)
  $testResults += Test-Step "Migrate when already at target version" {
    # Registry is already V1 from previous test
    & $strapPs1 migrate --yes
    if ($LASTEXITCODE -ne 0) { throw "Migration failed with exit code $LASTEXITCODE" }

    # Should still be V1
    $content = Get-Content -LiteralPath $registryPath -Raw
    $registry = $content | ConvertFrom-Json
    if ($registry.registry_version -ne 1) { throw "Version changed unexpectedly" }

    Write-Host "  Verified: No-op when already at target version"
  }

  # Test 3: Plan mode (no changes)
  $testResults += Test-Step "Plan mode does not modify registry" {
    # Get current updated_at
    $before = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $updatedAtBefore = $before.updated_at

    Start-Sleep -Seconds 1

    # Run with --plan
    & $strapPs1 migrate --plan
    if ($LASTEXITCODE -ne 0) { throw "Plan failed with exit code $LASTEXITCODE" }

    # Check registry was NOT modified
    $after = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    if ($after.updated_at -ne $updatedAtBefore) { throw "Registry was modified during plan mode" }

    Write-Host "  Verified: Plan mode preserved registry state"
  }

  # Test 4: Dry run mode
  $testResults += Test-Step "Dry run mode does not modify registry" {
    # Create V0 registry again
    $v0Registry = @(
      [PSCustomObject]@{
        name = "test-dryrun"
        scope = "software"
        path = "P:\software\test-dryrun"
        shims = @()
        updated_at = "2024-01-01T00:00:00Z"
      }
    )
    $json = $v0Registry | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($registryPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    # Get file hash before
    $hashBefore = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash

    # Run with --dry-run
    & $strapPs1 migrate --dry-run
    if ($LASTEXITCODE -ne 0) { throw "Dry run failed with exit code $LASTEXITCODE" }

    # Get file hash after
    $hashAfter = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash

    # Check file was NOT modified
    if ($hashBefore -ne $hashAfter) {
      throw "Registry file was modified during dry run"
    }

    Write-Host "  Verified: Dry run preserved registry file"
  }

  # Test 5: Backup creation
  $testResults += Test-Step "Backup creation with --backup" {
    # Create fresh V0 registry
    $v0Registry = @(
      [PSCustomObject]@{
        name = "test-backup"
        scope = "software"
        path = "P:\software\test-backup"
        shims = @()
        updated_at = "2024-01-01T00:00:00Z"
      }
    )
    $json = $v0Registry | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($registryPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    # Small delay to ensure write completes
    Start-Sleep -Milliseconds 100

    # Migrate with --backup
    & $strapPs1 migrate --yes --backup
    if ($LASTEXITCODE -ne 0) { throw "Migration failed with exit code $LASTEXITCODE" }

    # Check backup was created
    $backupFiles = Get-ChildItem -Path (Split-Path $registryPath -Parent) -Filter "registry.json.bak-*"
    if ($backupFiles.Count -eq 0) { throw "No backup file created" }

    # Get latest backup
    $latestBackup = $backupFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    # The backup should preserve whatever was in the file before migration
    # Since we just wrote V0 array, backup should be V0 array
    Write-Host "  Backup file: $($latestBackup.Name)"

    # Clean up backup
    Remove-Item -LiteralPath $latestBackup.FullName -Force

    Write-Host "  Verified: Backup created successfully"
  }

  # Test 6: Duplicate detection fails migration
  Write-Host "`n=== Duplicate detection fails migration ===" -ForegroundColor Cyan

  # Create V0 registry with duplicates
  $v0Duplicates = @(
    [PSCustomObject]@{
      name = "duplicate-name"
      scope = "software"
      path = "P:\software\dup1"
      shims = @()
      updated_at = "2024-01-01T00:00:00Z"
    }
    [PSCustomObject]@{
      name = "duplicate-name"
      scope = "tool"
      path = "P:\software\dup2"
      shims = @()
      updated_at = "2024-01-01T00:00:00Z"
    }
  )
  $json = $v0Duplicates | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($registryPath, $json, (New-Object System.Text.UTF8Encoding($false)))

  # Try to migrate (should fail)
  pwsh -NoProfile -Command "& '$strapPs1' migrate --yes" 2>&1 | Out-Null
  $exitCode = $LASTEXITCODE

  if ($exitCode -ne 0) {
    Write-Host "  Verified: Correctly failed on duplicate entries"
    Write-Host "✓ PASS" -ForegroundColor Green
    $testResults += $true
  } else {
    Write-Host "✗ FAIL: Should have failed on duplicates" -ForegroundColor Red
    $testResults += $false
  }

  # Test 7: Empty registry
  $testResults += Test-Step "Migrate empty registry" {
    # Create empty registry
    "[]" | Set-Content -LiteralPath $registryPath -NoNewline

    # Run migrate
    & $strapPs1 migrate --yes
    if ($LASTEXITCODE -ne 0) { throw "Migration failed with exit code $LASTEXITCODE" }

    # Verify result
    $content = Get-Content -LiteralPath $registryPath -Raw
    $migrated = $content | ConvertFrom-Json

    if ($migrated.registry_version -ne 1) { throw "Version not set to 1" }
    if ($migrated.entries.Count -ne 0) { throw "Expected empty entries array" }

    Write-Host "  Verified: Empty registry migrated to V1"
  }

  # Test 8: Doctor detects outdated registry
  $testResults += Test-Step "Doctor detects outdated registry version" {
    # Create V0 registry
    $v0Registry = @(
      [PSCustomObject]@{
        name = "test-doctor"
        scope = "software"
        path = "P:\software\test-doctor"
        shims = @()
        updated_at = "2024-01-01T00:00:00Z"
      }
    )
    $json = $v0Registry | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($registryPath, $json, (New-Object System.Text.UTF8Encoding($false)))

    # Small delay to ensure write completes
    Start-Sleep -Milliseconds 100

    # Run doctor with JSON output (easier to parse)
    $output = & $strapPs1 doctor --json 2>&1 | Out-String
    if ($LASTEXITCODE -eq 1) { throw "Doctor should not FAIL on outdated registry, should WARN (exit 0)" }

    # Parse JSON output
    try {
      $report = $output | ConvertFrom-Json
    } catch {
      Write-Host "Failed to parse JSON output:" -ForegroundColor Yellow
      Write-Host $output
      throw "Doctor output is not valid JSON: $_"
    }

    # Check registry version is detected
    if (-not $report.registry_check.PSObject.Properties['version']) {
      Write-Host "Registry check object:" -ForegroundColor Yellow
      $report.registry_check | ConvertTo-Json -Depth 5 | Write-Host
      throw "Doctor report missing registry version"
    }

    if ($report.registry_check.version -ne 0) {
      throw "Doctor should detect version 0, got $($report.registry_check.version)"
    }

    # Check there's an issue about outdated version
    $hasVersionIssue = $report.registry_check.issues | Where-Object { $_ -match "(?i)version.*outdated" }
    if (-not $hasVersionIssue) {
      throw "Doctor should report version as outdated"
    }

    Write-Host "  Verified: Doctor detects outdated registry and suggests migration"
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

    # Restore registry backup
    if ($registryBackup) {
      [System.IO.File]::WriteAllText($registryPath, $registryBackup, (New-Object System.Text.UTF8Encoding($false)))
    }
  }

  exit 1
}
