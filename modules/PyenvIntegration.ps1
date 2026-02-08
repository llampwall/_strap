# PyenvIntegration.ps1 - Python version management via pyenv-win

function Get-VendoredPyenvPath {
    <#
    .SYNOPSIS
    Gets the path to the vendored pyenv-win installation.

    .OUTPUTS
    String path to vendored pyenv-win directory.
    #>
    return "P:\software\_python-tools\pyenv-win"
}

function Get-PythonVersionsPath {
    <#
    .SYNOPSIS
    Gets the path where Python versions are stored by pyenv-win.

    .OUTPUTS
    String path to Python versions directory.
    #>
    # pyenv-win doesn't respect PYENV_ROOT for installations
    # It always uses pyenv-win\versions regardless of environment variables
    $vendorPath = Get-VendoredPyenvPath
    return Join-Path $vendorPath "pyenv-win\versions"
}

function Install-PyenvWin {
    <#
    .SYNOPSIS
    Installs pyenv-win to the vendored location.

    .PARAMETER Force
    Force reinstallation even if already exists.

    .OUTPUTS
    Boolean indicating success.
    #>
    param(
        [switch]$Force
    )

    $vendorPath = Get-VendoredPyenvPath
    $pythonVersionsPath = Get-PythonVersionsPath

    # Check if already installed
    if ((Test-Path $vendorPath) -and -not $Force) {
        Write-Host "  pyenv-win already installed at $vendorPath" -ForegroundColor Yellow
        return $true
    }

    Write-Host "  Installing pyenv-win to $vendorPath..." -ForegroundColor Cyan

    # Create parent directory
    $parentDir = Split-Path $vendorPath -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }

    # Remove existing if forcing reinstall
    if ((Test-Path $vendorPath) -and $Force) {
        Write-Host "  Removing existing installation..." -ForegroundColor Gray
        Remove-Item -Path $vendorPath -Recurse -Force
    }

    try {
        # Clone pyenv-win repository
        Write-Host "  Cloning pyenv-win repository..." -ForegroundColor Gray
        $gitOutput = & git clone https://github.com/pyenv-win/pyenv-win.git $vendorPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [X] Failed to clone pyenv-win" -ForegroundColor Red
            Write-Host $gitOutput
            return $false
        }

        # Create Python versions directory if it doesn't exist
        if (-not (Test-Path $pythonVersionsPath)) {
            New-Item -Path $pythonVersionsPath -ItemType Directory -Force | Out-Null
            Write-Host "  Created Python versions directory: $pythonVersionsPath" -ForegroundColor Gray
        }

        # Configure pyenv-win to use custom Python versions path
        # This is done via PYENV_ROOT environment variable, which we'll set in the shim

        Write-Host "  [OK] pyenv-win installed successfully" -ForegroundColor Green
        Write-Host "  Location: $vendorPath" -ForegroundColor Gray
        Write-Host "  Python versions will be stored in: $pythonVersionsPath" -ForegroundColor Gray

        return $true

    } catch {
        Write-Host "  [X] Error installing pyenv-win: $_" -ForegroundColor Red
        return $false
    }
}

function Test-PyenvInstalled {
    <#
    .SYNOPSIS
    Checks if pyenv-win is installed and available.

    .OUTPUTS
    Boolean indicating if pyenv is available.
    #>
    # Check vendored location first
    $vendorPath = Get-VendoredPyenvPath
    $vendorBin = Join-Path $vendorPath "pyenv-win\bin\pyenv.bat"

    if (Test-Path $vendorBin) {
        return $true
    }

    # Fall back to checking PATH
    $pyenvCmd = Get-Command pyenv -ErrorAction SilentlyContinue
    return $null -ne $pyenvCmd
}

function Get-PyenvCommand {
    <#
    .SYNOPSIS
    Gets the path to the pyenv executable.

    .OUTPUTS
    String path to pyenv executable or 'pyenv' if in PATH.
    #>
    # Check vendored location first
    $vendorPath = Get-VendoredPyenvPath
    $vendorBin = Join-Path $vendorPath "pyenv-win\bin\pyenv.bat"

    if (Test-Path $vendorBin) {
        return $vendorBin
    }

    # Fall back to PATH
    $pyenvCmd = Get-Command pyenv -ErrorAction SilentlyContinue
    if ($pyenvCmd) {
        return $pyenvCmd.Source
    }

    return $null
}

function Get-PythonVersionFromFile {
    <#
    .SYNOPSIS
    Detects required Python version from project files.

    .PARAMETER RepoPath
    Path to the repository root.

    .OUTPUTS
    String with Python version (e.g., "3.11.9") or $null if not found.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RepoPath
    )

    # 1. Check .python-version file (highest priority)
    $pythonVersionFile = Join-Path $RepoPath ".python-version"
    if (Test-Path $pythonVersionFile) {
        $version = (Get-Content $pythonVersionFile -Raw).Trim()

        # Handle both "3.11.9" and "3.11" formats
        if ($version -match '^\d+\.\d+\.\d+$') {
            Write-Verbose "Found Python version in .python-version: $version"
            return $version
        } elseif ($version -match '^\d+\.\d+$') {
            # Major.minor only - query pyenv for latest stable patch version
            $latestPatch = Get-LatestPyenvVersion -MajorMinor $version
            if ($latestPatch) {
                Write-Verbose "Found Python version in .python-version: $version (using $latestPatch from pyenv)"
                return $latestPatch
            } else {
                # Fallback to .0 if can't query pyenv
                $fullVersion = "$version.0"
                Write-Verbose "Found Python version in .python-version: $version (using $fullVersion as fallback)"
                return $fullVersion
            }
        }
    }

    # 2. Check pyproject.toml for requires-python
    $pyprojectPath = Join-Path $RepoPath "pyproject.toml"
    if (Test-Path $pyprojectPath) {
        $content = Get-Content $pyprojectPath -Raw

        # Match requires-python = ">=3.11" or "^3.11" or "~=3.11.0"
        if ($content -match "requires-python\s*=\s*[`"']([~^>=<]+)?(\d+\.\d+(?:\.\d+)?)[`"']") {
            $versionSpec = $matches[2]

            # If only major.minor, try to find latest patch version
            if ($versionSpec -match '^\d+\.\d+$') {
                Write-Verbose "Found Python version spec in pyproject.toml: $versionSpec (will use latest patch)"
                return "$versionSpec.0"  # Default to .0 patch version
            } else {
                Write-Verbose "Found Python version in pyproject.toml: $versionSpec"
                return $versionSpec
            }
        }
    }

    # 3. Check requirements.txt for python_version comment
    $requirementsPath = Join-Path $RepoPath "requirements.txt"
    if (Test-Path $requirementsPath) {
        $content = Get-Content $requirementsPath -Raw

        # Match # python_version: 3.11.9 or # requires python >= 3.11
        if ($content -match '#.*python[_\s]*version:?\s*(\d+\.\d+\.\d+)') {
            $version = $matches[1]
            Write-Verbose "Found Python version in requirements.txt: $version"
            return $version
        }
    }

    Write-Verbose "No Python version found in project files"
    return $null
}

function Get-PyenvVersions {
    <#
    .SYNOPSIS
    Gets list of Python versions installed via pyenv.

    .OUTPUTS
    Array of version strings (e.g., @("3.11.9", "3.12.0"))
    #>
    $pyenvCmd = Get-PyenvCommand
    if (-not $pyenvCmd) {
        return @()
    }

    try {
        $output = & $pyenvCmd versions --bare 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $output | Where-Object { $_ -match '^\d+\.\d+\.\d+$' }
        }
    } catch {
        Write-Verbose "Failed to get pyenv versions: $_"
    }

    return @()
}

function Get-LatestPyenvVersion {
    <#
    .SYNOPSIS
    Finds the latest stable patch version for a given major.minor version.

    .PARAMETER MajorMinor
    Major.minor version (e.g., "3.11")

    .OUTPUTS
    String with latest patch version (e.g., "3.11.9") or $null if not found.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$MajorMinor
    )

    $pyenvCmd = Get-PyenvCommand
    if (-not $pyenvCmd) {
        return $null
    }

    try {
        # Get list of all available versions
        $output = & $pyenvCmd install --list 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        # Filter to stable versions matching major.minor (e.g., "3.11.9", not "3.11.0rc1")
        $pattern = "^\s*$MajorMinor\.(\d+)$"
        $matches = $output | Where-Object { $_ -match $pattern }

        if ($matches) {
            # Get the last one (highest patch version)
            $latest = $matches | Select-Object -Last 1
            $latest = $latest.Trim()
            Write-Verbose "Found latest version for $MajorMinor : $latest"
            return $latest
        }
    } catch {
        Write-Verbose "Failed to query pyenv versions: $_"
    }

    return $null
}

function Install-PyenvVersion {
    <#
    .SYNOPSIS
    Installs a Python version using pyenv.

    .PARAMETER Version
    Python version to install (e.g., "3.11.9").

    .OUTPUTS
    Boolean indicating success.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $pyenvCmd = Get-PyenvCommand
    if (-not $pyenvCmd) {
        Write-Host "  [!] pyenv-win not installed - run 'strap doctor' to install" -ForegroundColor Yellow
        return $false
    }

    Write-Host "  Installing Python $Version via pyenv..." -ForegroundColor Cyan

    try {
        & $pyenvCmd install $Version
        if ($LASTEXITCODE -eq 0) {
            # Validate that Python actually works
            $pythonPath = Get-PyenvPythonPath -Version $Version
            if ($pythonPath -and (Test-Path $pythonPath)) {
                try {
                    $testOutput = & $pythonPath --version 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "  [OK] Python $Version installed and validated" -ForegroundColor Green
                        return $true
                    } else {
                        Write-Host "  [X] Python $Version installed but fails to execute (exit code: $LASTEXITCODE)" -ForegroundColor Red
                        return $false
                    }
                } catch {
                    Write-Host "  [X] Python $Version installed but fails to execute: $_" -ForegroundColor Red
                    return $false
                }
            } else {
                Write-Host "  [X] Python $Version installed but executable not found at expected location" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "  [X] Failed to install Python $Version" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  [X] Error installing Python $Version : $_" -ForegroundColor Red
        return $false
    }
}

function Set-PyenvLocalVersion {
    <#
    .SYNOPSIS
    Sets the local Python version for a repository.

    .PARAMETER RepoPath
    Path to the repository.

    .PARAMETER Version
    Python version to set (e.g., "3.11.9").

    .OUTPUTS
    Boolean indicating success.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RepoPath,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $pyenvCmd = Get-PyenvCommand
    if (-not $pyenvCmd) {
        Write-Host "  [!] pyenv-win not installed" -ForegroundColor Yellow
        return $false
    }

    Push-Location $RepoPath
    try {
        $env:PYENV_ROOT = Get-PythonVersionsPath
        & $pyenvCmd local $Version
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] Set local Python version to $Version" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  [X] Failed to set local Python version" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  [X] Error setting local Python version: $_" -ForegroundColor Red
        return $false
    } finally {
        Remove-Item Env:\PYENV_ROOT -ErrorAction SilentlyContinue
        Pop-Location
    }
}

function Get-PyenvPythonPath {
    <#
    .SYNOPSIS
    Gets the path to Python executable for a specific version.

    .PARAMETER Version
    Python version (e.g., "3.11.9").

    .OUTPUTS
    String path to python.exe or $null if not found.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $pyenvCmd = Get-PyenvCommand
    if (-not $pyenvCmd) {
        return $null
    }

    try {
        # Use our custom Python versions path
        $pyenvRoot = Get-PythonVersionsPath
        $pythonPath = Join-Path $pyenvRoot "$Version\python.exe"

        if (Test-Path $pythonPath) {
            return $pythonPath
        }
    } catch {
        Write-Verbose "Failed to get pyenv Python path: $_"
    }

    return $null
}

function New-PyenvShim {
    <#
    .SYNOPSIS
    Creates system-wide shim for pyenv command.

    .PARAMETER ShimsDir
    Directory where shims are stored (e.g., P:\software\bin).

    .OUTPUTS
    Boolean indicating success.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ShimsDir
    )

    $vendorPath = Get-VendoredPyenvPath
    $pyenvBat = Join-Path $vendorPath "pyenv-win\bin\pyenv.bat"
    $pythonVersionsPath = Get-PythonVersionsPath

    if (-not (Test-Path $pyenvBat)) {
        Write-Host "  [X] pyenv-win not found at $vendorPath" -ForegroundColor Red
        return $false
    }

    # Create shims directory if needed
    if (-not (Test-Path $ShimsDir)) {
        New-Item -Path $ShimsDir -ItemType Directory -Force | Out-Null
    }

    $ps1Path = Join-Path $ShimsDir "pyenv.ps1"
    $cmdPath = Join-Path $ShimsDir "pyenv.cmd"

    # PowerShell shim
    $ps1Content = @"
# pyenv.ps1 - System-wide shim for vendored pyenv-win
`$env:PYENV = "$vendorPath"
`$env:PYENV_ROOT = "$pythonVersionsPath"
`$env:PYENV_HOME = "$vendorPath"

& "$pyenvBat" `$args
exit `$LASTEXITCODE
"@

    # CMD wrapper
    $cmdContent = @"
@echo off
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1Path" %*
"@

    try {
        Set-Content -Path $ps1Path -Value $ps1Content -Encoding UTF8
        Set-Content -Path $cmdPath -Value $cmdContent -Encoding ASCII

        Write-Host "  [OK] Created pyenv shim" -ForegroundColor Green
        Write-Host "  PowerShell: $ps1Path" -ForegroundColor Gray
        Write-Host "  CMD: $cmdPath" -ForegroundColor Gray

        return $true
    } catch {
        Write-Host "  [X] Failed to create pyenv shim: $_" -ForegroundColor Red
        return $false
    }
}
