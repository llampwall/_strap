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
    [switch] $VerboseLogging,
    [string] $StrapRootPath
  )

  # Enable verbose output if requested
  $script:VerboseSetup = $VerboseLogging

  function Verbose-Log {
    param([string]$Message)
    if ($script:VerboseSetup) {
      Write-Host "  [VERBOSE] $Message" -ForegroundColor DarkGray
    }
  }

  # Load config and registry
  Verbose-Log "Loading config and registry..."
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config
  Verbose-Log "Config loaded from: $($config.strap_root)\config.json"
  Verbose-Log "Registry loaded with $($registry.Count) entries"

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
    Verbose-Log "Scanning for stack markers in $resolvedPath..."
    $detectedStacks = @()

    if (Test-Path "pyproject.toml") {
      $detectedStacks += "python"
      Verbose-Log "Found pyproject.toml - Python stack detected"
    }
    elseif (Test-Path "requirements.txt") {
      $detectedStacks += "python"
      Verbose-Log "Found requirements.txt - Python stack detected"
    }

    if (Test-Path "package.json") {
      $detectedStacks += "node"
      Verbose-Log "Found package.json - Node stack detected"
    }
    if (Test-Path "Cargo.toml") {
      $detectedStacks += "rust"
      Verbose-Log "Found Cargo.toml - Rust stack detected"
    }
    if (Test-Path "go.mod") {
      $detectedStacks += "go"
      Verbose-Log "Found go.mod - Go stack detected"
    }

    $dockerDetected = $false
    if ((Test-Path "Dockerfile") -or (Test-Path "compose.yaml") -or (Test-Path "docker-compose.yml")) {
      $dockerDetected = $true
      Verbose-Log "Docker files detected"
    }

    Verbose-Log "Stack detection complete: $($detectedStacks -join ', ')"

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

    # Node version management via fnm
    $detectedNodeVersion = $null
    $fnmNodePath = $null

    if ($stack -eq "node") {
      # Detect required Node version
      Verbose-Log "Detecting Node version requirement..."
      $detectedNodeVersion = Get-NodeVersionFromFile -RepoPath $resolvedPath

      if ($detectedNodeVersion) {
        Info "Detected Node version requirement: $detectedNodeVersion"
        Verbose-Log "Checking if fnm is installed..."

        # Check if fnm is installed
        if (Test-FnmInstalled) {
          Verbose-Log "fnm is installed"
          # Check if this version is already installed
          Verbose-Log "Checking installed Node versions..."
          $installedVersions = Get-FnmVersions
          Verbose-Log "Installed versions: $($installedVersions -join ', ')"
          if ($installedVersions -notcontains $detectedNodeVersion) {
            Write-Host "  Installing Node $detectedNodeVersion via fnm..." -ForegroundColor Cyan
            Verbose-Log "Running: fnm install $detectedNodeVersion"
            $installSuccess = Install-FnmVersion -Version $detectedNodeVersion

            if (-not $installSuccess) {
              Write-Host ""
              Write-Host "  Failed to install Node $detectedNodeVersion" -ForegroundColor Red
              Write-Host "  Please install manually and try again" -ForegroundColor Yellow
              Pop-Location
              Die "Setup failed"
            }
          } else {
            Info "Node $detectedNodeVersion already installed"
          }

          # Get path to fnm's Node executable
          $fnmNodePath = Get-FnmNodePath -Version $detectedNodeVersion
          if ($fnmNodePath) {
            Info "Using Node: $fnmNodePath"
          }
        } else {
          Write-Host ""
          Write-Host "  [!] Node version $detectedNodeVersion required but fnm not installed" -ForegroundColor Yellow
          Write-Host "  Run 'strap doctor --install-fnm' to install fnm, or install Node manually" -ForegroundColor Yellow
          Write-Host ""
        }
      }
    }

    # Python version management via pyenv
    $detectedPythonVersion = $null
    $pyenvPythonPath = $null

    if ($stack -eq "python") {
      # Detect required Python version
      Verbose-Log "Detecting Python version requirement..."
      $detectedPythonVersion = Get-PythonVersionFromFile -RepoPath $resolvedPath

      if ($detectedPythonVersion) {
        Info "Detected Python version requirement: $detectedPythonVersion"
        Verbose-Log "Checking if pyenv-win is installed..."

        # Check if pyenv is installed
        if (Test-PyenvInstalled) {
          Verbose-Log "pyenv-win is installed"
          # Check if this version is already installed
          Verbose-Log "Checking installed Python versions..."
          $installedVersions = Get-PyenvVersions
          Verbose-Log "Installed versions: $($installedVersions -join ', ')"
          if ($installedVersions -notcontains $detectedPythonVersion) {
            Write-Host "  Installing Python $detectedPythonVersion via pyenv..." -ForegroundColor Cyan
            Verbose-Log "Running: pyenv install $detectedPythonVersion"
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
        $pm = $PackageManager

        # Determine if corepack is needed
        # Only enable corepack if:
        # 1. User explicitly requested it via --enable-corepack, OR
        # 2. package.json has a packageManager field (indicates corepack usage)
        $needsCorepack = $false
        $packageJsonPath = Join-Path $resolvedPath "package.json"
        if (Test-Path $packageJsonPath) {
          try {
            $packageJson = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
            if ($packageJson.PSObject.Properties['packageManager']) {
              $needsCorepack = $true
            }
          } catch {
            # Ignore JSON parse errors
          }
        }

        # Override if user explicitly set the flag
        if ($PSBoundParameters.ContainsKey('EnableCorepack')) {
          $needsCorepack = $EnableCorepack
        }

        # Step 1: Enable corepack (if needed)
        if ($needsCorepack) {
          # If no specific Node version was detected, find any installed fnm Node.
          # Without this, corepack runs in the global PATH (nvm's Node) and fails
          # with EPERM trying to write shims into the nvm directory.
          if (-not $fnmNodePath -and (Test-FnmInstalled)) {
            $installedVersions = Get-FnmVersions
            if ($installedVersions -and $installedVersions.Count -gt 0) {
              $fallbackVersion = @($installedVersions | Sort-Object { [version]$_ })[-1]
              $fnmNodePath = Get-FnmNodePath -Version $fallbackVersion
              if ($fnmNodePath) {
                Verbose-Log "No Node version required; using fnm $fallbackVersion for corepack environment"
              }
            }
          }

          # Use fnm-managed Node's corepack if available
          if ($fnmNodePath) {
            $nodeDir = Split-Path $fnmNodePath -Parent
            $corepackPath = Join-Path $nodeDir "corepack.cmd"
            if (Test-Path $corepackPath) {
              $corepackCmd = "& '$corepackPath' enable"
            } else {
              Warn "corepack.cmd not found in fnm Node directory, using global"
              $corepackCmd = "corepack enable"
            }
          } else {
            $corepackCmd = "corepack enable"
          }

          $plan += @{
            Description = "Enable corepack"
            Command = $corepackCmd
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

        # Step 3: Run build step if present
        $packageJsonPath = Join-Path $resolvedPath "package.json"
        if (Test-Path $packageJsonPath) {
          try {
            $packageJson = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
            if ($packageJson.scripts.build) {
              $plan += @{
                Description = "Build project"
                Command = "$pm run build"
              }
            } elseif ($packageJson.scripts.prepare) {
              $plan += @{
                Description = "Prepare project"
                Command = "$pm run prepare"
              }
            }
          } catch {
            # Ignore JSON parse errors
          }
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

    # Prepare environment for fnm-managed Node (if applicable)
    $nodeEnvSetup = ""
    if ($stack -eq "node" -and $fnmNodePath) {
      $nodeDir = Split-Path $fnmNodePath -Parent
      # Prepend fnm Node directory to PATH for this execution session
      $nodeEnvSetup = "`$env:PATH = '$nodeDir;' + `$env:PATH; "
    }

    foreach ($step in $plan) {
      Info $step.Description
      Write-Host "  > $($step.Command)" -ForegroundColor Gray
      Verbose-Log "Executing setup step: $($step.Description)"

      # Execute command using pwsh to avoid Invoke-Expression issues
      # This properly handles quoted paths and special characters
      # For Node projects with fnm, prepend the fnm Node directory to PATH
      $cmdWithEnv = if ($nodeEnvSetup) {
        Verbose-Log "Prepending fnm Node to PATH: $nodeEnvSetup"
        $nodeEnvSetup + $step.Command
      } else {
        $step.Command
      }

      Verbose-Log "Full command: pwsh -NoProfile -Command `"$cmdWithEnv`""
      $output = pwsh -NoProfile -Command $cmdWithEnv 2>&1

      if ($script:VerboseSetup) {
        Write-Host "  [VERBOSE] Command output:" -ForegroundColor DarkGray
        Write-Host $output -ForegroundColor DarkGray
      }

      if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: Command failed with exit code $LASTEXITCODE" -ForegroundColor Red
        Write-Host "Command: $($step.Command)" -ForegroundColor Yellow
        Write-Host "Output:" -ForegroundColor Yellow
        Write-Host $output
        Pop-Location
        Die "Setup failed at step: $($step.Description)"
      }

      Verbose-Log "Step completed successfully (exit code: $LASTEXITCODE)"
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

        # Update Node version if detected
        if ($detectedNodeVersion) {
          if ($currentEntry.PSObject.Properties['node_version']) {
            $currentEntry.node_version = $detectedNodeVersion
          } else {
            $currentEntry | Add-Member -NotePropertyName 'node_version' -NotePropertyValue $detectedNodeVersion -Force
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

