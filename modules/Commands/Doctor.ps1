# Doctor.ps1 - Health checks for strap system

#region Shim Health Checks

function Invoke-DoctorShimChecks {
    param(
        [Parameter(Mandatory)][object]$Config,
        [array]$Registry = @()
    )

    $results = @()
    $shimsDir = $Config.roots.shims

    # SHIM001: Shims directory on PATH
    $pathEntries = $env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') }
    $shimsNormalized = $shimsDir.TrimEnd('\')
    $onPath = $shimsNormalized -in $pathEntries

    $results += @{
        id = "SHIM001"
        check = "Shims directory on PATH"
        severity = "critical"
        passed = $onPath
        message = if (-not $onPath) { "Shims directory not on PATH: $shimsDir" } else { $null }
        fix = if (-not $onPath) {
            "`$p = [Environment]::GetEnvironmentVariable('PATH','User'); [Environment]::SetEnvironmentVariable('PATH',`"$shimsDir;`$p`",'User')"
        } else { $null }
    }

    # SHIM002: Shim file exists
    # SHIM003: Exe resolvable
    # SHIM007: Venv valid
    # SHIM008: Launcher pair complete
    foreach ($entry in $Registry) {
        foreach ($shim in $entry.shims) {
            $ps1Path = $shim.ps1Path
            $cmdPath = $ps1Path -replace '\.ps1$', '.cmd'

            # SHIM002
            $ps1Exists = Test-Path $ps1Path
            $results += @{
                id = "SHIM002"
                check = "Shim file exists: $($shim.name)"
                severity = "error"
                passed = $ps1Exists
                message = if (-not $ps1Exists) { "Shim file missing: $ps1Path" } else { $null }
                fix = if (-not $ps1Exists) { "Remove from registry or run: strap shim --regen $($entry.name)" } else { $null }
            }

            # SHIM003: Exe resolvable
            if ($shim.exe) {
                $exeExists = if ([System.IO.Path]::IsPathRooted($shim.exe)) {
                    Test-Path $shim.exe
                } else {
                    $null -ne (Get-Command $shim.exe -ErrorAction SilentlyContinue)
                }
                $results += @{
                    id = "SHIM003"
                    check = "Exe resolvable: $($shim.name)"
                    severity = "error"
                    passed = $exeExists
                    message = if (-not $exeExists) { "Exe not found: $($shim.exe)" } else { $null }
                    fix = $null
                }
            }

            # SHIM007: Venv valid (if venv type)
            if ($shim.venv) {
                $pythonExe = Join-Path $shim.venv "Scripts\python.exe"
                $venvValid = Test-Path $pythonExe
                $results += @{
                    id = "SHIM007"
                    check = "Venv valid: $($shim.name)"
                    severity = "error"
                    passed = $venvValid
                    message = if (-not $venvValid) { "Venv invalid: $($shim.venv)" } else { $null }
                    fix = if (-not $venvValid) { "python -m venv $($shim.venv)" } else { $null }
                }
            }

            # SHIM008: Launcher pair complete
            if ($ps1Exists) {
                $cmdExists = Test-Path $cmdPath
                $results += @{
                    id = "SHIM008"
                    check = "Launcher pair: $($shim.name)"
                    severity = "warning"
                    passed = $cmdExists
                    message = if (-not $cmdExists) { "Missing .cmd launcher for $($shim.name)" } else { $null }
                    fix = if (-not $cmdExists) { "strap shim --regen $($entry.name)" } else { $null }
                }
            }
        }
    }

    # SHIM009: Config exe paths valid
    if ($Config.defaults.pwshExe) {
        $pwshValid = Test-Path $Config.defaults.pwshExe
        $results += @{
            id = "SHIM009"
            check = "Config pwshExe valid"
            severity = "warning"
            passed = $pwshValid
            message = if (-not $pwshValid) { "pwshExe not found: $($Config.defaults.pwshExe)" } else { $null }
            fix = $null
        }
    }

    if ($Config.defaults.nodeExe) {
        $nodeValid = Test-Path $Config.defaults.nodeExe
        $results += @{
            id = "SHIM009"
            check = "Config nodeExe valid"
            severity = "warning"
            passed = $nodeValid
            message = if (-not $nodeValid) { "nodeExe not found: $($Config.defaults.nodeExe)" } else { $null }
            fix = $null
        }
    }

    return $results
}

function Format-DoctorShimResults {
    param([Parameter(Mandatory)][array]$Results)

    $output = @()
    $output += "=== SHIM HEALTH ==="
    $output += ""

    $grouped = $Results | Group-Object severity

    foreach ($group in $grouped | Sort-Object { @{critical=0;error=1;warning=2}[$_.Name] }) {
        $color = switch ($group.Name) {
            "critical" { "Red" }
            "error" { "Red" }
            "warning" { "Yellow" }
            default { "White" }
        }

        $output += "[$($group.Name.ToUpper())]"

        foreach ($result in $group.Group) {
            if ($result.passed) {
                $output += "  [OK] $($result.check)"
            } else {
                $output += "  [X] $($result.check)"
                if ($result.message) { $output += "    $($result.message)" }
                if ($result.fix) { $output += "    Fix: $($result.fix)" }
            }
        }
        $output += ""
    }

    $passed = ($Results | Where-Object { $_.passed }).Count
    $failed = ($Results | Where-Object { -not $_.passed }).Count
    $output += "Passed: $passed | Failed: $failed"

    return $output -join "`n"
}

#endregion

#region System Dependency Checks

function Invoke-DoctorSystemChecks {
    <#
    .SYNOPSIS
    Checks for required system dependencies like pyenv-win.

    .PARAMETER Interactive
    If true, offer to install missing dependencies.

    .PARAMETER Config
    Configuration object with paths.
    #>
    param(
        [switch]$Interactive,
        [object]$Config
    )

    $results = @()

    # SYS001: pyenv-win installed
    $pyenvInstalled = Test-PyenvInstalled

    $results += @{
        id = "SYS001"
        check = "pyenv-win installed"
        severity = "warning"
        passed = $pyenvInstalled
        message = if (-not $pyenvInstalled) {
            "pyenv-win not found - required for Python version management"
        } else { $null }
        fix = if (-not $pyenvInstalled) {
            "Run: strap doctor --install-pyenv"
        } else { $null }
    }

    # SYS002: pyenv shim exists (only if installed)
    if ($pyenvInstalled -and $Config) {
        $shimPath = Join-Path $Config.roots.shims "pyenv.ps1"
        $shimExists = Test-Path $shimPath

        $results += @{
            id = "SYS002"
            check = "pyenv shim exists"
            severity = "warning"
            passed = $shimExists
            message = if (-not $shimExists) {
                "pyenv shim not found - command may not be available system-wide"
            } else { $null }
            fix = if (-not $shimExists) {
                "Run: strap doctor --install-pyenv"
            } else { $null }
        }
    }

    # SYS003: fnm installed
    $fnmInstalled = Test-FnmInstalled
    $results += @{
        id = "SYS003"
        check = "fnm installed"
        severity = "warning"
        passed = $fnmInstalled
        message = if (-not $fnmInstalled) {
            "fnm not found - required for Node version management"
        } else { $null }
        fix = if (-not $fnmInstalled) {
            "Run: strap doctor --install-fnm"
        } else { $null }
    }

    # SYS004: fnm shim exists (only if installed)
    if ($fnmInstalled -and $Config) {
        $shimPath = Join-Path $Config.roots.shims "fnm.ps1"
        $shimExists = Test-Path $shimPath

        $results += @{
            id = "SYS004"
            check = "fnm shim exists"
            severity = "warning"
            passed = $shimExists
            message = if (-not $shimExists) {
                "fnm shim not found - command may not be available system-wide"
            } else { $null }
            fix = if (-not $shimExists) {
                "Run: strap doctor --install-fnm"
            } else { $null }
        }
    }

    return $results
}

function Invoke-DoctorNodeChecks {
    <#
    .SYNOPSIS
    Validates Node projects have proper version management setup.

    .DESCRIPTION
    Checks that Node projects have version files, versions match registry,
    and detected versions are installed via fnm.
    #>
    param(
        [Parameter(Mandatory)][object]$Config,
        [array]$Registry = @()
    )

    $results = @()

    # Only run checks if fnm is installed
    if (-not (Test-FnmInstalled)) {
        return $results
    }

    # Get all Node projects
    $nodeProjects = $Registry | Where-Object { $_.stack -eq 'node' }

    foreach ($project in $nodeProjects) {
        $projectName = $project.name
        $projectPath = $project.path

        # NODE001: Node project has version file
        $detectedVersion = Get-NodeVersionFromFile -RepoPath $projectPath
        $hasVersionFile = $null -ne $detectedVersion

        $results += @{
            id = "NODE001"
            check = "Version file exists: $projectName"
            severity = "warning"
            passed = $hasVersionFile
            message = if (-not $hasVersionFile) {
                "No .nvmrc, .node-version, or package.json engines.node found"
            } else { $null }
            fix = if (-not $hasVersionFile) {
                "Add .nvmrc file: echo '20.19.0' > $projectPath\.nvmrc"
            } else { $null }
        }

        if ($hasVersionFile) {
            # NODE002: Detected version matches registry
            $registryVersion = if ($project.PSObject.Properties['node_version']) {
                $project.node_version
            } else { $null }

            $versionsMatch = $detectedVersion -eq $registryVersion
            $results += @{
                id = "NODE002"
                check = "Version consistent: $projectName"
                severity = "warning"
                passed = $versionsMatch
                message = if (-not $versionsMatch) {
                    "Version file: $detectedVersion, Registry: $registryVersion"
                } else { $null }
                fix = if (-not $versionsMatch) {
                    "Run: strap setup $projectName"
                } else { $null }
            }

            # NODE003: Detected version is installed via fnm
            $installedVersions = Get-FnmVersions
            $versionInstalled = $installedVersions -contains $detectedVersion

            $results += @{
                id = "NODE003"
                check = "Version installed: $projectName ($detectedVersion)"
                severity = "warning"
                passed = $versionInstalled
                message = if (-not $versionInstalled) {
                    "Node $detectedVersion not installed via fnm"
                } else { $null }
                fix = if (-not $versionInstalled) {
                    "Run: fnm install $detectedVersion"
                } else { $null }
            }
        }
    }

    return $results
}

function Format-DoctorSystemResults {
    param([Parameter(Mandatory)][array]$Results)

    $output = @()
    $output += "=== SYSTEM DEPENDENCIES ==="
    $output += ""

    $grouped = $Results | Group-Object severity

    foreach ($group in $grouped | Sort-Object { @{critical=0;error=1;warning=2}[$_.Name] }) {
        $color = switch ($group.Name) {
            "critical" { "Red" }
            "error" { "Red" }
            "warning" { "Yellow" }
            default { "White" }
        }

        $output += "[$($group.Name.ToUpper())]"

        foreach ($result in $group.Group) {
            if ($result.passed) {
                $output += "  [OK] $($result.check)"
            } else {
                $output += "  [X] $($result.check)"
                if ($result.message) { $output += "    $($result.message)" }
                if ($result.fix) { $output += "    $($result.fix)" }
            }
        }
        $output += ""
    }

    $passed = ($Results | Where-Object { $_.passed }).Count
    $failed = ($Results | Where-Object { -not $_.passed }).Count
    $output += "Passed: $passed | Failed: $failed"

    return $output -join "`n"
}

function Format-DoctorNodeResults {
    param([Parameter(Mandatory)][array]$Results)

    if ($Results.Count -eq 0) {
        return ""
    }

    $output = @()
    $output += "=== NODE VERSION MANAGEMENT ==="
    $output += ""

    $grouped = $Results | Group-Object severity

    foreach ($group in $grouped | Sort-Object { @{critical=0;error=1;warning=2}[$_.Name] }) {
        $color = switch ($group.Name) {
            "critical" { "Red" }
            "error" { "Red" }
            "warning" { "Yellow" }
            default { "White" }
        }

        $output += "[$($group.Name.ToUpper())]"

        foreach ($result in $group.Group) {
            if ($result.passed) {
                $output += "  [OK] $($result.check)"
            } else {
                $output += "  [X] $($result.check)"
                if ($result.message) { $output += "    $($result.message)" }
                if ($result.fix) { $output += "    $($result.fix)" }
            }
        }
        $output += ""
    }

    $passed = ($Results | Where-Object { $_.passed }).Count
    $failed = ($Results | Where-Object { -not $_.passed }).Count
    $output += "Passed: $passed | Failed: $failed"

    return $output -join "`n"
}

#endregion
