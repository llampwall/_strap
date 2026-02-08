# setup.ps1
# Command: Invoke-Setup

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
        return
      } else {
        Die "No recognized stack detected. Use --stack to force selection."
      }
    } elseif ($detectedStacks.Count -gt 1) {
      Write-Host ""
      Write-Host "Multiple stacks detected: $($detectedStacks -join ', ')" -ForegroundColor Yellow
      Write-Host "Use --stack <stack> to select one" -ForegroundColor Yellow
      Pop-Location
      Die "Setup failed"
    } else {
      $stack = $detectedStacks[0]
      Info "Detected stack: $stack"
    }

    if ($dockerDetected -and -not $ForceStack) {
      Write-Host "  (Docker also detected; not auto-running)" -ForegroundColor Yellow
    }

    # Python version management via pyenv
    $detectedPythonVersion = $null
    $pyenvPythonPath = $null

    if ($stack -eq "python") {
      # Detect required Python version
      $detectedPythonVersion = Get-PythonVersionFromFile -RepoPath $resolvedPath

      if ($detectedPythonVersion) {
        Info "Detected Python version requirement: $detectedPythonVersion"

        # Check if pyenv is installed
        if (Test-PyenvInstalled) {
          # Check if this version is already installed
          $installedVersions = Get-PyenvVersions
          if ($installedVersions -notcontains $detectedPythonVersion) {
            Write-Host "  Installing Python $detectedPythonVersion via pyenv..." -ForegroundColor Cyan
            $installSuccess = Install-PyenvVersion -Version $detectedPythonVersion

            if (-not $installSuccess) {
              Write-Host ""
              Write-Host "  Failed to install Python $detectedPythonVersion" -ForegroundColor Red
              Write-Host "  Please install manually and try again" -ForegroundColor Yellow
              Pop-Location
              Die "Setup failed"
            }
          } else {
            Info "Python $detectedPythonVersion already installed"
          }

          # Set local version for this repo
          $setSuccess = Set-PyenvLocalVersion -RepoPath $resolvedPath -Version $detectedPythonVersion
          if (-not $setSuccess) {
            Write-Host "  Warning: Failed to set local Python version" -ForegroundColor Yellow
          }

          # Get path to pyenv's Python executable
          $pyenvPythonPath = Get-PyenvPythonPath -Version $detectedPythonVersion
          if ($pyenvPythonPath) {
            Info "Using Python: $pyenvPythonPath"
          }
        } else {
          Write-Host ""
          Write-Host "  [!] Python version $detectedPythonVersion required but pyenv-win not installed" -ForegroundColor Yellow
          Write-Host "  Run 'strap doctor' to install pyenv-win, or install Python manually" -ForegroundColor Yellow
          Write-Host ""
        }
      }
    }

    # Generate install plan
    $plan = @()

    switch ($stack) {
      "python" {
        # Defaults
        $venvDir = if ($VenvPath) { $VenvPath } else { ".venv" }

        # Use pyenv Python if detected, otherwise fall back to user-specified or default
        if ($pyenvPythonPath -and -not $PythonExe) {
          $pythonCmd = "& '$pyenvPythonPath'"
        } elseif ($PythonExe) {
          $pythonCmd = $PythonExe
        } else {
          $pythonCmd = "python"
        }

        # Default to pip (more conservative/reliable), users can opt-in to uv with --use-uv
        $useUvFlag = if ($PSBoundParameters.ContainsKey('UseUv')) { $UseUv } else { $false }

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
      return
    }

    # Confirmation
    if (-not $NonInteractive) {
      $response = Read-Host "Proceed with setup? (y/n)"
      if ($response -ne "y") {
        Info "Aborted by user"
        Pop-Location
        Die "Setup failed"
      }
    }

    # Execute plan
    Write-Host "=== EXECUTING ===" -ForegroundColor Cyan
    foreach ($step in $plan) {
      Info $step.Description
      Write-Host "  > $($step.Command)" -ForegroundColor Gray

      # Execute command using pwsh to avoid Invoke-Expression issues
      # This properly handles quoted paths and special characters
      $output = pwsh -NoProfile -Command $step.Command 2>&1
      if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: Command failed with exit code $LASTEXITCODE" -ForegroundColor Red
        Write-Host $output
        Pop-Location
        Die "Setup failed"
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

        # Update stack array
        if (-not $currentEntry.PSObject.Properties['stack']) {
          $currentEntry | Add-Member -NotePropertyName 'stack' -NotePropertyValue @() -Force
        }
        if ($currentEntry.stack -notcontains $stack) {
          $currentEntry.stack = @($stack)
        }

        # Update Python version if detected
        if ($detectedPythonVersion) {
          if ($currentEntry.PSObject.Properties['python_version']) {
            $currentEntry.python_version = $detectedPythonVersion
          } else {
            $currentEntry | Add-Member -NotePropertyName 'python_version' -NotePropertyValue $detectedPythonVersion -Force
          }
        }

        # Update setup status (nested object)
        $setupStatus = [PSCustomObject]@{
          result = "succeeded"
          error = $null
          last_attempt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        if ($currentEntry.PSObject.Properties['setup']) {
          $currentEntry.setup = $setupStatus
        } else {
          $currentEntry | Add-Member -NotePropertyName 'setup' -NotePropertyValue $setupStatus -Force
        }

        # Save registry
        try {
          Save-Registry $config $registry
          Write-Host "  registry updated" -ForegroundColor Green
        } catch {
          Write-Host "  ERROR updating registry: $_" -ForegroundColor Red
          Pop-Location
          Die "Setup failed"
        }
      }
    }

    Pop-Location
    return

  } catch {
    Write-Host ""
    Write-Host "ERROR: $_" -ForegroundColor Red

    # Update registry with failure status if entry exists
    if ($registryEntry) {
      $entryIndex = -1
      for ($i = 0; $i -lt $registry.Count; $i++) {
        if ($registry[$i].id -eq $registryEntry.id) {
          $entryIndex = $i
          break
        }
      }

      if ($entryIndex -ne -1) {
        $currentEntry = $registry[$entryIndex]
        $setupStatus = [PSCustomObject]@{
          result = "failed"
          error = $_.Exception.Message
          last_attempt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        if ($currentEntry.PSObject.Properties['setup']) {
          $currentEntry.setup = $setupStatus
        } else {
          $currentEntry | Add-Member -NotePropertyName 'setup' -NotePropertyValue $setupStatus -Force
        }
        try {
          Save-Registry $config $registry
        } catch {}
      }
    }

    Pop-Location
    Die "Setup failed"
  }
}

