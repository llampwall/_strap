# upgrade-python.ps1
# Command: Invoke-UpgradePython

function Invoke-UpgradePython {
    param(
        [string]$RepoNameOrPath,
        [string]$Version,          # Target version (optional)
        [switch]$Latest,           # Upgrade to latest stable
        [switch]$ListOnly,         # Just show available versions
        [switch]$NonInteractive,
        [string]$StrapRootPath
    )

    # Load config and registry
    $config = Load-Config $StrapRootPath
    $registry = Load-Registry $config

    # Check pyenv is installed
    if (-not (Test-PyenvInstalled)) {
        Die "pyenv-win not installed. Run 'strap doctor --install-pyenv' first."
    }

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
        Info "Upgrading Python for: $RepoNameOrPath"
    } else {
        # Use current directory
        $repoPath = Get-Location
        Info "Upgrading Python in current directory: $repoPath"

        # Try to find matching registry entry
        $registryEntry = $registry | Where-Object { $_.path -eq $repoPath }
    }

    # Safety validation
    $resolvedPath = [System.IO.Path]::GetFullPath($repoPath)
    $softwareRoot = "P:\software"

    if (-not $resolvedPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Die "Path is not within managed root: $resolvedPath"
    }

    # Detect current version
    $currentVersion = Get-PythonVersionFromFile -RepoPath $resolvedPath

    if (-not $currentVersion) {
        Die "No Python version file found. Add .python-version first: echo '3.12.0' > .python-version"
    }

    Write-Host ""
    Write-Host "Current version: $currentVersion" -ForegroundColor Cyan
    Write-Host ""

    # Get available versions from pyenv
    Write-Host "Fetching available versions..." -ForegroundColor Gray
    $pyenvCmd = Get-PyenvCommand
    $env:PYENV = Get-VendoredPyenvPath
    $allVersions = & $pyenvCmd install --list 2>$null
    Remove-Item Env:\PYENV -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -ne 0 -or -not $allVersions) {
        Die "Failed to fetch available versions from pyenv"
    }

    # Parse versions (filter out rc/beta/dev)
    $stableVersions = $allVersions | Where-Object {
        $_ -match '^\s*(\d+\.\d+\.\d+)\s*$'
    } | ForEach-Object {
        if ($_ -match '^\s*(\d+\.\d+\.\d+)\s*$') { $matches[1] }
    } | Sort-Object {
        $parts = $_ -split '\.'
        [version]"$($parts[0]).$($parts[1]).$($parts[2])"
    }

    # Extract major.minor from current version
    if ($currentVersion -match '^(\d+)\.(\d+)') {
        $currentMajor = [int]$matches[1]
        $currentMinor = [int]$matches[2]
    } else {
        Die "Cannot parse current version: $currentVersion"
    }

    # Find newer versions
    $newerVersions = $stableVersions | Where-Object {
        if ($_ -match '^(\d+)\.(\d+)\.(\d+)$') {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            $patch = [int]$matches[3]

            # Greater major, or same major + greater minor, or same major.minor + greater patch
            ($major -gt $currentMajor) -or
            ($major -eq $currentMajor -and $minor -gt $currentMinor) -or
            ($major -eq $currentMajor -and $minor -eq $currentMinor -and $patch -gt ($currentVersion -split '\.')[2])
        }
    }

    if (-not $newerVersions -or $newerVersions.Count -eq 0) {
        Write-Host "You're already on the latest version!" -ForegroundColor Green
        return
    }

    # Get latest version
    $latestVersion = $newerVersions | Select-Object -Last 1

    # Show available upgrades
    Write-Host "Available upgrades:" -ForegroundColor Cyan
    Write-Host ""

    # Group by major.minor
    $grouped = @($newerVersions | Group-Object -Property {
        if ($_ -match '^(\d+)\.(\d+)') {
            return "$($matches[1]).$($matches[2])"
        } else {
            return "unknown"
        }
    })

    # Sort groups by version
    $sorted = @($grouped | Sort-Object -Property {
        if ($_.Name -ne "unknown") {
            $parts = $_.Name -split '\.'
            if ($parts.Count -ge 2) {
                return [version]"$($parts[0]).$($parts[1]).0"
            }
        }
        return [version]"0.0.0"
    })

    # Display grouped versions
    & {
        foreach ($group in $sorted) {
            if ($group.Name -eq "unknown") { continue }

            # Get the last item from the group
            $items = @($group.Group)
            if ($items.Count -gt 0) {
                $latest = $items[-1]  # Use negative indexing
                $isLatest = $latest -eq $latestVersion
                $marker = if ($isLatest) { " (latest)" } else { "" }
                $color = if ($isLatest) { "Green" } else { "Gray" }
                Write-Host "  $($group.Name).x → $latest$marker" -ForegroundColor $color
            }
        }
    }

    Write-Host ""

    if ($ListOnly) {
        return
    }

    # Determine target version
    $targetVersion = $null

    if ($Version) {
        # User specified version
        if ($newerVersions -notcontains $Version) {
            Die "Version $Version is not a valid upgrade. Use --list-only to see available versions."
        }
        $targetVersion = $Version
    } elseif ($Latest) {
        # Use latest
        $targetVersion = $latestVersion
    } else {
        # Interactive selection
        if ($NonInteractive) {
            Die "No version specified. Use --latest or --version <version> in non-interactive mode."
        }

        Write-Host "Select upgrade target:" -ForegroundColor Cyan
        Write-Host "  1. Latest stable ($latestVersion)" -ForegroundColor Green
        Write-Host "  2. Specify version manually" -ForegroundColor Gray
        Write-Host ""

        $choice = Read-Host "Choice [1-2]"

        if ($choice -eq "1") {
            $targetVersion = $latestVersion
        } elseif ($choice -eq "2") {
            $targetVersion = Read-Host "Enter version (e.g., 3.12.0)"
            if ($newerVersions -notcontains $targetVersion) {
                Die "Invalid version: $targetVersion"
            }
        } else {
            Die "Invalid choice"
        }
    }

    Write-Host ""
    Write-Host "=== UPGRADE PLAN ===" -ForegroundColor Cyan
    Write-Host "Repository: $resolvedPath"
    Write-Host "Current version: $currentVersion"
    Write-Host "Target version: $targetVersion"
    Write-Host ""

    # Confirmation
    if (-not $NonInteractive) {
        $response = Read-Host "Proceed with upgrade? (y/n)"
        if ($response -ne "y") {
            Info "Aborted by user"
            return
        }
    }

    Write-Host ""
    Write-Host "=== EXECUTING UPGRADE ===" -ForegroundColor Cyan

    # Step 1: Update version file
    $pythonVersionPath = Join-Path $resolvedPath ".python-version"

    Write-Host "Updating .python-version..." -ForegroundColor Cyan
    $targetVersion | Set-Content $pythonVersionPath -NoNewline
    Write-Host "  [OK] .python-version updated to $targetVersion" -ForegroundColor Green

    # Step 2: Install new version via pyenv
    Write-Host ""
    Write-Host "Installing Python $targetVersion via pyenv..." -ForegroundColor Cyan
    $installSuccess = Install-PyenvVersion -Version $targetVersion

    if (-not $installSuccess) {
        Die "Failed to install Python $targetVersion"
    }

    # Step 3: Run setup if registry entry exists
    if ($registryEntry) {
        Write-Host ""
        Write-Host "Running setup to update venv and dependencies..." -ForegroundColor Cyan
        Push-Location $resolvedPath
        try {
            & "$StrapRootPath\strap.ps1" setup --yes 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] Setup completed" -ForegroundColor Green
            } else {
                Write-Host "  [!] Setup completed with warnings (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "  [X] Setup error: $_" -ForegroundColor Red
            Pop-Location
            Die "Upgrade failed"
        } finally {
            Pop-Location
        }

        # Step 4: Regenerate shims if they exist
        if ($registryEntry.shims -and $registryEntry.shims.Count -gt 0) {
            Write-Host ""
            Write-Host "Regenerating shims..." -ForegroundColor Cyan
            & "$StrapRootPath\strap.ps1" shim --regen $registryEntry.name 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] Shims regenerated" -ForegroundColor Green
            } else {
                Write-Host "  [!] Shim regeneration completed with warnings" -ForegroundColor Yellow
            }
        }
    }

    Write-Host ""
    Write-Host "=== UPGRADE COMPLETE ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Python version upgraded: $currentVersion → $targetVersion" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Gray
    Write-Host "  1. Test your application with the new version" -ForegroundColor Gray
    Write-Host "  2. Commit the updated .python-version file" -ForegroundColor Gray
    if ($registryEntry -and $registryEntry.shims -and $registryEntry.shims.Count -gt 0) {
        Write-Host "  3. Verify CLI commands work: $($registryEntry.shims[0].name) --version" -ForegroundColor Gray
    }
}
