param(
  [Parameter(Mandatory=$true, Position=0)]
  [string] $RepoName,

  [Alias("t")]
  [ValidateSet("node-ts-service","node-ts-web","python","mono")]
  [string] $Template,

  [Alias("p")]
  [string] $Path = "P:\\software",

  [Alias("skip-install")]
  [switch] $SkipInstall,

  [switch] $Install,

  [switch] $Start,

  [switch] $Keep,

  [string] $StrapRoot,

  [string] $Source,
  [string] $Message,
  [switch] $Push,
  [switch] $Force,
  [switch] $AllowDirty,

  [switch] $Tool,
  [string] $Name,
  [string] $Dest,

  [switch] $Software,
  [switch] $Json,

  [switch] $Yes,
  [switch] $DryRun,
  [switch] $KeepFolder,
  [switch] $KeepShims,

  [string] $Cwd,
  [string] $Repo,
  [string] $Cmd,

  [switch] $Rebase,
  [switch] $Stash,
  [switch] $Setup,
  [switch] $All,

  [ValidateSet("python", "node", "go", "rust")]
  [string] $Stack,
  [string] $Venv,
  [switch] $Uv,
  [string] $Python,
  [ValidateSet("npm", "pnpm", "yarn")]
  [string] $Pm,
  [switch] $Corepack,

  [int] $To,
  [switch] $Plan,
  [switch] $Backup,

  [switch] $RehomeShims,
  [switch] $MoveFolder,
  [string] $NewName,

  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]] $ExtraArgs
)

$ErrorActionPreference = "Stop"

# ============================================================================
# KILL SWITCH - Disabled commands pending review
# See: docs/incidents/2026-02-02-environment-corruption.md
# See: docs/incidents/2026-02-02-tdd-tasks-status.md
# ============================================================================
$UNSAFE_COMMANDS = @(
    'Invoke-Snapshot',
    'Invoke-Audit',
    'Invoke-Migrate',
    'Invoke-Migration-0-to-1',
    'Should-ExcludePath',
    'Copy-RepoSnapshot',
    'Invoke-ConsolidateExecuteMove',
    'Invoke-ConsolidateRollbackMove',
    'Invoke-ConsolidateTransaction',
    'Invoke-ConsolidateMigrationWorkflow',
    'Test-ConsolidateArgs',
    'Test-ConsolidateRegistryDisk',
    'Test-ConsolidateEdgeCaseGuards'
)

function Assert-CommandSafe {
    param([string]$CommandName)
    if ($CommandName -in $UNSAFE_COMMANDS) {
        Write-Warning "[DISABLED] '$CommandName' is disabled pending review."
        Write-Warning "See: docs/incidents/2026-02-02-environment-corruption.md"
        return $false
    }
    return $true
}
# ============================================================================

function Die($msg) { Write-Error "❌ $msg"; exit 1 }
function Info($msg) { Write-Host "➡️  $msg" }
function Ok($msg) { Write-Host "✅ $msg" }
function Warn($msg) { Write-Warning $msg }

function Apply-ExtraArgs {
  param([string[]] $ArgsList)

  if (-not $ArgsList) { return }

  for ($i = 0; $i -lt $ArgsList.Count; $i++) {
    $arg = $ArgsList[$i]
    switch ($arg) {
      "--start" { $script:Start = $true; continue }
      "--install" { $script:Install = $true; continue }
      "--skip-install" { $script:SkipInstall = $true; continue }
      "--keep" { $script:Keep = $true; continue }
      "--strap-root" { if ($i + 1 -lt $ArgsList.Count) { $script:StrapRoot = $ArgsList[$i + 1]; $i++; continue } }
      "--template" { if ($i + 1 -lt $ArgsList.Count) { $script:Template = $ArgsList[$i + 1]; $i++; continue } }
      "-t" { if ($i + 1 -lt $ArgsList.Count) { $script:Template = $ArgsList[$i + 1]; $i++; continue } }
      "--path" { if ($i + 1 -lt $ArgsList.Count) { $script:Path = $ArgsList[$i + 1]; $i++; continue } }
      "-p" { if ($i + 1 -lt $ArgsList.Count) { $script:Path = $ArgsList[$i + 1]; $i++; continue } }
      "--source" { if ($i + 1 -lt $ArgsList.Count) { $script:Source = $ArgsList[$i + 1]; $i++; continue } }
      "--message" { if ($i + 1 -lt $ArgsList.Count) { $script:Message = $ArgsList[$i + 1]; $i++; continue } }
      "--push" { $script:Push = $true; continue }
      "--force" { $script:Force = $true; continue }
      "--allow-dirty" { $script:AllowDirty = $true; continue }
      "--tool" { $script:Tool = $true; continue }
      "--name" { if ($i + 1 -lt $ArgsList.Count) { $script:Name = $ArgsList[$i + 1]; $i++; continue } }
      "--dest" { if ($i + 1 -lt $ArgsList.Count) { $script:Dest = $ArgsList[$i + 1]; $i++; continue } }
      "--software" { $script:Software = $true; continue }
      "--no-chinvex" { $script:NoChinvex = $true; continue }
      "--json" { $script:Json = $true; continue }
      "--yes" { $script:Yes = $true; continue }
      "--dry-run" { $script:DryRun = $true; continue }
      "--keep-folder" { $script:KeepFolder = $true; continue }
      "--keep-shims" { $script:KeepShims = $true; continue }
      "--cwd" { if ($i + 1 -lt $ArgsList.Count) { $script:Cwd = $ArgsList[$i + 1]; $i++; continue } }
      "--repo" { if ($i + 1 -lt $ArgsList.Count) { $script:Repo = $ArgsList[$i + 1]; $i++; continue } }
      "--cmd" { if ($i + 1 -lt $ArgsList.Count) { $script:Cmd = $ArgsList[$i + 1]; $i++; continue } }
      "--rebase" { $script:Rebase = $true; continue }
      "--stash" { $script:Stash = $true; continue }
      "--setup" { $script:Setup = $true; continue }
      "--all" { $script:All = $true; continue }
      "--stack" { if ($i + 1 -lt $ArgsList.Count) { $script:Stack = $ArgsList[$i + 1]; $i++; continue } }
      "--venv" { if ($i + 1 -lt $ArgsList.Count) { $script:Venv = $ArgsList[$i + 1]; $i++; continue } }
      "--uv" { $script:Uv = $true; continue }
      "--python" { if ($i + 1 -lt $ArgsList.Count) { $script:Python = $ArgsList[$i + 1]; $i++; continue } }
      "--pm" { if ($i + 1 -lt $ArgsList.Count) { $script:Pm = $ArgsList[$i + 1]; $i++; continue } }
      "--corepack" { $script:Corepack = $true; continue }
      "--to" { if ($i + 1 -lt $ArgsList.Count) { $script:To = [int]$ArgsList[$i + 1]; $i++; continue } }
      "--plan" { $script:Plan = $true; continue }
      "--backup" { $script:Backup = $true; continue }
      "--rehome-shims" { $script:RehomeShims = $true; continue }
      "--move-folder" { $script:MoveFolder = $true; continue }
      default { }
    }
  }
}

Apply-ExtraArgs $ExtraArgs

function Parse-GlobalFlags {
  <#
  .SYNOPSIS
      Extracts chinvex-related global flags from command line arguments.
  .DESCRIPTION
      Parses --no-chinvex, --tool, and --software flags.
      Returns a hashtable with flag values and remaining arguments.
  .PARAMETER Arguments
      The full argument list from CLI.
  .OUTPUTS
      [hashtable] with keys: NoChinvex, IsTool, IsSoftware, RemainingArgs
  #>
  param(
      [string[]] $Arguments
  )

  $result = @{
      NoChinvex = $false
      IsTool = $false
      IsSoftware = $false
      RemainingArgs = @()
  }

  foreach ($arg in $Arguments) {
      switch ($arg) {
          "--no-chinvex" { $result.NoChinvex = $true }
          "--tool" { $result.IsTool = $true }
          "--software" { $result.IsSoftware = $true }
          default { $result.RemainingArgs += $arg }
      }
  }

  return $result
}

$TemplateRoot = if ($StrapRoot) { $StrapRoot } else { $PSScriptRoot }
$DefaultBranch = if ($env:BOOTSTRAP_BRANCH) { $env:BOOTSTRAP_BRANCH } else { "main" }

function Show-Help {
  @"
strap usage:
  strap <project-name> -t <template> [-p <parent-dir>] [--skip-install] [--install] [--start]
  strap clone <git-url> [--tool] [--name <name>] [--dest <dir>]
  strap list [--tool] [--software] [--json]
  strap open <name>
  strap move <name> --dest <path> [--yes] [--dry-run] [--force] [--rehome-shims]
  strap rename <name> --to <newName> [--yes] [--dry-run] [--move-folder] [--force]
  strap adopt [--path <dir>] [--name <name>] [--tool|--software] [--yes] [--dry-run]
  strap setup [--yes] [--dry-run] [--stack python|node|go|rust] [--repo <name>]
  strap setup [--venv <path>] [--uv] [--python <exe>] [--pm npm|pnpm|yarn] [--corepack]
  strap update <name> [--yes] [--dry-run] [--rebase] [--stash] [--setup]
  strap update --all [--tool] [--software] [--yes] [--dry-run] [--rebase] [--stash] [--setup]
  strap uninstall <name> [--yes] [--dry-run] [--keep-folder] [--keep-shims]
  strap shim <name> --- <command...> [--cwd <path>] [--repo <name>] [--force] [--dry-run] [--yes]
  strap shim <name> --cmd "<command>" [--cwd <path>] [--repo <name>] [--force] [--dry-run] [--yes]
  strap doctor [--json]
  strap migrate [--yes] [--dry-run] [--backup] [--json] [--to <version>] [--plan]
  strap templatize <templateName> [--source <path>] [--message "<msg>"] [--push] [--force] [--allow-dirty]

Templates:
  node-ts-service | node-ts-web | python | mono

Flags:
  --skip-install  skip dependency install
  --install       run full install after initial commit
  --start         full install, then start dev
  --keep          keep doctor artifacts
  --strap-root    override strap repo root
  --tool          filter by tool scope or clone to tools directory
  --software      filter by software scope
  --json          output raw JSON
  --name          custom name for cloned repo or shim
  --dest          full destination path (overrides --tool)
  --yes           non-interactive mode (no confirmation prompt)
  --dry-run       show planned actions without executing
  --keep-folder   preserve repo folder during uninstall
  --keep-shims    preserve shims during uninstall
  --cwd           working directory for shim execution
  --cmd           command string (alternative to --- for complex commands with flags)
  --repo          attach shim to specific registry entry or run setup for registered repo
  --stack         force stack selection (python|node|go|rust)
  --venv          venv directory for Python (default .venv)
  --uv            use uv for Python installs (default on)
  --python        python executable for venv creation (default python)
  --pm            force package manager for Node (npm|pnpm|yarn)
  --corepack      enable corepack before Node install (default on)
  --rebase        use git pull --rebase for update
  --stash         auto-stash dirty working tree before update
  --setup         run strap setup after successful update
  --all           update all registered repos (filtered by --tool/--software)
  --source        source repo for templatize
  --message       commit message for templatize
  --push          push after templatize commit
  --force         overwrite existing file/template (or allow unsafe move/rename)
  --allow-dirty   allow templatize when strap repo is dirty
  --rehome-shims  update shim content with new repo path (move only)
  --move-folder   also rename folder on disk (rename only)
  --to            new name for rename command
"@ | Write-Host
}

if ($RepoName -in @("--help","-h","help")) {
  Show-Help
  exit 0
}

function Ensure-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { Die "Missing required command: $name" }
}

function Has-Command($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Load-Config($strapRoot) {
  $configPath = Join-Path $strapRoot "config.json"
  if (-not (Test-Path $configPath)) {
    Die "Config not found: $configPath"
  }
  $json = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

  # Apply chinvex integration defaults (new fields)
  if ($null -eq $json.chinvex_integration) {
    $json | Add-Member -NotePropertyName chinvex_integration -NotePropertyValue $true -Force
  }
  if ($null -eq $json.chinvex_whitelist) {
    $json | Add-Member -NotePropertyName chinvex_whitelist -NotePropertyValue @("tools", "archive") -Force
  }
  if ($null -eq $json.software_root) {
    $json | Add-Member -NotePropertyName software_root -NotePropertyValue "P:\software" -Force
  }
  if ($null -eq $json.tools_root) {
    $json | Add-Member -NotePropertyName tools_root -NotePropertyValue "P:\software\_scripts" -Force
  }

  return $json
}

# ============================================================================
# CHINVEX INTEGRATION - CLI Wrappers
# ============================================================================

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

# ============================================================================
# CHINVEX INTEGRATION - Helper Functions
# ============================================================================

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

function Parse-GitUrl($url) {
  # Extract repo name from git URL
  # Examples:
  #   https://github.com/user/repo.git -> repo
  #   https://github.com/user/repo -> repo
  #   git@github.com:user/repo.git -> repo
  #   https://github.com/user/repo/ -> repo
  #   https://github.com/user/repo.git?foo=bar -> repo

  $url = $url.Trim()

  # Remove query string if present
  if ($url -match '\?') {
    $url = $url.Substring(0, $url.IndexOf('?'))
  }

  # Remove trailing slashes
  $url = $url.TrimEnd('/')

  # Remove .git suffix if present
  if ($url.EndsWith(".git")) {
    $url = $url.Substring(0, $url.Length - 4)
  }

  # Extract last segment (handle both / and : separators for SSH URLs)
  $segments = $url -split '[/:]'
  $name = $segments[-1]

  if (-not $name) {
    Die "Could not parse repo name from URL: $url"
  }

  return $name
}

function Load-Registry($configObj) {
  $registryPath = $configObj.registry
  if (-not (Test-Path $registryPath)) {
    # Create empty registry if it doesn't exist
    $parentDir = Split-Path $registryPath -Parent
    if (-not (Test-Path $parentDir)) {
      New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    "[]" | Set-Content -LiteralPath $registryPath -NoNewline
    return @()
  }
  $content = Get-Content -LiteralPath $registryPath -Raw
  if ($content.Trim() -eq "[]") {
    return @()
  }
  $json = $content | ConvertFrom-Json

  # Handle both legacy (array) and new (object) formats
  if ($json -is [System.Array]) {
    # Legacy format: bare array
    return @($json)
  } elseif ($json.PSObject.Properties['entries']) {
    # New format: object with entries property
    $entries = $json.entries
    if ($entries -is [System.Array]) {
      return @($entries)
    } else {
      return @($entries)
    }
  } else {
    # Unknown format or single object: wrap in array
    return @($json)
  }
}

function Save-Registry($configObj, $entries) {
  $registryPath = $configObj.registry
  $tmpPath = "$registryPath.tmp"

  # Always write in versioned format (V1)
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $registryObj = [PSCustomObject]@{
    registry_version = 1
    updated_at = $timestamp
    entries = @($entries)
  }

  $json = $registryObj | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($tmpPath, $json, (New-Object System.Text.UTF8Encoding($false)))

  # Atomic move (overwrites destination)
  Move-Item -LiteralPath $tmpPath -Destination $registryPath -Force
}

# Migration constants and helpers

$script:LATEST_REGISTRY_VERSION = 1

function Get-RegistryVersion($registryPath) {
  if (-not (Test-Path $registryPath)) {
    return $null
  }

  $content = Get-Content -LiteralPath $registryPath -Raw
  if ($content.Trim() -eq "[]") {
    return 0
  }

  try {
    $json = $content | ConvertFrom-Json
  } catch {
    throw "Invalid JSON in registry"
  }

  # If it's an array, it's version 0
  if ($json -is [System.Array]) {
    return 0
  }

  # If it has registry_version, use it
  if ($json.PSObject.Properties['registry_version']) {
    return $json.registry_version
  }

  # Otherwise it's a legacy object, version 0
  return 0
}

# Consolidate helper functions

function Normalize-Path {
  param([string] $Path)
  if (-not $Path) { return "" }
  return [System.IO.Path]::GetFullPath($Path).ToLowerInvariant().Replace('/', '\').TrimEnd('\')
}

function Test-PathWithinRoot {
  param(
    [string] $Path,
    [string] $RootPath
  )
  if (-not $Path -or -not $RootPath) { return $false }
  $normalizedPath = Normalize-Path $Path
  $normalizedRoot = Normalize-Path $RootPath
  return $normalizedPath.StartsWith($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Find-DuplicatePaths {
  param([array] $Paths)

  $seen = @{}
  foreach ($path in $Paths) {
    if (-not $path) { continue }
    $key = $path.ToLowerInvariant()
    if ($seen.ContainsKey($key) -and $seen[$key] -ne $path) {
      return "$($seen[$key]) <-> $path"
    }
    $seen[$key] = $path
  }
  return $null
}

function Test-ProcessRunning {
  param([int] $ProcessId)
  try {
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    return $null -ne $process
  } catch {
    return $false
  }
}

function Get-DirectorySize {
  param([string] $Path)
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  try {
    $size = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
      Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    return [long]($size ?? 0)
  } catch {
    return 0
  }
}

function Invoke-Migration-0-to-1 {
  param(
    [PSCustomObject] $RegistryData,
    [ref] $Report
  )
  if (-not (Assert-CommandSafe 'Invoke-Migration-0-to-1')) { return }

  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $entries = $RegistryData.entries
  $modified = 0
  $backfilled = @{}

  # Process each entry
  for ($i = 0; $i -lt $entries.Count; $i++) {
    $entry = $entries[$i]
    $changed = $false

    # Ensure id exists
    if (-not $entry.PSObject.Properties['id']) {
      $entry | Add-Member -MemberType NoteProperty -Name 'id' -Value $entry.name -Force
      $changed = $true
      if (-not $backfilled.ContainsKey('id')) { $backfilled['id'] = 0 }
      $backfilled['id']++
    }

    # Ensure shims exists
    if (-not $entry.PSObject.Properties['shims']) {
      $entry | Add-Member -MemberType NoteProperty -Name 'shims' -Value @() -Force
      $changed = $true
      if (-not $backfilled.ContainsKey('shims')) { $backfilled['shims'] = 0 }
      $backfilled['shims']++
    }

    # Ensure created_at exists
    if (-not $entry.PSObject.Properties['created_at']) {
      $fallback = if ($entry.PSObject.Properties['updated_at']) { $entry.updated_at } else { $timestamp }
      $entry | Add-Member -MemberType NoteProperty -Name 'created_at' -Value $fallback -Force
      $changed = $true
      if (-not $backfilled.ContainsKey('created_at')) { $backfilled['created_at'] = 0 }
      $backfilled['created_at']++
    }

    # Ensure updated_at exists
    if (-not $entry.PSObject.Properties['updated_at']) {
      $entry | Add-Member -MemberType NoteProperty -Name 'updated_at' -Value $timestamp -Force
      $changed = $true
      if (-not $backfilled.ContainsKey('updated_at')) { $backfilled['updated_at'] = 0 }
      $backfilled['updated_at']++
    }

    if ($changed) { $modified++ }
  }

  # Check for duplicates by name
  $nameGroups = $entries | Group-Object -Property name
  $duplicates = $nameGroups | Where-Object { $_.Count -gt 1 }

  if ($duplicates) {
    $dupNames = $duplicates | ForEach-Object { $_.Name }
    throw "Duplicate entries found (manual resolution required): $($dupNames -join ', ')"
  }

  # Update report
  $Report.Value.backfilled = $backfilled
  $Report.Value.entries_modified = $modified
  $Report.Value.duplicates = @()

  # Return upgraded registry
  return [PSCustomObject]@{
    registry_version = 1
    updated_at = $timestamp
    entries = $entries
  }
}

function Validate-RegistrySchema {
  param([array] $Entries)

  $issues = @()

  for ($i = 0; $i -lt $Entries.Count; $i++) {
    $entry = $Entries[$i]
    $idx = $i + 1

    # Required fields
    if (-not $entry.PSObject.Properties['name'] -or -not $entry.name) {
      $issues += "Entry ${idx}: missing required field 'name'"
    }
    if (-not $entry.PSObject.Properties['id'] -or -not $entry.id) {
      $issues += "Entry ${idx}: missing required field 'id'"
    }
    if (-not $entry.PSObject.Properties['scope'] -or $entry.scope -notin @('tool', 'software')) {
      $issues += "Entry ${idx}: missing or invalid 'scope' (must be 'tool' or 'software')"
    }
    if (-not $entry.PSObject.Properties['path'] -or -not $entry.path) {
      $issues += "Entry ${idx}: missing required field 'path'"
    }
    if (-not $entry.PSObject.Properties['shims']) {
      $issues += "Entry ${idx}: missing required field 'shims'"
    }
    if (-not $entry.PSObject.Properties['created_at'] -or -not $entry.created_at) {
      $issues += "Entry ${idx}: missing required field 'created_at'"
    }
    if (-not $entry.PSObject.Properties['updated_at'] -or -not $entry.updated_at) {
      $issues += "Entry ${idx}: missing required field 'updated_at'"
    }
  }

  return $issues
}

function Copy-TemplateDir($src, $dest) {
  if (-not (Test-Path $src)) { Die "Template dir missing: $src" }
  Get-ChildItem -LiteralPath $src -Force | ForEach-Object {
    $target = Join-Path $dest $_.Name
    if ($_.PSIsContainer) {
      if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target | Out-Null }
      Get-ChildItem -LiteralPath $_.FullName -Force | ForEach-Object {
        $childTarget = Join-Path $target $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $childTarget -Recurse -Force
      }
    } else {
      Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
  }
}

function Is-ProbablyTextFile($path) {
  $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
  $binary = @(".png",".jpg",".jpeg",".gif",".ico",".pdf",".zip",".gz",".tgz",".woff",".woff2",".ttf",".eot",".exe",".dll")
  return -not ($binary -contains $ext)
}

function Normalize-TextFiles($root) {
  Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
    $p = $_.FullName
    if (-not (Is-ProbablyTextFile $p)) { return }

    $content = Get-Content -LiteralPath $p -Raw
    if ($null -eq $content) { $content = "" }
    $content = $content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($p, $content, (New-Object System.Text.UTF8Encoding($false)))
  }
}

function Replace-Tokens($root, $tokens) {
  Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
    $p = $_.FullName
    if (-not (Is-ProbablyTextFile $p)) { return }

    $content = Get-Content -LiteralPath $p -Raw
    if ($null -eq $content) { $content = "" }
    foreach ($k in $tokens.Keys) {
      $content = $content.Replace($k, $tokens[$k])
    }
    $content = $content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($p, $content, (New-Object System.Text.UTF8Encoding($false)))
  }
}

function Get-TokenMatches($root) {
  $pattern = "\{\{REPO_NAME\}\}|\{\{PY_PACKAGE\}\}|<REPO_NAME>|<PY_PACKAGE>"
  $ignoreGlobs = @(
    "!**/.git/**",
    "!**/node_modules/**",
    "!**/dist/**",
    "!**/build/**",
    "!**/coverage/**",
    "!**/.venv/**",
    "!**/__pycache__/**",
    "!**/.turbo/**",
    "!**/.vite/**",
    "!**/.pnpm-store/**"
  )

  $results = @()

  if (Has-Command rg) {
    $args = @("-n","-o") + ($ignoreGlobs | ForEach-Object { @("--glob", $_) }) + @($pattern, $root)
    $lines = & rg @args
    foreach ($line in $lines) {
      if ($line -match "^(.*?):(\\d+):(.*)$") {
        $results += [pscustomobject]@{ Path = $matches[1]; Line = [int]$matches[2]; Match = $matches[3] }
      }
    }
  } else {
    $files = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
      $_.FullName -notmatch "[\\/]\.git[\\/]" -and
      $_.FullName -notmatch "[\\/]node_modules[\\/]" -and
      $_.FullName -notmatch "[\\/]dist[\\/]" -and
      $_.FullName -notmatch "[\\/]build[\\/]" -and
      $_.FullName -notmatch "[\\/]coverage[\\/]" -and
      $_.FullName -notmatch "[\\/]\.venv[\\/]" -and
      $_.FullName -notmatch "[\\/]__pycache__[\\/]" -and
      $_.FullName -notmatch "[\\/]\.turbo[\\/]" -and
      $_.FullName -notmatch "[\\/]\.vite[\\/]" -and
      $_.FullName -notmatch "[\\/]\.pnpm-store[\\/]"
    }
    foreach ($file in $files) {
      $matches = Select-String -LiteralPath $file.FullName -Pattern $pattern -AllMatches -ErrorAction SilentlyContinue
      foreach ($m in $matches) {
        foreach ($one in $m.Matches) {
          $results += [pscustomobject]@{ Path = $m.Path; Line = $m.LineNumber; Match = $one.Value }
        }
      }
    }
  }

  $results | Where-Object { $_.Path -notmatch "[\\/]\.git[\\/]" }
}

function Replace-TokenNames($root, $tokens) {
  $entries = Get-ChildItem -LiteralPath $root -Recurse -Force
  $sorted = $entries | Sort-Object { $_.FullName.Length } -Descending

  foreach ($item in $sorted) {
    $name = $item.Name
    $newName = $name
    foreach ($k in $tokens.Keys) {
      $newName = $newName.Replace($k, $tokens[$k])
    }

    if ($newName -ne $name) {
      Rename-Item -LiteralPath $item.FullName -NewName $newName -Force
    }
  }
}

function Resolve-RemainingTokens($root, $tokens) {
  Replace-Tokens $root $tokens
  Replace-TokenNames $root $tokens
  Normalize-TextFiles $root

  $matches = Get-TokenMatches $root
  if ($matches -and $matches.Count -gt 0) {
    Warn "Unresolved template tokens remain:"
    $matches | ForEach-Object { Warn ("  {0}:{1} -> {2}" -f $_.Path, $_.Line, $_.Match) }
    exit 1
  }
}

function Prompt-Template() {
  Write-Host "Select template:"
  Write-Host "  1) node-ts-service"
  Write-Host "  2) node-ts-web"
  Write-Host "  3) python"
  Write-Host "  4) mono (pnpm workspace)"
  $choice = Read-Host ">"

  switch ($choice) {
    "1" { return "node-ts-service" }
    "2" { return "node-ts-web" }
    "3" { return "python" }
    "4" { return "mono" }
    default { Die "Invalid choice" }
  }
}

function Stop-ProcessTree($processId) {
  $children = Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $processId }
  foreach ($child in $children) {
    Stop-ProcessTree $child.ProcessId
  }
  try { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue } catch { }
}

function Wait-For-Health($port) {
  $deadline = (Get-Date).AddSeconds(10)
  while ((Get-Date) -lt $deadline) {
    try {
      $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri ("http://127.0.0.1:{0}/health" -f $port)
      if ($resp.StatusCode -eq 200) { return $true }
    } catch { }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

function Get-FreePort($preferred) {
  $port = $preferred
  for ($i = 0; $i -lt 20; $i++) {
    try {
      $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
      $listener.Start()
      $listener.Stop()
      return $port
    } catch {
      $port = $port + 1
    }
  }
  return $preferred
}

function Read-EnvDefaults($path) {
  $vars = @{}
  if (-not (Test-Path $path)) { return $vars }
  Get-Content -LiteralPath $path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) { return }
    $parts = $line.Split("=", 2)
    if ($parts.Count -eq 2) {
      $vars[$parts[0].Trim()] = $parts[1].Trim()
    }
  }
  return $vars
}

function Resolve-GitRoot($path) {
  $p = (Resolve-Path -LiteralPath $path).Path
  $gitRoot = & git -C $p rev-parse --show-toplevel 2>$null
  if (-not $gitRoot) { return $null }
  return $gitRoot.Trim()
}

function Get-TemplateNameFromArgs([string[]] $ArgsList) {
  if (-not $ArgsList) { return $null }
  $skipNext = $false
  foreach ($arg in $ArgsList) {
    if ($skipNext) { $skipNext = $false; continue }
    switch -Regex ($arg) {
      '^(--source|--message)$' { $skipNext = $true; continue }
      '^(--push|--force|--allow-dirty)$' { continue }
      '^-{1,2}.*' { continue }
      default { return $arg }
    }
  }
  return $null
}

function Get-ScheduledTaskReferences {
    <#
    .SYNOPSIS
    Detects Windows scheduled tasks that reference repository paths

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'name' and 'path' properties
    #>
    param(
        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    try {
        # Get all scheduled tasks as CSV
        $csv = & schtasks /query /fo csv /v 2>$null
        if (-not $csv) { return @() }

        # Parse CSV output
        $tasks = $csv | ConvertFrom-Csv -ErrorAction SilentlyContinue
        if (-not $tasks) { return @() }

        # Normalize repo paths for comparison
        $normalizedRepoPaths = $RepoPaths | ForEach-Object {
            $_.Replace('/', '\').TrimEnd('\').ToLower()
        }

        # Scan each task for path references
        $references = [System.Collections.ArrayList]::new()
        foreach ($task in $tasks) {
            # Combine task name, command, and arguments for path extraction
            $searchText = "$($task.TaskName) $($task.'Task To Run')"

            # Extract Windows paths (e.g., C:\path\to\file)
            $pathMatches = [regex]::Matches($searchText, '[A-Za-z]:\\[^\s,\"]+')

            foreach ($match in $pathMatches) {
                $extractedPath = $match.Value.TrimEnd('\').ToLower()

                # Check if path starts with any repo path
                $matchesRepo = $normalizedRepoPaths | Where-Object {
                    $extractedPath.StartsWith($_)
                }

                if ($matchesRepo) {
                    $null = $references.Add(@{
                        name = $task.TaskName
                        path = $match.Value
                    })
                    break  # Only add task once even if multiple paths match
                }
            }
        }

        return ,$references.ToArray()

    } catch {
        # schtasks failed or not available - return empty array
        Write-Verbose "Failed to query scheduled tasks: $_"
        return @()
    }
}

function Get-ShimReferences {
    <#
    .SYNOPSIS
    Detects .cmd shim files that reference repository paths

    .PARAMETER ShimDir
    Directory containing shim files (typically build/shims)

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'name' and 'target' properties
    #>
    param(
        [Parameter(Mandatory)]
        [string] $ShimDir,

        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    # Check if shim directory exists
    if (-not (Test-Path $ShimDir)) {
        Write-Verbose "Shim directory not found: $ShimDir"
        return @()
    }

    # Normalize repo paths for comparison
    $normalizedRepoPaths = $RepoPaths | ForEach-Object {
        $_.Replace('/', '\').TrimEnd('\').ToLower()
    }

    # Scan all .cmd files in shim directory
    $references = [System.Collections.ArrayList]::new()
    $shimFiles = Get-ChildItem -Path $ShimDir -Filter "*.cmd" -ErrorAction SilentlyContinue

    foreach ($shimFile in $shimFiles) {
        try {
            # Read shim content
            $content = Get-Content $shimFile.FullName -Raw -ErrorAction Stop

            # Extract Windows paths from content
            $pathMatches = [regex]::Matches($content, '[A-Za-z]:\\[^\r\n\"]+')

            foreach ($match in $pathMatches) {
                $extractedPath = $match.Value.TrimEnd('\').ToLower()

                # Check if path starts with any repo path
                $matchesRepo = $normalizedRepoPaths | Where-Object {
                    $extractedPath.StartsWith($_)
                }

                if ($matchesRepo) {
                    $null = $references.Add(@{
                        name = $shimFile.BaseName
                        target = $match.Value
                    })
                    break  # Only add shim once even if multiple paths match
                }
            }
        } catch {
            Write-Verbose "Failed to read shim file $($shimFile.FullName): $_"
            continue
        }
    }

    return ,$references.ToArray()
}

function Get-PathReferences {
    <#
    .SYNOPSIS
    Detects PATH environment variable entries that reference repository paths

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'type' and 'path' properties
    #>
    param(
        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    # Normalize repo paths for comparison
    $normalizedRepoPaths = $RepoPaths | ForEach-Object {
        $_.Replace('/', '\').TrimEnd('\').ToLower()
    }

    # Get User and Machine PATH variables
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

    # Combine and split by semicolon
    $allPathEntries = @()
    if ($userPath) { $allPathEntries += $userPath -split ';' }
    if ($machinePath) { $allPathEntries += $machinePath -split ';' }

    # Find matching entries
    $references = [System.Collections.ArrayList]::new()
    foreach ($pathEntry in $allPathEntries) {
        if ([string]::IsNullOrWhiteSpace($pathEntry)) { continue }

        $normalizedEntry = $pathEntry.TrimEnd('\').ToLower()

        # Check if entry starts with any repo path
        $matchesRepo = $normalizedRepoPaths | Where-Object {
            $normalizedEntry.StartsWith($_)
        }

        if ($matchesRepo) {
            $null = $references.Add(@{
                type = "PATH"
                path = $pathEntry
            })
        }
    }

    return ,$references.ToArray()
}

function Get-ProfileReferences {
    <#
    .SYNOPSIS
    Detects PowerShell profile references to repository paths

    .PARAMETER ProfilePath
    Path to PowerShell profile file (defaults to $PROFILE)

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'type' and 'path' properties
    #>
    param(
        [Parameter()]
        [string] $ProfilePath = $PROFILE,

        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    # Check if profile exists
    if (-not (Test-Path $ProfilePath)) {
        Write-Verbose "Profile not found: $ProfilePath"
        return @()
    }

    try {
        # Read profile content
        $content = Get-Content $ProfilePath -Raw -ErrorAction Stop

        # Normalize repo paths for comparison
        $normalizedRepoPaths = $RepoPaths | ForEach-Object {
            $_.Replace('/', '\').TrimEnd('\').ToLower()
        }

        # Extract Windows paths from content
        $pathMatches = [regex]::Matches($content, '[A-Za-z]:\\[^\s\r\n\"\'']+')

        # Find matching paths
        $references = [System.Collections.ArrayList]::new()
        foreach ($match in $pathMatches) {
            $extractedPath = $match.Value.TrimEnd('\').ToLower()

            # Check if path starts with any repo path
            $matchesRepo = $normalizedRepoPaths | Where-Object {
                $extractedPath.StartsWith($_)
            }

            if ($matchesRepo) {
                $null = $references.Add(@{
                    type = "profile"
                    path = $match.Value
                })
            }
        }

        return ,$references.ToArray()

    } catch {
        Write-Verbose "Failed to read profile $ProfilePath`: $_"
        return @()
    }
}

function Find-PathReferences {
    <#
    .SYNOPSIS
    Scans repository files for hardcoded Windows path references

    .PARAMETER RepoPath
    Path to repository to scan

    .OUTPUTS
    Array of strings in format "filepath:linenum"
    #>
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    # Check if repo exists
    if (-not (Test-Path $RepoPath)) {
        Write-Verbose "Repository not found: $RepoPath"
        return @()
    }

    try {
        # Scan common file types for path references
        $fileExtensions = @('*.ps1', '*.js', '*.ts', '*.json', '*.yml', '*.yaml', '*.md', '*.txt', '*.config')
        $files = Get-ChildItem -Path $RepoPath -Recurse -File -Include $fileExtensions -ErrorAction SilentlyContinue

        $references = @()

        foreach ($file in $files) {
            try {
                $lineNum = 0
                $lines = Get-Content $file.FullName -ErrorAction Stop

                foreach ($line in $lines) {
                    $lineNum++

                    # Check if line contains Windows path pattern
                    if ($line -match '[A-Za-z]:\\[^\s\r\n\"\'']+') {
                        $references += "$($file.FullName):$lineNum"
                    }
                }
            } catch {
                Write-Verbose "Failed to read file $($file.FullName): $_"
                continue
            }
        }

        return $references

    } catch {
        Write-Verbose "Failed to scan repository $RepoPath`: $_"
        return @()
    }
}

function Build-AuditIndex {
    <#
    .SYNOPSIS
    Builds or loads cached audit index of path references across all repositories

    .PARAMETER IndexPath
    Path to audit index JSON file

    .PARAMETER RebuildIndex
    Force rebuild even if cached index is fresh

    .PARAMETER RegistryUpdatedAt
    ISO8601 timestamp of registry last update

    .PARAMETER Registry
    Array of registry entries (hashtables with 'name', 'path', 'last_commit')

    .OUTPUTS
    Hashtable with audit index structure
    #>
    param(
        [Parameter(Mandatory)]
        [string] $IndexPath,

        [Parameter(Mandatory)]
        [bool] $RebuildIndex,

        [Parameter(Mandatory)]
        [string] $RegistryUpdatedAt,

        [Parameter(Mandatory)]
        [array] $Registry
    )

    # Check if existing index is fresh
    if ((Test-Path $IndexPath) -and -not $RebuildIndex) {
        try {
            $existingJson = Get-Content $IndexPath -Raw | ConvertFrom-Json

            # Check if cached index is still valid
            # Note: ConvertFrom-Json converts ISO8601 strings to DateTime in local timezone
            # We need to compare UTC times to handle timezone differences
            $existingTime = $null
            $inputTime = $null

            if ($existingJson.registry_updated_at -is [DateTime]) {
                $existingTime = $existingJson.registry_updated_at.ToUniversalTime()
            } else {
                $existingTime = ([DateTime]::Parse($existingJson.registry_updated_at)).ToUniversalTime()
            }

            $inputTime = ([DateTime]::Parse($RegistryUpdatedAt)).ToUniversalTime()

            $isFresh = ($existingTime -eq $inputTime) -and
                       ($existingJson.repo_count -eq $Registry.Count)

            if ($isFresh) {
                Write-Verbose "Using cached audit index"

                # Convert PSCustomObject to hashtable for consistency
                # Convert DateTime objects back to ISO8601 strings
                $builtAtStr = $existingJson.built_at
                if ($builtAtStr -is [DateTime]) {
                    $builtAtStr = $builtAtStr.ToUniversalTime().ToString("o")
                }

                $regUpdatedAtStr = $existingJson.registry_updated_at
                if ($regUpdatedAtStr -is [DateTime]) {
                    $regUpdatedAtStr = $regUpdatedAtStr.ToUniversalTime().ToString("o")
                }

                $existing = @{
                    built_at = $builtAtStr
                    registry_updated_at = $regUpdatedAtStr
                    repo_count = $existingJson.repo_count
                    repos = @{}
                }

                # Convert repos object to hashtable
                $existingJson.repos.PSObject.Properties | ForEach-Object {
                    $repoRefs = @()
                    if ($_.Value.references) {
                        $repoRefs = @($_.Value.references)
                    }
                    $existing.repos[$_.Name] = @{
                        references = $repoRefs
                    }
                }

                return $existing
            }
        } catch {
            Write-Verbose "Failed to read existing index, rebuilding"
        }
    }

    # Build new index
    Write-Host "Building audit index for $($Registry.Count) repositories..." -ForegroundColor Cyan

    $repos = @{}
    foreach ($entry in $Registry) {
        Write-Verbose "Scanning $($entry.name) at $($entry.path)"

        # Scan repo for path references
        $references = Find-PathReferences -RepoPath $entry.path

        $repos[$entry.path] = @{
            references = $references
        }
    }

    # Build index structure
    $index = @{
        built_at = (Get-Date).ToUniversalTime().ToString("o")
        registry_updated_at = $RegistryUpdatedAt
        repo_count = $Registry.Count
        repos = $repos
    }

    # Write to disk
    try {
        $indexDir = Split-Path $IndexPath -Parent
        if ($indexDir -and -not (Test-Path $indexDir)) {
            New-Item -ItemType Directory -Path $indexDir -Force | Out-Null
        }

        $index | ConvertTo-Json -Depth 10 | Set-Content $IndexPath -Encoding UTF8
        Write-Verbose "Audit index written to $IndexPath"
    } catch {
        Write-Warning "Failed to write audit index to disk: $_"
    }

    return $index
}

function Invoke-Snapshot {
    <#
    .SYNOPSIS
    Captures comprehensive environment snapshot with git metadata and external references

    .PARAMETER ScanDirs
    Array of directories to scan (defaults to C:\Code, P:\software, etc.)

    .PARAMETER OutputPath
    Path to write snapshot JSON file

    .PARAMETER StrapRootPath
    Path to strap root directory

    .OUTPUTS
    Hashtable with snapshot manifest structure
    #>
    param(
        [Parameter()]
        [string[]] $ScanDirs,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [Parameter(Mandatory)]
        [string] $StrapRootPath
    )
    if (-not (Assert-CommandSafe 'Invoke-Snapshot')) { return }

    Write-Host "Capturing environment snapshot..." -ForegroundColor Cyan

    # Default scan directories
    $defaultScanDirs = @("C:\Code", "P:\software", "C:\Users\$env:USERNAME\Documents\Code")
    if ($ScanDirs.Count -eq 0) {
        $ScanDirs = $defaultScanDirs | Where-Object { Test-Path $_ }
    }

    # Load registry
    $config = Load-Config $StrapRootPath
    $registryPath = $config.registry
    $registry = $null
    $registryVersion = 1

    if (Test-Path $registryPath) {
        try {
            $registryContent = Get-Content $registryPath -Raw | ConvertFrom-Json
            if ($registryContent.PSObject.Properties['entries']) {
                # New format
                $registry = $registryContent.entries
                $registryVersion = $registryContent.version
            } else {
                # Legacy format
                $registry = $registryContent
            }
        } catch {
            Write-Warning "Failed to load registry: $_"
            $registry = @()
        }
    } else {
        $registry = @()
    }

    # Build registry lookup by path (case-insensitive)
    $registryByPath = @{}
    foreach ($entry in $registry) {
        if ($entry.path) {
            $registryByPath[$entry.path.ToLower()] = $entry.name
        }
    }

    # Scan directories top-level
    Write-Verbose "Scanning directories: $($ScanDirs -join ', ')"
    $discovered = @()

    foreach ($scanDir in $ScanDirs) {
        if (-not (Test-Path $scanDir)) {
            Write-Verbose "Skipping non-existent directory: $scanDir"
            continue
        }

        $items = Get-ChildItem -Path $scanDir -ErrorAction SilentlyContinue

        foreach ($item in $items) {
            $itemPath = $item.FullName
            $inRegistry = $registryByPath.ContainsKey($itemPath.ToLower())

            if ($item.PSIsContainer) {
                # Check if it's a git repo
                $gitDir = Join-Path $itemPath ".git"
                if (Test-Path $gitDir) {
                    # Git repository
                    $remoteUrl = $null
                    $lastCommit = $null

                    try {
                        $remoteRaw = & git -C $itemPath remote get-url origin 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $remoteUrl = $remoteRaw.Trim()
                            # Normalize remote URL
                            if ($remoteUrl -match '^git@([^:]+):(.+)$') {
                                $remoteUrl = "https://$($Matches[1])/$($Matches[2])"
                            }
                            $remoteUrl = $remoteUrl -replace '\.git$', ''
                        }
                    } catch {}

                    try {
                        $commitRaw = & git -C $itemPath log -1 --format=%cI 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $lastCommit = $commitRaw.Trim()
                        }
                    } catch {}

                    $discovered += @{
                        path = $itemPath
                        name = $item.Name
                        type = "git"
                        in_registry = $inRegistry
                        remote_url = $remoteUrl
                        last_commit = $lastCommit
                    }
                } else {
                    # Regular directory
                    $discovered += @{
                        path = $itemPath
                        name = $item.Name
                        type = "directory"
                        in_registry = $inRegistry
                    }
                }
            } else {
                # File
                $discovered += @{
                    path = $itemPath
                    name = $item.Name
                    type = "file"
                }
            }
        }
    }

    # Collect external references
    Write-Verbose "Collecting external references..."
    $repoPaths = @($registry | Where-Object { $_.path } | ForEach-Object { $_.path })

    $externalRefs = @{
        pm2 = @()
        scheduled_tasks = @()
        shims = @()
        path_entries = @()
        profile_refs = @()
    }

    # PM2 processes
    if (Has-Command "pm2") {
        try {
            $pm2List = & pm2 jlist 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
            foreach ($proc in $pm2List) {
                if ($proc.pm2_env.pm_cwd) {
                    $externalRefs.pm2 += @{
                        name = $proc.name
                        cwd = $proc.pm2_env.pm_cwd
                    }
                }
            }
        } catch {}
    }

    # Only collect references if we have repos to check
    if ($repoPaths.Count -gt 0) {
        # Scheduled tasks
        $externalRefs.scheduled_tasks = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Shims
        $shimDir = Join-Path $StrapRootPath "build\shims"
        $externalRefs.shims = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # PATH entries
        $externalRefs.path_entries = Get-PathReferences -RepoPaths $repoPaths

        # Profile references
        $externalRefs.profile_refs = Get-ProfileReferences -RepoPaths $repoPaths
    }

    # Get disk usage
    $diskUsage = @{}
    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' }
        foreach ($drive in $drives) {
            $diskUsage[$drive.Name + ":"] = @{
                total_gb = [Math]::Round($drive.Used / 1GB + $drive.Free / 1GB, 2)
                free_gb = [Math]::Round($drive.Free / 1GB, 2)
            }
        }
    } catch {
        Write-Verbose "Failed to get disk usage: $_"
    }

    # Build snapshot manifest
    $manifest = @{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        registry = @{
            version = $registryVersion
            entries = $registry
        }
        discovered = $discovered
        external_refs = $externalRefs
        disk_usage = $diskUsage
    }

    # Write to output file
    try {
        $outputDir = Split-Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        $manifest | ConvertTo-Json -Depth 10 | Set-Content $OutputPath -Encoding UTF8
        Write-Host "Snapshot written to: $OutputPath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to write snapshot to $OutputPath`: $_"
    }

    return $manifest
}

function Invoke-Audit {
    <#
    .SYNOPSIS
    Audits repositories for hardcoded path references

    .PARAMETER TargetName
    Name of specific repository to audit

    .PARAMETER AllRepos
    Audit all repositories in registry

    .PARAMETER ToolScope
    Filter to tool-scoped repositories only

    .PARAMETER SoftwareScope
    Filter to software-scoped repositories only

    .PARAMETER RebuildIndex
    Force rebuild of audit index even if cached

    .PARAMETER OutputJson
    Output results as JSON

    .PARAMETER StrapRootPath
    Path to strap root directory

    .OUTPUTS
    Hashtable or array with audit results
    #>
    param(
        [Parameter()]
        [string] $TargetName,

        [Parameter()]
        [switch] $AllRepos,

        [Parameter()]
        [switch] $ToolScope,

        [Parameter()]
        [switch] $SoftwareScope,

        [Parameter()]
        [switch] $RebuildIndex,

        [Parameter()]
        [switch] $OutputJson,

        [Parameter(Mandatory)]
        [string] $StrapRootPath
    )
    if (-not (Assert-CommandSafe 'Invoke-Audit')) { return }

    # Load config and registry
    $config = Load-Config $StrapRootPath
    $registryPath = $config.registry

    if (-not (Test-Path $registryPath)) {
        Die "Registry not found: $registryPath"
    }

    $registryContent = Get-Content $registryPath -Raw | ConvertFrom-Json
    $registryUpdatedAt = $registryContent.updated_at
    $registry = if ($registryContent.PSObject.Properties['entries']) {
        $registryContent.entries
    } else {
        $registryContent
    }

    # Filter by scope if requested
    if ($ToolScope) {
        $registry = $registry | Where-Object { $_.scope -eq "tool" }
    }
    if ($SoftwareScope) {
        $registry = $registry | Where-Object { $_.scope -eq "software" }
    }

    # Build audit index
    $indexPath = Join-Path $StrapRootPath "build\audit-index.json"
    $auditIndex = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $RebuildIndex.IsPresent `
        -RegistryUpdatedAt $registryUpdatedAt -Registry $registry

    # Process audit results
    if ($AllRepos) {
        # Audit all repositories
        $results = @()
        foreach ($repoPath in $auditIndex.repos.Keys) {
            $entry = $registry | Where-Object { $_.path -eq $repoPath } | Select-Object -First 1
            if (-not $entry) { continue }

            $refs = $auditIndex.repos[$repoPath].references
            $results += @{
                repository = $entry.name
                path = $repoPath
                references = $refs
                reference_count = $refs.Count
            }
        }

        if ($OutputJson) {
            $results | ConvertTo-Json -Depth 10
        } else {
            Write-Host "`nAudit Results - All Repositories:" -ForegroundColor Cyan
            foreach ($res in $results) {
                Write-Host "`n$($res.repository) ($($res.path))" -ForegroundColor Yellow
                Write-Host "  References found: $($res.reference_count)"
                if ($res.reference_count -gt 0) {
                    $res.references | Select-Object -First 5 | ForEach-Object {
                        Write-Host "    - $_" -ForegroundColor Gray
                    }
                    if ($res.reference_count -gt 5) {
                        Write-Host "    ... and $($res.reference_count - 5) more" -ForegroundColor Gray
                    }
                }
            }
        }

        return $results

    } else {
        # Audit specific repository
        if (-not $TargetName) {
            Die "Audit requires a target name or --all flag"
        }

        $entry = $registry | Where-Object { $_.name -eq $TargetName -or $_.id -eq $TargetName } | Select-Object -First 1
        if (-not $entry) {
            Die "Repository '$TargetName' not found in registry"
        }

        $refs = $auditIndex.repos[$entry.path].references
        $result = @{
            repository = $entry.name
            path = $entry.path
            references = $refs
            reference_count = $refs.Count
        }

        if ($OutputJson) {
            $result | ConvertTo-Json -Depth 10
        } else {
            Write-Host "`nAudit Results for $($entry.name):" -ForegroundColor Cyan
            Write-Host "Path: $($entry.path)"
            Write-Host "References found: $($refs.Count)"
            if ($refs.Count -gt 0) {
                Write-Host "`nReferences:" -ForegroundColor Yellow
                $refs | ForEach-Object {
                    Write-Host "  - $_" -ForegroundColor Gray
                }
            } else {
                Write-Host "No hardcoded path references found." -ForegroundColor Green
            }
        }

        return $result
    }
}

function Should-ExcludePath($fullPath, $root) {
  if (-not (Assert-CommandSafe 'Should-ExcludePath')) { return $false }
  $rel = $fullPath.Substring($root.Length).TrimStart('\\','/')
  if (-not $rel) { return $false }
  if ($rel -match '(?i)^[^\\/]*\\.git(\\|/|$)') { return $true }
  if ($rel -match '(?i)(\\|/)(\.git|node_modules|dist|build|\.turbo|\.vite|\.next|coverage|\.pytest_cache|__pycache__|\.venv|venv|\.pnpm-store|pnpm-store)(\\|/|$)') { return $true }
  if ($rel -match '(?i)\.(log|tmp)$') { return $true }
  return $false
}

function Copy-RepoSnapshot($src, $dest) {
  if (-not (Assert-CommandSafe 'Copy-RepoSnapshot')) { return $false }
  if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
  if (Has-Command robocopy) {
    $xd = @('.git','node_modules','dist','build','.turbo','.vite','.next','coverage','.pytest_cache','__pycache__','.venv','venv','.pnpm-store','pnpm-store')
    $xf = @('*.log','*.tmp')
    $args = @($src, $dest, '/E','/SL','/XJ','/R:2','/W:1','/NFL','/NDL','/NJH','/NJS','/NP')
    foreach ($d in $xd) { $args += '/XD'; $args += $d }
    foreach ($f in $xf) { $args += '/XF'; $args += $f }
    & robocopy @args | Out-Null
    $code = $LASTEXITCODE
    if ($code -ge 8) { return $false }
    return $true
  }

  $items = Get-ChildItem -LiteralPath $src -Recurse -Force
  foreach ($item in $items) {
    $full = $item.FullName
    if (Should-ExcludePath $full $src) { continue }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }

    $rel = $full.Substring($src.Length).TrimStart('\\','/')
    $target = Join-Path $dest $rel

    if ($item.PSIsContainer) {
      if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target | Out-Null }
    } else {
      $parent = Split-Path $target -Parent
      if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
      Copy-Item -LiteralPath $full -Destination $target -Force
    }
  }
  return $true
}

function Invoke-Clone {
  param(
    [string] $GitUrl,
    [string] $CustomName,
    [string] $DestPath,
    [switch] $IsTool,
    [switch] $NoChinvex,
    [string] $StrapRootPath
  )

  Ensure-Command git

  if (-not $GitUrl) { Die "clone requires a git URL" }

  # Load config
  $config = Load-Config $StrapRootPath

  # Parse repo name from URL
  $repoName = if ($CustomName) { $CustomName } else { Parse-GitUrl $GitUrl }

  # Determine scope
  $scope = if ($IsTool) { "tool" } else { "software" }

  # Reserved name check (before any filesystem changes)
  if (Test-ReservedContextName -Name $repoName -Scope $scope) {
    Die "Cannot use reserved name '$repoName' for software repos. Reserved names: tools, archive"
  }

  # Determine destination
  $destPath = if ($DestPath) {
    $DestPath
  } elseif ($IsTool) {
    Join-Path $config.roots.tools $repoName
  } else {
    Join-Path $config.roots.software $repoName
  }

  # Check if destination already exists
  if (Test-Path $destPath) {
    Die "Destination already exists: $destPath"
  }

  # Load registry and check for duplicate name BEFORE cloning
  $registry = Load-Registry $config
  $existing = $registry | Where-Object { $_.name -eq $repoName }
  if ($existing) {
    Die "Entry with name '$repoName' already exists in registry at $($existing.path). Use --name to specify a different name."
  }

  Info "Cloning $GitUrl -> $destPath"

  # Clone the repo (capture output for error reporting)
  $gitOutput = & git clone $GitUrl $destPath 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Git clone failed with output:"
    Write-Host $gitOutput
    Die "Git clone failed"
  }

  Ok "Cloned to $destPath"

  # Resolve to absolute path for registry
  $absolutePath = (Resolve-Path -LiteralPath $destPath).Path

  # Create new entry with ID and chinvex fields
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $entry = [PSCustomObject]@{
    id              = $repoName
    name            = $repoName
    url             = $GitUrl
    path            = $absolutePath
    scope           = $scope
    chinvex_context = $null  # Default, updated below if sync succeeds
    shims           = @()
    stack           = @()
    created_at      = $timestamp
    updated_at      = $timestamp
  }

  # Add to registry
  $newRegistry = @()
  foreach ($item in $registry) {
    $newRegistry += $item
  }
  $newRegistry += $entry
  Save-Registry $config $newRegistry

  # Chinvex sync (after registry write)
  if (Test-ChinvexEnabled -NoChinvex:$NoChinvex -StrapRootPath $StrapRootPath) {
    $contextName = Sync-ChinvexForEntry -Scope $scope -Name $repoName -RepoPath $absolutePath
    if ($contextName) {
      # Update entry with successful chinvex context
      $entry.chinvex_context = $contextName
      # Re-save registry with updated chinvex_context
      $updatedRegistry = @()
      foreach ($item in $newRegistry) {
        if ($item.name -eq $repoName) {
          $item.chinvex_context = $contextName
        }
        $updatedRegistry += $item
      }
      Save-Registry $config $updatedRegistry
    }
  }

  Ok "Added to registry"

  # TODO: Offer to run setup / create shim
  Info "Next steps:"
  Info "  strap setup --repo $repoName"
  Info "  strap shim <name> --- <command> --repo $repoName"
}

function Invoke-List {
  param(
    [switch] $FilterTool,
    [switch] $FilterSoftware,
    [switch] $OutputJson,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Apply filters
  $filtered = $registry
  if ($FilterTool) {
    $filtered = $filtered | Where-Object { $_.scope -eq "tool" }
  }
  if ($FilterSoftware) {
    $filtered = $filtered | Where-Object { $_.scope -eq "software" }
  }

  # Output
  if ($OutputJson) {
    $json = $filtered | ConvertTo-Json -Depth 10
    Write-Host $json
  } else {
    if ($filtered.Count -eq 0) {
      Info "No entries found"
      return
    }

    # Format as table
    Write-Host ""
    Write-Host ("NAME" + (" " * 20) + "SCOPE" + (" " * 5) + "PATH" + (" " * 40) + "URL" + (" " * 40) + "UPDATED")
    Write-Host ("-" * 150)

    foreach ($entry in $filtered) {
      $name = if ($entry.name.Length -gt 20) { $entry.name.Substring(0, 17) + "..." } else { $entry.name.PadRight(24) }
      $scope = $entry.scope.PadRight(10)
      $path = if ($entry.path.Length -gt 40) { "..." + $entry.path.Substring($entry.path.Length - 37) } else { $entry.path.PadRight(44) }
      $url = if ($entry.url.Length -gt 40) { $entry.url.Substring(0, 37) + "..." } else { $entry.url.PadRight(44) }
      $updated = if ($entry.updated_at) { $entry.updated_at } else { "N/A" }

      Write-Host "$name$scope$path$url$updated"
    }
    Write-Host ""
    Write-Host "Total: $($filtered.Count) entries"
  }
}

function Invoke-Open {
  param(
    [string] $NameToOpen,
    [string] $StrapRootPath
  )

  if (-not $NameToOpen) { Die "open requires <name>" }

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Find entry by name
  $entry = $registry | Where-Object { $_.name -eq $NameToOpen }
  if (-not $entry) {
    Die "No entry found with name '$NameToOpen'. Use 'strap list' to see all entries."
  }

  $repoPath = $entry.path
  if (-not $repoPath) {
    Die "Registry entry has no path field"
  }

  if (-not (Test-Path $repoPath)) {
    Warn "Path does not exist: $repoPath"
    Die "Cannot open non-existent path"
  }

  Info "Opening: $repoPath"
  & explorer.exe $repoPath
}

function Invoke-Move {
  param(
    [string] $NameToMove,
    [string] $DestPath,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $ForceOverwrite,
    [switch] $RehomeShims,
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
  if ($newPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase)) {
    $entry.scope = "software"
  } elseif ($newPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)) {
    $entry.scope = "tool"
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

function Invoke-Rename {
  param(
    [string] $NameToRename,
    [string] $NewName,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $MoveFolder,
    [switch] $ForceOverwrite,
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

  $oldPath = $entry.path
  $newPath = $null

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

  # Save registry
  try {
    Save-Registry $config $registry
    Ok "Registry updated"
  } catch {
    Die "Failed to save registry: $_"
  }

  Ok "Rename complete"
}

function Invoke-Uninstall {
  param(
    [string] $NameToRemove,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $PreserveFolder,
    [switch] $PreserveShims,
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
  Write-Host "Entry:  $($entry.name) ($($entry.scope))"
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

function Invoke-Shim {
  param(
    [string] $ShimName,
    [string] $CommandLine,
    [string] $WorkingDir,
    [string] $RegistryEntryName,
    [switch] $ForceOverwrite,
    [switch] $DryRunMode,
    [switch] $NonInteractive,
    [string] $StrapRootPath
  )

  if (-not $ShimName) { Die "shim requires <name>" }
  if (-not $CommandLine) { Die "shim requires a command (use --- <command...> or --cmd `"<command>`")" }

  # Validate shim name (no path separators or reserved chars)
  if ($ShimName -match '[\\/:*?"<>|]') {
    Die "Invalid shim name: '$ShimName' (contains path separators or reserved characters)"
  }

  # Normalize name (trim, replace spaces with -)
  $ShimName = $ShimName.Trim() -replace '\s+', '-'

  # Load config
  $config = Load-Config $StrapRootPath
  $shimsRoot = $config.roots.shims

  # Determine shim path
  $shimPath = Join-Path $shimsRoot "$ShimName.cmd"
  $shimPathResolved = [System.IO.Path]::GetFullPath($shimPath)

  # Safety: ensure shimPath is within shimsRoot
  $shimsRootResolved = [System.IO.Path]::GetFullPath($shimsRoot)
  if (-not $shimPathResolved.StartsWith($shimsRootResolved, [StringComparison]::OrdinalIgnoreCase)) {
    Die "Shim path is not within shims root: $shimPathResolved"
  }

  # Load registry
  $registry = Load-Registry $config

  # Determine registry attachment
  $attachedEntry = $null

  if ($RegistryEntryName) {
    # User specified --repo
    $attachedEntry = $registry | Where-Object { $_.name -eq $RegistryEntryName }
    if (-not $attachedEntry) {
      Die "Registry entry not found: '$RegistryEntryName'. Use 'strap list' to see all entries."
    }
  } else {
    # Try to match current directory to a registry entry
    $currentDir = (Get-Location).Path
    $currentDirResolved = [System.IO.Path]::GetFullPath($currentDir)

    foreach ($entry in $registry) {
      $entryPathResolved = [System.IO.Path]::GetFullPath($entry.path)

      # Check if current dir equals or is inside entry path
      if ($currentDirResolved -eq $entryPathResolved -or
          $currentDirResolved.StartsWith("$entryPathResolved\", [StringComparison]::OrdinalIgnoreCase)) {
        $attachedEntry = $entry
        break
      }
    }

    if (-not $attachedEntry) {
      Die "No registry entry found for current directory. Run from inside a registered repo or use --repo <name>."
    }
  }

  # Preview
  Write-Host ""
  Write-Host "=== SHIM PREVIEW ===" -ForegroundColor Cyan
  Write-Host "Shim name:      $ShimName"
  Write-Host "Shim path:      $shimPathResolved"
  Write-Host "Attached repo:  $($attachedEntry.name) ($($attachedEntry.scope))"
  Write-Host "Repo path:      $($attachedEntry.path)"
  Write-Host "Command:        $CommandLine"
  if ($WorkingDir) {
    Write-Host "Working dir:    $WorkingDir"
  }

  # Check if shim already exists
  if (Test-Path $shimPathResolved) {
    if (-not $ForceOverwrite) {
      Write-Host ""
      Write-Host "Shim already exists at: $shimPathResolved" -ForegroundColor Yellow
      Die "Use --force to overwrite"
    }
    Write-Host ""
    Write-Host "Will overwrite existing shim (--force)" -ForegroundColor Yellow
  }

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

  # Generate shim content
  $shimContent = @"
@echo off
setlocal

"@

  if ($WorkingDir) {
    $shimContent += @"
pushd "$WorkingDir" >nul

"@
  }

  $shimContent += @"
$CommandLine %*
set "EC=%ERRORLEVEL%"

"@

  if ($WorkingDir) {
    $shimContent += @"
popd >nul

"@
  }

  $shimContent += @"
exit /b %EC%
"@

  # Write shim file
  Info "Creating shim..."
  try {
    # Ensure shims directory exists
    if (-not (Test-Path $shimsRoot)) {
      New-Item -ItemType Directory -Path $shimsRoot -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($shimPathResolved, $shimContent, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  created: $shimPathResolved" -ForegroundColor Green
  } catch {
    Write-Host "  ERROR creating shim: $_" -ForegroundColor Red
    exit 2
  }

  # Update registry entry
  Info "Updating registry..."

  # Find the entry in the registry array (we need to work with the original array)
  $entryIndex = -1
  for ($i = 0; $i -lt $registry.Count; $i++) {
    if ($registry[$i].name -eq $attachedEntry.name) {
      $entryIndex = $i
      break
    }
  }

  if ($entryIndex -eq -1) {
    Die "Internal error: could not find entry in registry after validation"
  }

  # Ensure shims array exists
  if (-not $registry[$entryIndex].shims) {
    $registry[$entryIndex] | Add-Member -NotePropertyName "shims" -NotePropertyValue @() -Force
  }

  # Add shim path if not already present
  $shimsList = @($registry[$entryIndex].shims)
  if ($shimPathResolved -notin $shimsList) {
    $shimsList += $shimPathResolved
    $registry[$entryIndex].shims = $shimsList
  }

  # Update timestamp
  $registry[$entryIndex].updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

  # Save registry
  try {
    Save-Registry $config $registry
    Ok "Registry updated"
  } catch {
    Write-Host "ERROR updating registry: $_" -ForegroundColor Red
    exit 3
  }

  Write-Host ""
  Ok "Shim created: $ShimName"
  Info "You can now run '$ShimName' from anywhere"
}

function Invoke-Setup {
  param(
    [string] $RepoNameOrPath,
    [string] $ForceStack,
    [string] $VenvPath,
    [switch] $UseUv,
    [string] $PythonExe,
    [string] $PackageManager,
    [switch] $EnableCorepack,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Determine repo path
  $repoPath = $null
  $registryEntry = $null

  if ($RepoNameOrPath) {
    # Look up in registry
    $registryEntry = $registry | Where-Object { $_.name -eq $RepoNameOrPath -or $_.id -eq $RepoNameOrPath }
    if (-not $registryEntry) {
      Die "Registry entry not found: '$RepoNameOrPath'. Use 'strap list' to see all entries."
    }
    $repoPath = $registryEntry.path
    Info "Setting up registered repo: $RepoNameOrPath"
    Info "Path: $repoPath"
  } else {
    # Use current directory
    $repoPath = Get-Location
    Info "Setting up current directory: $repoPath"

    # Try to find matching registry entry
    $registryEntry = $registry | Where-Object { $_.path -eq $repoPath }
  }

  # Safety validation: ensure path is within managed roots
  $resolvedPath = [System.IO.Path]::GetFullPath($repoPath)
  $softwareRoot = "P:\software"
  $scriptsRoot = "P:\software\_scripts"

  $withinSoftware = $resolvedPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase)
  $withinScripts = $resolvedPath.StartsWith($scriptsRoot, [StringComparison]::OrdinalIgnoreCase)

  if (-not ($withinSoftware -or $withinScripts)) {
    Die "Path is not within managed roots: $resolvedPath"
  }

  # Change to repo directory
  Push-Location $resolvedPath

  try {
    # Stack detection
    $detectedStacks = @()

    if (Test-Path "pyproject.toml") { $detectedStacks += "python" }
    elseif (Test-Path "requirements.txt") { $detectedStacks += "python" }

    if (Test-Path "package.json") { $detectedStacks += "node" }
    if (Test-Path "Cargo.toml") { $detectedStacks += "rust" }
    if (Test-Path "go.mod") { $detectedStacks += "go" }

    $dockerDetected = $false
    if ((Test-Path "Dockerfile") -or (Test-Path "compose.yaml") -or (Test-Path "docker-compose.yml")) {
      $dockerDetected = $true
    }

    # Determine stack to use
    $stack = $null
    if ($ForceStack) {
      $stack = $ForceStack
      Info "Forced stack: $stack"
    } elseif ($detectedStacks.Count -eq 0) {
      if ($dockerDetected) {
        Write-Host ""
        Write-Host "Docker detected; not auto-running containers (manual step)." -ForegroundColor Yellow
        Pop-Location
        exit 0
      } else {
        Die "No recognized stack detected. Use --stack to force selection."
      }
    } elseif ($detectedStacks.Count -gt 1) {
      Write-Host ""
      Write-Host "Multiple stacks detected: $($detectedStacks -join ', ')" -ForegroundColor Yellow
      Write-Host "Use --stack <stack> to select one" -ForegroundColor Yellow
      Pop-Location
      exit 1
    } else {
      $stack = $detectedStacks[0]
      Info "Detected stack: $stack"
    }

    if ($dockerDetected -and -not $ForceStack) {
      Write-Host "  (Docker also detected; not auto-running)" -ForegroundColor Yellow
    }

    # Generate install plan
    $plan = @()

    switch ($stack) {
      "python" {
        # Defaults
        $venvDir = if ($VenvPath) { $VenvPath } else { ".venv" }
        $pythonCmd = if ($PythonExe) { $PythonExe } else { "python" }
        $useUvFlag = if ($PSBoundParameters.ContainsKey('UseUv')) { $UseUv } else { $true }

        $venvPython = Join-Path $venvDir "Scripts\python.exe"

        # Step 1: Create venv if missing
        if (-not (Test-Path $venvPython)) {
          $plan += @{
            Description = "Create Python virtual environment"
            Command = "$pythonCmd -m venv $venvDir"
          }
        }

        # Step 2: Install/upgrade pip and uv
        if ($useUvFlag) {
          $plan += @{
            Description = "Install/upgrade pip and uv in venv"
            Command = "$venvPython -m pip install -U pip uv"
          }
        } else {
          $plan += @{
            Description = "Install/upgrade pip in venv"
            Command = "$venvPython -m pip install -U pip"
          }
        }

        # Step 3: Install dependencies
        if (Test-Path "pyproject.toml") {
          if ($useUvFlag) {
            $plan += @{
              Description = "Install dependencies via uv sync"
              Command = "$venvPython -m uv sync"
            }
          } else {
            $plan += @{
              Description = "Install dependencies via pip (editable)"
              Command = "$venvPython -m pip install -e ."
            }
          }
        } elseif (Test-Path "requirements.txt") {
          if ($useUvFlag) {
            $plan += @{
              Description = "Install dependencies from requirements.txt via uv"
              Command = "$venvPython -m uv pip install -r requirements.txt"
            }
          } else {
            $plan += @{
              Description = "Install dependencies from requirements.txt via pip"
              Command = "$venvPython -m pip install -r requirements.txt"
            }
          }
        }
      }

      "node" {
        # Defaults
        $enableCorepackFlag = if ($PSBoundParameters.ContainsKey('EnableCorepack')) { $EnableCorepack } else { $true }
        $pm = $PackageManager

        # Step 1: Enable corepack if requested
        if ($enableCorepackFlag) {
          $plan += @{
            Description = "Enable corepack"
            Command = "corepack enable"
          }
        }

        # Step 2: Determine package manager and install
        if (-not $pm) {
          if (Test-Path "pnpm-lock.yaml") {
            $pm = "pnpm"
          } elseif (Test-Path "yarn.lock") {
            $pm = "yarn"
          } else {
            $pm = "npm"
          }
        }

        $plan += @{
          Description = "Install Node dependencies via $pm"
          Command = "$pm install"
        }
      }

      "rust" {
        $plan += @{
          Description = "Build Rust project"
          Command = "cargo build"
        }
      }

      "go" {
        $plan += @{
          Description = "Download Go modules"
          Command = "go mod download"
        }
      }

      default {
        Die "Unsupported stack: $stack"
      }
    }

    # Print plan preview
    Write-Host ""
    Write-Host "=== SETUP PLAN ===" -ForegroundColor Cyan
    Write-Host "Repo path:  $resolvedPath"
    Write-Host "Stack:      $stack"
    Write-Host ""
    Write-Host "Commands to execute:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $plan.Count; $i++) {
      Write-Host "  $($i + 1). $($plan[$i].Description)" -ForegroundColor Yellow
      Write-Host "     $($plan[$i].Command)" -ForegroundColor Gray
    }
    Write-Host ""

    if ($DryRunMode) {
      Write-Host "DRY RUN - no changes will be made" -ForegroundColor Yellow
      Pop-Location
      exit 0
    }

    # Confirmation
    if (-not $NonInteractive) {
      $response = Read-Host "Proceed with setup? (y/n)"
      if ($response -ne "y") {
        Info "Aborted by user"
        Pop-Location
        exit 1
      }
    }

    # Execute plan
    Write-Host "=== EXECUTING ===" -ForegroundColor Cyan
    foreach ($step in $plan) {
      Info $step.Description
      Write-Host "  > $($step.Command)" -ForegroundColor Gray

      # Execute command
      $output = Invoke-Expression $step.Command 2>&1
      if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: Command failed with exit code $LASTEXITCODE" -ForegroundColor Red
        Write-Host $output
        Pop-Location
        exit 2
      }
    }

    Write-Host ""
    Ok "Setup completed successfully"

    # Update registry if entry exists
    if ($registryEntry) {
      Info "Updating registry metadata..."

      # Find entry index
      $entryIndex = -1
      for ($i = 0; $i -lt $registry.Count; $i++) {
        if ($registry[$i].id -eq $registryEntry.id) {
          $entryIndex = $i
          break
        }
      }

      if ($entryIndex -ne -1) {
        $currentEntry = $registry[$entryIndex]

        # Update timestamp
        $currentEntry.updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Add/update setup metadata
        if ($currentEntry.PSObject.Properties['stack_detected']) {
          $currentEntry.stack_detected = $stack
        } else {
          $currentEntry | Add-Member -NotePropertyName 'stack_detected' -NotePropertyValue $stack -Force
        }

        if ($currentEntry.PSObject.Properties['setup_last_run_at']) {
          $currentEntry.setup_last_run_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        } else {
          $currentEntry | Add-Member -NotePropertyName 'setup_last_run_at' -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")) -Force
        }

        if ($currentEntry.PSObject.Properties['setup_status']) {
          $currentEntry.setup_status = "success"
        } else {
          $currentEntry | Add-Member -NotePropertyName 'setup_status' -NotePropertyValue "success" -Force
        }

        # Save registry
        try {
          Save-Registry $config $registry
          Write-Host "  registry updated" -ForegroundColor Green
        } catch {
          Write-Host "  ERROR updating registry: $_" -ForegroundColor Red
          Pop-Location
          exit 3
        }
      }
    }

    Pop-Location
    exit 0

  } catch {
    Write-Host ""
    Write-Host "ERROR: $_" -ForegroundColor Red
    Pop-Location
    exit 2
  }
}

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

function Invoke-Templatize {
  param(
    [string] $TemplateName,
    [string] $SourcePath,
    [string] $RootPath,
    [switch] $ForceTemplate,
    [switch] $AllowDirtyWorktree,
    [string] $MessageText,
    [switch] $DoPush
  )

  Ensure-Command git

  if (-not $TemplateName) { Die "templatize requires <templateName>" }

  $sourceBase = if ($SourcePath) { $SourcePath } else { (Get-Location).Path }
  $srcRoot = Resolve-GitRoot $sourceBase
  if (-not $srcRoot) { Die "Source path is not a git repo: $sourceBase" }

  $strapRoot = if ($RootPath) { $RootPath } else { $PSScriptRoot }
  if (-not (Test-Path $strapRoot)) { Die "strap root not found: $strapRoot" }

  $dirty = & git -C $strapRoot status --porcelain
  if ($dirty -and -not $AllowDirtyWorktree) {
    Die "strap repo is dirty; commit/stash or use --allow-dirty"
  }

  $dest = Join-Path $strapRoot (Join-Path "templates" $TemplateName)
  if (Test-Path $dest) {
    if (-not $ForceTemplate) { Die "Template already exists: $dest (use --force to overwrite)" }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $dest
  }

  Info "Templatizing from $srcRoot -> $dest"
  $ok = Copy-RepoSnapshot $srcRoot $dest
  if (-not $ok) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $dest
    Die "Copy failed"
  }

  $rel = (Resolve-Path -LiteralPath $dest).Path.Substring($strapRoot.Length + 1)
  & git -C $strapRoot add -- $rel | Out-Null

  & git -C $strapRoot diff --staged --quiet
  if ($LASTEXITCODE -eq 0) {
    Warn "No changes to commit for $rel"
    return
  }

  $srcName = Split-Path $srcRoot -Leaf
  $msg = if ($MessageText) { $MessageText } else { "templates: templatize $TemplateName from $srcName" }
  & git -C $strapRoot commit -m $msg | Out-Null
  Ok "templatize commit created"

  if ($DoPush) {
    & git -C $strapRoot push | Out-Null
    Ok "pushed"
  }
}

function Invoke-Doctor {
  param(
    [string] $StrapRootPath,
    [switch] $OutputJson
  )

  # Load config
  $config = Load-Config $StrapRootPath

  $report = [PSCustomObject]@{
    config = @{
      software_root = $config.roots.software
      tools_root = $config.roots.tools
      shims_root = $config.roots.shims
      registry_path = $config.registry
      strap_root = $StrapRootPath
    }
    path_check = @{
      shims_in_path = $false
      path_entry = $null
    }
    tools = @()
    registry_check = @{
      exists = $false
      valid_json = $false
      issues = @()
    }
    status = "OK"
  }

  # Check PATH for shims
  $processPath = $env:PATH -split ';'
  $shimsRoot = $config.roots.shims
  $foundInPath = $processPath | Where-Object { $_ -like "*$shimsRoot*" } | Select-Object -First 1
  $report.path_check.shims_in_path = ($null -ne $foundInPath)
  $report.path_check.path_entry = if ($foundInPath) { $foundInPath } else { "missing" }

  # Check tool availability
  function Get-ToolInfo {
    param([string]$Command, [string]$VersionArg = "--version")

    $result = @{
      name = $Command
      found = $false
      path = $null
      version = $null
    }

    try {
      $cmd = Get-Command $Command -ErrorAction SilentlyContinue
      if ($cmd) {
        $result.found = $true
        $result.path = $cmd.Source

        # Try to get version
        $versionOutput = & $Command $VersionArg 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
          $result.version = ($versionOutput -split "`n")[0].Trim()
        }
      }
    } catch {}

    return [PSCustomObject]$result
  }

  $report.tools += Get-ToolInfo "git"
  $report.tools += Get-ToolInfo "pwsh" "-v"
  $report.tools += Get-ToolInfo "python"

  # Check uv (try both standalone and python -m)
  $uvInfo = Get-ToolInfo "uv"
  if (-not $uvInfo.found) {
    try {
      $versionOutput = & python -m uv --version 2>&1 | Out-String
      if ($LASTEXITCODE -eq 0) {
        $uvInfo.found = $true
        $uvInfo.path = "python -m uv"
        $uvInfo.version = ($versionOutput -split "`n")[0].Trim()
      }
    } catch {}
  }
  $report.tools += $uvInfo

  $report.tools += Get-ToolInfo "node"
  $report.tools += Get-ToolInfo "npm"
  $report.tools += Get-ToolInfo "pnpm"
  $report.tools += Get-ToolInfo "yarn"
  $report.tools += Get-ToolInfo "corepack"
  $report.tools += Get-ToolInfo "go" "version"
  $report.tools += Get-ToolInfo "cargo"

  # Check registry integrity
  $registryPath = $config.registry
  $report.registry_check.exists = (Test-Path $registryPath)

  if ($report.registry_check.exists) {
    try {
      # Check registry version
      $registryVersion = Get-RegistryVersion $registryPath
      $report.registry_check['version'] = $registryVersion

      if ($registryVersion -ne $null -and $registryVersion -lt $script:LATEST_REGISTRY_VERSION) {
        $report.registry_check.issues += "Registry version $registryVersion is outdated (latest: $script:LATEST_REGISTRY_VERSION). Run 'strap migrate' to upgrade."
        $report.status = "WARN"
      }

      $content = Get-Content -LiteralPath $registryPath -Raw
      if ($content.Trim() -eq "[]") {
        $registry = @()
      } else {
        $registry = $content | ConvertFrom-Json
        # Handle both legacy (array) and new (object) formats
        if ($registry -is [array]) {
          # Legacy format
          $entries = $registry
        } elseif ($registry.PSObject.Properties['entries']) {
          # New format
          $entries = $registry.entries
        } else {
          # Unknown format
          $entries = @($registry)
        }
        $registry = $entries
      }
      $report.registry_check.valid_json = $true

      if ($registry.Count -gt 0) {
        # Check each entry
        $seenNames = @{}
        foreach ($entry in $registry) {
          # Check required fields
          $required = @('name', 'scope', 'path', 'updated_at', 'shims')
          foreach ($field in $required) {
            if (-not $entry.PSObject.Properties[$field]) {
              $report.registry_check.issues += "Entry missing required field '$field': $($entry.name)"
            }
          }

          # Check for duplicate names
          if ($seenNames.ContainsKey($entry.name)) {
            $report.registry_check.issues += "Duplicate name: $($entry.name)"
            $report.status = "WARN"
          }
          $seenNames[$entry.name] = $true

          # Check if path exists
          if ($entry.path -and -not (Test-Path $entry.path)) {
            $report.registry_check.issues += "Path does not exist: $($entry.name) -> $($entry.path)"
            $report.status = "WARN"
          }

          # Check if shims exist
          if ($entry.shims) {
            foreach ($shim in $entry.shims) {
              if (-not (Test-Path $shim)) {
                $report.registry_check.issues += "Shim does not exist: $($entry.name) -> $shim"
                $report.status = "WARN"
              }
            }
          }
        }
      }
    } catch {
      $report.registry_check.valid_json = $false
      $report.registry_check.issues += "Invalid JSON: $_"
      $report.status = "FAIL"
    }
  }

  # Adjust status based on warnings
  $missingCriticalTools = $report.tools | Where-Object { $_.name -in @('git', 'pwsh') -and -not $_.found }
  if ($missingCriticalTools) {
    $report.status = "WARN"
  }

  if (-not $report.path_check.shims_in_path) {
    $report.status = "WARN"
  }

  # Output
  if ($OutputJson) {
    $report | ConvertTo-Json -Depth 10
  } else {
    Write-Host ""
    Write-Host "=== STRAP DOCTOR ===" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Config paths:" -ForegroundColor Yellow
    Write-Host "  software_root:  $($report.config.software_root)"
    Write-Host "  tools_root:     $($report.config.tools_root)"
    Write-Host "  shims_root:     $($report.config.shims_root)"
    Write-Host "  registry_path:  $($report.config.registry_path)"
    Write-Host "  strap_root:     $($report.config.strap_root)"
    Write-Host ""

    Write-Host "PATH check:" -ForegroundColor Yellow
    if ($report.path_check.shims_in_path) {
      Write-Host "  ✓ shims_root in PATH: $($report.path_check.path_entry)" -ForegroundColor Green
    } else {
      Write-Host "  ✗ shims_root NOT in PATH" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "Tool availability:" -ForegroundColor Yellow
    foreach ($tool in $report.tools) {
      if ($tool.found) {
        Write-Host "  ✓ $($tool.name.PadRight(10)) $($tool.version)" -ForegroundColor Green
      } else {
        Write-Host "  ✗ $($tool.name.PadRight(10)) not found" -ForegroundColor Red
      }
    }
    Write-Host ""

    Write-Host "Registry integrity:" -ForegroundColor Yellow
    if (-not $report.registry_check.exists) {
      Write-Host "  Registry: missing (ok if new)" -ForegroundColor Yellow
    } elseif (-not $report.registry_check.valid_json) {
      Write-Host "  ✗ Invalid JSON" -ForegroundColor Red
      foreach ($issue in $report.registry_check.issues) {
        Write-Host "    - $issue" -ForegroundColor Red
      }
    } else {
      Write-Host "  ✓ Valid JSON" -ForegroundColor Green
      if ($report.registry_check.ContainsKey('version') -and $report.registry_check.version -ne $null) {
        $versionText = "Version $($report.registry_check.version)"
        if ($report.registry_check.version -lt $script:LATEST_REGISTRY_VERSION) {
          Write-Host "  ⚠ $versionText (outdated, latest: $script:LATEST_REGISTRY_VERSION)" -ForegroundColor Yellow
        } else {
          Write-Host "  ✓ $versionText (current)" -ForegroundColor Green
        }
      }
      if ($report.registry_check.issues.Count -eq 0) {
        Write-Host "  ✓ No issues found" -ForegroundColor Green
      } else {
        Write-Host "  Issues:" -ForegroundColor Yellow
        foreach ($issue in $report.registry_check.issues) {
          Write-Host "    - $issue" -ForegroundColor Yellow
        }
      }
    }
    Write-Host ""

    $statusColor = switch ($report.status) {
      "OK" { "Green" }
      "WARN" { "Yellow" }
      "FAIL" { "Red" }
    }
    Write-Host "Status: $($report.status)" -ForegroundColor $statusColor
  }

  # Exit code
  if ($report.status -eq "FAIL") {
    exit 1
  } else {
    exit 0
  }
}

function Invoke-Adopt {
  param(
    [string] $TargetPath,
    [string] $CustomName,
    [switch] $ForceTool,
    [switch] $ForceSoftware,
    [switch] $NoChinvex,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Determine target path
  if (-not $TargetPath) {
    $TargetPath = Get-Location
  }

  # Resolve to absolute path
  $resolvedPath = [System.IO.Path]::GetFullPath($TargetPath)

  # Validate within managed roots
  $softwareRoot = $config.roots.software
  $toolsRoot = $config.roots.tools

  $withinSoftware = $resolvedPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase)
  $withinTools = $resolvedPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

  if (-not ($withinSoftware -or $withinTools)) {
    Die "Path is not within managed roots: $resolvedPath"
  }

  # Validate it's a git repo
  $gitDir = Join-Path $resolvedPath ".git"
  if (-not (Test-Path $gitDir)) {
    # Try git command
    try {
      & git -C $resolvedPath rev-parse --is-inside-work-tree 2>&1 | Out-Null
      if ($LASTEXITCODE -ne 0) {
        Die "Not a git repository: $resolvedPath"
      }
    } catch {
      Die "Not a git repository: $resolvedPath"
    }
  }

  # Determine name
  $name = if ($CustomName) { $CustomName } else { Split-Path $resolvedPath -Leaf }

  # Check for duplicates
  $existing = $registry | Where-Object { $_.name -eq $name }
  if ($existing) {
    Die "Entry with name '$name' already exists in registry at $($existing.path)"
  }

  # Determine scope (explicit flag > auto-detect from path)
  $scope = if ($ForceTool) {
    "tool"
  } elseif ($ForceSoftware) {
    "software"
  } else {
    # Auto-detect from path
    $detectedScope = Detect-RepoScope -Path $resolvedPath -StrapRootPath $StrapRootPath
    if ($null -eq $detectedScope) {
      Warn "Path is outside managed roots. Defaulting to 'software'. Use --tool or --software to override."
      "software"
    } else {
      Info "Auto-detected scope: $detectedScope (from path)"
      $detectedScope
    }
  }

  # Reserved name check (before any filesystem changes)
  if (Test-ReservedContextName -Name $name -Scope $scope) {
    Die "Cannot use reserved name '$name' for software repos. Reserved names: tools, archive"
  }

  # Extract git metadata (best-effort)
  $url = $null
  $lastHead = $null
  $defaultBranch = $null

  try {
    $remoteUrl = & git -C $resolvedPath remote get-url origin 2>&1
    if ($LASTEXITCODE -eq 0) {
      $url = $remoteUrl.Trim()
    }
  } catch {}

  try {
    $head = & git -C $resolvedPath rev-parse HEAD 2>&1
    if ($LASTEXITCODE -eq 0) {
      $lastHead = $head.Trim()
    }
  } catch {}

  try {
    $branch = & git -C $resolvedPath symbolic-ref --short refs/remotes/origin/HEAD 2>&1
    if ($LASTEXITCODE -eq 0) {
      $defaultBranch = $branch.Trim() -replace '^origin/', ''
    }
  } catch {}

  # Detect stack (best-effort)
  $stackDetected = $null
  Push-Location $resolvedPath
  try {
    if (Test-Path "pyproject.toml") { $stackDetected = "python" }
    elseif (Test-Path "requirements.txt") { $stackDetected = "python" }
    elseif (Test-Path "package.json") { $stackDetected = "node" }
    elseif (Test-Path "Cargo.toml") { $stackDetected = "rust" }
    elseif (Test-Path "go.mod") { $stackDetected = "go" }
  } finally {
    Pop-Location
  }

  # Dry run: show what would happen
  if ($DryRunMode) {
    Info "[DRY RUN] Would adopt: $resolvedPath"
    Info "[DRY RUN] Name: $name"
    Info "[DRY RUN] Scope: $scope"
    Info "[DRY RUN] URL: $url"
    Info "[DRY RUN] Stack: $stackDetected"
    return
  }

  # Create entry
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $entry = [PSCustomObject]@{
    id              = $name
    name            = $name
    url             = $url
    path            = $resolvedPath
    scope           = $scope
    chinvex_context = $null  # Default, updated below if sync succeeds
    shims           = @()
    stack           = if ($stackDetected) { @($stackDetected) } else { @() }
    last_head       = $lastHead
    default_branch  = $defaultBranch
    created_at      = $timestamp
    updated_at      = $timestamp
  }

  # Add to registry
  $newRegistry = @()
  foreach ($item in $registry) {
    $newRegistry += $item
  }
  $newRegistry += $entry
  Save-Registry $config $newRegistry

  # Chinvex sync (after registry write)
  if (Test-ChinvexEnabled -NoChinvex:$NoChinvex -StrapRootPath $StrapRootPath) {
    $contextName = Sync-ChinvexForEntry -Scope $scope -Name $name -RepoPath $resolvedPath
    if ($contextName) {
      # Update entry with successful chinvex context
      $entry.chinvex_context = $contextName
      # Re-save registry with updated chinvex_context
      $updatedRegistry = @()
      foreach ($item in $newRegistry) {
        if ($item.name -eq $name) {
          $item.chinvex_context = $contextName
        }
        $updatedRegistry += $item
      }
      Save-Registry $config $updatedRegistry
    }
  }

  Ok "Adopted: $name ($resolvedPath)"
  Info "Scope: $scope"
  if ($url) { Info "Remote: $url" }
  if ($stackDetected) { Info "Stack: $stackDetected" }
}

function Invoke-Migrate {
  param(
    [int] $TargetVersion = $script:LATEST_REGISTRY_VERSION,
    [switch] $PlanOnly,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $CreateBackup,
    [switch] $OutputJson,
    [string] $StrapRootPath
  )
  if (-not (Assert-CommandSafe 'Invoke-Migrate')) { return }

  # Load config
  $config = Load-Config $StrapRootPath
  $registryPath = $config.registry

  # Check if registry exists
  if (-not (Test-Path $registryPath)) {
    if ($OutputJson) {
      $report = [PSCustomObject]@{
        status = "nothing_to_do"
        message = "No registry found"
      }
      $report | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Info "No registry found; nothing to migrate"
    }
    exit 0
  }

  # Read and parse registry
  $content = Get-Content -LiteralPath $registryPath -Raw
  try {
    if ($content.Trim() -eq "[]") {
      $json = @()
      $currentVersion = 0
    } else {
      $json = $content | ConvertFrom-Json

      # Detect version
      if ($json -is [System.Array]) {
        $currentVersion = 0
      } elseif ($json.PSObject.Properties['registry_version']) {
        $currentVersion = $json.registry_version
      } else {
        $currentVersion = 0
      }
    }
  } catch {
    if ($OutputJson) {
      $report = [PSCustomObject]@{
        status = "error"
        message = "Invalid JSON in registry"
        error = $_.Exception.Message
      }
      $report | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Write-Host ""
      Write-Host "ERROR: Invalid JSON in registry: $_" -ForegroundColor Red
    }
    exit 1
  }

  # Check if target version is too new
  if ($TargetVersion -gt $script:LATEST_REGISTRY_VERSION) {
    $msg = "Target version $TargetVersion is not supported (latest: $script:LATEST_REGISTRY_VERSION)"
    if ($OutputJson) {
      $report = [PSCustomObject]@{
        status = "error"
        message = $msg
      }
      $report | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Write-Host ""
      Write-Host "ERROR: $msg" -ForegroundColor Red
    }
    exit 1
  }

  # Check if already at target version
  if ($currentVersion -eq $TargetVersion) {
    if ($OutputJson) {
      $report = [PSCustomObject]@{
        status = "nothing_to_do"
        current_version = $currentVersion
        target_version = $TargetVersion
        message = "Registry already at version $TargetVersion"
      }
      $report | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Info "Registry already at version $TargetVersion; nothing to do"
    }
    exit 0
  }

  # Prepare registry data structure
  if ($json -is [System.Array]) {
    $registryData = [PSCustomObject]@{
      registry_version = 0
      updated_at = $null
      entries = $json
    }
  } else {
    $registryData = $json
    if (-not $registryData.PSObject.Properties['entries']) {
      # Legacy object format: treat as single entry wrapped in array
      $registryData = [PSCustomObject]@{
        registry_version = 0
        updated_at = $null
        entries = @($json)
      }
    }
  }

  # Plan migrations
  $migrationsToApply = @()
  for ($v = $currentVersion; $v -lt $TargetVersion; $v++) {
    $migrationsToApply += "$v->$($v + 1)"
  }

  # Initialize report
  $migrationReport = [PSCustomObject]@{
    current_version = $currentVersion
    target_version = $TargetVersion
    migrations_planned = $migrationsToApply
    entries_scanned = $registryData.entries.Count
    entries_modified = 0
    backfilled = @{}
    duplicates = @()
    warnings = @()
    backup_path = $null
  }

  # Display plan
  if (-not $OutputJson) {
    Write-Host ""
    Write-Host "=== MIGRATION PLAN ===" -ForegroundColor Cyan
    Write-Host "Current version: $currentVersion"
    Write-Host "Target version:  $TargetVersion"
    Write-Host "Migrations:      $($migrationsToApply -join ', ')"
    Write-Host "Entries:         $($registryData.entries.Count)"
    Write-Host ""
  }

  if ($PlanOnly) {
    if ($OutputJson) {
      $migrationReport | Add-Member -NotePropertyName 'status' -NotePropertyValue 'plan_only' -Force
      $migrationReport | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Info "Plan only; no changes will be made"
    }
    exit 0
  }

  # Apply migrations
  try {
    $reportRef = [ref]$migrationReport

    for ($v = $currentVersion; $v -lt $TargetVersion; $v++) {
      $nextVersion = $v + 1

      if ($nextVersion -eq 1) {
        $registryData = Invoke-Migration-0-to-1 -RegistryData $registryData -Report $reportRef
      } else {
        throw "Migration $v->$nextVersion not implemented"
      }
    }
  } catch {
    if ($OutputJson) {
      $migrationReport | Add-Member -NotePropertyName 'status' -NotePropertyValue 'error' -Force
      $migrationReport | Add-Member -NotePropertyName 'error' -NotePropertyValue $_.Exception.Message -Force
      $migrationReport | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Write-Host ""
      Write-Host "ERROR during migration: $_" -ForegroundColor Red
    }
    exit 1
  }

  # Validate schema
  $validationIssues = Validate-RegistrySchema -Entries $registryData.entries
  if ($validationIssues.Count -gt 0) {
    if ($OutputJson) {
      $migrationReport | Add-Member -NotePropertyName 'status' -NotePropertyValue 'validation_failed' -Force
      $migrationReport | Add-Member -NotePropertyName 'validation_errors' -NotePropertyValue $validationIssues -Force
      $migrationReport | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Write-Host ""
      Write-Host "ERROR: Schema validation failed:" -ForegroundColor Red
      foreach ($issue in $validationIssues) {
        Write-Host "  - $issue" -ForegroundColor Red
      }
    }
    exit 1
  }

  # Display migration summary
  if (-not $OutputJson) {
    Write-Host "=== MIGRATION SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Entries scanned:  $($migrationReport.entries_scanned)"
    Write-Host "Entries modified: $($migrationReport.entries_modified)"
    if ($migrationReport.backfilled.Count -gt 0) {
      Write-Host "Backfilled fields:"
      foreach ($field in $migrationReport.backfilled.Keys) {
        Write-Host "  - ${field}: $($migrationReport.backfilled[$field])"
      }
    }
    Write-Host ""
  }

  if ($DryRunMode) {
    if ($OutputJson) {
      $migrationReport | Add-Member -NotePropertyName 'status' -NotePropertyValue 'dry_run' -Force
      $migrationReport | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Write-Host "DRY RUN - no changes will be made" -ForegroundColor Yellow
    }
    exit 0
  }

  # Confirmation
  if (-not $NonInteractive) {
    $response = Read-Host "Apply migrations now? (y/n)"
    if ($response -ne "y") {
      Info "Aborted by user"
      exit 1
    }
  }

  # Create backup if requested
  if ($CreateBackup) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$registryPath.bak-$timestamp"
    try {
      Copy-Item -LiteralPath $registryPath -Destination $backupPath -Force
      $migrationReport.backup_path = $backupPath
      if (-not $OutputJson) {
        Info "Backup created: $backupPath"
      }
    } catch {
      if ($OutputJson) {
        $migrationReport | Add-Member -NotePropertyName 'status' -NotePropertyValue 'error' -Force
        $migrationReport | Add-Member -NotePropertyName 'error' -NotePropertyValue "Backup failed: $_" -Force
        $migrationReport | ConvertTo-Json -Depth 10 | Write-Host
      } else {
        Write-Host ""
        Write-Host "ERROR creating backup: $_" -ForegroundColor Red
      }
      exit 3
    }
  }

  # Write migrated registry
  try {
    $tmpPath = "$registryPath.tmp"
    $json = $registryData | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($tmpPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmpPath -Destination $registryPath -Force

    if ($OutputJson) {
      $migrationReport | Add-Member -NotePropertyName 'status' -NotePropertyValue 'success' -Force
      $migrationReport | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Write-Host ""
      Ok "Registry migrated to version $TargetVersion"
      if ($CreateBackup) {
        Info "Backup: $backupPath"
      }
    }
  } catch {
    if ($OutputJson) {
      $migrationReport | Add-Member -NotePropertyName 'status' -NotePropertyValue 'error' -Force
      $migrationReport | Add-Member -NotePropertyName 'error' -NotePropertyValue "Write failed: $_" -Force
      $migrationReport | ConvertTo-Json -Depth 10 | Write-Host
    } else {
      Write-Host ""
      Write-Host "ERROR writing registry: $_" -ForegroundColor Red
    }
    exit 3
  }

  exit 0
}

# ============================================================================
# Consolidate command functions
# ============================================================================

function Test-ConsolidateArgs {
  param(
    [string] $FromPath,
    [string] $ToPath,
    [string] $TrustMode
  )
  if (-not (Assert-CommandSafe 'Test-ConsolidateArgs')) { return }

  if (-not $FromPath) {
    Die "--from is required for consolidate command"
  }

  if ($TrustMode -ne "registry-first") {
    Die "strap consolidate is registry-first only; manual registry repair required for disk-discovery recovery"
  }

  if (-not (Test-Path -LiteralPath $FromPath)) {
    Die "--from directory does not exist: $FromPath"
  }
}

function Test-ConsolidateRegistryDisk {
  param(
    [array] $RegisteredMoves,
    [array] $DiscoveredCandidates
  )
  if (-not (Assert-CommandSafe 'Test-ConsolidateRegistryDisk')) { return @{ warnings = @() } }

  $warnings = @()

  # Check registry paths exist (no drift)
  foreach ($move in $RegisteredMoves) {
    if (-not (Test-Path -LiteralPath $move.registryPath)) {
      throw "Registry path drift detected for '$($move.name)'. Fix registry.json manually or re-adopt the repo."
    }

    # Check destination doesn't already exist
    if (Test-Path -LiteralPath $move.destinationPath) {
      throw "Conflict: destination already exists for '$($move.name)': $($move.destinationPath). Resolve manually before consolidate."
    }
  }

  # Check for name collisions
  foreach ($candidate in $DiscoveredCandidates) {
    $matching = $RegisteredMoves | Where-Object { $_.name.ToLowerInvariant() -eq $candidate.name.ToLowerInvariant() }
    if ($matching) {
      $normalizedRegistry = Normalize-Path $matching.registryPath
      $normalizedCandidate = Normalize-Path $candidate.sourcePath

      if ($normalizedRegistry -ne $normalizedCandidate) {
        $warnings += "Name collision: discovered repo '$($candidate.name)' differs from registered path. Treating as separate repo; rename before adopt to avoid confusion."
      }
    }
  }

  return @{ warnings = $warnings }
}

function Test-ConsolidateEdgeCaseGuards {
  param(
    [array] $MovePlans,
    [string] $LockFilePath,
    [switch] $NonInteractive
  )
  if (-not (Assert-CommandSafe 'Test-ConsolidateEdgeCaseGuards')) { return }

  # Check for running process locks
  if ($LockFilePath -and (Test-Path -LiteralPath $LockFilePath)) {
    try {
      $lockData = Get-Content -LiteralPath $LockFilePath -Raw | ConvertFrom-Json
      $running = Test-ProcessRunning -ProcessId $lockData.pid
      if ($running) {
        throw "Another consolidation in progress (PID $($lockData.pid))"
      }
      # Remove stale lock
      Remove-Item -LiteralPath $LockFilePath -Force -ErrorAction SilentlyContinue
    } catch {
      # If lock file is corrupted, remove it
      Remove-Item -LiteralPath $LockFilePath -Force -ErrorAction SilentlyContinue
    }
  }

  # Check for destination path collisions
  $destinationPaths = $MovePlans | ForEach-Object { $_.toPath }
  $collision = Find-DuplicatePaths -Paths $destinationPaths
  if ($collision) {
    throw "Destination path collision detected: $collision"
  }

  # Check for adoption ID collisions
  $proposedIds = $MovePlans | ForEach-Object { $_.name }
  $seenIds = @{}
  $resolved = @()

  foreach ($plan in $MovePlans) {
    $key = $plan.name.ToLowerInvariant()
    if ($seenIds.ContainsKey($key)) {
      if ($NonInteractive) {
        throw "Adoption ID collision detected for '$($plan.name)' in --yes mode."
      }
      # In interactive mode, would prompt for resolution
      # For now, just error out
      throw "Adoption ID collision detected for '$($plan.name)'. Use unique names."
    }
    $seenIds[$key] = $true
    $resolved += $plan
  }

  return @{ ok = $true; resolved = $resolved }
}

function Invoke-ConsolidateExecuteMove {
  param(
    [string] $Name,
    [string] $FromPath,
    [string] $ToPath
  )
  if (-not (Assert-CommandSafe 'Invoke-ConsolidateExecuteMove')) { return }

  # Create parent directory if needed
  $parentDir = Split-Path -Parent $ToPath
  if (-not (Test-Path -LiteralPath $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
  }

  # Check if destination already exists
  if (Test-Path -LiteralPath $ToPath) {
    throw "Destination already exists: $ToPath"
  }

  # Execute move
  try {
    Move-Item -LiteralPath $FromPath -Destination $ToPath -Force
  } catch {
    throw "Failed to move $Name from $FromPath to $ToPath : $_"
  }

  # Verify git integrity
  Push-Location $ToPath
  try {
    $gitStatus = git status 2>&1
    if ($LASTEXITCODE -ne 0) {
      throw "Git integrity check failed after move"
    }
  } finally {
    Pop-Location
  }
}

function Invoke-ConsolidateRollbackMove {
  param(
    [string] $Name,
    [string] $FromPath,
    [string] $ToPath
  )
  if (-not (Assert-CommandSafe 'Invoke-ConsolidateRollbackMove')) { return }

  if (Test-Path -LiteralPath $ToPath) {
    try {
      Move-Item -LiteralPath $ToPath -Destination $FromPath -Force
      Write-Host "  Rolled back: $Name" -ForegroundColor Yellow
    } catch {
      Warn "Failed to rollback $Name : $_"
    }
  }
}

function Invoke-ConsolidateTransaction {
  param(
    [array] $Plans,
    [object] $Config,
    [array] $Registry,
    [string] $StrapRootPath
  )
  if (-not (Assert-CommandSafe 'Invoke-ConsolidateTransaction')) { return @{ success = $false; completed = @(); registry = $Registry } }

  $completed = @()
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $rollbackLogPath = Join-Path $StrapRootPath "build\consolidate-rollback-$timestamp.json"

  # Ensure build directory exists
  $buildDir = Split-Path -Parent $rollbackLogPath
  if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
  }

  # Write rollback log start
  @{
    timestamp = $timestamp
    status = "in_progress"
    plans = $Plans
  } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $rollbackLogPath

  # Execute moves
  try {
    foreach ($plan in $Plans) {
      Info "Moving $($plan.name) to $($plan.scope) scope..."
      Invoke-ConsolidateExecuteMove -Name $plan.name -FromPath $plan.fromPath -ToPath $plan.toPath
      $completed += $plan
    }
  } catch {
    # Rollback in reverse order
    Write-Host "`n⚠️  Move failed, rolling back..." -ForegroundColor Red
    for ($i = $completed.Count - 1; $i -ge 0; $i--) {
      $plan = $completed[$i]
      Invoke-ConsolidateRollbackMove -Name $plan.name -FromPath $plan.fromPath -ToPath $plan.toPath
    }

    # Write rollback log result
    @{
      timestamp = $timestamp
      status = "failed"
      completed = $completed | ForEach-Object { $_.name }
      error = $_.Exception.Message
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $rollbackLogPath

    throw
  }

  # Backup registry before updates
  $registryPath = $Config.registry
  $registryBackup = "$registryPath.backup-$timestamp"
  Copy-Item -LiteralPath $registryPath -Destination $registryBackup -Force

  # Update registry with new paths
  $registryData = if (Test-Path $registryPath) {
    Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
  } else {
    @{ registry_version = 1; entries = @() }
  }

  foreach ($plan in $completed) {
    $entry = $registryData.entries | Where-Object { $_.name -eq $plan.name } | Select-Object -First 1
    if ($entry) {
      $entry.path = $plan.toPath
      $entry.scope = $plan.scope
      $entry.updated_at = (Get-Date).ToUniversalTime().ToString('o')
    } else {
      # Add new entry
      $registryData.entries += @{
        name = $plan.name
        path = $plan.toPath
        scope = $plan.scope
        shims = @()
        updated_at = (Get-Date).ToUniversalTime().ToString('o')
      }
    }
  }

  # Save registry
  try {
    $tmpPath = "$registryPath.tmp"
    $registryData | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmpPath
    Move-Item -LiteralPath $tmpPath -Destination $registryPath -Force
  } catch {
    # Restore registry backup
    Copy-Item -LiteralPath $registryBackup -Destination $registryPath -Force
    throw "Failed to update registry: $_"
  }

  # Update chinvex contexts if chinvex is available
  if (Has-Command "chinvex") {
    try {
      foreach ($plan in $completed) {
        & chinvex context set $plan.name --scope $plan.scope --path $plan.toPath 2>&1 | Out-Null
      }
    } catch {
      # Restore registry backup if chinvex fails
      Copy-Item -LiteralPath $registryBackup -Destination $registryPath -Force
      throw "Failed to update chinvex contexts: $_"
    }
  }

  # Write rollback log result
  @{
    timestamp = $timestamp
    status = "success"
    completed = $completed | ForEach-Object { $_.name }
  } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $rollbackLogPath

  return @{
    moved = $completed | ForEach-Object { $_.name }
    rollbackLogPath = $rollbackLogPath
  }
}

function Invoke-ConsolidateMigrationWorkflow {
  param(
    [string] $FromPath,
    [string] $ToPath,
    [switch] $DryRun,
    [switch] $Yes,
    [switch] $StopPm2,
    [switch] $AckScheduledTasks,
    [switch] $AllowDirty,
    [switch] $AllowAutoArchive,
    [string] $StrapRootPath
  )
  if (-not (Assert-CommandSafe 'Invoke-ConsolidateMigrationWorkflow')) { return @{ executed = $false; manualFixes = @() } }

  Write-Host "`n🔄 Starting consolidation workflow..." -ForegroundColor Cyan
  Write-Host "   From: $FromPath" -ForegroundColor Gray

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Step 1: Snapshot
  Write-Host "`n[1/6] Creating snapshot..." -ForegroundColor Yellow
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $snapshotDir = Join-Path $StrapRootPath "build"
  if (-not (Test-Path $snapshotDir)) {
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
  }
  $snapshotPath = Join-Path $snapshotDir "consolidate-snapshot-$timestamp.json"

  $snapshot = @{
    timestamp = $timestamp
    fromPath = $FromPath
    registryCount = $registry.Count
    dryRun = $DryRun.IsPresent
  }
  $snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $snapshotPath
  Info "Snapshot saved: $snapshotPath"

  # Step 2: Discovery
  Write-Host "`n[2/6] Discovering repositories..." -ForegroundColor Yellow
  $discovered = @()

  if (Test-Path -LiteralPath $FromPath) {
    $subdirs = Get-ChildItem -LiteralPath $FromPath -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $subdirs) {
      $gitDir = Join-Path $dir.FullName ".git"
      if (Test-Path -LiteralPath $gitDir) {
        $repoName = $dir.Name
        Info "Found: $repoName"
        $discovered += @{
          name = $repoName
          sourcePath = $dir.FullName
        }
      }
    }
  }

  if ($discovered.Count -eq 0) {
    Info "No repositories found to consolidate"
    return @{ executed = $false; manualFixes = @() }
  }

  Info "Discovered $($discovered.Count) repositories"

  # Step 3: Determine destinations and build move plans
  Write-Host "`n[3/6] Planning moves..." -ForegroundColor Yellow
  $softwareRoot = $config.roots.software
  $toolsRoot = $config.roots.tools
  $movePlans = @()

  foreach ($repo in $discovered) {
    # Determine scope (software vs tool) - use interactive prompt if not --yes
    $scope = "software"  # default
    if (-not $Yes) {
      $choice = Read-Host "Where should '$($repo.name)' go? (s)oftware / (t)ool [s]"
      if ($choice -eq "t") {
        $scope = "tool"
      }
    }

    $destPath = if ($scope -eq "tool") {
      Join-Path $toolsRoot $repo.name
    } else {
      Join-Path $softwareRoot $repo.name
    }

    # Check for naming collisions
    $existingEntry = $registry | Where-Object { $_.name.ToLowerInvariant() -eq $repo.name.ToLowerInvariant() }
    if ($existingEntry) {
      if (-not $Yes) {
        Write-Host "  Name collision detected: '$($repo.name)' already exists in registry" -ForegroundColor Yellow
        $newName = Read-Host "  Enter new name (or press Enter to skip)"
        if ($newName) {
          $repo.name = $newName
          $destPath = if ($scope -eq "tool") {
            Join-Path $toolsRoot $newName
          } else {
            Join-Path $softwareRoot $newName
          }
        } else {
          Write-Host "  Skipping $($repo.name)" -ForegroundColor Yellow
          continue
        }
      } else {
        Warn "Skipping $($repo.name) - name collision in --yes mode"
        continue
      }
    }

    $movePlans += @{
      name = $repo.name
      fromPath = $repo.sourcePath
      toPath = $destPath
      scope = $scope
    }
  }

  if ($movePlans.Count -eq 0) {
    Info "No repositories to move after collision resolution"
    return @{ executed = $false; manualFixes = @() }
  }

  # Show move plan
  Write-Host "`nMove plan:" -ForegroundColor Cyan
  foreach ($plan in $movePlans) {
    Write-Host "  $($plan.name): $($plan.fromPath) → $($plan.toPath) [$($plan.scope)]" -ForegroundColor Gray
  }

  # Step 4: Audit for external references
  Write-Host "`n[4/6] Auditing external references..." -ForegroundColor Yellow
  $auditWarnings = @()

  # Determine repo paths to check
  $repoPaths = @($FromPath)

  # 1. Check scheduled tasks
  Write-Verbose "Checking scheduled tasks..."
  $scheduledTasks = Get-ScheduledTaskReferences -RepoPaths $repoPaths
  foreach ($task in $scheduledTasks) {
    $auditWarnings += "Scheduled task '$($task.name)' references $($task.path)"
  }

  # 2. Check shims
  Write-Verbose "Checking shims..."
  $shimDir = Join-Path $StrapRootPath "build\shims"
  $shims = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths
  foreach ($shim in $shims) {
    $auditWarnings += "Shim '$($shim.name)' targets $($shim.target)"
  }

  # 3. Check PATH environment variables
  Write-Verbose "Checking PATH entries..."
  $pathRefs = Get-PathReferences -RepoPaths $repoPaths
  foreach ($pathRef in $pathRefs) {
    $auditWarnings += "PATH entry: $($pathRef.path)"
  }

  # 4. Check PowerShell profile
  Write-Verbose "Checking PowerShell profile..."
  $profileRefs = Get-ProfileReferences -RepoPaths $repoPaths
  foreach ($profileRef in $profileRefs) {
    $auditWarnings += "Profile reference: $($profileRef.path)"
  }

  # 5. Check PM2 processes (existing check)
  if (Has-Command "pm2") {
    try {
      $pm2List = & pm2 jlist 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
      foreach ($proc in $pm2List) {
        if ($proc.pm2_env.pm_cwd -and $proc.pm2_env.pm_cwd.StartsWith($FromPath, [StringComparison]::OrdinalIgnoreCase)) {
          $auditWarnings += "PM2 process '$($proc.name)' references $FromPath"
        }
      }
    } catch {
      # PM2 not available or error - skip
    }
  }

  # 6. Build audit index for hardcoded path references
  Write-Verbose "Building audit index..."
  $indexPath = Join-Path $StrapRootPath "build\audit-index.json"
  $registryPath = Join-Path $StrapRootPath "registry-v2.json"

  if (Test-Path $registryPath) {
    try {
      $registryData = Get-Content $registryPath -Raw | ConvertFrom-Json
      $registryUpdatedAt = $registryData.updated_at

      # Convert DateTime to string if needed
      if ($registryUpdatedAt -is [DateTime]) {
        $registryUpdatedAt = $registryUpdatedAt.ToUniversalTime().ToString("o")
      }

      $auditIndex = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
        -RegistryUpdatedAt $registryUpdatedAt -Registry $registryData.entries

      # Check if any repos have hardcoded references to $FromPath
      foreach ($repoPath in $auditIndex.repos.Keys) {
        $refs = $auditIndex.repos[$repoPath].references
        foreach ($ref in $refs) {
          # Parse reference format: filepath:linenum
          if ($ref -match [regex]::Escape($FromPath)) {
            $auditWarnings += "Hardcoded path in $ref"
          }
        }
      }
    } catch {
      Write-Warning "Failed to build audit index: $_"
    }
  }

  # Display warnings and enforce --ack-scheduled-tasks flag
  if ($auditWarnings.Count -gt 0) {
    Warn "External references detected:"
    foreach ($w in $auditWarnings) {
      Write-Host "  - $w" -ForegroundColor Yellow
    }

    if (-not $AckScheduledTasks) {
      Die "External references detected. Re-run with --ack-scheduled-tasks to continue."
    }

    Write-Host "`nProceeding with --ack-scheduled-tasks flag set." -ForegroundColor Yellow
  } else {
    Write-Host "No external references detected." -ForegroundColor Green
  }

  # Step 5: Preflight checks
  Write-Host "`n[5/6] Running preflight checks..." -ForegroundColor Yellow
  $sourceSize = Get-DirectorySize -Path $FromPath
  $sourceSizeMB = [math]::Round($sourceSize / 1MB, 2)
  Info "Source size: $sourceSizeMB MB"

  # Check for dirty worktrees
  if (-not $AllowDirty) {
    foreach ($plan in $movePlans) {
      Push-Location $plan.fromPath
      try {
        $gitStatus = git status --porcelain 2>&1
        if ($gitStatus) {
          if (-not $Yes) {
            $continue = Read-Host "$($plan.name) has uncommitted changes. Continue anyway? (y/n)"
            if ($continue -ne "y") {
              Pop-Location
              Die "Aborted due to dirty worktree"
            }
          } else {
            Warn "$($plan.name) has uncommitted changes but continuing due to --allow-dirty"
          }
        }
      } finally {
        Pop-Location
      }
    }
  }

  if ($DryRun) {
    Write-Host "`n✅ DRY RUN complete - no changes made" -ForegroundColor Green
    Write-Host "   Repos discovered: $($discovered.Count)" -ForegroundColor Gray
    Write-Host "   Repos planned: $($movePlans.Count)" -ForegroundColor Gray
    return @{ executed = $false; manualFixes = @() }
  }

  # Step 6: Execute transaction
  Write-Host "`n[6/6] Executing moves..." -ForegroundColor Yellow

  if (-not $Yes) {
    Write-Host "`n⚠️  This will move $($movePlans.Count) repositories and update the registry." -ForegroundColor Yellow
    $confirm = Read-Host "Continue? (y/n)"
    if ($confirm -ne "y") {
      Die "Aborted by user"
    }
  }

  try {
    $result = Invoke-ConsolidateTransaction -Plans $movePlans -Config $config -Registry $registry -StrapRootPath $StrapRootPath
    Info "Moved $($result.moved.Count) repositories"
    Info "Rollback log: $($result.rollbackLogPath)"
  } catch {
    Write-Host "`n❌ Consolidation failed: $_" -ForegroundColor Red
    throw
  }

  # Run doctor verification
  Write-Host "`nRunning doctor verification..." -ForegroundColor Yellow
  try {
    Invoke-Doctor -StrapRootPath $StrapRootPath -OutputJson:$false
  } catch {
    Warn "Doctor verification found issues (non-fatal): $_"
  }

  Write-Host "`n✅ Consolidation complete!" -ForegroundColor Green

  # Collect manual fixes
  $manualFixes = @()
  if ($auditWarnings.Count -gt 0) {
    Write-Host "`n⚠️  Manual fixes required:" -ForegroundColor Yellow
    foreach ($w in $auditWarnings) {
      Write-Host "  - $w" -ForegroundColor Yellow
      $manualFixes += $w
    }
  }

  return @{ executed = $true; manualFixes = $manualFixes }
}

if ($RepoName -eq "templatize") {
  $templateName = Get-TemplateNameFromArgs $ExtraArgs
  Invoke-Templatize -TemplateName $templateName -SourcePath $Source -RootPath $TemplateRoot -ForceTemplate:$Force.IsPresent -AllowDirtyWorktree:$AllowDirty.IsPresent -MessageText $Message -DoPush:$Push.IsPresent
  exit 0
}

if ($RepoName -eq "doctor") {
  Invoke-Doctor -StrapRootPath $TemplateRoot -OutputJson:$Json.IsPresent
  exit 0
}

if ($RepoName -eq "migrate") {
  $targetVersion = if ($To -gt 0) { $To } else { $script:LATEST_REGISTRY_VERSION }
  Invoke-Migrate -TargetVersion $targetVersion -PlanOnly:$Plan.IsPresent -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -CreateBackup:$Backup.IsPresent -OutputJson:$Json.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "consolidate") {
  # Parse consolidate-specific args from $ExtraArgs
  $fromPath = $null
  $toPath = $null
  $stopPm2 = $false
  $ackScheduledTasks = $false
  $allowDirty = $false
  $allowAutoArchive = $false

  # Parse ExtraArgs for consolidate flags
  for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
    if ($ExtraArgs[$i] -eq "--from" -and ($i + 1) -lt $ExtraArgs.Count) {
      $fromPath = $ExtraArgs[$i + 1]
      $i++
    }
    elseif ($ExtraArgs[$i] -eq "--to" -and ($i + 1) -lt $ExtraArgs.Count) {
      $toPath = $ExtraArgs[$i + 1]
      $i++
    }
    elseif ($ExtraArgs[$i] -eq "--stop-pm2") { $stopPm2 = $true }
    elseif ($ExtraArgs[$i] -eq "--ack-scheduled-tasks") { $ackScheduledTasks = $true }
    elseif ($ExtraArgs[$i] -eq "--allow-dirty") { $allowDirty = $true }
    elseif ($ExtraArgs[$i] -eq "--allow-auto-archive") { $allowAutoArchive = $true }
  }

  # Validate args
  Test-ConsolidateArgs -FromPath $fromPath -ToPath $toPath -TrustMode "registry-first"

  # Call main workflow
  $result = Invoke-ConsolidateMigrationWorkflow `
    -FromPath $fromPath `
    -ToPath $toPath `
    -DryRun:$DryRun.IsPresent `
    -Yes:$Yes.IsPresent `
    -StopPm2:$stopPm2 `
    -AckScheduledTasks:$ackScheduledTasks `
    -AllowDirty:$allowDirty `
    -AllowAutoArchive:$allowAutoArchive `
    -StrapRootPath $TemplateRoot

  if ($result.manualFixes.Count -gt 0) {
    exit 1
  }

  exit 0
}

if ($RepoName -eq "snapshot") {
  # Parse --output and --scan flags
  $outputPath = "build/snapshot.json"
  $scanDirs = @()

  for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
    if ($ExtraArgs[$i] -eq "--output" -and ($i + 1) -lt $ExtraArgs.Count) {
      $outputPath = $ExtraArgs[$i + 1]
      $i++
      continue
    }
    if ($ExtraArgs[$i] -eq "--scan" -and ($i + 1) -lt $ExtraArgs.Count) {
      $scanDirs += $ExtraArgs[$i + 1]
      $i++
    }
  }

  Invoke-Snapshot -ScanDirs $scanDirs -OutputPath $outputPath -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "audit") {
    # Parse flags
    $targetName = if ($ExtraArgs.Count -gt 0 -and -not $ExtraArgs[0].StartsWith("--")) { $ExtraArgs[0] } else { $null }
    $allFlag = $ExtraArgs -contains "--all"
    $toolFlag = $ExtraArgs -contains "--tool"
    $softwareFlag = $ExtraArgs -contains "--software"
    $jsonFlag = $ExtraArgs -contains "--json"
    $rebuildFlag = $ExtraArgs -contains "--rebuild-index"

    Invoke-Audit -TargetName $targetName -AllRepos:$allFlag -ToolScope:$toolFlag `
        -SoftwareScope:$softwareFlag -RebuildIndex:$rebuildFlag -OutputJson:$jsonFlag `
        -StrapRootPath $TemplateRoot
    exit 0
}

if ($RepoName -eq "adopt") {
  # Check if --path was explicitly provided in ExtraArgs
  $pathProvided = $false
  if ($ExtraArgs) {
    for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
      if ($ExtraArgs[$i] -eq "--path" -or $ExtraArgs[$i] -eq "-p") {
        $pathProvided = $true
        break
      }
    }
  }

  $targetPath = if ($pathProvided) { $Path } else { $null }
  Invoke-Adopt -TargetPath $targetPath -CustomName $Name -ForceTool:$Tool.IsPresent -ForceSoftware:$Software.IsPresent -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "clone") {
  # Extract git URL from ExtraArgs
  $gitUrl = $null
  if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    foreach ($arg in $ExtraArgs) {
      if ($arg -notmatch '^--') {
        $gitUrl = $arg
        break
      }
    }
  }
  Invoke-Clone -GitUrl $gitUrl -CustomName $Name -DestPath $Dest -IsTool:$Tool.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "list") {
  Invoke-List -FilterTool:$Tool.IsPresent -FilterSoftware:$Software.IsPresent -OutputJson:$Json.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "open") {
  # Extract name from ExtraArgs
  $nameToOpen = $null
  if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    foreach ($arg in $ExtraArgs) {
      if ($arg -notmatch '^--') {
        $nameToOpen = $arg
        break
      }
    }
  }
  Invoke-Open -NameToOpen $nameToOpen -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "move") {
  # Extract name from ExtraArgs
  $nameToMove = $null
  if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    foreach ($arg in $ExtraArgs) {
      if ($arg -notmatch '^--') {
        $nameToMove = $arg
        break
      }
    }
  }
  Invoke-Move -NameToMove $nameToMove -DestPath $Dest -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -ForceOverwrite:$Force.IsPresent -RehomeShims:$RehomeShims.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "rename") {
  # Extract name from ExtraArgs
  $nameToRename = $null
  if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    foreach ($arg in $ExtraArgs) {
      if ($arg -notmatch '^--') {
        $nameToRename = $arg
        break
      }
    }
  }

  # Extract --to value from ExtraArgs (since $To is already used as [int] for migrate)
  $toName = $null
  if ($NewName) {
    $toName = $NewName
  } elseif ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
      if ($ExtraArgs[$i] -eq "--to" -and $i + 1 -lt $ExtraArgs.Count) {
        $toName = $ExtraArgs[$i + 1]
        break
      }
    }
  }

  Invoke-Rename -NameToRename $nameToRename -NewName $toName -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -MoveFolder:$MoveFolder.IsPresent -ForceOverwrite:$Force.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "setup") {
  Invoke-Setup -RepoNameOrPath $Repo -ForceStack $Stack -VenvPath $Venv -UseUv:$Uv.IsPresent -PythonExe $Python -PackageManager $Pm -EnableCorepack:$Corepack.IsPresent -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "update") {
  # Extract name from ExtraArgs (if not using --all)
  $nameToUpdate = $null
  if (-not $All -and $ExtraArgs -and $ExtraArgs.Count -gt 0) {
    foreach ($arg in $ExtraArgs) {
      if ($arg -notmatch '^--') {
        $nameToUpdate = $arg
        break
      }
    }
  }
  Invoke-Update -NameToUpdate $nameToUpdate -UpdateAll:$All.IsPresent -FilterTool:$Tool.IsPresent -FilterSoftware:$Software.IsPresent -UseRebase:$Rebase.IsPresent -AutoStash:$Stash.IsPresent -RunSetup:$Setup.IsPresent -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "uninstall") {
  # Extract name from ExtraArgs
  $nameToRemove = $null
  if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    foreach ($arg in $ExtraArgs) {
      if ($arg -notmatch '^--') {
        $nameToRemove = $arg
        break
      }
    }
  }
  Invoke-Uninstall -NameToRemove $nameToRemove -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -PreserveFolder:$KeepFolder.IsPresent -PreserveShims:$KeepShims.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "shim") {
  # Two input modes:
  # 1. --cmd "<command>" - command passed as string (avoids PowerShell parameter binding)
  # 2. strap shim <name> --- <command...> - command parsed from args (uses --- to avoid conflicts)

  $shimName = $null
  $commandLine = $null

  if ($Cmd) {
    # --cmd mode: command already provided as string
    # Extract shim name from ExtraArgs (first non-flag arg)
    if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
      foreach ($arg in $ExtraArgs) {
        if ($arg -notmatch '^--' -and -not $shimName) {
          $shimName = $arg
          break
        }
      }
    }
    $commandLine = $Cmd
  } else {
    # --- mode: parse separator and extract args
    $commandArgs = @()
    $foundSeparator = $false

    if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
      for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
        $arg = $ExtraArgs[$i]

        if ($arg -eq "---" -or $arg -eq "--") {
          $foundSeparator = $true
          # Everything after --- is the command
          if ($i + 1 -lt $ExtraArgs.Count) {
            $commandArgs = $ExtraArgs[($i + 1)..($ExtraArgs.Count - 1)]
          }
          break
        }

        # Before ---, look for the shim name (first non-flag arg)
        if (-not $foundSeparator -and $arg -notmatch '^--' -and -not $shimName) {
          $shimName = $arg
        }
      }
    }

    if ($commandArgs.Count -gt 0) {
      $commandLine = $commandArgs -join ' '
    }
  }

  Invoke-Shim -ShimName $shimName -CommandLine $commandLine -WorkingDir $Cwd -RegistryEntryName $Repo -ForceOverwrite:$Force.IsPresent -DryRunMode:$DryRun.IsPresent -NonInteractive:$Yes.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if (-not $Template) { $Template = Prompt-Template }

$ProfileDir = Join-Path "templates" $Template

if (-not (Test-Path $Path)) {
  New-Item -ItemType Directory -Path $Path | Out-Null
}

$Dest = Join-Path $Path $RepoName
if (Test-Path $Dest) { Die "Path exists: $Dest" }

Info "Creating repo: $RepoName ($Template)"
New-Item -ItemType Directory -Path $Dest | Out-Null

$CommonDir = Join-Path $TemplateRoot "templates\common"
$ProfilePath = Join-Path $TemplateRoot $ProfileDir

Info "Copying templates from $TemplateRoot"
Copy-TemplateDir $CommonDir $Dest
Copy-TemplateDir $ProfilePath $Dest

$year = (Get-Date).Year
$pyPackage = ($RepoName -replace "-", "_")
$tokens = @{
  "{{REPO_NAME}}" = $RepoName
  "{{PY_PACKAGE}}" = $pyPackage
  "<REPO_NAME>" = $RepoName
  "<PY_PACKAGE>" = $pyPackage
  "{{YEAR}}"      = "$year"
}

if ($Template -eq "python" -and $pyPackage -eq $RepoName) {
  $conflictPath = Join-Path (Join-Path $Dest "src") "{{REPO_NAME}}"
  if (Test-Path $conflictPath) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $conflictPath
  }
}

Resolve-RemainingTokens $Dest $tokens

if ($Template -eq "python") {
  $legacyPath = Join-Path $Dest $RepoName
  if (Test-Path $legacyPath) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $legacyPath
  }
  $legacySrcPath = Join-Path (Join-Path $Dest "src") $RepoName
  if (Test-Path $legacySrcPath) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $legacySrcPath
  }
}

$envExample = Join-Path $Dest ".env.example"
if (-not (Test-Path $envExample)) {
  Set-Content -LiteralPath $envExample -NoNewline -Value "# Example environment variables`n# FOO=bar`n"
}

Get-ChildItem -LiteralPath $Dest -Recurse -File -Filter ".keep" | Remove-Item -Force -ErrorAction SilentlyContinue

Ensure-Command git
Push-Location $Dest

git init | Out-Null
git checkout -b $DefaultBranch 2>$null | Out-Null
Ok "git initialized ($DefaultBranch)"

$env:CI = "1"
if ($Start.IsPresent -and $SkipInstall.IsPresent) {
  Warn "Both --start and --skip-install were provided; skipping --start."
  $Start = $false
}

$fullInstall = $Install.IsPresent -or $Start.IsPresent
if ($SkipInstall.IsPresent) {
  Info "Skipping install (--skip-install)"
} else {
  switch ($Template) {
    "node-ts-service" {
      if (Has-Command pnpm) {
        pnpm install --lockfile-only | Out-Null
      } else {
        Warn "pnpm not found. install with corepack enable / npm i -g pnpm, or rerun strap with --skip-install"
      }
    }
    "node-ts-web" {
      if (Has-Command pnpm) {
        pnpm install --lockfile-only | Out-Null
      } else {
        Warn "pnpm not found. install with corepack enable / npm i -g pnpm, or rerun strap with --skip-install"
      }
    }
    "mono" {
      if (Has-Command pnpm) {
        pnpm install --lockfile-only | Out-Null
      } else {
        Warn "pnpm not found. install with corepack enable / npm i -g pnpm, or rerun strap with --skip-install"
      }
    }
    "python" {
      Ensure-Command python
      python -m pip install -e . ruff pytest | Out-Null
    }
  }
}

$ContextHookCmd = Join-Path $TemplateRoot "context-hook.cmd"
$ContextHookPs1 = Join-Path $TemplateRoot "context-hook.ps1"
if (Test-Path $ContextHookCmd) {
  & $ContextHookCmd install | Out-Null
} elseif (Test-Path $ContextHookPs1) {
  & $ContextHookPs1 install | Out-Null
} else {
  Die "context-hook not found in strap root"
}

Normalize-TextFiles $Dest

git add . | Out-Null
git commit -m "init repo from $Template template" 2>$null | Out-Null
Ok "initial commit created"

if (-not $SkipInstall.IsPresent -and $fullInstall) {
  switch ($Template) {
    "node-ts-service" { if (Has-Command pnpm) { pnpm install | Out-Null } }
    "node-ts-web" { if (Has-Command pnpm) { pnpm install | Out-Null } }
    "mono" { if (Has-Command pnpm) { pnpm install | Out-Null } }
    "python" { }
  }
}

if (-not $SkipInstall.IsPresent -and $Start.IsPresent) {
  switch ($Template) {
    "node-ts-service" { if (Has-Command pnpm) { pnpm dev } }
    "node-ts-web" { if (Has-Command pnpm) { pnpm dev } }
    "mono" { if (Has-Command pnpm) { pnpm dev } }
    "python" { python -m $pyPackage }
  }
}

Pop-Location
Ok "Done."
Write-Host "Next:"
Write-Host "  cd $Dest"
switch ($Template) {
  "node-ts-service" { Write-Host "  pnpm dev" }
  "node-ts-web" { Write-Host "  pnpm dev" }
  "mono" { Write-Host "  pnpm dev" }
  "python" { Write-Host "  $pyPackage --help" }
}
