# Chinvex.ps1
# Chinvex integration for strap

# Dot-source dependencies
. "$PSScriptRoot\Core.ps1"
. "$PSScriptRoot\Config.ps1"

# Script-level cache for chinvex availability check
$script:chinvexChecked = $false
$script:chinvexAvailable = $false

function Test-ChinvexAvailable {
    <#
    .SYNOPSIS
        Checks if chinvex CLI is available on PATH. Result is cached.
    .OUTPUTS
        [bool] True if chinvex command exists, false otherwise.
    #>
    if (-not $script:chinvexChecked) {
        $script:chinvexChecked = $true
        $script:chinvexAvailable = [bool](Get-Command chinvex -ErrorAction SilentlyContinue)
        if (-not $script:chinvexAvailable) {
            Warn "Chinvex not installed or not on PATH. Skipping context sync."
        }
    }
    return $script:chinvexAvailable
}

function Test-ChinvexEnabled {
    <#
    .SYNOPSIS
        Determines if chinvex integration should run.
    .DESCRIPTION
        Precedence: -NoChinvex flag > config.chinvex_integration > default (true)
    .PARAMETER NoChinvex
        If set, always returns false (explicit opt-out).
    .PARAMETER StrapRootPath
        Path to strap root for loading config.
    .OUTPUTS
        [bool] True if chinvex integration should run.
    #>
    param(
        [switch] $NoChinvex,
        [string] $StrapRootPath
    )

    # Flag overrides everything
    if ($NoChinvex) { return $false }

    # Config check
    $config = Load-Config $StrapRootPath
    if ($config.chinvex_integration -eq $false) { return $false }

    # Default: enabled, but only if chinvex is actually installed
    return (Test-ChinvexAvailable)
}

function Invoke-Chinvex {
    <#
    .SYNOPSIS
        Runs chinvex CLI command. Returns $true on exit 0, $false otherwise.
    .DESCRIPTION
        Does NOT throw - caller checks return value.
        Canonical error handling: any failure returns $false.
    .PARAMETER Arguments
        Array of arguments to pass to chinvex CLI.
    .PARAMETER StdIn
        Optional string to pipe to stdin (e.g., "y" for confirmation prompts).
    .PARAMETER TimeoutSeconds
        Optional timeout in seconds. If the command exceeds this, it is killed
        and $false is returned. Default $null means no timeout.
    .OUTPUTS
        [bool] True if exit code 0, false otherwise.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments,
        [string] $StdIn = $null,
        [int] $TimeoutSeconds = 0
    )

    if (-not (Test-ChinvexAvailable)) { return $false }

    try {
        if ($TimeoutSeconds -gt 0) {
            # Run with timeout via background job
            $job = Start-Job -ScriptBlock {
                param($args, $stdIn)
                if ($stdIn) {
                    $stdIn | & chinvex @args 2>&1 | Out-Null
                } else {
                    & chinvex @args 2>&1 | Out-Null
                }
                return $LASTEXITCODE
            } -ArgumentList $Arguments, $StdIn

            $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
            if ($completed) {
                $exitCode = Receive-Job -Job $job
                Remove-Job -Job $job -Force
                return ($exitCode -eq 0)
            } else {
                Stop-Job -Job $job
                Remove-Job -Job $job -Force
                return $false
            }
        } elseif ($StdIn) {
            $StdIn | & chinvex @Arguments 2>&1 | Out-Null
        } else {
            & chinvex @Arguments 2>&1 | Out-Null
        }
        return ($LASTEXITCODE -eq 0)
    } catch {
        Warn "Chinvex command failed: $_"
        return $false
    }
}

function Invoke-ChinvexQuery {
    <#
    .SYNOPSIS
        Runs chinvex CLI command and returns stdout. Returns $null on failure.
    .PARAMETER Arguments
        Array of arguments to pass to chinvex CLI.
    .OUTPUTS
        [string] Command output on success, $null on failure.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    if (-not (Test-ChinvexAvailable)) { return $null }

    try {
        $output = & chinvex @Arguments 2>$null
        if ($LASTEXITCODE -eq 0) {
            return ($output -join "`n")
        }
        return $null
    } catch {
        Warn "Chinvex query error: $_"
        return $null
    }
}

function Test-ReservedContextName {
    <#
    .SYNOPSIS
        Checks if a name is reserved for system contexts.
    .DESCRIPTION
        Reserved names ('tools', 'archive', 'strap') cannot be used for repos.
    .PARAMETER Name
        The name to check.
    .OUTPUTS
        [bool] True if name is reserved.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $reserved = @('tools', 'archive', 'strap')
    return ($reserved -contains $Name.ToLower())
}

function Sync-ChinvexForEntry {
    <#
    .SYNOPSIS
        High-level function to create chinvex context and ingest repo.
    .DESCRIPTION
        Creates individual context with metadata, then fully ingests the repo.
        Returns context name on success, $null on any failure (canonical error handling).
    .PARAMETER Name
        The entry/repo name.
    .PARAMETER RepoPath
        Full path to the repository.
    .PARAMETER ChinvexDepth
        Ingestion depth: 'full', 'light', or 'index'.
    .PARAMETER Status
        Lifecycle state: 'active', 'stable', or 'dormant'.
    .PARAMETER Tags
        Free-form tags for grouping.
    .PARAMETER RebuildIndex
        If set, passes --rebuild-index to force full reingest (used when depth changes).
    .OUTPUTS
        [string] Context name on success, $null on failure.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Name,
        [Parameter(Mandatory)]
        [string] $RepoPath,
        [Parameter(Mandatory)]
        [string] $ChinvexDepth,
        [Parameter(Mandatory)]
        [string] $Status,
        [AllowEmptyCollection()]
        [array] $Tags = @(),
        [switch] $RebuildIndex
    )

    # Create individual context (no more shared contexts)
    $contextName = $Name

    # Step 1: Create context with metadata
    $tagsArg = if ($Tags.Count -gt 0) { "--tags", ($Tags -join ",") } else { @() }
    $args = @("context", "create", $contextName, "--idempotent") + $tagsArg

    $created = Invoke-Chinvex -Arguments $args
    if (-not $created) {
        Warn "Failed to create chinvex context '$contextName'"
        return $null
    }

    # Step 2: Ingest repo in the background - large repos can take minutes to
    # index and we don't want clone to block. The context name is returned
    # immediately so the registry is populated and uninstall can clean it up.
    $ingestArgs = @(
        "ingest", "--context", $contextName,
        "--repo", $RepoPath,
        "--chinvex-depth", $ChinvexDepth,
        "--status", $Status
    )

    # Add tags if present
    if ($Tags.Count -gt 0) {
        $ingestArgs += "--tags"
        $ingestArgs += ($Tags -join ",")
    }

    # Add --rebuild-index if requested (forces full reingest when depth changes)
    if ($RebuildIndex) {
        $ingestArgs += "--rebuild-index"
    }

    $ingestCmd = "chinvex " + ($ingestArgs -join " ")
    Start-Process pwsh -ArgumentList "-NoProfile", "-WindowStyle", "Hidden", "-Command", $ingestCmd -NoNewWindow:$false

    $tagsDisplay = if ($Tags.Count -gt 0) { ", tags=$($Tags -join ',')" } else { "" }
    Info "Synced to chinvex context: $contextName (indexing in background...)"
    return $contextName
}
