# sync-chinvex.ps1
# Command: Invoke-SyncChinvex

function Invoke-SyncChinvex {
    <#
    .SYNOPSIS
        Reconciles strap registry with chinvex contexts.
    .DESCRIPTION
        Default (no flags): equivalent to --dry-run (shows drift without changes).
        --dry-run: Show what would change without making changes.
        --reconcile: Apply reconciliation actions.

        IMPORTANT: This command ALWAYS runs regardless of --no-chinvex flag or
        config.chinvex_integration setting. It IS the chinvex management command.

        Reconciliation rules:
        - Missing contexts: Create contexts for strap entries with chinvex_context = null
        - Orphaned contexts: Archive contexts with no strap entry (except whitelist)
        - Whitelist: Never archive 'tools', 'archive', or user-defined whitelist entries
    .PARAMETER DryRun
        Show what would change without making changes.
    .PARAMETER Reconcile
        Apply reconciliation actions.
    .PARAMETER StrapRootPath
        Path to strap root for loading config/registry.
    .PARAMETER OutputMode
        'Table' for human-readable output, 'Object' for machine-readable.
    #>
    param(
        [switch] $DryRun,
        [switch] $Reconcile,
        [string] $StrapRootPath,
        [ValidateSet('Table', 'Object')]
        [string] $OutputMode = 'Table'
    )

    # Default to dry-run if neither flag specified
    $isDryRun = (-not $Reconcile) -or $DryRun

    $result = @{
        Success = $true
        DryRun = $isDryRun
        Actions = @()
        Error = $null
    }

    # Check chinvex availability (sync-chinvex ignores config disable, but needs chinvex installed)
    if (-not (Test-ChinvexAvailable)) {
        $result.Success = $false
        $result.Error = "Chinvex not available. Install chinvex and ensure it is on PATH."
        if ($OutputMode -eq 'Object') {
            return [PSCustomObject]$result
        }
        Warn $result.Error
        return
    }

    # Load registry and config
    $config = Load-Config $StrapRootPath
    $registry = Load-Registry $config

    # Build whitelist (system defaults + user config)
    $whitelist = @("tools", "archive")
    if ($config.chinvex_whitelist) {
        $whitelist += $config.chinvex_whitelist
    }
    $whitelist = $whitelist | Sort-Object -Unique

    # Get chinvex contexts
    $chinvexJson = Invoke-ChinvexQuery -Arguments @("context", "list", "--json")
    $chinvexContexts = @()
    if ($chinvexJson) {
        try {
            $chinvexContexts = $chinvexJson | ConvertFrom-Json
        } catch {
            Warn "Failed to parse chinvex context list: $_"
        }
    }

    # Build lookup of chinvex contexts by name
    $chinvexLookup = @{}
    foreach ($ctx in $chinvexContexts) {
        $chinvexLookup[$ctx.name] = $ctx
    }

    # Track which chinvex contexts are accounted for
    $accountedContexts = @{}

    # Phase 1: Find registry entries that need syncing
    foreach ($entry in $registry) {
        if ($null -eq $entry.chinvex_context) {
            # Entry needs context created (individual context = entry name)
            $contextName = $entry.name

            $action = @{
                Action = "create"
                Context = $contextName
                EntryName = $entry.name
                Depth = $entry.chinvex_depth
                Status = $entry.status
                Tags = $entry.tags
                RepoPath = $entry.path
            }
            $result.Actions += [PSCustomObject]$action

            if (-not $isDryRun) {
                # Perform reconciliation
                $syncedContext = Sync-ChinvexForEntry -Name $entry.name -RepoPath $entry.path `
                    -ChinvexDepth $entry.chinvex_depth -Status $entry.status -Tags $entry.tags
                if ($syncedContext) {
                    $entry.chinvex_context = $syncedContext
                    Ok "Created context '$contextName' for $($entry.name)"
                } else {
                    Warn "Failed to create context '$contextName' for $($entry.name)"
                }
            } else {
                Info "Would create context '$contextName' for registry entry '$($entry.name)'"
            }

            $accountedContexts[$contextName] = $true
        } else {
            # Entry has context, mark as accounted
            $accountedContexts[$entry.chinvex_context] = $true
        }
    }

    # Phase 2: Find orphaned chinvex contexts
    foreach ($ctx in $chinvexContexts) {
        if (-not $accountedContexts.ContainsKey($ctx.name)) {
            # Check whitelist
            if ($whitelist -contains $ctx.name) {
                Info "Skipping whitelisted context '$($ctx.name)'"
                continue
            }

            $action = @{
                Action = "archive"
                Context = $ctx.name
                Reason = "no strap entry"
            }
            $result.Actions += [PSCustomObject]$action

            if (-not $isDryRun) {
                $archived = Invoke-Chinvex -Arguments @("context", "archive", $ctx.name)
                if ($archived) {
                    Ok "Archived orphaned context '$($ctx.name)'"
                } else {
                    Warn "Failed to archive context '$($ctx.name)'"
                }
            } else {
                Info "Would archive orphaned context '$($ctx.name)'"
            }
        }
    }

    # Save registry if changes were made
    if (-not $isDryRun -and $result.Actions.Count -gt 0) {
        Save-Registry $config $registry
    }

    # Output
    if ($OutputMode -eq 'Object') {
        return [PSCustomObject]$result
    }

    # Summary
    Write-Host ""
    if ($isDryRun) {
        Write-Host "DRY RUN - No changes made" -ForegroundColor Yellow
    }

    $createCount = ($result.Actions | Where-Object { $_.Action -eq "create" }).Count
    $archiveCount = ($result.Actions | Where-Object { $_.Action -eq "archive" }).Count

    if ($result.Actions.Count -eq 0) {
        Ok "Registry and chinvex contexts are in sync"
    } else {
        Info "Actions: $createCount context(s) to create, $archiveCount context(s) to archive"
    }
    Write-Host ""
}

