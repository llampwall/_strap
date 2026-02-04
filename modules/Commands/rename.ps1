# rename.ps1
# Command: Invoke-Rename

function Invoke-Rename {
  param(
    [string] $NameToRename,
    [string] $NewName,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $MoveFolder,
    [switch] $ForceOverwrite,
    [switch] $NoChinvex,
    [string] $StrapRootPath
  )

  if (-not $NameToRename) { Die "rename requires <name>" }
  if (-not $NewName) { Die "rename requires --to <newName>" }

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config
  $softwareRoot = $config.roots.software
  $toolsRoot = $config.roots.tools

  # Find entry by name
  $entry = $registry | Where-Object { $_.name -eq $NameToRename }
  if (-not $entry) {
    Die "No entry found with name '$NameToRename'. Use 'strap list' to see all entries."
  }

  # Store old values for chinvex operations
  $oldName = $entry.name
  $oldChinvexContext = $entry.chinvex_context
  $oldPath = $entry.path

  # Validate new name
  if ([string]::IsNullOrWhiteSpace($NewName)) {
    Die "New name cannot be empty"
  }

  # Check for reserved filesystem characters
  $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
  $reservedChars = '\/:*?"<>|'
  foreach ($char in $reservedChars.ToCharArray()) {
    if ($NewName.Contains($char)) {
      Die "New name contains invalid character: $char"
    }
  }

  # Check if new name already exists in registry
  $existingEntry = $registry | Where-Object { $_.name -eq $NewName }
  if ($existingEntry) {
    Die "Registry already contains an entry named '$NewName'"
  }

  $newPath = $null
  $folderMoved = $false

  # Compute new path if --move-folder
  if ($MoveFolder) {
    if (-not $oldPath) {
      Die "Registry entry has no path field"
    }

    $parent = Split-Path $oldPath -Parent
    $newPath = Join-Path $parent $NewName

    # Validate new path is inside managed roots
    $newPathIsManaged = $newPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase) -or
                        $newPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

    if (-not $newPathIsManaged) {
      Die "New path is not within managed roots: $newPath"
    }

    # Check if destination exists
    if (Test-Path $newPath) {
      Die "Destination folder already exists: $newPath"
    }
  }

  # Plan preview
  Write-Host ""
  Write-Host "=== RENAME PLAN ===" -ForegroundColor Cyan
  Write-Host "ENTRY: $NameToRename -> $NewName"
  if ($MoveFolder) {
    Write-Host "FOLDER: $oldPath -> $newPath"
  }
  Write-Host ""

  if ($DryRunMode) {
    Info "Dry run mode - no changes made"
    return
  }

  # Confirmation
  if (-not $NonInteractive) {
    $response = Read-Host "Rename $NameToRename now? (y/n)"
    if ($response -ne 'y') {
      Info "Rename cancelled"
      return
    }
  }

  # Optional folder rename
  if ($MoveFolder) {
    if (-not (Test-Path $oldPath)) {
      Die "Source folder does not exist: $oldPath"
    }

    try {
      Move-Item -LiteralPath $oldPath -Destination $newPath -ErrorAction Stop
      Ok "Renamed folder: $oldPath -> $newPath"
      $entry.path = $newPath
      $folderMoved = $true
    } catch {
      Die "Failed to rename folder: $_"
    }
  }

  # Update registry entry
  $entry.name = $NewName
  # If id convention is id=name, also update id
  if ($entry.id -eq $NameToRename) {
    $entry.id = $NewName
  }
  $entry.updated_at = Get-Date -Format "o"

  # Chinvex integration
  if (Test-ChinvexEnabled -NoChinvex:$NoChinvex -StrapRootPath $StrapRootPath) {
    if ($oldChinvexContext) {
      # Rename the chinvex context
      $renamed = Invoke-Chinvex -Arguments @("context", "rename", $oldChinvexContext, $NewName)
      if ($renamed) {
        $entry.chinvex_context = $NewName
        Info "Chinvex: renamed context '$oldChinvexContext' -> '$NewName'"

        # If folder was also moved, update the path in the context
        if ($folderMoved) {
          $added = Invoke-Chinvex -Arguments @("ingest", "--context", $NewName, "--repo", $newPath, "--register-only")
          if ($added) {
            Invoke-Chinvex -Arguments @("context", "remove-repo", $NewName, "--repo", $oldPath) | Out-Null
            Info "Chinvex: updated path in context '$NewName'"
          } else {
            $entry.chinvex_context = $null
            Warn "Chinvex path update failed. Context marked for reconciliation."
          }
        }
      } else {
        $entry.chinvex_context = $null
        Warn "Chinvex context rename failed. Context marked for reconciliation."
      }
    }
  }

  # Save registry
  try {
    Save-Registry $config $registry
    Ok "Registry updated"
  } catch {
    Die "Failed to save registry: $_"
  }

  Ok "Rename complete"
}

