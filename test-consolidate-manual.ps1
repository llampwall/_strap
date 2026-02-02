$ErrorActionPreference = 'Stop'

# Create test directory
$testRoot = Join-Path $env:TEMP "strap-consolidate-test-$(Get-Random)"
Write-Host "Creating test directory: $testRoot"

if (Test-Path $testRoot) {
  Remove-Item -LiteralPath $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

# Create a test git repo
$testRepo = Join-Path $testRoot "test-repo"
New-Item -ItemType Directory -Path $testRepo -Force | Out-Null
Push-Location $testRepo
try {
  git init
  git config user.email "test@test.com"
  git config user.name "Test User"
  "# Test Repo" | Set-Content "README.md"
  git add .
  git commit -m "Initial commit"
} finally {
  Pop-Location
}

Write-Host "`nTest repo created at: $testRepo"
Write-Host "`nNow testing: strap consolidate --from `"$testRoot`" --dry-run"
Write-Host ""

# Test the consolidate command
& "P:\software\_strap\strap.cmd" consolidate --from $testRoot --dry-run

Write-Host "`n`nTest directory: $testRoot"
Write-Host "Cleanup: Remove-Item -LiteralPath '$testRoot' -Recurse -Force"
