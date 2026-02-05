# configure.ps1
# Command: Invoke-Configure

function Invoke-Configure {
  param(
    [string] $NameToConfigure,
    [string] $NewDepth,
    [string] $NewStatus,
    [string[]] $NewTags,
    [switch] $ClearTags,
    [switch] $AddTags,
    [switch] $RemoveTags,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $OutputJson,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Validate name provided
  if (-not $NameToConfigure) {
    Die "configure requires a repository name"
  }

  # Find entry
  $entry = $registry | Where-Object { $_.name -eq $NameToConfigure }
  if (-not $entry) {
    Die "Repository not found: $NameToConfigure"
  }

  # Validate depth value if provided
  if ($NewDepth -and $NewDepth -notin @('light', 'full')) {
    Die "Invalid depth value: $NewDepth (must be 'light' or 'full')"
  }

  # Validate status value if provided
  if ($NewStatus -and $NewStatus -notin @('active', 'stable', 'archived', 'deprecated')) {
    Die "Invalid status value: $NewStatus (must be 'active', 'stable', 'archived', or 'deprecated')"
  }

  # Track what changed
  $changes = @()
  $oldDepth = $entry.chinvex_depth
  $oldStatus = $entry.status
  $oldTags = if ($entry.tags) { $entry.tags } else { @() }

  # Determine new values
  $finalDepth = if ($NewDepth) { $NewDepth } else { $oldDepth }
  $finalStatus = if ($NewStatus) { $NewStatus } else { $oldStatus }

  # Handle tags modifications
  $finalTags = $oldTags
  if ($ClearTags) {
    $finalTags = @()
    $changes += "Clear all tags"
  } elseif ($AddTags -and $NewTags) {
    # Add tags (avoid duplicates)
    $tagSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($tag in $oldTags) {
      [void]$tagSet.Add($tag)
    }
    foreach ($tag in $NewTags) {
      [void]$tagSet.Add($tag)
    }
    $finalTags = @($tagSet)
    $changes += "Add tags: $($NewTags -join ', ')"
  } elseif ($RemoveTags -and $NewTags) {
    # Remove tags
    $finalTags = @($oldTags | Where-Object { $_ -notin $NewTags })
    $changes += "Remove tags: $($NewTags -join ', ')"
  } elseif ($NewTags) {
    # Replace tags completely
    $finalTags = $NewTags
    $changes += "Set tags: $($NewTags -join ', ')"
  }

  # Check what changed
  if ($NewDepth -and $NewDepth -ne $oldDepth) {
    $changes += "depth: $oldDepth -> $NewDepth"
  }
  if ($NewStatus -and $NewStatus -ne $oldStatus) {
    $changes += "status: $oldStatus -> $NewStatus"
  }

  # If nothing changed, exit early
  if ($changes.Count -eq 0) {
    if ($OutputJson) {
      $result = [PSCustomObject]@{
        status = "no_changes"
        name = $NameToConfigure
        message = "No changes requested"
      }
      $result | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Info "No changes to apply for: $NameToConfigure"
    }
    return
  }

  # Show changes
  if (-not $OutputJson) {
    Write-Host ""
    Write-Host "=== CONFIGURATION CHANGES ===" -ForegroundColor Cyan
    Write-Host "Repository: $NameToConfigure"
    Write-Host ""
    foreach ($change in $changes) {
      Write-Host "  $change" -ForegroundColor Yellow
    }
    Write-Host ""
  }

  # Dry run check
  if ($DryRunMode) {
    if ($OutputJson) {
      $result = [PSCustomObject]@{
        status = "dry_run"
        name = $NameToConfigure
        changes = $changes
        new_values = @{
          chinvex_depth = $finalDepth
          status = $finalStatus
          tags = $finalTags
        }
      }
      $result | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Info "[DRY RUN] No changes will be applied"
    }
    return
  }

  # Confirmation
  if (-not $NonInteractive) {
    $response = Read-Host "Apply changes? (y/n)"
    if ($response -ne "y") {
      Info "Aborted by user"
      return
    }
  }

  # Update entry
  $entry.chinvex_depth = $finalDepth
  $entry.status = $finalStatus
  $entry.tags = $finalTags
  $entry.updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

  # Save registry
  Save-Registry $config $registry

  # Sync with chinvex if enabled
  $chinvexUpdated = $false
  if ($entry.chinvex_context) {
    try {
      # Detect if depth changed
      $depthChanged = ($NewDepth -and $NewDepth -ne $oldDepth)

      # Step 1: Always sync metadata from registry to context.json
      $syncResult = Invoke-Chinvex -Arguments @("context", "sync-metadata-from-strap", "--context", $NameToConfigure)
      if ($syncResult) {
        $chinvexUpdated = $true
        Info "Synced metadata to chinvex context"
      } else {
        Warn "Failed to sync metadata to chinvex context '$NameToConfigure'"
      }

      # Step 2: If depth changed, trigger full reingest
      if ($depthChanged -and $syncResult) {
        $ingestArgs = @(
          "ingest",
          "--context", $NameToConfigure,
          "--repo", $entry.path,
          "--rebuild-index"
        )
        $ingestResult = Invoke-Chinvex -Arguments $ingestArgs
        if ($ingestResult) {
          Info "Triggered full reingest due to depth change: $oldDepth -> $finalDepth"
        } else {
          Warn "Failed to reingest repo in chinvex context '$NameToConfigure'"
          $chinvexUpdated = $false
        }
      }
    } catch {
      Warn "Failed to sync with chinvex: $_"
    }
  }

  # Output result
  if ($OutputJson) {
    $result = [PSCustomObject]@{
      status = "success"
      name = $NameToConfigure
      changes = $changes
      chinvex_synced = $chinvexUpdated
      new_values = @{
        chinvex_depth = $finalDepth
        status = $finalStatus
        tags = $finalTags
      }
    }
    $result | ConvertTo-Json -Depth 10 | Write-Host
  } else {
    Ok "Configuration updated for: $NameToConfigure"
    if ($chinvexUpdated) {
      Info "Chinvex context synced"
    }
  }
}
