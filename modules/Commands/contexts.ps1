# contexts.ps1
# Command: Invoke-Contexts

function Invoke-Contexts {
    <#
    .SYNOPSIS
        Lists all chinvex contexts and their sync status with strap registry.
    .DESCRIPTION
        Combines data from strap registry and chinvex context list to show:
        - Synced contexts (both registry and chinvex match)
        - Unsynced contexts (registry entry exists but chinvex_context is null)
        - Orphaned contexts (chinvex context exists but no registry entry)
    .PARAMETER StrapRootPath
        Path to strap root directory.
    .PARAMETER OutputMode
        'Table' for formatted table output, 'Object' for structured objects.
    #>
    param(
        [string] $StrapRootPath,
        [ValidateSet('Table', 'Object')]
        [string] $OutputMode = 'Table'
    )

    # Load config and registry
    $config = Load-Config $StrapRootPath
    $registry = Load-Registry $config

    # Build result list
    $results = @()

    # Check if chinvex is available
    $chinvexAvail = Test-ChinvexAvailable

    # Get chinvex contexts if available
    $chinvexContexts = @()
    if ($chinvexAvail) {
        $jsonOutput = Invoke-ChinvexQuery -Arguments @("context", "list", "--json")
        if ($jsonOutput) {
            try {
                $chinvexContexts = $jsonOutput | ConvertFrom-Json
            } catch {
                Warn "Failed to parse chinvex context list: $_"
            }
        }
    }

    # Build lookup of chinvex contexts by name
    $chinvexLookup = @{}
    foreach ($ctx in $chinvexContexts) {
        $chinvexLookup[$ctx.name] = $ctx
    }

    # Track which chinvex contexts are accounted for by registry
    $accountedContexts = @{}

    # Process registry entries (all have individual contexts now)
    foreach ($entry in $registry) {
        $contextName = $entry.chinvex_context
        $syncStatus = "unknown"

        if (-not $chinvexAvail) {
            $syncStatus = "unknown (chinvex unavailable)"
        } elseif ($null -eq $contextName) {
            $syncStatus = "not synced"
        } elseif ($chinvexLookup.ContainsKey($contextName)) {
            $syncStatus = "synced"
            $accountedContexts[$contextName] = $true
        } else {
            $syncStatus = "context missing"
        }

        $chinvexData = if ($contextName) { $chinvexLookup[$contextName] } else { $null }

        # Determine type from tags (third-party = tool, otherwise software)
        $type = if ($entry.tags -contains "third-party") { "tool" } else { "software" }

        $results += [PSCustomObject]@{
            Name = $entry.name
            Type = $type
            RepoCount = if ($chinvexData) { $chinvexData.repo_count } else { 1 }
            LastIngest = if ($chinvexData) { $chinvexData.last_ingest } else { "-" }
            SyncStatus = $syncStatus
        }
    }

    # Find orphaned chinvex contexts (in chinvex but not in registry)
    foreach ($ctx in $chinvexContexts) {
        if (-not $accountedContexts.ContainsKey($ctx.name)) {
            # This is an orphaned context
            $results += [PSCustomObject]@{
                Name = $ctx.name
                Type = "unknown"
                RepoCount = $ctx.repo_count
                LastIngest = $ctx.last_ingest
                SyncStatus = "no strap entry"
            }
        }
    }

    # Output
    if ($OutputMode -eq 'Object') {
        return ,$results
    }

    # Table output
    if ($results.Count -eq 0) {
        Info "No contexts found"
        return
    }

    Write-Host ""
    Write-Host "Context         Type       Repos  Last Ingest         Sync Status" -ForegroundColor Cyan
    Write-Host "-------         ----       -----  -----------         -----------" -ForegroundColor Gray

    foreach ($ctx in $results | Sort-Object Name) {
        $nameCol = $ctx.Name.PadRight(15)
        $typeCol = $ctx.Type.PadRight(10)
        $repoCol = $ctx.RepoCount.ToString().PadRight(6)
        $ingestCol = if ($ctx.LastIngest -eq "-") { "-".PadRight(19) } else { $ctx.LastIngest.Substring(0, [Math]::Min(19, $ctx.LastIngest.Length)).PadRight(19) }

        $statusColor = switch ($ctx.SyncStatus) {
            "synced" { "Green" }
            "not synced" { "Yellow" }
            "context missing" { "Yellow" }
            "no strap entry" { "Red" }
            default { "Gray" }
        }

        $statusSymbol = switch ($ctx.SyncStatus) {
            "synced" { "[OK]" }
            "not synced" { "[!]" }
            "context missing" { "[!]" }
            "no strap entry" { "[?]" }
            default { "[-]" }
        }

        Write-Host "$nameCol $typeCol $repoCol $ingestCol " -NoNewline
        Write-Host "$statusSymbol $($ctx.SyncStatus)" -ForegroundColor $statusColor
    }

    Write-Host ""
}
