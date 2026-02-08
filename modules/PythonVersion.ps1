# PythonVersion.ps1
# Python version detection, installation, and management for strap

<#
.SYNOPSIS
Detects required Python version from project files.

.DESCRIPTION
Checks multiple sources in priority order:
1. .python-version file (exact version like "3.11.14" or constraint like ">=3.11")
2. pyproject.toml requires-python field
3. requirements.txt header comment (# requires: python>=3.11)

.PARAMETER RepoPath
Path to the repository to check

.OUTPUTS
String representing the version requirement (e.g., "3.11", ">=3.11", "3.11.14")
or $null if no version requirement found
#>
function Get-RequiredPythonVersion {
  param(
    [Parameter(Mandatory=$true)]
    [string] $RepoPath
  )

  # Check .python-version file
  $pythonVersionFile = Join-Path $RepoPath ".python-version"
  if (Test-Path $pythonVersionFile) {
    $content = (Get-Content $pythonVersionFile -Raw).Trim()
    if ($content) {
      Write-Verbose "Found .python-version: $content"
      return $content
    }
  }

  # Check pyproject.toml requires-python
  $pyprojectFile = Join-Path $RepoPath "pyproject.toml"
  if (Test-Path $pyprojectFile) {
    $content = Get-Content $pyprojectFile -Raw
    if ($content -match 'requires-python\s*=\s*[''"]([^''"]+)[''"]') {
      $version = $matches[1]
      Write-Verbose "Found requires-python in pyproject.toml: $version"
      return $version
    }
  }

  # Check requirements.txt header comment
  $requirementsFile = Join-Path $RepoPath "requirements.txt"
  if (Test-Path $requirementsFile) {
    $firstLine = Get-Content $requirementsFile -First 1
    if ($firstLine -match '#\s*requires?:\s*python\s*([><=!~]+)?\s*([\d.]+)') {
      $operator = $matches[1]
      $version = $matches[2]
      $requirement = if ($operator) { "$operator$version" } else { $version }
      Write-Verbose "Found python requirement in requirements.txt: $requirement"
      return $requirement
    }
  }

  return $null
}

<#
.SYNOPSIS
Parses a version requirement string into operator and version.

.DESCRIPTION
Parses strings like ">=3.11", "3.11.14", "~=3.10" into components.

.PARAMETER Requirement
Version requirement string (e.g., ">=3.11", "3.11.14")

.OUTPUTS
Hashtable with 'operator' and 'version' keys
#>
function Parse-VersionRequirement {
  param(
    [Parameter(Mandatory=$true)]
    [string] $Requirement
  )

  # Match operator and version
  if ($Requirement -match '^([><=!~]+)?\s*([\d.]+)$') {
    $operator = if ($matches[1]) { $matches[1] } else { "==" }
    $version = $matches[2]

    # Parse version parts
    $parts = $version.Split('.')
    $major = [int]$parts[0]
    $minor = if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 }
    $patch = if ($parts.Count -gt 2) { [int]$parts[2] } else { $null }

    return @{
      operator = $operator
      version = $version
      major = $major
      minor = $minor
      patch = $patch
    }
  }

  throw "Invalid version requirement format: $Requirement"
}

<#
.SYNOPSIS
Gets all Python versions available on the system.

.DESCRIPTION
Checks:
1. Managed versions in P:\software\_python-versions
2. System Python via py launcher

.OUTPUTS
Array of hashtables with 'version', 'path', and 'source' keys
#>
function Get-InstalledPythonVersions {
  param(
    [string] $ManagedRoot = "P:\software\_python-versions"
  )

  $versions = @()

  # Check managed versions
  if (Test-Path $ManagedRoot) {
    Get-ChildItem $ManagedRoot -Directory | ForEach-Object {
      $versionDir = $_
      $pythonExe = Join-Path $versionDir.FullName "python.exe"
      if (Test-Path $pythonExe) {
        try {
          $versionOutput = & $pythonExe --version 2>&1 | Out-String
          if ($versionOutput -match 'Python\s+([\d.]+)') {
            $parsed = Parse-VersionRequirement -Requirement $matches[1]
            $versions += @{
              version = $matches[1]
              major = $parsed.major
              minor = $parsed.minor
              patch = $parsed.patch
              path = $pythonExe
              source = "managed"
            }
          }
        } catch {
          Write-Verbose "Failed to get version from $pythonExe"
        }
      }
    }
  }

  # Check system Python via py launcher
  try {
    $pyList = & py -0 2>&1 | Out-String
    $pyList -split "`n" | ForEach-Object {
      if ($_ -match '-V:?([\d.]+)') {
        $version = $matches[1]
        $parsed = Parse-VersionRequirement -Requirement $version
        $versions += @{
          version = $version
          major = $parsed.major
          minor = $parsed.minor
          patch = $parsed.patch
          path = "py -$version"
          source = "system"
        }
      }
    }
  } catch {
    Write-Verbose "py launcher not available"
  }

  return $versions
}

<#
.SYNOPSIS
Finds the best matching Python version for a requirement.

.DESCRIPTION
Given a version requirement (e.g., ">=3.11"), finds the best installed version.
For constraints (>=, ~=, etc.), returns the highest matching version.
For exact versions, returns exact match if available.

.PARAMETER Requirement
Version requirement string

.PARAMETER Versions
Array of version hashtables from Get-InstalledPythonVersions

.OUTPUTS
Hashtable of the best matching version, or $null if no match
#>
function Find-MatchingPythonVersion {
  param(
    [Parameter(Mandatory=$true)]
    [string] $Requirement,

    [Parameter(Mandatory=$true)]
    [array] $Versions
  )

  $req = Parse-VersionRequirement -Requirement $Requirement
  $matches = @()

  foreach ($ver in $Versions) {
    $match = $false

    switch ($req.operator) {
      "==" {
        # Exact match - can be major.minor or major.minor.patch
        if ($req.patch -ne $null) {
          $match = ($ver.major -eq $req.major -and $ver.minor -eq $req.minor -and $ver.patch -eq $req.patch)
        } else {
          $match = ($ver.major -eq $req.major -and $ver.minor -eq $req.minor)
        }
      }
      ">=" {
        # Greater or equal
        if ($ver.major -gt $req.major) { $match = $true }
        elseif ($ver.major -eq $req.major -and $ver.minor -gt $req.minor) { $match = $true }
        elseif ($ver.major -eq $req.major -and $ver.minor -eq $req.minor) { $match = $true }
      }
      ">" {
        # Greater than
        if ($ver.major -gt $req.major) { $match = $true }
        elseif ($ver.major -eq $req.major -and $ver.minor -gt $req.minor) { $match = $true }
      }
      "<=" {
        # Less or equal
        if ($ver.major -lt $req.major) { $match = $true }
        elseif ($ver.major -eq $req.major -and $ver.minor -lt $req.minor) { $match = $true }
        elseif ($ver.major -eq $req.major -and $ver.minor -eq $req.minor) { $match = $true }
      }
      "<" {
        # Less than
        if ($ver.major -lt $req.major) { $match = $true }
        elseif ($ver.major -eq $req.major -and $ver.minor -lt $req.minor) { $match = $true }
      }
      "~=" {
        # Compatible version (~=3.10 means >=3.10, <3.11)
        $match = ($ver.major -eq $req.major -and $ver.minor -eq $req.minor)
      }
    }

    if ($match) {
      $matches += $ver
    }
  }

  if ($matches.Count -eq 0) {
    return $null
  }

  # Return highest matching version (prefer managed over system)
  $sorted = $matches | Sort-Object -Property @{Expression={$_.source -eq "managed"}; Descending=$true}, major, minor, patch -Descending
  return $sorted[0]
}

<#
.SYNOPSIS
Gets the latest available version for a major.minor release.

.DESCRIPTION
Fetches the latest patch version from python.org for the specified major.minor version.
For example, for "3.11" returns "3.11.14" (or whatever is latest).

.PARAMETER MajorMinor
Major.minor version string (e.g., "3.11")

.OUTPUTS
String representing the latest patch version, or $null if not found
#>
function Get-LatestPythonPatchVersion {
  param(
    [Parameter(Mandatory=$true)]
    [string] $MajorMinor
  )

  try {
    # Fetch python.org downloads page
    $url = "https://www.python.org/downloads/"
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10

    # Find all versions matching major.minor
    $pattern = "Python\s+($MajorMinor\.\d+)"
    $matches = [regex]::Matches($response.Content, $pattern)

    if ($matches.Count -eq 0) {
      Write-Verbose "No versions found for $MajorMinor on python.org"
      return $null
    }

    # Get highest patch version
    $versions = $matches | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    $sorted = $versions | Sort-Object -Descending
    return $sorted[0]
  } catch {
    Write-Verbose "Failed to fetch latest version for $MajorMinor from python.org: $_"
    return $null
  }
}

<#
.SYNOPSIS
Downloads and installs a specific Python version.

.DESCRIPTION
Downloads the embeddable Python package from python.org and extracts it to
P:\software\_python-versions\<version>.

.PARAMETER Version
Full version string (e.g., "3.11.14")

.PARAMETER InstallRoot
Root directory for managed Python installations

.OUTPUTS
Path to python.exe, or $null if installation failed
#>
function Install-PythonVersion {
  param(
    [Parameter(Mandatory=$true)]
    [string] $Version,

    [string] $InstallRoot = "P:\software\_python-versions"
  )

  Write-Host "Installing Python $Version..." -ForegroundColor Cyan

  # Create install directory
  $installDir = Join-Path $InstallRoot $Version
  if (Test-Path $installDir) {
    Write-Host "  Python $Version already exists at $installDir" -ForegroundColor Yellow
    $pythonExe = Join-Path $installDir "python.exe"
    if (Test-Path $pythonExe) {
      return $pythonExe
    }
  }

  New-Item -Path $installDir -ItemType Directory -Force | Out-Null

  # Use NuGet package (portable, includes venv support)
  $downloadUrl = "https://www.python.org/ftp/python/$Version/python-$Version-amd64.exe"
  $installerPath = Join-Path $env:TEMP "python-$Version-installer.exe"

  try {
    Write-Host "  Downloading from $downloadUrl..." -ForegroundColor Gray
    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec 300

    Write-Host "  Installing to $installDir..." -ForegroundColor Gray
    # Install silently with minimal options: no shortcuts, no PATH, targeted install
    $installArgs = @(
      "/quiet"
      "InstallAllUsers=0"
      "PrependPath=0"
      "Include_test=0"
      "Include_tcltk=0"
      "Include_launcher=0"
      "TargetDir=$installDir"
    )
    & $installerPath $installArgs | Out-Null

    # Wait for installation to complete
    Start-Sleep -Seconds 10

    # Remove the installer
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

    # Verify installation
    $pythonExe = Join-Path $installDir "python.exe"
    if (-not (Test-Path $pythonExe)) {
      throw "Installation failed - python.exe not found"
    }

    Write-Host "  Python $Version installed successfully" -ForegroundColor Green
    Write-Host "  Location: $installDir" -ForegroundColor Gray

    return $pythonExe
  } catch {
    Write-Host "  ERROR: Failed to install Python $Version" -ForegroundColor Red
    Write-Host "  $_" -ForegroundColor Red

    # Clean up partial install
    if (Test-Path $installDir) {
      Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    return $null
  }
}

<#
.SYNOPSIS
Finds or installs the best Python version for a requirement.

.DESCRIPTION
Main orchestrator function that:
1. Finds installed versions matching the requirement
2. If no match found, installs the latest patch version
3. Returns path to python.exe

.PARAMETER Requirement
Version requirement string (e.g., ">=3.11", "3.11", "3.11.14")

.PARAMETER NonInteractive
If true, automatically installs without prompting

.OUTPUTS
Path to python.exe, or $null if failed
#>
function Find-Or-InstallPython {
  param(
    [Parameter(Mandatory=$true)]
    [string] $Requirement,

    [switch] $NonInteractive
  )

  Write-Host ""
  Write-Host "=== Python Version Management ===" -ForegroundColor Cyan
  Write-Host "Required: Python $Requirement" -ForegroundColor Yellow

  # Get all installed versions
  $installedVersions = Get-InstalledPythonVersions
  Write-Host "Installed versions: $($installedVersions.Count)" -ForegroundColor Gray

  # Find matching version
  $match = Find-MatchingPythonVersion -Requirement $Requirement -Versions $installedVersions

  if ($match) {
    Write-Host "Found matching version: Python $($match.version) ($($match.source))" -ForegroundColor Green
    Write-Host "Path: $($match.path)" -ForegroundColor Gray
    Write-Host ""

    # Return the path
    if ($match.path -like "py -*") {
      return $match.path
    } else {
      return $match.path
    }
  }

  # No match found - need to install
  Write-Host "No matching Python version found" -ForegroundColor Yellow

  # Parse requirement to determine what to install
  $req = Parse-VersionRequirement -Requirement $Requirement
  $majorMinor = "$($req.major).$($req.minor)"

  # If exact patch version specified, install that
  $versionToInstall = if ($req.patch -ne $null) {
    "$($req.major).$($req.minor).$($req.patch)"
  } else {
    # Otherwise, get latest patch version
    Write-Host "Fetching latest patch version for Python $majorMinor..." -ForegroundColor Gray
    $latest = Get-LatestPythonPatchVersion -MajorMinor $majorMinor
    if (-not $latest) {
      # Fallback to common latest versions if web fetch fails
      $fallbacks = @{
        "3.13" = "3.13.1"
        "3.12" = "3.12.8"
        "3.11" = "3.11.14"
        "3.10" = "3.10.16"
        "3.9" = "3.9.21"
      }
      $latest = $fallbacks[$majorMinor]
      if ($latest) {
        Write-Host "  Using fallback version: $latest" -ForegroundColor Yellow
      } else {
        Write-Host "  ERROR: Could not determine version to install" -ForegroundColor Red
        return $null
      }
    }
    $latest
  }

  Write-Host "Will install: Python $versionToInstall" -ForegroundColor Yellow

  # Confirm installation
  if (-not $NonInteractive) {
    $response = Read-Host "Proceed with installation? (y/n)"
    if ($response -ne "y") {
      Write-Host "Installation cancelled" -ForegroundColor Yellow
      return $null
    }
  }

  # Install
  $pythonPath = Install-PythonVersion -Version $versionToInstall

  if ($pythonPath) {
    Write-Host ""
    Write-Host "Python $versionToInstall is ready" -ForegroundColor Green
    Write-Host ""
    return $pythonPath
  }

  return $null
}
