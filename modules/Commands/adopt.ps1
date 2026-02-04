# adopt.ps1
# Command: Invoke-Adopt

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

