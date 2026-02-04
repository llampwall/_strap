# move.ps1
# Command: Invoke-Move

function Invoke-Move {
  param(
    [string] $NameToMove,
    [string] $DestPath,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $ForceOverwrite,
    [switch] $RehomeShims,
    [switch] $NoChinvex,
    [string] $StrapRootPath
  )

  if (-not $NameToMove) { Die "move requires <name>" }
  if (-not $DestPath) { Die "move requires --dest <path>" }

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config
  $softwareRoot = $config.roots.software
  $toolsRoot = $config.roots.tools

  # Find entry by name
  $entry = $registry | Where-Object { $_.name -eq $NameToMove }
  if (-not $entry) {
    Die "No entry found with name '$NameToMove'. Use 'strap list' to see all entries."
  }

  $oldPath = $entry.path
  if (-not $oldPath) {
    Die "Registry entry has no path field"
  }

  # Validate source is absolute and inside managed roots
  if (-not [System.IO.Path]::IsPathRooted($oldPath)) {
    Die "Source path is not absolute: $oldPath"
  }

  $oldPathIsManaged = $oldPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase) -or
                      $oldPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

  if (-not $oldPathIsManaged) {
    Die "Source path is not within managed roots: $oldPath"
  }

  if (-not (Test-Path $oldPath)) {
    Die "Source folder does not exist: $oldPath"
  }

  # Compute new path
  $newPath = $null
  $destResolved = [System.IO.Path]::GetFullPath($DestPath)

  # If dest ends with \ or exists as directory, treat as parent
  if ($destResolved.EndsWith([System.IO.Path]::DirectorySeparatorChar) -or (Test-Path $destResolved -PathType Container)) {
    $folderName = Split-Path $oldPath -Leaf
    $newPath = Join-Path $destResolved $folderName
  } else {
    $newPath = $destResolved
  }

  # Validate new path is inside managed roots
  $newPathIsManaged = $newPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase) -or
                      $newPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

  if (-not $newPathIsManaged) {
    Die "Destination path is not within managed roots: $newPath"
  }

  # Reject if trying to move to root directory
  if ($newPath -eq $softwareRoot -or $newPath -eq $toolsRoot) {
    Die "Cannot move to root directory: $newPath"
  }

  # Check if destination exists
  if (Test-Path $newPath) {
    if (-not $ForceOverwrite) {
      Die "Destination already exists: $newPath (use --force to overwrite)"
    }
    # With --force, check if destination is empty
    $destItems = Get-ChildItem -LiteralPath $newPath -Force
    if ($destItems.Count -gt 0) {
      Die "Destination exists and is not empty: $newPath (unsafe to overwrite)"
    }
  }

  # Plan preview
  Write-Host ""
  Write-Host "=== MOVE PLAN ===" -ForegroundColor Cyan
  Write-Host "Entry: $NameToMove ($($entry.scope))"
  Write-Host "FROM:  $oldPath"
  Write-Host "TO:    $newPath"
  if ($RehomeShims -and $entry.shims -and $entry.shims.Count -gt 0) {
    Write-Host "Shims: Will update $($entry.shims.Count) shim(s) to reference new path"
  }
  Write-Host ""

  if ($DryRunMode) {
    Info "Dry run mode - no changes made"
    return
  }

  # Confirmation
  if (-not $NonInteractive) {
    $response = Read-Host "Move $NameToMove now? (y/n)"
    if ($response -ne 'y') {
      Info "Move cancelled"
      return
    }
  }

  # Perform move
  try {
    Move-Item -LiteralPath $oldPath -Destination $newPath -ErrorAction Stop
    Ok "Moved folder: $oldPath -> $newPath"
  } catch {
    Die "Failed to move folder: $_"
  }

  # Update registry entry
  $entry.path = $newPath
  $entry.updated_at = Get-Date -Format "o"

  # Optional: update scope if moved between roots
  $oldScope = $entry.scope
  $newScope = $oldScope
  if ($newPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase)) {
    $newScope = "software"
    $entry.scope = "software"
  } elseif ($newPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)) {
    $newScope = "tool"
    $entry.scope = "tool"
  }

  # Chinvex integration: update context after move
  if (Test-ChinvexEnabled -NoChinvex:$NoChinvex -StrapRootPath $StrapRootPath) {
    $oldChinvexContext = $entry.chinvex_context
    $scopeChanged = $oldScope -ne $newScope

    if ($scopeChanged) {
      # Scope changed - need to handle context migration
      $newContextName = Get-ContextName -Scope $newScope -Name $NameToMove

      # Create new context if needed
      if ($newScope -eq "software") {
        # Moving to software - create individual context
        $createResult = Invoke-Chinvex @("context", "create", $newContextName)
        if ($createResult) {
          Info "Created chinvex context: $newContextName"
        }
      } elseif ($newScope -eq "tool") {
        # Moving to tools - ensure tools context exists
        $createResult = Invoke-Chinvex @("context", "create", "tools")
        if ($createResult) {
          Info "Created chinvex context: tools"
        }
      }

      # Register new path in new context
      $ingestResult = Invoke-Chinvex @("ingest", $newPath, "--context", $newContextName, "--register-only")
      if ($ingestResult) {
        $entry.chinvex_context = $newContextName
        Info "Registered with chinvex context: $newContextName"

        # Archive old context if it was software-scoped
        if ($oldScope -eq "software" -and $oldChinvexContext) {
          $archiveResult = Invoke-Chinvex @("context", "archive", $oldChinvexContext)
          if ($archiveResult) {
            Info "Archived old chinvex context: $oldChinvexContext"
          }
        } elseif ($oldScope -eq "tool") {
          # Remove from tools context
          $removeResult = Invoke-Chinvex @("context", "remove-repo", "--context", "tools", "--path", $oldPath)
          if ($removeResult) {
            Info "Removed from tools context"
          }
        }
      } else {
        Warn "Failed to register with chinvex context: $newContextName"
        $entry.chinvex_context = $null
      }
    } else {
      # Same scope - just update path
      $contextName = $entry.chinvex_context
      if ($contextName) {
        # Remove old path
        $removeResult = Invoke-Chinvex @("context", "remove-repo", "--context", $contextName, "--path", $oldPath)
        if ($removeResult) {
          Info "Removed old path from chinvex context: $contextName"
        }

        # Add new path
        $ingestResult = Invoke-Chinvex @("ingest", $newPath, "--context", $contextName, "--register-only")
        if ($ingestResult) {
          Info "Updated chinvex context: $contextName"
        } else {
          Warn "Failed to update chinvex context"
          $entry.chinvex_context = $null
        }
      }
    }
  }

  # Optional shim rehome
  if ($RehomeShims -and $entry.shims -and $entry.shims.Count -gt 0) {
    $shimsUpdated = 0
    foreach ($shimPath in $entry.shims) {
      if (-not (Test-Path $shimPath)) {
        Warn "Shim not found, skipping: $shimPath"
        continue
      }

      try {
        $content = Get-Content -LiteralPath $shimPath -Raw
        if ($content -match [regex]::Escape($oldPath)) {
          $newContent = $content -replace [regex]::Escape($oldPath), $newPath
          Set-Content -LiteralPath $shimPath -Value $newContent -NoNewline
          $shimsUpdated++
        }
      } catch {
        Warn "Failed to update shim: $shimPath ($_)"
      }
    }
    if ($shimsUpdated -gt 0) {
      Ok "Updated $shimsUpdated shim(s)"
    }
  }

  # Save registry
  try {
    Save-Registry $config $registry
    Ok "Registry updated"
  } catch {
    Die "Failed to save registry: $_"
  }

  Ok "Move complete"
}

