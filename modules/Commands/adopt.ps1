# adopt.ps1
# Command: Invoke-Adopt

function Invoke-Adopt {
  param(
    [string] $TargetPath,
    [string] $CustomName,
    [switch] $ForceTool,
    [switch] $ForceSoftware,
    [switch] $NoChinvex,
    [switch] $SkipSetup,
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

  # Validate within managed root
  $softwareRoot = $config.software_root
  $withinSoftware = $resolvedPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase)
  if (-not $withinSoftware) {
    Die "Path is not within managed root: $resolvedPath"
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

  # Determine preset
  if ($ForceTool) {
    $depth = 'light'
    $status = 'stable'
    $tags = @('third-party')
  } elseif ($ForceSoftware) {
    $depth = 'full'
    $status = 'active'
    $tags = @()
  } else {
    # Default preset
    $depth = 'full'
    $status = 'active'
    $tags = @()
    Info "Using default preset: depth=full, status=active"
  }

  # Reserved name check
  if (Test-ReservedContextName -Name $name) {
    Die "Cannot use reserved name '$name'. Reserved names: tools, archive, strap"
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
  $pythonVersion = $null

  Push-Location $resolvedPath
  try {
    if (Test-Path "pyproject.toml") { $stackDetected = "python" }
    elseif (Test-Path "requirements.txt") { $stackDetected = "python" }
    elseif (Test-Path "package.json") { $stackDetected = "node" }
    elseif (Test-Path "Cargo.toml") { $stackDetected = "rust" }
    elseif (Test-Path "go.mod") { $stackDetected = "go" }

    # Detect Python version if Python stack
    if ($stackDetected -eq "python") {
      $pythonVersion = Get-PythonVersionFromFile -RepoPath $resolvedPath
      if ($pythonVersion) {
        Info "Detected Python version: $pythonVersion"
      }
    }
  } finally {
    Pop-Location
  }

  # Dry run: show what would happen
  if ($DryRunMode) {
    Info "[DRY RUN] Would adopt: $resolvedPath"
    Info "[DRY RUN] Name: $name"
    Info "[DRY RUN] Depth: $depth"
    Info "[DRY RUN] Status: $status"
    Info "[DRY RUN] Tags: $($tags -join ', ')"
    Info "[DRY RUN] URL: $url"
    Info "[DRY RUN] Stack: $stackDetected"
    if ($pythonVersion) { Info "[DRY RUN] Python version: $pythonVersion" }
    return
  }

  # Create entry
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $entry = [PSCustomObject]@{
    id              = $name
    name            = $name
    url             = $url
    path            = $resolvedPath
    chinvex_depth   = $depth
    status          = $status
    tags            = $tags
    chinvex_context = $null  # Default, updated below if sync succeeds
    shims           = @()
    stack           = if ($stackDetected) { @($stackDetected) } else { @() }
    python_version  = $pythonVersion
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
    $contextName = Sync-ChinvexForEntry -Name $name -RepoPath $resolvedPath `
        -ChinvexDepth $entry.chinvex_depth -Status $entry.status -Tags $entry.tags
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
      $newRegistry = $updatedRegistry
    }
  }

  # Run setup automatically (unless --skip-setup)
  $setupSucceeded = $false
  $setupError = $null
  if (-not $SkipSetup -and $stackDetected) {
    Write-Host ""
    Info "Running automatic setup for $stackDetected stack..."
    Push-Location $resolvedPath
    try {
      Invoke-Setup -StrapRootPath $StrapRootPath -NonInteractive
      $setupSucceeded = $true
    } catch {
      $setupError = $_.Exception.Message
      Warn "Setup failed: $_"
      Warn "You can run 'strap setup --repo $name' manually"
    } finally {
      Pop-Location
    }

    # Update entry with setup status
    if ($stackDetected) {
      $setupStatus = [PSCustomObject]@{
        result = if ($setupSucceeded) { "succeeded" } else { "failed" }
        error = $setupError
        last_attempt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
      }
      $entry | Add-Member -NotePropertyName 'setup' -NotePropertyValue $setupStatus -Force
    }
  } elseif ($SkipSetup -and $stackDetected) {
    # Setup was skipped
    $setupStatus = [PSCustomObject]@{
      result = "skipped"
      error = $null
      last_attempt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    $entry | Add-Member -NotePropertyName 'setup' -NotePropertyValue $setupStatus -Force
  } else {
    # No stack detected, setup not attempted
    $entry | Add-Member -NotePropertyName 'setup' -NotePropertyValue $null -Force
  }

  # Auto-discover and create shims
  $autoShims = Invoke-ShimAutoDiscover -RepoEntry $entry -Config $config -Registry $newRegistry
  if ($autoShims.Count -gt 0) {
    # Update entry with created shims
    $entry.shims = $autoShims
    # Re-save registry with shims
    $finalRegistry = @()
    foreach ($item in $newRegistry) {
      if ($item.name -eq $name) {
        $item.shims = $autoShims
      }
      $finalRegistry += $item
    }
    Save-Registry $config $finalRegistry
  }

  Ok "Adopted: $name ($resolvedPath)"
  Info "Depth: $depth, Status: $status, Tags: $($tags -join ', ')"
  if ($url) { Info "Remote: $url" }
  if ($stackDetected) { Info "Stack: $stackDetected" }

  if (-not $SkipSetup -and $stackDetected -and $autoShims.Count -gt 0) {
    Write-Host ""
    Ok "Ready to use! Try: $($autoShims[0].name) --help"
  }
}

