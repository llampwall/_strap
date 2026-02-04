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
