$ErrorActionPreference = "Stop"

$registryPath = "P:\software\_strap\registry.json.test-temp"
$strapPs1 = "P:\software\_strap\strap.ps1"

# Backup actual registry
$actualRegistry = "P:\software\_strap\registry.json"
$actualBackup = $null
if (Test-Path $actualRegistry) {
  $actualBackup = Get-Content -LiteralPath $actualRegistry -Raw
}

# Point to test registry
$env:_STRAP_REGISTRY_OVERRIDE = $registryPath

try {
  # Create V0 registry
  Write-Host "Creating V0 registry..."
  $v0Registry = @(
    [PSCustomObject]@{
      name = 'test'
      scope = 'software'
      path = 'P:\test'
      shims = @()
      updated_at = '2024-01-01T00:00:00Z'
    }
  )
  $json = $v0Registry | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($registryPath, $json, (New-Object System.Text.UTF8Encoding($false)))

  # Check it's V0
  Write-Host "`nBefore dry-run:"
  $before = Get-Content -LiteralPath $registryPath -Raw
  Write-Host "Content: $($before.Substring(0, [Math]::Min(100, $before.Length)))..."
  $beforeObj = $before | ConvertFrom-Json
  Write-Host "Is array: $($beforeObj -is [array])"

  # Run migrate dry-run
  Write-Host "`nRunning migrate --dry-run..."
  & $strapPs1 migrate --dry-run 2>&1 | Out-String | Write-Host

  # Check after
  Write-Host "`nAfter dry-run:"
  $after = Get-Content -LiteralPath $registryPath -Raw
  Write-Host "Content: $($after.Substring(0, [Math]::Min(100, $after.Length)))..."
  $afterObj = $after | ConvertFrom-Json
  Write-Host "Is array: $($afterObj -is [array])"

  if ($afterObj -is [array]) {
    Write-Host "`n✓ SUCCESS: Registry still V0 array after dry-run" -ForegroundColor Green
  } else {
    Write-Host "`n✗ FAIL: Registry converted to object after dry-run" -ForegroundColor Red
    exit 1
  }

} finally {
  # Cleanup
  if (Test-Path $registryPath) {
    Remove-Item -LiteralPath $registryPath -Force
  }

  # Restore actual registry
  if ($actualBackup) {
    [System.IO.File]::WriteAllText($actualRegistry, $actualBackup, (New-Object System.Text.UTF8Encoding($false)))
  }
}
