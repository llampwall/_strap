# update.ps1
# Command: Invoke-Update

function Invoke-Update {
  param(
    [string] $NameToUpdate,
    [switch] $UpdateAll,
    [switch] $FilterTool,
    [switch] $FilterSoftware,
    [switch] $UseRebase,
    [switch] $AutoStash,
    [switch] $RunSetup,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  if (-not $registry -or $registry.Count -eq 0) {
    Info "No entries in registry"
    exit 0
  }

  # Determine which entries to update
  $entriesToUpdate = @()

  if ($UpdateAll) {
    # Filter by scope if requested
    $entriesToUpdate = $registry | Where-Object {
      if ($FilterTool -and $_.scope -ne "tool") { return $false }
      if ($FilterSoftware -and $_.scope -ne "software") { return $false }
      return $true
    }

    if ($entriesToUpdate.Count -eq 0) {
      Info "No entries match filter criteria"
      exit 0
    }
  } else {
    # Find single entry by name
    if (-not $NameToUpdate) {
      Die "update requires <name> or --all flag"
    }

    $entry = $registry | Where-Object { $_.name -eq $NameToUpdate -or $_.id -eq $NameToUpdate }
    if (-not $entry) {
      Die "Registry entry not found: '$NameToUpdate'. Use 'strap list' to see all entries."
    }

    $entriesToUpdate = @($entry)
  }

  # Counters for summary
  $updated = 0
  $skippedDirty = 0
  $failed = 0
  $dryRunCount = 0

  foreach ($entry in $entriesToUpdate) {
    $entryName = $entry.name
    $entryPath = $entry.path
    $entryScope = if ($entry.scope) { $entry.scope } else { "unknown" }

    Write-Host ""
    Write-Host "=== UPDATE: $entryName ($entryScope) ===" -ForegroundColor Cyan

    # Safety validation: ensure path is absolute and within managed roots
    if (-not [System.IO.Path]::IsPathRooted($entryPath)) {
      Write-Host "  ERROR: Path is not absolute: $entryPath" -ForegroundColor Red
      $failed++
      continue
    }

    $resolvedPath = [System.IO.Path]::GetFullPath($entryPath)
    $softwareRoot = "P:\software"
    $scriptsRoot = "P:\software\_scripts"

    $withinSoftware = $resolvedPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase)
    $withinScripts = $resolvedPath.StartsWith($scriptsRoot, [StringComparison]::OrdinalIgnoreCase)

    if (-not ($withinSoftware -or $withinScripts)) {
      Write-Host "  ERROR: Path is not within managed roots: $resolvedPath" -ForegroundColor Red
      $failed++
      continue
    }

    # Reject root directories themselves
    if ($resolvedPath -eq $softwareRoot -or $resolvedPath -eq $scriptsRoot) {
      Write-Host "  ERROR: Cannot update root directory: $resolvedPath" -ForegroundColor Red
      $failed++
      continue
    }

    # Check git presence
    $gitDir = Join-Path $resolvedPath ".git"
    if (-not (Test-Path $gitDir)) {
      Write-Host "  WARN: No .git directory found, skipping" -ForegroundColor Yellow
      $skippedDirty++
      continue
    }

    # Preview
    Write-Host "Path:           $resolvedPath"
    $pullCommand = if ($UseRebase) { "pull --rebase" } else { "pull" }
    Write-Host "Operation:      git $pullCommand"

    # Check dirty status
    $dirtyOutput = & git -C $resolvedPath status --porcelain 2>&1
    $isDirty = $dirtyOutput -and ($dirtyOutput.Count -gt 0)

    if ($isDirty) {
      Write-Host "Status:         DIRTY (uncommitted changes)" -ForegroundColor Yellow
      if ($AutoStash) {
        Write-Host "Policy:         auto-stash before pull" -ForegroundColor Yellow
      } else {
        Write-Host "Policy:         abort (use --stash to allow)" -ForegroundColor Yellow
        if ($UpdateAll) {
          Write-Host "  SKIP: Working tree is dirty" -ForegroundColor Yellow
          $skippedDirty++
          continue
        } else {
          Die "Working tree is dirty. Use --stash to auto-stash, or commit/stash changes manually."
        }
      }
    } else {
      Write-Host "Status:         clean"
    }

    if ($RunSetup) {
      Write-Host "Follow-on:      strap setup (after successful pull)"
    }

    if ($DryRunMode) {
      Write-Host ""
      Write-Host "DRY RUN - no changes will be made" -ForegroundColor Yellow
      $dryRunCount++
      continue
    }

    # Confirmation
    if (-not $NonInteractive) {
      $response = Read-Host "`nProceed updating $entryName? (y/n)"
      if ($response -ne "y") {
        Info "Skipped by user"
        continue
      }
    }

    Write-Host ""

    # Stash if needed
    $stashCreated = $false
    if ($isDirty -and $AutoStash) {
      Info "Stashing changes..."
      & git -C $resolvedPath stash push -u -m "strap update" 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) {
        $stashCreated = $true
        Write-Host "  stashed" -ForegroundColor Green
      } else {
        Write-Host "  ERROR: stash failed" -ForegroundColor Red
        $failed++
        continue
      }
    }

    # Git fetch
    Info "Fetching..."
    $fetchOutput = & git -C $resolvedPath fetch --all --prune 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  ERROR: fetch failed" -ForegroundColor Red
      Write-Host $fetchOutput

      # Try to restore stash
      if ($stashCreated) {
        Info "Restoring stash..."
        & git -C $resolvedPath stash pop 2>&1 | Out-Null
      }

      $failed++
      continue
    }

    # Git pull
    Info "Pulling..."
    if ($UseRebase) {
      $pullOutput = & git -C $resolvedPath pull --rebase 2>&1
    } else {
      $pullOutput = & git -C $resolvedPath pull 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
      Write-Host "  ERROR: pull failed" -ForegroundColor Red
      Write-Host $pullOutput

      # Try to restore stash
      if ($stashCreated) {
        Info "Restoring stash..."
        & git -C $resolvedPath stash pop 2>&1 | Out-Null
      }

      $failed++
      continue
    }

    Write-Host "  pulled" -ForegroundColor Green

    # Restore stash
    if ($stashCreated) {
      Info "Restoring stash..."
      $popOutput = & git -C $resolvedPath stash pop 2>&1
      if ($LASTEXITCODE -eq 0) {
        Write-Host "  stash restored" -ForegroundColor Green
      } else {
        Write-Host "  WARN: stash pop failed (may have conflicts)" -ForegroundColor Yellow
        Write-Host $popOutput
      }
    }

    # Update registry metadata
    Info "Updating registry..."

    # Get current HEAD
    $headHash = & git -C $resolvedPath rev-parse HEAD 2>&1
    $remoteHash = & git -C $resolvedPath rev-parse "@{u}" 2>&1

    # Find entry index
    $entryIndex = -1
    for ($i = 0; $i -lt $registry.Count; $i++) {
      if ($registry[$i].name -eq $entryName) {
        $entryIndex = $i
        break
      }
    }

    if ($entryIndex -eq -1) {
      Write-Host "  ERROR: Registry entry not found after update" -ForegroundColor Red
      $failed++
      continue
    }

    # Update metadata (add properties if they don't exist)
    $currentEntry = $registry[$entryIndex]

    # Update existing timestamp
    $currentEntry.updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Add or update last_pull_at
    if ($currentEntry.PSObject.Properties['last_pull_at']) {
      $currentEntry.last_pull_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    } else {
      $currentEntry | Add-Member -NotePropertyName 'last_pull_at' -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")) -Force
    }

    # Add or update last_head
    if ($headHash -and $LASTEXITCODE -eq 0) {
      $headValue = $headHash.Trim()
      if ($currentEntry.PSObject.Properties['last_head']) {
        $currentEntry.last_head = $headValue
      } else {
        $currentEntry | Add-Member -NotePropertyName 'last_head' -NotePropertyValue $headValue -Force
      }
    }

    # Add or update last_remote
    if ($remoteHash -and $LASTEXITCODE -eq 0) {
      $remoteValue = $remoteHash.Trim()
      if ($currentEntry.PSObject.Properties['last_remote']) {
        $currentEntry.last_remote = $remoteValue
      } else {
        $currentEntry | Add-Member -NotePropertyName 'last_remote' -NotePropertyValue $remoteValue -Force
      }
    }

    # Save registry
    try {
      Save-Registry $config $registry
      Write-Host "  registry updated" -ForegroundColor Green
    } catch {
      Write-Host "  ERROR updating registry: $_" -ForegroundColor Red
      $failed++
      continue
    }

    $updated++
    Ok "Updated $entryName"

    # Run setup if requested
    if ($RunSetup) {
      Write-Host ""
      Info "Running setup..."
      # TODO: Implement strap setup command
      Write-Host "  WARN: strap setup not yet implemented" -ForegroundColor Yellow
    }
  }

  # Summary for --all
  if ($UpdateAll -and $entriesToUpdate.Count -gt 1) {
    Write-Host ""
    Write-Host "=== UPDATE SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Updated:       $updated"
    if ($skippedDirty -gt 0) {
      Write-Host "Skipped dirty: $skippedDirty" -ForegroundColor Yellow
    }
    if ($failed -gt 0) {
      Write-Host "Failed:        $failed" -ForegroundColor Red
    }
  }

  # Exit code logic
  if ($failed -gt 0) {
    exit 2
  }

  # If dry run, exit success if we processed at least one entry
  if ($DryRunMode -and $dryRunCount -gt 0) {
    exit 0
  }

  if ($updated -eq 0 -and $skippedDirty -eq 0 -and $dryRunCount -eq 0) {
    exit 1
  }
}

