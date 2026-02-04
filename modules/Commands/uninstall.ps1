# uninstall.ps1
# Command: Invoke-Uninstall

function Invoke-Uninstall {
  param(
    [string] $NameToRemove,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $PreserveFolder,
    [switch] $PreserveShims,
    [switch] $NoChinvex,
    [string] $StrapRootPath
  )

  if (-not $NameToRemove) { Die "uninstall requires <name>" }

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Find entry by name
  $entry = $registry | Where-Object { $_.name -eq $NameToRemove }
  if (-not $entry) {
    Die "No entry found with name '$NameToRemove'. Use 'strap list' to see all entries."
  }

  # Safety validation - check managed roots
  $softwareRoot = $config.roots.software
  $toolsRoot = $config.roots.tools
  $shimsRoot = $config.roots.shims

  # Validate repo path
  $repoPath = $entry.path
  if (-not $repoPath) {
    Die "Registry entry has no path field"
  }

  # Check that path is within managed roots
  $pathIsManaged = $repoPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase) -or
                   $repoPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

  if (-not $pathIsManaged) {
    Die "Path is not within managed roots: $repoPath"
  }

  # Disallow deleting the root directories themselves
  if ($repoPath -eq $softwareRoot -or $repoPath -eq $toolsRoot) {
    Die "Cannot delete root directory: $repoPath"
  }

  # Validate shim paths
  $shimsToDelete = @()
  if (-not $PreserveShims -and $entry.shims) {
    foreach ($shim in $entry.shims) {
      # Must be absolute
      if (-not [System.IO.Path]::IsPathRooted($shim)) {
        Die "Shim path is not absolute: $shim"
      }

      # Must be within shims root
      if (-not $shim.StartsWith($shimsRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Die "Shim path is not within shims root: $shim"
      }

      # Must not be the root directory itself
      if ($shim -eq $shimsRoot) {
        Die "Cannot delete shims root directory: $shim"
      }

      # Must be a file path (ends with .cmd, .ps1, etc., not a directory)
      if (Test-Path $shim) {
        $item = Get-Item -LiteralPath $shim
        if ($item.PSIsContainer) {
          Die "Shim path is a directory, not a file: $shim"
        }
      }

      $shimsToDelete += $shim
    }
  }

  # Preview
  Write-Host ""
  Write-Host "=== UNINSTALL PREVIEW ===" -ForegroundColor Cyan
  Write-Host "Entry:  $($entry.name)"
  if ($entry.url) {
    Write-Host "URL:    $($entry.url)"
  }
  Write-Host "Path:   $repoPath"

  if ($shimsToDelete.Count -gt 0) {
    Write-Host ""
    Write-Host "Will remove shims:" -ForegroundColor Yellow
    foreach ($shim in $shimsToDelete) {
      Write-Host "  - $shim"
    }
  } elseif ($PreserveShims -and $entry.shims -and $entry.shims.Count -gt 0) {
    Write-Host ""
    Write-Host "Will keep shims (--keep-shims):" -ForegroundColor Green
    foreach ($shim in $entry.shims) {
      Write-Host "  - $shim"
    }
  }

  if (-not $PreserveFolder) {
    Write-Host ""
    Write-Host "Will remove folder:" -ForegroundColor Yellow
    Write-Host "  - $repoPath"
  } else {
    Write-Host ""
    Write-Host "Will keep folder (--keep-folder):" -ForegroundColor Green
    Write-Host "  - $repoPath"
  }

  Write-Host ""
  Write-Host "Will remove registry entry: $($entry.name)" -ForegroundColor Yellow

  if ($DryRunMode) {
    Write-Host ""
    Write-Host "DRY RUN - no changes will be made" -ForegroundColor Cyan
    return
  }

  # Confirmation
  if (-not $NonInteractive) {
    Write-Host ""
    $response = Read-Host "Proceed? (y/n)"
    if ($response -ne "y") {
      Info "Aborted by user"
      exit 1
    }
  }

  Write-Host ""

  # Chinvex cleanup (BEFORE removing shims/folder/registry)
  if (Test-ChinvexEnabled -NoChinvex:$NoChinvex -StrapRootPath $StrapRootPath) {
    if ($entry.chinvex_context) {
      $deleted = Invoke-Chinvex -Arguments @("context", "delete", $entry.chinvex_context, "--force")
      if ($deleted) {
        Info "Chinvex: deleted context '$($entry.chinvex_context)'"
      } else {
        Warn "Chinvex: failed to delete context '$($entry.chinvex_context)' (continuing with uninstall)"
      }
    }
  }

  # Execute deletions
  # 1. Remove shims
  if ($shimsToDelete.Count -gt 0) {
    Info "Removing shims..."
    foreach ($shim in $shimsToDelete) {
      if (-not (Test-Path $shim)) {
        Write-Host "  skip (not found): $shim" -ForegroundColor Gray
      } else {
        try {
          Remove-Item -LiteralPath $shim -Force -ErrorAction Stop
          Write-Host "  deleted: $shim" -ForegroundColor Green
        } catch {
          Write-Host "  ERROR deleting $shim : $_" -ForegroundColor Red
          Die "Failed to delete shim: $shim"
        }
      }
    }
  }

  # 2. Remove folder
  if (-not $PreserveFolder) {
    Info "Removing folder..."
    if (-not (Test-Path $repoPath)) {
      Write-Host "  skip (not found): $repoPath" -ForegroundColor Gray
    } else {
      try {
        Remove-Item -LiteralPath $repoPath -Recurse -Force -ErrorAction Stop
        Write-Host "  deleted: $repoPath" -ForegroundColor Green
      } catch {
        Write-Host "  ERROR deleting $repoPath : $_" -ForegroundColor Red
        Die "Failed to delete folder: $repoPath"
      }
    }
  }

  # 3. Remove registry entry
  Info "Updating registry..."
  $newRegistry = @()
  foreach ($item in $registry) {
    if ($item.name -ne $NameToRemove) {
      $newRegistry += $item
    }
  }

  try {
    Save-Registry $config $newRegistry
    Ok "Registry updated"
  } catch {
    Write-Host "ERROR updating registry: $_" -ForegroundColor Red
    exit 3
  }

  Write-Host ""
  Ok "Uninstalled '$NameToRemove'"
}

