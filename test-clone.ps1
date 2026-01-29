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
$strapCmd = "P:\software\_strap\build\strap.cmd"
$registryPath = "P:\software\_strap\build\registry.json"

# Backup registry if it exists
$registryBackup = $null
if (Test-Path $registryPath) {
  $registryBackup = Get-Content -LiteralPath $registryPath -Raw
}

try {
  # Test 1: HTTP URL no .git with --tool
  $testResults += Test-Step "HTTP URL no .git with --tool" {
    & $strapCmd clone "https://github.com/psf/requests" --tool
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path "P:\software\_scripts\requests")) { throw "Clone directory not created" }
    if (-not (Test-Path "P:\software\_scripts\requests\.git")) { throw "Not a git repo" }

    # Check registry
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entry = $registry | Where-Object { $_.name -eq "requests" -and $_.scope -eq "tool" }
    if (-not $entry) { throw "Registry entry not found" }
    if ($entry.path -ne "P:\software\_scripts\requests") { throw "Registry path incorrect: $($entry.path)" }
    Write-Host "  Registry: name=$($entry.name), scope=$($entry.scope), path=$($entry.path)"
  }

  # Test 2: HTTP URL with .git (no --tool, goes to software) - use unique name
  $testResults += Test-Step "HTTP URL with .git (software dir)" {
    & $strapCmd clone "https://github.com/psf/requests.git" --name "requests-software"
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path "P:\software\requests-software")) { throw "Clone directory not created" }
    if (-not (Test-Path "P:\software\requests-software\.git")) { throw "Not a git repo" }

    # Check registry
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entry = $registry | Where-Object { $_.name -eq "requests-software" -and $_.scope -eq "software" }
    if (-not $entry) { throw "Registry entry not found" }
    if ($entry.path -ne "P:\software\requests-software") { throw "Registry path incorrect: $($entry.path)" }
    Write-Host "  Registry: name=$($entry.name), scope=$($entry.scope), path=$($entry.path)"
  }

  # Test 3: Name override with --tool (using HTTPS instead of SSH)
  $testResults += Test-Step "Name override with custom name" {
    & $strapCmd clone "https://github.com/psf/requests.git" --tool --name requests-custom
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path "P:\software\_scripts\requests-custom")) { throw "Clone directory not created" }
    if (-not (Test-Path "P:\software\_scripts\requests-custom\.git")) { throw "Not a git repo" }

    # Check registry
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entry = $registry | Where-Object { $_.name -eq "requests-custom" }
    if (-not $entry) { throw "Registry entry not found" }
    Write-Host "  Registry: name=$($entry.name), scope=$($entry.scope), path=$($entry.path)"
  }

  # Test 4: Name override
  $testResults += Test-Step "Name override with --tool" {
    & $strapCmd clone "https://github.com/psf/requests" --tool --name requests2
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path "P:\software\_scripts\requests2")) { throw "Clone directory not created" }
    if (-not (Test-Path "P:\software\_scripts\requests2\.git")) { throw "Not a git repo" }

    # Check registry
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entry = $registry | Where-Object { $_.name -eq "requests2" }
    if (-not $entry) { throw "Registry entry not found" }
    if ($entry.path -ne "P:\software\_scripts\requests2") { throw "Registry path incorrect: $($entry.path)" }
    Write-Host "  Registry: name=$($entry.name), scope=$($entry.scope), path=$($entry.path)"
  }

  # Test 5: Dest override - use unique name
  $testResults += Test-Step "Dest override" {
    & $strapCmd clone "https://github.com/psf/requests" --dest "P:\software\_scripts\_scratch\RequestsX" --name "requests-dest"
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
    if (-not (Test-Path "P:\software\_scripts\_scratch\RequestsX")) { throw "Clone directory not created" }
    if (-not (Test-Path "P:\software\_scripts\_scratch\RequestsX\.git")) { throw "Not a git repo" }

    # Check registry
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
    $entry = $registry | Where-Object { $_.name -eq "requests-dest" -and $_.path -like "*RequestsX" }
    if (-not $entry) { throw "Registry entry not found" }
    Write-Host "  Registry: name=$($entry.name), scope=$($entry.scope), path=$($entry.path)"
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

  # Clean up cloned repos
  $dirsToRemove = @(
    "P:\software\_scripts\requests",
    "P:\software\requests-software",
    "P:\software\_scripts\requests-custom",
    "P:\software\_scripts\requests2",
    "P:\software\_scripts\_scratch\RequestsX"
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
      "P:\software\_scripts\requests",
      "P:\software\requests-software",
      "P:\software\_scripts\requests-custom",
      "P:\software\_scripts\requests2",
      "P:\software\_scripts\_scratch\RequestsX"
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
