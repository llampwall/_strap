# purge.ps1
# Command: Invoke-Purge
# Clears the entire registry (removes all repository entries)

function Invoke-Purge {
  param(
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $NoChinvex,
    [switch] $CleanupChinvex,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  if ($registry.Count -eq 0) {
    Info "Registry is already empty; nothing to purge"
    exit 0
  }

  # Preview
  Write-Host ""
  Write-Host "=== PURGE REGISTRY ===" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "This will remove ALL repository entries from the registry." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Entries to be removed: $($registry.Count)" -ForegroundColor Yellow
  Write-Host ""

  # List all entries
  foreach ($entry in $registry) {
    Write-Host "  - $($entry.name)" -ForegroundColor Gray
    if ($entry.path) {
      Write-Host "    path: $($entry.path)" -ForegroundColor DarkGray
    }
    if ($entry.shims -and $entry.shims.Count -gt 0) {
      Write-Host "    shims: $($entry.shims.Count)" -ForegroundColor DarkGray
    }
  }

  Write-Host ""
  Write-Host "NOTE: This command only clears the registry." -ForegroundColor Yellow
  Write-Host "      It does NOT delete folders or shims." -ForegroundColor Yellow
  Write-Host "      Use 'strap uninstall' to fully remove repositories." -ForegroundColor Yellow
  Write-Host ""

  if ($CleanupChinvex) {
    Write-Host "Will also attempt to delete chinvex contexts (--cleanup-chinvex)" -ForegroundColor Yellow
    Write-Host ""
  }

  if ($DryRunMode) {
    Write-Host "DRY RUN - no changes will be made" -ForegroundColor Cyan
    return
  }

  # Confirmation
  if (-not $NonInteractive) {
    $response = Read-Host "Are you sure you want to purge the entire registry? (y/n)"
    if ($response -ne "y") {
      Info "Aborted by user"
      exit 1
    }
  }

  Write-Host ""

  # Chinvex cleanup (if requested)
  if ($CleanupChinvex -and (Test-ChinvexEnabled -NoChinvex:$NoChinvex -StrapRootPath $StrapRootPath)) {
    Info "Cleaning up chinvex contexts..."
    $cleaned = 0
    $failed = 0

    foreach ($entry in $registry) {
      if ($entry.chinvex_context) {
        $deleted = Invoke-Chinvex -Arguments @("context", "purge", $entry.chinvex_context) -StdIn "y"
        if ($deleted) {
          Write-Host "  deleted: $($entry.chinvex_context)" -ForegroundColor Green
          $cleaned++
        } else {
          Write-Host "  failed: $($entry.chinvex_context)" -ForegroundColor Yellow
          $failed++
        }
      }
    }

    if ($cleaned -gt 0) {
      Info "Cleaned up $cleaned chinvex context(s)"
    }
    if ($failed -gt 0) {
      Warn "Failed to clean up $failed chinvex context(s)"
    }
  }

  # Clear the registry
  Info "Purging registry..."
  try {
    Save-Registry $config @()
    Ok "Registry purged (all entries removed)"
  } catch {
    Write-Host "ERROR purging registry: $_" -ForegroundColor Red
    exit 3
  }

  Write-Host ""
  Info "Registry is now empty"
  Info "Use 'strap list' to verify"
}
