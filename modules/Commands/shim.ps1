# shim.ps1
# Command: Invoke-Shim

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

