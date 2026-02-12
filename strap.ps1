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
# MODULE IMPORTS
# ============================================================================
$ModulesPath = Join-Path $PSScriptRoot "modules"
. (Join-Path $ModulesPath "Core.ps1")
. (Join-Path $ModulesPath "Utils.ps1")
. (Join-Path $ModulesPath "Path.ps1")
. (Join-Path $ModulesPath "Config.ps1")
. (Join-Path $ModulesPath "Chinvex.ps1")
. (Join-Path $ModulesPath "PyenvIntegration.ps1")
. (Join-Path $ModulesPath "FnmIntegration.ps1")
. (Join-Path $ModulesPath "CLI.ps1")
. (Join-Path $ModulesPath "References.ps1")
. (Join-Path $ModulesPath "Audit.ps1")
. (Join-Path $ModulesPath "Consolidate.ps1")
$CommandsPath = Join-Path $ModulesPath "Commands"
Get-ChildItem -Path $CommandsPath -Filter "*.ps1" | ForEach-Object {
    . $_.FullName
}

# ============================================================================
# KILL SWITCH - Disabled commands pending review
# See: docs/incidents/2026-02-02-environment-corruption.md
# See: docs/incidents/2026-02-02-tdd-tasks-status.md
# NOTE: UNSAFE_COMMANDS list and Assert-CommandSafe moved to modules\Core.ps1
# ============================================================================

# NOTE: Die, Info, Ok, Warn functions moved to modules\Core.ps1

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
      "--skip-setup" { $script:SkipSetup = $true; continue }
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

# NOTE: Parse-GlobalFlags moved to modules\CLI.ps1

$TemplateRoot = if ($StrapRoot) { $StrapRoot } else { $PSScriptRoot }
$DefaultBranch = if ($env:BOOTSTRAP_BRANCH) { $env:BOOTSTRAP_BRANCH } else { "main" }

function Show-Help {
  @"
strap - Repository lifecycle management with chinvex integration

USAGE:
    strap <command> [options]

COMMANDS:
    clone <url> [--tool|--software] [--no-chinvex] [--skip-setup]
        Clone and register a repository (auto-runs setup + creates shims)
        --tool        Use tool preset (depth=light, status=stable, tags=[third-party])
        --software    Use software preset (depth=full, status=active, default)
        --no-chinvex  Skip chinvex integration
        --skip-setup  Skip automatic dependency installation

    adopt [--path <dir>] [--tool|--software] [--no-chinvex] [--skip-setup]
        Adopt existing repository into registry (auto-runs setup + creates shims)
        --tool        Use tool preset
        --software    Use software preset
        --no-chinvex  Skip chinvex integration
        --skip-setup  Skip automatic dependency installation

    configure <name> [--depth <light|full>] [--status <status>] [--tags <tag1,tag2>]
        Modify repository metadata after adoption/cloning
        --depth <value>     Set chinvex depth (light or full)
        --status <value>    Set status (active, stable, archived, deprecated)
        --tags <tags>       Replace tags (comma-separated)
        --add-tags <tags>   Add tags without removing existing ones
        --remove-tags <tags> Remove specific tags
        --clear-tags        Remove all tags
        --json              Output as JSON
        --dry-run           Preview changes without applying
        --yes               Skip confirmation prompt

    move <name> --dest <path> [--no-chinvex]
        Move repository to new location
        --no-chinvex  Skip chinvex path updates

    rename <name> --to <new> [--move-folder] [--no-chinvex]
        Rename repository (and optionally its folder)
        --move-folder  Also rename the folder on disk
        --no-chinvex   Skip chinvex context rename

    uninstall <name> [--no-chinvex]
        Remove repository (archives chinvex context for software repos)
        --no-chinvex  Skip chinvex cleanup

    purge [--cleanup-chinvex] [--yes] [--dry-run]
        Clear entire registry (removes all repository entries)
        --cleanup-chinvex  Also delete associated chinvex contexts
        --yes             Skip confirmation prompt
        --dry-run         Preview changes without applying
        NOTE: Does not delete folders or shims, only registry entries

    list
        List all registered repositories

    contexts
        List chinvex contexts with sync status
        Shows which contexts are synced, missing, or orphaned

    sync-chinvex [--dry-run|--reconcile]
        Reconcile registry with chinvex contexts
        --dry-run     Show what would change (default)
        --reconcile   Apply reconciliation actions:
                      - Create missing contexts
                      - Archive orphaned contexts

    setup <name>
        Run setup script for repository

    update [name]
        Update repository (or all if no name given)

    shim <name> --source <path>
        Create shim for executable

    open <name>
        Open repository in file explorer

    doctor
        Check system health

    help
        Show this help message

GLOBAL FLAGS:
    --no-chinvex    Skip chinvex integration for this command
    --tool          Use tool preset (third-party repos)
    --software      Use software preset (default)

CHINVEX INTEGRATION:
    Strap automatically manages chinvex contexts:
    - All repos get individual contexts (context name = repo name)
    - Metadata (depth, status, tags) passed to chinvex
    - Use 'strap contexts' to view sync status
    - Use 'strap sync-chinvex --reconcile' to fix drift

    Disable globally via config.json: { "chinvex_integration": false }
    Or per-command with --no-chinvex flag

EXAMPLES:
    strap clone https://github.com/user/myproject
    strap clone https://github.com/user/mytool --tool
    strap adopt --path P:\software\existing-repo
    strap configure myrepo --depth light --status stable
    strap configure myrepo --add-tags third-party,archived
    strap move myrepo --dest P:\software\subdir
    strap contexts
    strap sync-chinvex --reconcile

"@ | Write-Host
}

if ($RepoName -in @("--help","-h","help")) {
  Show-Help
  exit 0
}

# NOTE: Has-Command moved to modules\Utils.ps1

# NOTE: Load-Config moved to modules\Config.ps1

# ============================================================================
# CHINVEX INTEGRATION - CLI Wrappers
# ============================================================================

# Script-level cache for chinvex availability check
$script:chinvexChecked = $false
$script:chinvexAvailable = $false

# ============================================================================
# CHINVEX INTEGRATION - Helper Functions
# ============================================================================

# NOTE: Parse-GitUrl moved to modules\Path.ps1

# Migration constants and helpers

$script:LATEST_REGISTRY_VERSION = 3

# Consolidate helper functions

# NOTE: Path and utility functions moved to modules\Path.ps1 and modules\Utils.ps1
# - Normalize-Path, Test-PathWithinRoot, Find-DuplicatePaths -> Path.ps1
# - Test-ProcessRunning, Get-DirectorySize -> Utils.ps1

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
  $pattern = "\{\{REPO_NAME\}\}|\{\{PY_PACKAGE\}\}"
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
          $required = @('name', 'chinvex_depth', 'status', 'tags', 'path', 'updated_at', 'shims')
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
      Write-Host "  [OK] shims_root in PATH: $($report.path_check.path_entry)" -ForegroundColor Green
    } else {
      Write-Host "  [X] shims_root NOT in PATH" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "Tool availability:" -ForegroundColor Yellow
    foreach ($tool in $report.tools) {
      if ($tool.found) {
        Write-Host "  [OK] $($tool.name.PadRight(10)) $($tool.version)" -ForegroundColor Green
      } else {
        Write-Host "  [X] $($tool.name.PadRight(10)) not found" -ForegroundColor Red
      }
    }
    Write-Host ""

    Write-Host "Registry integrity:" -ForegroundColor Yellow
    if (-not $report.registry_check.exists) {
      Write-Host "  Registry: missing (ok if new)" -ForegroundColor Yellow
    } elseif (-not $report.registry_check.valid_json) {
      Write-Host "  [X] Invalid JSON" -ForegroundColor Red
      foreach ($issue in $report.registry_check.issues) {
        Write-Host "    - $issue" -ForegroundColor Red
      }
    } else {
      Write-Host "  [OK] Valid JSON" -ForegroundColor Green
      if ($report.registry_check.ContainsKey('version') -and $report.registry_check.version -ne $null) {
        $versionText = "Version $($report.registry_check.version)"
        if ($report.registry_check.version -lt $script:LATEST_REGISTRY_VERSION) {
          Write-Host "  [!] $versionText (outdated, latest: $script:LATEST_REGISTRY_VERSION)" -ForegroundColor Yellow
        } else {
          Write-Host "  [OK] $versionText (current)" -ForegroundColor Green
        }
      }
      if ($report.registry_check.issues.Count -eq 0) {
        Write-Host "  [OK] No issues found" -ForegroundColor Green
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

if ($RepoName -eq "templatize") {
  $templateName = Get-TemplateNameFromArgs $ExtraArgs
  Invoke-Templatize -TemplateName $templateName -SourcePath $Source -RootPath $TemplateRoot -ForceTemplate:$Force.IsPresent -AllowDirtyWorktree:$AllowDirty.IsPresent -MessageText $Message -DoPush:$Push.IsPresent
  exit 0
}

if ($RepoName -eq "doctor") {
  $config = Load-Config $PSScriptRoot
  $registry = Load-Registry $config

  $runShims = $ExtraArgs -contains "--shims"
  $runSystem = $ExtraArgs -contains "--system"
  $runNode = $ExtraArgs -contains "--node"
  $installPyenv = $ExtraArgs -contains "--install-pyenv"
  $installFnm = $ExtraArgs -contains "--install-fnm"
  $runAll = -not $runShims -and -not $runSystem -and -not $runNode -and -not $installPyenv -and -not $installFnm  # Default: run all checks

  # Handle pyenv installation
  if ($installPyenv) {
    Write-Host "=== INSTALLING PYENV-WIN ===" -ForegroundColor Cyan
    Write-Host ""

    # Install pyenv-win
    $success = Install-PyenvWin
    if (-not $success) {
      Write-Host ""
      Write-Host "[X] Failed to install pyenv-win" -ForegroundColor Red
      exit 1
    }

    # Create shim
    Write-Host ""
    Write-Host "Creating system-wide shim..." -ForegroundColor Cyan
    $shimSuccess = New-PyenvShim -ShimsDir $config.roots.shims
    if (-not $shimSuccess) {
      Write-Host ""
      Write-Host "[X] Failed to create pyenv shim" -ForegroundColor Red
      exit 1
    }

    Write-Host ""
    Write-Host "[OK] pyenv-win installed and configured successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Verify: pyenv --version" -ForegroundColor Gray
    Write-Host "  2. Install Python: pyenv install 3.11.9" -ForegroundColor Gray
    Write-Host "  3. Use in projects via: strap setup" -ForegroundColor Gray
    exit 0
  }

  # Handle fnm installation
  if ($installFnm) {
    Write-Host "=== INSTALLING FNM ===" -ForegroundColor Cyan
    Write-Host ""

    # Install fnm binary
    $success = Install-FnmBinary
    if (-not $success) {
      Write-Host ""
      Write-Host "[X] Failed to install fnm" -ForegroundColor Red
      exit 1
    }

    # Create system-wide shim
    Write-Host ""
    Write-Host "Creating system-wide shim..." -ForegroundColor Cyan
    $shimSuccess = New-FnmShim -ShimsDir $config.roots.shims
    if (-not $shimSuccess) {
      Write-Host ""
      Write-Host "[X] Failed to create fnm shim" -ForegroundColor Red
      exit 1
    }

    Write-Host ""
    Write-Host "[OK] fnm installed and configured successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Verify: fnm --version" -ForegroundColor Gray
    Write-Host "  2. Install Node: fnm install 18.17.0" -ForegroundColor Gray
    Write-Host "  3. Use in projects via: strap setup" -ForegroundColor Gray
    exit 0
  }

  $anyFailed = $false

  # Run system dependency checks
  if ($runSystem -or $runAll) {
    $results = Invoke-DoctorSystemChecks -Config $config
    $output = Format-DoctorSystemResults $results
    Write-Host $output
    Write-Host ""

    $failed = ($results | Where-Object { -not $_.passed -and $_.severity -in @("critical", "error") }).Count
    if ($failed -gt 0) { $anyFailed = $true }
  }

  # Run shim checks
  if ($runShims -or $runAll) {
    $results = Invoke-DoctorShimChecks -Config $config -Registry $registry
    $output = Format-DoctorShimResults $results
    Write-Host $output
    Write-Host ""

    $failed = ($results | Where-Object { -not $_.passed -and $_.severity -in @("critical", "error") }).Count
    if ($failed -gt 0) { $anyFailed = $true }
  }

  # Run Node version management checks
  if ($runNode -or $runAll) {
    $results = Invoke-DoctorNodeChecks -Config $config -Registry $registry
    if ($results.Count -gt 0) {
      $output = Format-DoctorNodeResults $results
      Write-Host $output

      $failed = ($results | Where-Object { -not $_.passed -and $_.severity -in @("critical", "error") }).Count
      if ($failed -gt 0) { $anyFailed = $true }
    }
  }

  exit $(if ($anyFailed) { 1 } else { 0 })
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
  Invoke-Adopt -TargetPath $targetPath -CustomName $Name -ForceTool:$Tool.IsPresent -ForceSoftware:$Software.IsPresent -NoChinvex:$NoChinvex.IsPresent -SkipSetup:$SkipSetup.IsPresent -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "configure") {
  # Extract name from ExtraArgs
  $nameToConfigure = $null
  if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    foreach ($arg in $ExtraArgs) {
      if ($arg -notmatch '^--') {
        $nameToConfigure = $arg
        break
      }
    }
  }

  # Parse configure-specific flags
  $newDepth = $null
  $newStatus = $null
  $newTags = $null
  $clearTags = $false
  $addTags = $false
  $removeTags = $false

  for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
    $arg = $ExtraArgs[$i]
    switch ($arg) {
      "--depth" {
        if ($i + 1 -lt $ExtraArgs.Count) {
          $newDepth = $ExtraArgs[++$i]
        }
      }
      "--status" {
        if ($i + 1 -lt $ExtraArgs.Count) {
          $newStatus = $ExtraArgs[++$i]
        }
      }
      "--tags" {
        if ($i + 1 -lt $ExtraArgs.Count) {
          $newTags = $ExtraArgs[++$i] -split ','
        }
      }
      "--add-tags" {
        if ($i + 1 -lt $ExtraArgs.Count) {
          $newTags = $ExtraArgs[++$i] -split ','
          $addTags = $true
        }
      }
      "--remove-tags" {
        if ($i + 1 -lt $ExtraArgs.Count) {
          $newTags = $ExtraArgs[++$i] -split ','
          $removeTags = $true
        }
      }
      "--clear-tags" {
        $clearTags = $true
      }
    }
  }

  Invoke-Configure -NameToConfigure $nameToConfigure -NewDepth $newDepth -NewStatus $newStatus `
      -NewTags $newTags -ClearTags:$clearTags -AddTags:$addTags -RemoveTags:$removeTags `
      -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -OutputJson:$Json.IsPresent `
      -StrapRootPath $TemplateRoot
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
  Invoke-Clone -GitUrl $gitUrl -CustomName $Name -DestPath $Dest -IsTool:$Tool.IsPresent -NoChinvex:$NoChinvex.IsPresent -SkipSetup:$SkipSetup.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "list") {
  Invoke-List -FilterTool:$Tool.IsPresent -FilterSoftware:$Software.IsPresent -OutputJson:$Json.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "contexts") {
  Invoke-Contexts -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "sync-chinvex") {
  # Parse sync-chinvex specific flags
  $dryRunFlag = $false
  $reconcileFlag = $false
  if ($ExtraArgs) {
    foreach ($arg in $ExtraArgs) {
      switch ($arg) {
        "--dry-run" { $dryRunFlag = $true }
        "--reconcile" { $reconcileFlag = $true }
      }
    }
  }
  # Default to dry-run if neither specified
  if (-not $dryRunFlag -and -not $reconcileFlag) {
    $dryRunFlag = $true
  }
  Invoke-SyncChinvex -DryRun:$dryRunFlag -Reconcile:$reconcileFlag -StrapRootPath $TemplateRoot
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

if ($RepoName -eq "upgrade-node") {
  # Extract repo name from ExtraArgs (first non-flag argument)
  $repoName = $null
  $targetVersion = ""
  $latest = $false
  $listOnly = $false

  # Parse arguments
  $i = 0
  while ($i -lt $ExtraArgs.Count) {
    $arg = $ExtraArgs[$i]
    if ($arg -eq "--latest") {
      $latest = $true
    } elseif ($arg -eq "--list-only") {
      $listOnly = $true
    } elseif ($arg -match '^--version=(.+)$') {
      $targetVersion = $matches[1]
    } elseif ($arg -eq "--version") {
      $i++
      if ($i -lt $ExtraArgs.Count) {
        $targetVersion = $ExtraArgs[$i]
      }
    } elseif ($arg -notmatch '^--' -and -not $repoName) {
      # First non-flag argument is the repo name
      $repoName = $arg
    }
    $i++
  }

  $params = @{
    RepoNameOrPath = $repoName
    Latest = $latest
    ListOnly = $listOnly
    NonInteractive = $Yes.IsPresent
    StrapRootPath = $TemplateRoot
  }
  if ($targetVersion) { $params.Version = $targetVersion }

  $null = Invoke-UpgradeNode @params
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

if ($RepoName -eq "purge") {
  # Parse --cleanup-chinvex flag
  $cleanupChinvex = $false
  if ($ExtraArgs -contains "--cleanup-chinvex") {
    $cleanupChinvex = $true
  }
  Invoke-Purge -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -NoChinvex:$NoChinvex.IsPresent -CleanupChinvex:$cleanupChinvex -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "shim") {
  $config = Load-Config $PSScriptRoot
  $registry = Load-Registry $config

  # Check for --regen flag
  $regenIdx = -1
  for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
    if ($ExtraArgs[$i] -eq "--regen") {
      $regenIdx = $i
      break
    }
  }

  if ($regenIdx -ge 0) {
    # strap shim --regen <repo>
    $repoName = if ($ExtraArgs.Count -gt $regenIdx + 1) { $ExtraArgs[$regenIdx + 1] } else { Die "--regen requires repo name" }
    Invoke-ShimRegen -RepoName $repoName -Config $config -Registry $registry
    exit 0
  }

  # Parse shim creation args
  $shimName = $null
  $shimArgs = @{
    Config = $config
    Registry = $registry
  }

  # Extract shim name (first non-flag arg)
  for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
    if ($ExtraArgs[$i] -notmatch '^--' -and -not $shimName) {
      $shimName = $ExtraArgs[$i]
      break
    }
  }

  if (-not $shimName) { Die "Must specify shim name" }
  $shimArgs.ShimName = $shimName

  # Parse flags
  for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
    $arg = $ExtraArgs[$i]
    switch ($arg) {
      "--cmd" { $shimArgs.Cmd = $ExtraArgs[++$i] }
      "--exe" { $shimArgs.Exe = $ExtraArgs[++$i] }
      "--args" { $shimArgs.BaseArgs = $ExtraArgs[++$i] -split ',' }
      "--venv" {
        $shimArgs.ShimType = "venv"
        # Check if next arg is a path (doesn't start with --)
        if ($i + 1 -lt $ExtraArgs.Count -and -not $ExtraArgs[$i + 1].StartsWith("--")) {
          $shimArgs.VenvPath = $ExtraArgs[++$i]
        }
      }
      "--node" { $shimArgs.ShimType = "node" }
      "--node-exe" { $shimArgs.NodeExe = $ExtraArgs[++$i] }
      "--cwd" { $shimArgs.WorkingDir = $ExtraArgs[++$i] }
      "--repo" { $shimArgs.RegistryEntryName = $ExtraArgs[++$i] }
      "--force" { $shimArgs.ForceOverwrite = $true }
      "--dry-run" { $shimArgs.DryRun = $true }
    }
  }

  if (-not $shimArgs.RegistryEntryName) {
    Die "Must specify --repo <name>"
  }

  $shimEntry = Invoke-Shim @shimArgs

  if ($shimEntry -and -not $shimArgs.DryRun) {
    # Update registry
    $repoEntry = $registry | Where-Object { $_.name -eq $shimArgs.RegistryEntryName }

    # Remove existing shim entry if present
    $repoEntry.shims = @($repoEntry.shims | Where-Object { $_.name -ne $shimName })

    # Add new entry
    $repoEntry.shims += $shimEntry

    Save-Registry $config $registry
  }
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

$TemplatesDir = Join-Path $PSScriptRoot "templates"
$ContextHookCmd = Join-Path $TemplatesDir "context-hook.cmd"
$ContextHookPs1 = Join-Path $TemplatesDir "context-hook.ps1"
if (Test-Path $ContextHookCmd) {
  & $ContextHookCmd install | Out-Null
} elseif (Test-Path $ContextHookPs1) {
  & $ContextHookPs1 install | Out-Null
} else {
  Die "context-hook not found in templates directory"
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
