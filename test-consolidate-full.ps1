$ErrorActionPreference = 'Stop'

# Create test directory
$testRoot = Join-Path $env:TEMP "strap-consolidate-full-$(Get-Random)"
Write-Host "Creating test directory: $testRoot"

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

# Create test git repo
$testRepo = Join-Path $testRoot "consolidate-test-repo"
New-Item -ItemType Directory -Path $testRepo -Force | Out-Null
Push-Location $testRepo
try {
  git init | Out-Null
  git config user.email "test@test.com" | Out-Null
  git config user.name "Test User" | Out-Null
  "# Test Repo" | Set-Content "README.md"
  git add . | Out-Null
  git commit -m "Initial commit" | Out-Null
} finally {
  Pop-Location
}

Write-Host "Created test repo: $testRepo"
Write-Host "`nBacking up registry..."

# Backup registry
$registryPath = "P:\software\_strap\registry.json"
$backupPath = "$registryPath.test-backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
if (Test-Path $registryPath) {
  Copy-Item -LiteralPath $registryPath -Destination $backupPath
  Write-Host "Registry backed up to: $backupPath" -ForegroundColor Yellow
}

Write-Host "`nRunning: strap consolidate --from `"$testRoot`" --yes"
Write-Host ""

# Run consolidate
& "P:\software\_strap\strap.cmd" consolidate --from $testRoot --yes

Write-Host "`n`nCleanup commands:"
Write-Host "  Remove test dir: Remove-Item -LiteralPath '$testRoot' -Recurse -Force"
Write-Host "  Restore registry: Copy-Item -LiteralPath '$backupPath' -Destination '$registryPath' -Force"
