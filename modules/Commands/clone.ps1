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

