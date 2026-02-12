# FnmIntegration.ps1 - Node version management via fnm

function Get-VendoredFnmPath {
    <#
    .SYNOPSIS
    Gets the path to the vendored fnm installation.

    .OUTPUTS
    String path to vendored fnm directory.
    #>
    return "P:\software\_node-tools\fnm"
}

function Get-NodeVersionsPath {
    <#
    .SYNOPSIS
    Gets the path where Node versions are stored by fnm.

    .OUTPUTS
    String path to Node versions directory.
    #>
    $vendorPath = Get-VendoredFnmPath
    # fnm stores versions in node-versions subdirectory
    return Join-Path $vendorPath "node-versions"
}

function Install-FnmBinary {
    <#
    .SYNOPSIS
    Installs fnm binary to the vendored location.

    .PARAMETER Force
    Force reinstallation even if already exists.

    .OUTPUTS
    Boolean indicating success.
    #>
    param(
        [switch]$Force
    )

    $vendorPath = Get-VendoredFnmPath
    $fnmExe = Join-Path $vendorPath "fnm.exe"
    $nodeVersionsPath = Get-NodeVersionsPath

    # Check if already installed
    if ((Test-Path $fnmExe) -and -not $Force) {
        Write-Host "  fnm already installed at $vendorPath" -ForegroundColor Yellow
        return $true
    }

    Write-Host "  Installing fnm to $vendorPath..." -ForegroundColor Cyan

    # Create vendor directory
    if (-not (Test-Path $vendorPath)) {
        New-Item -Path $vendorPath -ItemType Directory -Force | Out-Null
    }

    # Remove existing if forcing reinstall
    if ((Test-Path $fnmExe) -and $Force) {
        Write-Host "  Removing existing installation..." -ForegroundColor Gray
        Remove-Item -Path $fnmExe -Force
    }

    try {
        # Download fnm from GitHub releases
        $downloadUrl = "https://github.com/Schniz/fnm/releases/latest/download/fnm-windows.zip"
        $zipPath = Join-Path $vendorPath "fnm-windows.zip"

        Write-Host "  Downloading fnm from GitHub..." -ForegroundColor Gray
        try {
            # Use curl.exe to avoid PowerShell alias issues
            & curl.exe -L -o $zipPath $downloadUrl 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  [X] Failed to download fnm" -ForegroundColor Red
                return $false
            }
        } catch {
            Write-Host "  [X] Failed to download fnm: $_" -ForegroundColor Red
            return $false
        }

        # Extract zip
        Write-Host "  Extracting fnm binary..." -ForegroundColor Gray
        try {
            Expand-Archive -Path $zipPath -DestinationPath $vendorPath -Force
            Remove-Item -Path $zipPath -Force
        } catch {
            Write-Host "  [X] Failed to extract fnm: $_" -ForegroundColor Red
            return $false
        }

        # Verify fnm.exe exists
        if (-not (Test-Path $fnmExe)) {
            Write-Host "  [X] fnm.exe not found after extraction" -ForegroundColor Red
            return $false
        }

        # Create node-versions directory if it doesn't exist
        if (-not (Test-Path $nodeVersionsPath)) {
            New-Item -Path $nodeVersionsPath -ItemType Directory -Force | Out-Null
            Write-Host "  Created Node versions directory: $nodeVersionsPath" -ForegroundColor Gray
        }

        Write-Host "  [OK] fnm installed successfully" -ForegroundColor Green
        Write-Host "  Location: $fnmExe" -ForegroundColor Gray
        Write-Host "  Node versions will be stored in: $nodeVersionsPath" -ForegroundColor Gray

        return $true

    } catch {
        Write-Host "  [X] Error installing fnm: $_" -ForegroundColor Red
        return $false
    }
}

function Test-FnmInstalled {
    <#
    .SYNOPSIS
    Checks if fnm is installed and available.

    .OUTPUTS
    Boolean indicating if fnm is available.
    #>
    # Check vendored location first
    $vendorPath = Get-VendoredFnmPath
    $vendorBin = Join-Path $vendorPath "fnm.exe"

    if (Test-Path $vendorBin) {
        return $true
    }

    # Fall back to checking PATH
    $fnmCmd = Get-Command fnm -ErrorAction SilentlyContinue
    return $null -ne $fnmCmd
}

function Get-FnmCommand {
    <#
    .SYNOPSIS
    Gets the path to the fnm executable.

    .OUTPUTS
    String path to fnm executable or $null if not found.
    #>
    # Check vendored location first
    $vendorPath = Get-VendoredFnmPath
    $vendorBin = Join-Path $vendorPath "fnm.exe"

    if (Test-Path $vendorBin) {
        return $vendorBin
    }

    # Fall back to PATH
    $fnmCmd = Get-Command fnm -ErrorAction SilentlyContinue
    if ($fnmCmd) {
        return $fnmCmd.Source
    }

    return $null
}

function Get-NodeVersionFromFile {
    <#
    .SYNOPSIS
    Detects required Node version from project files.

    .PARAMETER RepoPath
    Path to the repository root.

    .OUTPUTS
    String with Node version (e.g., "18.17.0") or $null if not found.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RepoPath
    )

    # 1. Check .nvmrc file (highest priority)
    $nvmrcFile = Join-Path $RepoPath ".nvmrc"
    if (Test-Path $nvmrcFile) {
        $version = (Get-Content $nvmrcFile -Raw).Trim()

        # Handle exact versions ("18.17.0"), major.minor ("18.17"), or lts aliases
        if ($version -match '^v?(\d+\.\d+\.\d+)$') {
            $cleanVersion = $matches[1]
            Write-Verbose "Found Node version in .nvmrc: $cleanVersion"
            return $cleanVersion
        } elseif ($version -match '^v?(\d+\.\d+)$') {
            # Major.minor only - query fnm for latest patch version
            $majorMinor = $matches[1]
            $latestPatch = Get-LatestFnmVersion -MajorMinor $majorMinor
            if ($latestPatch) {
                Write-Verbose "Found Node version in .nvmrc: $majorMinor (using $latestPatch from fnm)"
                return $latestPatch
            } else {
                # Fallback to .0 if can't query fnm
                $fullVersion = "$majorMinor.0"
                Write-Verbose "Found Node version in .nvmrc: $majorMinor (using $fullVersion as fallback)"
                return $fullVersion
            }
        } elseif ($version -match '^lts/(.+)$') {
            # Handle lts/version-name (e.g., lts/hydrogen)
            Write-Verbose "Found LTS alias in .nvmrc: $version (will use fnm to resolve)"
            # For now, return as-is and let fnm handle it
            return $version
        }
    }

    # 2. Check .node-version file
    $nodeVersionFile = Join-Path $RepoPath ".node-version"
    if (Test-Path $nodeVersionFile) {
        $version = (Get-Content $nodeVersionFile -Raw).Trim()

        # Same logic as .nvmrc
        if ($version -match '^v?(\d+\.\d+\.\d+)$') {
            $cleanVersion = $matches[1]
            Write-Verbose "Found Node version in .node-version: $cleanVersion"
            return $cleanVersion
        } elseif ($version -match '^v?(\d+\.\d+)$') {
            $majorMinor = $matches[1]
            $latestPatch = Get-LatestFnmVersion -MajorMinor $majorMinor
            if ($latestPatch) {
                Write-Verbose "Found Node version in .node-version: $majorMinor (using $latestPatch from fnm)"
                return $latestPatch
            } else {
                $fullVersion = "$majorMinor.0"
                Write-Verbose "Found Node version in .node-version: $majorMinor (using $fullVersion as fallback)"
                return $fullVersion
            }
        }
    }

    # 3. Check package.json engines.node field
    $packageJsonPath = Join-Path $RepoPath "package.json"
    if (Test-Path $packageJsonPath) {
        try {
            $packageJson = Get-Content $packageJsonPath -Raw | ConvertFrom-Json

            if ($packageJson.engines -and $packageJson.engines.node) {
                $nodeSpec = $packageJson.engines.node

                # Handle exact versions, ranges, or comparisons
                # Match: "18.17.0", ">=18.0.0", "^18.17.0", "~18.17.0", ">=20.19.0"
                if ($nodeSpec -match '(\d+\.\d+\.\d+)') {
                    $version = $matches[1]
                    Write-Verbose "Found Node version in package.json engines: $version"
                    return $version
                } elseif ($nodeSpec -match '(\d+\.\d+)') {
                    # Major.minor only
                    $majorMinor = $matches[1]
                    $latestPatch = Get-LatestFnmVersion -MajorMinor $majorMinor
                    if ($latestPatch) {
                        Write-Verbose "Found Node version spec in package.json: $majorMinor (using $latestPatch)"
                        return $latestPatch
                    } else {
                        $fullVersion = "$majorMinor.0"
                        Write-Verbose "Found Node version spec in package.json: $majorMinor (using $fullVersion as fallback)"
                        return $fullVersion
                    }
                }
            }
        } catch {
            Write-Verbose "Failed to parse package.json: $_"
        }
    }

    Write-Verbose "No Node version found in project files"
    return $null
}

function Get-FnmVersions {
    <#
    .SYNOPSIS
    Gets list of Node versions installed via fnm.

    .OUTPUTS
    Array of version strings (e.g., @("18.17.0", "20.19.0"))
    #>
    $fnmCmd = Get-FnmCommand
    if (-not $fnmCmd) {
        return @()
    }

    try {
        # Set FNM_DIR to vendored location
        $env:FNM_DIR = Get-VendoredFnmPath
        $output = & $fnmCmd list 2>$null
        Remove-Item Env:\FNM_DIR -ErrorAction SilentlyContinue

        if ($LASTEXITCODE -eq 0) {
            # Parse output - fnm list shows versions like "v18.17.0" or "* v20.19.0 default"
            return $output | ForEach-Object {
                if ($_ -match 'v?(\d+\.\d+\.\d+)') {
                    $matches[1]
                }
            } | Where-Object { $_ }
        }
    } catch {
        Write-Verbose "Failed to get fnm versions: $_"
        Remove-Item Env:\FNM_DIR -ErrorAction SilentlyContinue
    }

    return @()
}

function Get-LatestFnmVersion {
    <#
    .SYNOPSIS
    Finds the latest stable version for a given major.minor version.

    .PARAMETER MajorMinor
    Major.minor version (e.g., "18.17")

    .OUTPUTS
    String with latest patch version (e.g., "18.17.1") or $null if not found.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$MajorMinor
    )

    $fnmCmd = Get-FnmCommand
    if (-not $fnmCmd) {
        return $null
    }

    try {
        # Set FNM_DIR to vendored location
        $env:FNM_DIR = Get-VendoredFnmPath
        # Get list of all available versions from remote
        $output = & $fnmCmd list-remote 2>$null
        Remove-Item Env:\FNM_DIR -ErrorAction SilentlyContinue

        if ($LASTEXITCODE -ne 0) {
            return $null
        }

        # Filter to stable versions matching major.minor
        $pattern = "^v?$MajorMinor\.(\d+)$"
        $matches = $output | Where-Object { $_ -match $pattern }

        if ($matches) {
            # Get the last one (highest patch version)
            $latest = $matches | Select-Object -Last 1
            if ($latest -match 'v?(\d+\.\d+\.\d+)') {
                $version = $matches[1]
                Write-Verbose "Found latest version for $MajorMinor : $version"
                return $version
            }
        }
    } catch {
        Write-Verbose "Failed to query fnm versions: $_"
        Remove-Item Env:\FNM_DIR -ErrorAction SilentlyContinue
    }

    return $null
}

function Install-FnmVersion {
    <#
    .SYNOPSIS
    Installs a Node version using fnm.

    .PARAMETER Version
    Node version to install (e.g., "18.17.0" or "lts/hydrogen").

    .OUTPUTS
    Boolean indicating success.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $fnmCmd = Get-FnmCommand
    if (-not $fnmCmd) {
        Write-Host "  [!] fnm not installed - run 'strap doctor --install-fnm'" -ForegroundColor Yellow
        return $false
    }

    Write-Host "  Installing Node $Version via fnm..." -ForegroundColor Cyan

    try {
        # Set FNM_DIR to vendored location
        $env:FNM_DIR = Get-VendoredFnmPath
        & $fnmCmd install $Version
        $exitCode = $LASTEXITCODE
        Remove-Item Env:\FNM_DIR -ErrorAction SilentlyContinue

        if ($exitCode -eq 0) {
            # Validate that Node actually works
            $nodePath = Get-FnmNodePath -Version $Version
            if ($nodePath -and (Test-Path $nodePath)) {
                try {
                    $testOutput = & $nodePath --version 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "  [OK] Node $Version installed and validated" -ForegroundColor Green
                        return $true
                    } else {
                        Write-Host "  [X] Node $Version installed but fails to execute (exit code: $LASTEXITCODE)" -ForegroundColor Red
                        return $false
                    }
                } catch {
                    Write-Host "  [X] Node $Version installed but fails to execute: $_" -ForegroundColor Red
                    return $false
                }
            } else {
                Write-Host "  [X] Node $Version installed but executable not found at expected location" -ForegroundColor Red
                return $false
            }
        } else {
            Write-Host "  [X] Failed to install Node $Version" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "  [X] Error installing Node $Version : $_" -ForegroundColor Red
        Remove-Item Env:\FNM_DIR -ErrorAction SilentlyContinue
        return $false
    }
}

function Get-FnmNodePath {
    <#
    .SYNOPSIS
    Gets the path to Node executable for a specific version.

    .PARAMETER Version
    Node version (e.g., "18.17.0").

    .OUTPUTS
    String path to node.exe or $null if not found.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Version
    )

    $fnmCmd = Get-FnmCommand
    if (-not $fnmCmd) {
        return $null
    }

    try {
        # fnm stores versions in FNM_DIR/node-versions/v{version}/installation/node.exe
        $fnmDir = Get-VendoredFnmPath
        $nodeVersionsPath = Get-NodeVersionsPath

        # Try with 'v' prefix first
        $nodePath = Join-Path $nodeVersionsPath "v$Version\installation\node.exe"
        if (Test-Path $nodePath) {
            return $nodePath
        }

        # Try without 'v' prefix
        $nodePath = Join-Path $nodeVersionsPath "$Version\installation\node.exe"
        if (Test-Path $nodePath) {
            return $nodePath
        }

        # If version is an LTS alias, query fnm to find actual version
        if ($Version -match '^lts/') {
            $env:FNM_DIR = $fnmDir
            $output = & $fnmCmd list 2>$null
            Remove-Item Env:\FNM_DIR -ErrorAction SilentlyContinue

            # Find the installed version matching this alias
            foreach ($line in $output) {
                if ($line -match 'v?(\d+\.\d+\.\d+)') {
                    $installedVersion = $matches[1]
                    $nodePath = Join-Path $nodeVersionsPath "v$installedVersion\installation\node.exe"
                    if (Test-Path $nodePath) {
                        return $nodePath
                    }
                }
            }
        }
    } catch {
        Write-Verbose "Failed to get fnm Node path: $_"
    }

    return $null
}

function New-FnmShim {
    <#
    .SYNOPSIS
    Creates system-wide shim for fnm command.

    .PARAMETER ShimsDir
    Directory where shims are stored (e.g., P:\software\bin).

    .OUTPUTS
    Boolean indicating success.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ShimsDir
    )

    $vendorPath = Get-VendoredFnmPath
    $fnmExe = Join-Path $vendorPath "fnm.exe"
    $fnmDir = $vendorPath

    if (-not (Test-Path $fnmExe)) {
        Write-Host "  [X] fnm not found at $vendorPath" -ForegroundColor Red
        return $false
    }

    # Create shims directory if needed
    if (-not (Test-Path $ShimsDir)) {
        New-Item -Path $ShimsDir -ItemType Directory -Force | Out-Null
    }

    $ps1Path = Join-Path $ShimsDir "fnm.ps1"
    $cmdPath = Join-Path $ShimsDir "fnm.cmd"

    # PowerShell shim
    $ps1Content = @"
# fnm.ps1 - System-wide shim for vendored fnm
`$env:FNM_DIR = "$fnmDir"

& "$fnmExe" `$args
`$exitCode = `$LASTEXITCODE

Remove-Item Env:\FNM_DIR -ErrorAction SilentlyContinue
exit `$exitCode
"@

    # CMD wrapper
    $cmdContent = @"
@echo off
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1Path" %*
"@

    try {
        Set-Content -Path $ps1Path -Value $ps1Content -Encoding UTF8
        Set-Content -Path $cmdPath -Value $cmdContent -Encoding ASCII

        Write-Host "  [OK] Created fnm shim" -ForegroundColor Green
        Write-Host "  PowerShell: $ps1Path" -ForegroundColor Gray
        Write-Host "  CMD: $cmdPath" -ForegroundColor Gray

        return $true
    } catch {
        Write-Host "  [X] Failed to create fnm shim: $_" -ForegroundColor Red
        return $false
    }
}
