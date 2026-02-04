# modules/Consolidate.ps1
# Functions for the consolidate workflow

# Dependencies
$ModulesPath = $PSScriptRoot
. (Join-Path $ModulesPath "Core.ps1")
. (Join-Path $ModulesPath "Utils.ps1")
. (Join-Path $ModulesPath "Path.ps1")
. (Join-Path $ModulesPath "Config.ps1")
. (Join-Path $ModulesPath "Audit.ps1")

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

