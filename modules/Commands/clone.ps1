# clone.ps1
# Command: Invoke-Clone

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

  # Reserved name check (before any filesystem changes)
  if (Test-ReservedContextName -Name $repoName) {
    Die "Cannot use reserved name '$repoName'. Reserved names: tools, archive, strap"
  }

  # All repos go to software root
  $destPath = if ($DestPath) {
    $DestPath
  } else {
    Join-Path $config.software_root $repoName
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

  # Determine preset
  if ($IsTool) {
    $depth = 'light'
    $status = 'stable'
    $tags = @('third-party')
  } else {
    $depth = 'full'
    $status = 'active'
    $tags = @()
  }

  # Detect stack (best-effort)
  $stackDetected = $null
  Push-Location $absolutePath
  try {
    if (Test-Path "pyproject.toml") { $stackDetected = "python" }
    elseif (Test-Path "requirements.txt") { $stackDetected = "python" }
    elseif (Test-Path "package.json") { $stackDetected = "node" }
    elseif (Test-Path "Cargo.toml") { $stackDetected = "rust" }
    elseif (Test-Path "go.mod") { $stackDetected = "go" }
  } finally {
    Pop-Location
  }

  # Create new entry with V3 metadata fields
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $entry = [PSCustomObject]@{
    id              = $repoName
    name            = $repoName
    url             = $GitUrl
    path            = $absolutePath
    chinvex_depth   = $depth
    status          = $status
    tags            = $tags
    chinvex_context = $null  # Default, updated below if sync succeeds
    shims           = @()
    stack           = if ($stackDetected) { $stackDetected } else { @() }
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
    $contextName = Sync-ChinvexForEntry -Name $repoName -RepoPath $absolutePath `
        -ChinvexDepth $entry.chinvex_depth -Status $entry.status -Tags $entry.tags
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
      $newRegistry = $updatedRegistry
    }
  }

  # Auto-discover and create shims
  $autoShims = Invoke-ShimAutoDiscover -RepoEntry $entry -Config $config -Registry $newRegistry
  if ($autoShims.Count -gt 0) {
    # Update entry with created shims
    $entry.shims = $autoShims
    # Re-save registry with shims
    $finalRegistry = @()
    foreach ($item in $newRegistry) {
      if ($item.name -eq $repoName) {
        $item.shims = $autoShims
      }
      $finalRegistry += $item
    }
    Save-Registry $config $finalRegistry
  }

  Ok "Added to registry"

  Info "Next steps:"
  Info "  strap setup --repo $repoName"
  if ($autoShims.Count -eq 0) {
    Info "  strap shim <name> --exe <path> --repo $repoName  # Create shims manually if needed"
  }
}

