# clone.ps1
# Command: Invoke-Clone

function Invoke-Clone {
  param(
    [string] $GitUrl,
    [string] $CustomName,
    [string] $DestPath,
    [switch] $IsTool,
    [switch] $NoChinvex,
    [switch] $SkipSetup,
    [switch] $SkipValidation,
    [switch] $VerboseLogging,
    [string] $StrapRootPath
  )

  # Enable verbose output if requested
  $script:VerboseClone = $VerboseLogging

  function Verbose-Log {
    param([string]$Message)
    if ($script:VerboseClone) {
      Write-Host "  [VERBOSE] $Message" -ForegroundColor DarkGray
    }
  }

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
  Verbose-Log "Detecting stack type..."
  $stackDetected = $null
  $pythonVersion = $null
  $nodeVersion = $null

  Push-Location $absolutePath
  try {
    $allStacks = @()
    if ((Test-Path "pyproject.toml") -or (Test-Path "requirements.txt") -or (Test-Path "setup.py")) {
      $allStacks += "python"
      Verbose-Log "Found Python marker - python stack"
    }
    if (Test-Path "package.json") {
      $allStacks += "node"
      Verbose-Log "Found package.json - node stack"
    }
    if (Test-Path "Cargo.toml") {
      $allStacks += "rust"
      Verbose-Log "Found Cargo.toml - rust stack"
    }
    if (Test-Path "go.mod") {
      $allStacks += "go"
      Verbose-Log "Found go.mod - go stack"
    }

    # Pick primary stack by priority: python > node > rust > go
    $stackPriority = @('python', 'node', 'rust', 'go')
    foreach ($p in $stackPriority) {
      if ($allStacks -contains $p) {
        $stackDetected = $p
        break
      }
    }

    if ($allStacks.Count -gt 1) {
      Warn "Multiple stacks detected ($($allStacks -join ', ')). Using '$stackDetected'. Run 'strap setup --repo $repoName --stack <stack>' to use a different one."
    }

    # Detect Python version if Python stack
    if ($stackDetected -eq "python") {
      Verbose-Log "Detecting Python version requirement..."
      $pythonVersion = Get-PythonVersionFromFile -RepoPath $absolutePath
      if ($pythonVersion) {
        Info "Detected Python version: $pythonVersion"
        Verbose-Log "Python version detected: $pythonVersion"
      } else {
        Verbose-Log "No Python version requirement found"
      }
    }

    # Detect Node version if Node stack
    if ($stackDetected -eq "node") {
      Verbose-Log "Detecting Node version requirement..."
      $nodeVersion = Get-NodeVersionFromFile -RepoPath $absolutePath
      if ($nodeVersion) {
        Info "Detected Node version: $nodeVersion"
        Verbose-Log "Node version detected: $nodeVersion"
      } else {
        Verbose-Log "No Node version requirement found"
      }
    }
  } finally {
    Pop-Location
  }

  Verbose-Log "Stack detection complete: $($stackDetected ? $stackDetected : 'none')"

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
    python_version  = $pythonVersion
    node_version    = $nodeVersion
    created_at      = $timestamp
    updated_at      = $timestamp
  }

  Verbose-Log "Created registry entry: $repoName"
  Verbose-Log "  Path: $absolutePath"
  Verbose-Log "  Stack: $($stackDetected ? $stackDetected : 'none')"
  if ($pythonVersion) { Verbose-Log "  Python version: $pythonVersion" }
  if ($nodeVersion) { Verbose-Log "  Node version: $nodeVersion" }

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

  # Run setup automatically (unless --skip-setup)
  $setupSucceeded = $false
  $setupError = $null
  if (-not $SkipSetup -and $stackDetected) {
    Write-Host ""
    Info "Running automatic setup for $stackDetected stack..."
    Verbose-Log "Invoking setup with NonInteractive mode..."
    Push-Location $absolutePath
    try {
      # Pass verbose flag to setup
      if ($script:VerboseClone) {
        Invoke-Setup -StrapRootPath $StrapRootPath -NonInteractive -VerboseLogging
      } else {
        Invoke-Setup -StrapRootPath $StrapRootPath -NonInteractive
      }
      $setupSucceeded = $true
      Verbose-Log "Setup completed successfully"
    } catch {
      $setupError = $_.Exception.Message
      Warn "Setup failed: $_"
      Verbose-Log "Setup error: $setupError"
      Warn "You can run 'strap setup --repo $repoName' manually"
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
  Verbose-Log "Running auto-discovery for shims..."
  $autoShims = Invoke-ShimAutoDiscover -RepoEntry $entry -Config $config -Registry $newRegistry
  Verbose-Log "Auto-discovery found $($autoShims.Count) shim(s)"
  if ($autoShims.Count -gt 0) {
    foreach ($shim in $autoShims) {
      Verbose-Log "  - $($shim.name) ($($shim.type)): $($shim.exe)"
    }
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
    Verbose-Log "Saving registry with updated shims..."
    Save-Registry $config $finalRegistry
  } else {
    Verbose-Log "No shims auto-discovered"
  }

  Ok "Added to registry"

  # Validate shims (Tier 1 + 2) unless skipped
  if (-not $SkipValidation -and $autoShims.Count -gt 0) {
    Write-Host ""
    Write-Host "Validating shims..." -ForegroundColor Cyan
    Verbose-Log "Running Tier 1+2 validation on $($autoShims.Count) shim(s)..."

    $validationSummary = Invoke-RepoValidation -RepoEntry $entry -Config $config -Tiers @(1, 2) -TimeoutSeconds 10 -Quiet:$false

    if ($validationSummary.failedCount -gt 0) {
      Write-Host ""
      Write-Host "⚠ $($validationSummary.failedCount) shim(s) failed validation" -ForegroundColor Yellow
      Write-Host "Run 'strap verify $repoName' for detailed diagnostics" -ForegroundColor Yellow
    } else {
      Verbose-Log "All shims validated successfully"
    }
  } elseif ($SkipValidation) {
    Verbose-Log "Validation skipped (--skip-validation)"
  }

  if (-not $SkipSetup -and $stackDetected -and $autoShims.Count -gt 0) {
    Write-Host ""
    Ok "Ready to use! Try: $($autoShims[0].name) --help"
  } elseif ($autoShims.Count -eq 0) {
    Info "Next steps:"
    Info "  strap shim <name> --exe <path> --repo $repoName  # Create shims manually if needed"
  }
}

