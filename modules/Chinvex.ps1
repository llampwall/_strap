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
    .OUTPUTS
        [bool] True if exit code 0, false otherwise.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    if (-not (Test-ChinvexAvailable)) { return $false }

    try {
        & chinvex @Arguments 2>&1 | Out-Null
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

function Detect-RepoScope {
    <#
    .SYNOPSIS
        Determines repo scope based on path location.
    .DESCRIPTION
        Returns 'tool' if under tools_root, 'software' if under software_root,
        or $null if outside managed roots. Most-specific path match wins.
    .PARAMETER Path
        The repository path to check.
    .PARAMETER StrapRootPath
        Path to strap root for loading config.
    .OUTPUTS
        [string] 'tool', 'software', or $null.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path,
        [Parameter(Mandatory)]
        [string] $StrapRootPath
    )

    $config = Load-Config $StrapRootPath

    # Normalize paths for comparison (ensure trailing backslash for prefix matching)
    $normalPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    $toolsRoot = [System.IO.Path]::GetFullPath($config.tools_root).TrimEnd('\') + '\'
    $softwareRoot = [System.IO.Path]::GetFullPath($config.software_root).TrimEnd('\') + '\'

    # Check tools_root first (more specific - it's a subdirectory of software_root)
    if ($normalPath.StartsWith($toolsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'tool'
    }

    # Then check software_root
    if ($normalPath.StartsWith($softwareRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'software'
    }

    return $null
}

function Get-ContextName {
    <#
    .SYNOPSIS
        Maps scope + entry name to chinvex context name.
    .DESCRIPTION
        Tools share a single 'tools' context. Software repos get individual contexts.
    .PARAMETER Scope
        Either 'tool' or 'software'.
    .PARAMETER Name
        The entry/repo name.
    .OUTPUTS
        [string] Context name ('tools' for tools, entry name for software).
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('tool', 'software')]
        [string] $Scope,
        [Parameter(Mandatory)]
        [string] $Name
    )

    if ($Scope -eq 'tool') {
        return 'tools'
    }
    return $Name
}

function Test-ReservedContextName {
    <#
    .SYNOPSIS
        Checks if a name is reserved for system contexts.
    .DESCRIPTION
        Reserved names ('tools', 'archive') cannot be used for software repos.
        Tool repos can have any name since they all go into the 'tools' context.
    .PARAMETER Name
        The name to check.
    .PARAMETER Scope
        The intended scope ('tool' or 'software').
    .OUTPUTS
        [bool] True if name is reserved and scope is 'software'.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Name,
        [Parameter(Mandatory)]
        [ValidateSet('tool', 'software')]
        [string] $Scope
    )

    # Reserved names only matter for software scope
    if ($Scope -ne 'software') {
        return $false
    }

    $reserved = @('tools', 'archive')
    return ($reserved -contains $Name.ToLower())
}

function Sync-ChinvexForEntry {
    <#
    .SYNOPSIS
        High-level function to create chinvex context and register repo path.
    .DESCRIPTION
        Creates context (idempotent) then registers repo path (register-only, no full ingestion).
        Returns context name on success, $null on any failure (canonical error handling).
    .PARAMETER Scope
        Either 'tool' or 'software'.
    .PARAMETER Name
        The entry/repo name.
    .PARAMETER RepoPath
        Full path to the repository.
    .OUTPUTS
        [string] Context name on success, $null on failure.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('tool', 'software')]
        [string] $Scope,
        [Parameter(Mandatory)]
        [string] $Name,
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    $contextName = Get-ContextName -Scope $Scope -Name $Name

    # Step 1: Create context (idempotent)
    $created = Invoke-Chinvex -Arguments @("context", "create", $contextName, "--idempotent")
    if (-not $created) {
        Warn "Failed to create chinvex context '$contextName'"
        return $null
    }

    # Step 2: Register repo path (no full ingestion)
    $registered = Invoke-Chinvex -Arguments @("ingest", "--context", $contextName, "--repo", $RepoPath, "--register-only")
    if (-not $registered) {
        Warn "Failed to register repo in chinvex context '$contextName'"
        return $null
    }

    Info "Synced to chinvex context: $contextName"
    return $contextName
}

# Functions are automatically available when dot-sourced

# Functions extracted from strap.ps1
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
    .OUTPUTS
        [bool] True if exit code 0, false otherwise.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    if (-not (Test-ChinvexAvailable)) { return $false }

    try {
        & chinvex @Arguments 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        Warn "Chinvex error: $_"
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


function Detect-RepoScope {
    <#
    .SYNOPSIS
        Determines repo scope based on path location.
    .DESCRIPTION
        Returns 'tool' if under tools_root, 'software' if under software_root,
        or $null if outside managed roots. Most-specific path match wins.
    .PARAMETER Path
        The repository path to check.
    .PARAMETER StrapRootPath
        Path to strap root for loading config.
    .OUTPUTS
        [string] 'tool', 'software', or $null.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path,
        [Parameter(Mandatory)]
        [string] $StrapRootPath
    )

    $config = Load-Config $StrapRootPath

    # Normalize paths for comparison (ensure trailing backslash for prefix matching)
    $normalPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    $toolsRoot = [System.IO.Path]::GetFullPath($config.tools_root).TrimEnd('\') + '\'
    $softwareRoot = [System.IO.Path]::GetFullPath($config.software_root).TrimEnd('\') + '\'

    # Check tools_root first (more specific - it's a subdirectory of software_root)
    if ($normalPath.StartsWith($toolsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'tool'
    }

    # Then check software_root
    if ($normalPath.StartsWith($softwareRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'software'
    }

    return $null
}


function Get-ContextName {
    <#
    .SYNOPSIS
        Maps scope + entry name to chinvex context name.
    .DESCRIPTION
        Tools share a single 'tools' context. Software repos get individual contexts.
    .PARAMETER Scope
        Either 'tool' or 'software'.
    .PARAMETER Name
        The entry/repo name.
    .OUTPUTS
        [string] Context name ('tools' for tools, entry name for software).
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('tool', 'software')]
        [string] $Scope,
        [Parameter(Mandatory)]
        [string] $Name
    )

    if ($Scope -eq 'tool') {
        return 'tools'
    }
    return $Name
}


function Test-ReservedContextName {
    <#
    .SYNOPSIS
        Checks if a name is reserved for system contexts.
    .DESCRIPTION
        Reserved names ('tools', 'archive') cannot be used for software repos.
        Tool repos can have any name since they all go into the 'tools' context.
    .PARAMETER Name
        The name to check.
    .PARAMETER Scope
        The intended scope ('tool' or 'software').
    .OUTPUTS
        [bool] True if name is reserved and scope is 'software'.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Name,
        [Parameter(Mandatory)]
        [ValidateSet('tool', 'software')]
        [string] $Scope
    )

    # Reserved names only matter for software scope
    if ($Scope -ne 'software') {
        return $false
    }

    $reserved = @('tools', 'archive')
    return ($reserved -contains $Name.ToLower())
}


function Sync-ChinvexForEntry {
    <#
    .SYNOPSIS
        High-level function to create chinvex context and register repo path.
    .DESCRIPTION
        Creates context (idempotent) then registers repo path (register-only, no full ingestion).
        Returns context name on success, $null on any failure (canonical error handling).
    .PARAMETER Scope
        Either 'tool' or 'software'.
    .PARAMETER Name
        The entry/repo name.
    .PARAMETER RepoPath
        Full path to the repository.
    .OUTPUTS
        [string] Context name on success, $null on failure.
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('tool', 'software')]
        [string] $Scope,
        [Parameter(Mandatory)]
        [string] $Name,
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    $contextName = Get-ContextName -Scope $Scope -Name $Name

    # Step 1: Create context (idempotent)
    $created = Invoke-Chinvex -Arguments @("context", "create", $contextName, "--idempotent")
    if (-not $created) {
        Warn "Failed to create chinvex context '$contextName'"
        return $null
    }

    # Step 2: Register repo path (no full ingestion)
    $registered = Invoke-Chinvex -Arguments @("ingest", "--context", $contextName, "--repo", $RepoPath, "--register-only")
    if (-not $registered) {
        Warn "Failed to register repo in chinvex context '$contextName'"
        return $null
    }

    Info "Synced to chinvex context: $contextName"
    return $contextName
}

