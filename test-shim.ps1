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

function Test-ExpectedFailure {
  param([string] $Name, [scriptblock] $Action)
  Write-Host "`n=== $Name ===" -ForegroundColor Cyan
  $originalErrorPref = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    & $Action
    $ErrorActionPreference = $originalErrorPref
    Write-Host "✓ PASS" -ForegroundColor Green
    return $true
  } catch {
    $ErrorActionPreference = $originalErrorPref
    Write-Host "✗ FAIL: $_" -ForegroundColor Red
    return $false
  }
}

$testResults = @()
$strapPs1 = "P:\software\_strap\strap.ps1"
$strapCmd = "P:\software\_strap\strap.cmd"
$registryPath = "P:\software\_strap\registry.json"
$shimsPath = "P:\software\_scripts\_bin"

# Backup registry if it exists
$registryBackup = $null
if (Test-Path $registryPath) {
  $registryBackup = Get-Content -LiteralPath $registryPath -Raw
}

try {
  # Setup: Clone test repo
  Write-Host "`n=== SETUP ===" -ForegroundColor Cyan
  & $strapCmd clone "https://github.com/psf/requests" --tool --name test-shim-repo
  if ($LASTEXITCODE -ne 0) { throw "Setup failed: clone test-shim-repo" }
  Write-Host "✓ Setup complete" -ForegroundColor Green

  # Test 1: Create basic shim from inside repo directory
  $testResults += Test-Step "Create basic shim from repo directory" {
    Push-Location "P:\software\_scripts\test-shim-repo"
    try {
      & $strapPs1 shim basic-shim --yes --- python script.py
      if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

      # Check shim file was created
      if (-not (Test-Path "$shimsPath\basic-shim.cmd")) { throw "Shim file not created" }

      # Check shim content
      $content = Get-Content "$shimsPath\basic-shim.cmd" -Raw
      if ($content -notmatch "python script\.py") { throw "Shim content incorrect" }

      # Check registry was updated
      $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
      $entry = $registry | Where-Object { $_.name -eq "test-shim-repo" }
      if (-not $entry) { throw "Registry entry not found" }
      if ($entry.shims.Count -ne 1) { throw "Shim not added to registry" }
      if ($entry.shims[0] -notlike "*basic-shim.cmd") { throw "Shim path incorrect in registry" }

      Write-Host "  Verified: shim created, registry updated"
    } finally {
      Pop-Location
    }
  }

  # Test 2: Create shim with --cwd flag
  $testResults += Test-Step "Create shim with --cwd" {
    Push-Location "P:\software\_scripts\test-shim-repo"
    try {
      & $strapPs1 shim cwd-shim --yes --cwd "P:\software\_scripts\test-shim-repo" --- python test.py
      if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

      # Check shim content includes pushd/popd
      $content = Get-Content "$shimsPath\cwd-shim.cmd" -Raw
      if ($content -notmatch "pushd") { throw "Shim missing pushd" }
      if ($content -notmatch "popd") { throw "Shim missing popd" }

      Write-Host "  Verified: shim includes working directory commands"
    } finally {
      Pop-Location
    }
  }

  # Test 3: Create shim with --repo from different directory
  $testResults += Test-Step "Create shim with --repo flag" {
    Push-Location "P:\software"
    try {
      & $strapPs1 shim repo-shim --yes --repo test-shim-repo --- python main.py
      if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

      # Check shim was created
      if (-not (Test-Path "$shimsPath\repo-shim.cmd")) { throw "Shim file not created" }

      # Check it was attached to correct repo
      $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
      $entry = $registry | Where-Object { $_.name -eq "test-shim-repo" }
      if ($entry.shims.Count -ne 3) { throw "Shim count incorrect (expected 3, got $($entry.shims.Count))" }

      Write-Host "  Verified: shim attached to correct repo from different directory"
    } finally {
      Pop-Location
    }
  }

  # Test 4: Overwrite protection (should fail without --force)
  Write-Host "`n=== Overwrite protection without --force ===" -ForegroundColor Cyan
  Push-Location "P:\software\_scripts\test-shim-repo"
  pwsh -NoProfile -Command "& '$strapPs1' shim basic-shim --yes --- python updated.py" 2>&1 | Out-Null
  $exitCode = $LASTEXITCODE
  Pop-Location
  if ($exitCode -ne 0) {
    Write-Host "  Verified: overwrite correctly rejected"
    Write-Host "✓ PASS" -ForegroundColor Green
    $testResults += $true
  } else {
    Write-Host "✗ FAIL: Command should have failed but succeeded" -ForegroundColor Red
    $testResults += $false
  }

  # Test 5: Overwrite with --force
  $testResults += Test-Step "Overwrite with --force" {
    Push-Location "P:\software\_scripts\test-shim-repo"
    try {
      & $strapPs1 shim basic-shim --yes --force --- python updated.py
      if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

      # Check shim content was updated
      $content = Get-Content "$shimsPath\basic-shim.cmd" -Raw
      if ($content -notmatch "python updated\.py") { throw "Shim content not updated" }

      Write-Host "  Verified: shim successfully overwritten"
    } finally {
      Pop-Location
    }
  }

  # Test 6: Dry run does not create files
  $testResults += Test-Step "Dry run does not create files" {
    Push-Location "P:\software\_scripts\test-shim-repo"
    try {
      & $strapPs1 shim dryrun-shim --dry-run --- python dry.py
      if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

      # Check shim was NOT created
      if (Test-Path "$shimsPath\dryrun-shim.cmd") { throw "Shim file was created (should be dry run)" }

      # Check registry was NOT updated
      $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
      $entry = $registry | Where-Object { $_.name -eq "test-shim-repo" }
      if ($entry.shims.Count -ne 3) { throw "Registry was modified (should be dry run)" }

      Write-Host "  Verified: dry run preserved state"
    } finally {
      Pop-Location
    }
  }

  # Test 7: Create shim using --cmd mode (avoids PowerShell parameter binding)
  $testResults += Test-Step "Create shim with --cmd mode" {
    Push-Location "P:\software\_scripts\test-shim-repo"
    try {
      & $strapPs1 shim cmd-mode-shim --yes --cmd "python -m flask run" --repo test-shim-repo
      if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }

      # Check shim file was created
      if (-not (Test-Path "$shimsPath\cmd-mode-shim.cmd")) { throw "Shim file not created" }

      # Check shim content includes command with -m flag
      $content = Get-Content "$shimsPath\cmd-mode-shim.cmd" -Raw
      if ($content -notmatch "python -m flask run") { throw "Shim content incorrect" }

      # Check registry was updated
      $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
      $entry = $registry | Where-Object { $_.name -eq "test-shim-repo" }
      if ($entry.shims.Count -ne 4) { throw "Shim not added to registry" }

      Write-Host "  Verified: --cmd mode preserves flags like -m"
    } finally {
      Pop-Location
    }
  }

  # Test 9: Invalid shim name (with path separators)
  Write-Host "`n=== Invalid shim name rejected ===" -ForegroundColor Cyan
  Push-Location "P:\software\_scripts\test-shim-repo"
  pwsh -NoProfile -Command "& '$strapPs1' shim 'bad/name' --yes --- python test.py" 2>&1 | Out-Null
  $exitCode = $LASTEXITCODE
  Pop-Location
  if ($exitCode -ne 0) {
    Write-Host "  Verified: invalid name correctly rejected"
    Write-Host "✓ PASS" -ForegroundColor Green
    $testResults += $true
  } else {
    Write-Host "✗ FAIL: Command should have failed but succeeded" -ForegroundColor Red
    $testResults += $false
  }

  # Test 10: No registry entry for current directory (should fail)
  Write-Host "`n=== Fail when no registry entry found ===" -ForegroundColor Cyan
  Push-Location "P:\software"
  pwsh -NoProfile -Command "& '$strapPs1' shim orphan-shim --yes --- python test.py" 2>&1 | Out-Null
  $exitCode = $LASTEXITCODE
  Pop-Location
  if ($exitCode -ne 0) {
    Write-Host "  Verified: correctly failed when no registry entry found"
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

  # Clean up shims
  $shimsToRemove = @(
    "$shimsPath\basic-shim.cmd",
    "$shimsPath\cwd-shim.cmd",
    "$shimsPath\repo-shim.cmd",
    "$shimsPath\cmd-mode-shim.cmd"
  )

  foreach ($shim in $shimsToRemove) {
    if (Test-Path $shim) {
      Write-Host "Removing $shim"
      Remove-Item -LiteralPath $shim
    }
  }

  # Uninstall test repo
  & $strapCmd uninstall test-shim-repo --yes

  # Restore registry backup
  if ($registryBackup) {
    Write-Host "Restoring registry backup"
    [System.IO.File]::WriteAllText($registryPath, $registryBackup, (New-Object System.Text.UTF8Encoding($false)))
  } else {
    Write-Host "Clearing registry (no backup existed)"
    "[]" | Set-Content -LiteralPath $registryPath -NoNewline
  }

  Write-Host "`n✓ ALL TESTS PASSED" -ForegroundColor Green

  # Note about solution to PowerShell parameter binding
  Write-Host "`n📝 NOTE: PowerShell parameter binding with --- separator" -ForegroundColor Yellow
  Write-Host "Commands with single-letter flags (like 'python -m module') may conflict with" -ForegroundColor Yellow
  Write-Host "PowerShell parameters when using the --- separator." -ForegroundColor Yellow
  Write-Host "Solution: Use --cmd `"<command>`" instead of --- <command...>" -ForegroundColor Green
  Write-Host "Example: strap shim flask --cmd `"python -m flask run`"" -ForegroundColor Green

} catch {
  Write-Host "`n✗ TEST SUITE FAILED: $_" -ForegroundColor Red

  if (-not $KeepOnFailure) {
    Write-Host "`nCleaning up (use -KeepOnFailure to preserve test artifacts)..." -ForegroundColor Yellow

    # Clean up shims
    Get-ChildItem "$shimsPath\*.cmd" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    # Uninstall test repo
    & $strapCmd uninstall test-shim-repo --yes 2>&1 | Out-Null

    # Restore registry backup
    if ($registryBackup) {
      [System.IO.File]::WriteAllText($registryPath, $registryBackup, (New-Object System.Text.UTF8Encoding($false)))
    }
  }

  exit 1
}
