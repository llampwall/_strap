# Validation.ps1 - Shim and setup health validation
# Tiered validation strategy:
#   Tier 1: Filesystem checks only (always safe, <100ms)
#   Tier 2: Conservative shim invocation (default, skippable)
#   Tier 3: Deep diagnostics (strap verify only)

#region Tier 1: Filesystem Validation

function Test-ShimFilesExist {
    <#
    .SYNOPSIS
        Verify shim files exist on disk (.ps1 and .cmd).
    .OUTPUTS
        Hashtable with 'exists', 'ps1Path', 'cmdPath', 'missing' keys.
    #>
    param(
        [Parameter(Mandatory)][string]$ShimName,
        [Parameter(Mandatory)][string]$ShimsDir
    )

    $ps1Path = Join-Path $ShimsDir "$ShimName.ps1"
    $cmdPath = Join-Path $ShimsDir "$ShimName.cmd"

    $ps1Exists = Test-Path $ps1Path
    $cmdExists = Test-Path $cmdPath

    $missing = @()
    if (-not $ps1Exists) { $missing += "ps1" }
    if (-not $cmdExists) { $missing += "cmd" }

    return @{
        exists = ($ps1Exists -and $cmdExists)
        ps1Path = $ps1Path
        cmdPath = $cmdPath
        missing = $missing
    }
}

function Test-ShimTargetExists {
    <#
    .SYNOPSIS
        Verify the executable that the shim points to exists.
    .OUTPUTS
        Hashtable with 'exists', 'targetPath', 'error' keys.
    #>
    param(
        [Parameter(Mandatory)][object]$ShimEntry
    )

    $targetPath = $ShimEntry.exe

    # Handle relative paths (shouldn't happen, but be defensive)
    if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
        return @{
            exists = $false
            targetPath = $targetPath
            error = "Target path is not absolute"
        }
    }

    $exists = Test-Path $targetPath

    return @{
        exists = $exists
        targetPath = $targetPath
        error = if (-not $exists) { "Executable not found" } else { $null }
    }
}

function Test-VenvExists {
    <#
    .SYNOPSIS
        Verify Python venv directory and python.exe exist.
    .OUTPUTS
        Hashtable with 'exists', 'venvPath', 'pythonPath', 'error' keys.
    #>
    param(
        [Parameter(Mandatory)][string]$VenvPath
    )

    if (-not (Test-Path $VenvPath)) {
        return @{
            exists = $false
            venvPath = $VenvPath
            pythonPath = $null
            error = "Venv directory not found"
        }
    }

    $pythonPath = Join-Path $VenvPath "Scripts\python.exe"
    $pythonExists = Test-Path $pythonPath

    return @{
        exists = $pythonExists
        venvPath = $VenvPath
        pythonPath = $pythonPath
        error = if (-not $pythonExists) { "python.exe not found in venv" } else { $null }
    }
}

function Test-NodeModulesExists {
    <#
    .SYNOPSIS
        Verify node_modules directory exists.
    .OUTPUTS
        Hashtable with 'exists', 'path', 'error' keys.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoPath
    )

    $nodeModulesPath = Join-Path $RepoPath "node_modules"
    $exists = Test-Path $nodeModulesPath

    return @{
        exists = $exists
        path = $nodeModulesPath
        error = if (-not $exists) { "node_modules not found" } else { $null }
    }
}

function Invoke-Tier1Validation {
    <#
    .SYNOPSIS
        Run all Tier 1 filesystem checks for a shim.
    .OUTPUTS
        Hashtable with tier1 validation results.
    #>
    param(
        [Parameter(Mandatory)][object]$ShimEntry,
        [Parameter(Mandatory)][string]$ShimsDir,
        [string]$RepoPath
    )

    $results = @{
        tier = 1
        shimName = $ShimEntry.name
        checks = @{}
        passed = $true
        errors = @()
    }

    # Check 1: Shim files exist
    $filesCheck = Test-ShimFilesExist -ShimName $ShimEntry.name -ShimsDir $ShimsDir
    $results.checks.files = $filesCheck
    if (-not $filesCheck.exists) {
        $results.passed = $false
        $results.errors += "Missing shim files: $($filesCheck.missing -join ', ')"
    }

    # Check 2: Target executable exists
    $targetCheck = Test-ShimTargetExists -ShimEntry $ShimEntry
    $results.checks.target = $targetCheck
    if (-not $targetCheck.exists) {
        $results.passed = $false
        $results.errors += $targetCheck.error
    }

    # Check 3: Environment-specific checks
    if ($ShimEntry.type -eq "venv" -and $ShimEntry.venv) {
        $venvCheck = Test-VenvExists -VenvPath $ShimEntry.venv
        $results.checks.venv = $venvCheck
        if (-not $venvCheck.exists) {
            $results.passed = $false
            $results.errors += $venvCheck.error
        }
    }

    if ($ShimEntry.type -eq "node" -and $RepoPath) {
        $nodeModulesCheck = Test-NodeModulesExists -RepoPath $RepoPath
        $results.checks.nodeModules = $nodeModulesCheck
        if (-not $nodeModulesCheck.exists) {
            $results.passed = $false
            $results.errors += $nodeModulesCheck.error
        }
    }

    return $results
}

#endregion

#region Tier 2: Conservative Invocation

function Invoke-ShimSafely {
    <#
    .SYNOPSIS
        Attempt to invoke a shim with --version or --help, with timeout.
    .OUTPUTS
        Hashtable with 'success', 'exitCode', 'output', 'error', 'timedOut' keys.
    #>
    param(
        [Parameter(Mandatory)][string]$ShimName,
        [int]$TimeoutSeconds = 5
    )

    # Try --version first
    $attempts = @("--version", "--help")

    foreach ($arg in $attempts) {
        try {
            # Use job for timeout
            $job = Start-Job -ScriptBlock {
                param($shim, $arg)
                & $shim $arg 2>&1
                return $LASTEXITCODE
            } -ArgumentList $ShimName, $arg

            $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds

            if ($completed) {
                $output = Receive-Job -Job $job
                $exitCode = $output[-1]  # Last item is exit code
                Remove-Job -Job $job -Force

                # Any zero exit code = success
                if ($exitCode -eq 0) {
                    return @{
                        success = $true
                        exitCode = $exitCode
                        arg = $arg
                        output = ($output | Select-Object -SkipLast 1) -join "`n"
                        error = $null
                        timedOut = $false
                    }
                }
            } else {
                # Timeout
                Stop-Job -Job $job
                Remove-Job -Job $job -Force
                return @{
                    success = $false
                    exitCode = $null
                    arg = $arg
                    output = $null
                    error = "Timed out after ${TimeoutSeconds}s"
                    timedOut = $true
                }
            }
        } catch {
            # Continue to next attempt
            continue
        }
    }

    # All attempts failed
    return @{
        success = $false
        exitCode = $null
        arg = $null
        output = $null
        error = "All invocation attempts failed (--version, --help)"
        timedOut = $false
    }
}

function Invoke-Tier2Validation {
    <#
    .SYNOPSIS
        Run Tier 2 validation: conservative shim invocation.
    .OUTPUTS
        Hashtable with tier2 validation results.
    #>
    param(
        [Parameter(Mandatory)][object]$ShimEntry,
        [int]$TimeoutSeconds = 5
    )

    $results = @{
        tier = 2
        shimName = $ShimEntry.name
        invocation = $null
        passed = $false
        errors = @()
    }

    $invocation = Invoke-ShimSafely -ShimName $ShimEntry.name -TimeoutSeconds $TimeoutSeconds
    $results.invocation = $invocation

    if ($invocation.success) {
        $results.passed = $true
    } else {
        $results.errors += $invocation.error
    }

    return $results
}

#endregion

#region Tier 3: Deep Diagnostics

function Test-VenvCanImportPackage {
    <#
    .SYNOPSIS
        Check if venv can import its own package (for Python projects).
    .OUTPUTS
        Hashtable with 'success', 'error' keys.
    #>
    param(
        [Parameter(Mandatory)][string]$VenvPath,
        [Parameter(Mandatory)][string]$PackageName
    )

    $pythonPath = Join-Path $VenvPath "Scripts\python.exe"
    if (-not (Test-Path $pythonPath)) {
        return @{
            success = $false
            error = "Python not found in venv"
        }
    }

    try {
        $output = & $pythonPath -c "import $PackageName" 2>&1
        $success = $LASTEXITCODE -eq 0

        return @{
            success = $success
            error = if (-not $success) { "Import failed: $output" } else { $null }
        }
    } catch {
        return @{
            success = $false
            error = "Import test failed: $_"
        }
    }
}

function Test-GoBuildSucceeds {
    <#
    .SYNOPSIS
        Check if go build succeeds (for Go projects).
    .OUTPUTS
        Hashtable with 'success', 'error' keys.
    #>
    param(
        [Parameter(Mandatory)][string]$RepoPath
    )

    Push-Location $RepoPath
    try {
        $output = go build 2>&1
        $success = $LASTEXITCODE -eq 0

        return @{
            success = $success
            error = if (-not $success) { "Build failed: $output" } else { $null }
        }
    } catch {
        return @{
            success = $false
            error = "Build test failed: $_"
        }
    } finally {
        Pop-Location
    }
}

function Invoke-Tier3Validation {
    <#
    .SYNOPSIS
        Run Tier 3 validation: deep diagnostics (slow, for strap verify only).
    .OUTPUTS
        Hashtable with tier3 validation results.
    #>
    param(
        [Parameter(Mandatory)][object]$RepoEntry,
        [Parameter(Mandatory)][object]$Config
    )

    $results = @{
        tier = 3
        repoName = $RepoEntry.name
        checks = @{}
        passed = $true
        errors = @()
    }

    $stack = $RepoEntry.stack

    # Python: Try to import package
    if ($stack -eq "python" -and (Test-Path (Join-Path $RepoEntry.path "pyproject.toml"))) {
        # Extract package name from pyproject.toml
        $pyprojectContent = Get-Content (Join-Path $RepoEntry.path "pyproject.toml") -Raw
        if ($pyprojectContent -match '\[project\].*?name\s*=\s*["`'']([^"`'']+)["`'']') {
            $packageName = $matches[1]
            $venvPath = Join-Path $RepoEntry.path ".venv"

            if (Test-Path $venvPath) {
                $importCheck = Test-VenvCanImportPackage -VenvPath $venvPath -PackageName $packageName
                $results.checks.import = $importCheck
                if (-not $importCheck.success) {
                    $results.passed = $false
                    $results.errors += $importCheck.error
                }
            }
        }
    }

    # Go: Try to build
    if ($stack -eq "go") {
        $buildCheck = Test-GoBuildSucceeds -RepoPath $RepoEntry.path
        $results.checks.build = $buildCheck
        if (-not $buildCheck.success) {
            $results.passed = $false
            $results.errors += $buildCheck.error
        }
    }

    # Rust: cargo check (fast) or cargo build (slow)
    # TODO: Add if needed

    return $results
}

#endregion

#region Validation Orchestration

function Invoke-ShimValidation {
    <#
    .SYNOPSIS
        Validate a shim with specified tiers.
    .PARAMETER Tiers
        Array of tier numbers to run (1, 2, 3). Default: @(1, 2)
    .OUTPUTS
        Hashtable with all validation results.
    #>
    param(
        [Parameter(Mandatory)][object]$ShimEntry,
        [Parameter(Mandatory)][string]$ShimsDir,
        [string]$RepoPath,
        [int[]]$Tiers = @(1, 2),
        [int]$TimeoutSeconds = 5
    )

    $results = @{
        shimName = $ShimEntry.name
        tiers = @{}
        overallPassed = $true
    }

    if ($Tiers -contains 1) {
        $tier1 = Invoke-Tier1Validation -ShimEntry $ShimEntry -ShimsDir $ShimsDir -RepoPath $RepoPath
        $results.tiers[1] = $tier1
        if (-not $tier1.passed) {
            $results.overallPassed = $false
        }
    }

    # Only run Tier 2 if Tier 1 passed (no point invoking a broken shim)
    if ($Tiers -contains 2 -and $results.tiers[1].passed) {
        $tier2 = Invoke-Tier2Validation -ShimEntry $ShimEntry -TimeoutSeconds $TimeoutSeconds
        $results.tiers[2] = $tier2
        if (-not $tier2.passed) {
            $results.overallPassed = $false
        }
    }

    # Tier 3 handled separately at repo level

    return $results
}

function Invoke-RepoValidation {
    <#
    .SYNOPSIS
        Validate all shims for a repo.
    .OUTPUTS
        Hashtable with validation summary.
    #>
    param(
        [Parameter(Mandatory)][object]$RepoEntry,
        [Parameter(Mandatory)][object]$Config,
        [int[]]$Tiers = @(1, 2),
        [int]$TimeoutSeconds = 5,
        [switch]$Quiet
    )

    $shimsDir = $Config.roots.shims
    $shimResults = @()
    $passedCount = 0
    $failedCount = 0

    if (-not $RepoEntry.shims -or $RepoEntry.shims.Count -eq 0) {
        if (-not $Quiet) {
            Write-Host "No shims registered for '$($RepoEntry.name)'" -ForegroundColor Yellow
        }
        return @{
            repoName = $RepoEntry.name
            shimCount = 0
            passedCount = 0
            failedCount = 0
            results = @()
            tier3 = $null
        }
    }

    foreach ($shim in $RepoEntry.shims) {
        $result = Invoke-ShimValidation -ShimEntry $shim -ShimsDir $shimsDir -RepoPath $RepoEntry.path -Tiers $Tiers -TimeoutSeconds $TimeoutSeconds
        $shimResults += $result

        if ($result.overallPassed) {
            $passedCount++
        } else {
            $failedCount++
        }

        if (-not $Quiet) {
            if ($result.overallPassed) {
                Write-Host "  ✓ $($shim.name)" -ForegroundColor Green
            } else {
                Write-Host "  ✗ $($shim.name)" -ForegroundColor Red
                foreach ($tierNum in $result.tiers.Keys) {
                    $tierResult = $result.tiers[$tierNum]
                    if (-not $tierResult.passed) {
                        foreach ($error in $tierResult.errors) {
                            Write-Host "    - $error" -ForegroundColor Yellow
                        }
                    }
                }
            }
        }
    }

    # Tier 3 validation (repo-level, not shim-level)
    $tier3Result = $null
    if ($Tiers -contains 3) {
        if (-not $Quiet) {
            Write-Host ""
            Write-Host "Running deep diagnostics (Tier 3)..." -ForegroundColor Cyan
        }
        $tier3Result = Invoke-Tier3Validation -RepoEntry $RepoEntry -Config $Config
        if (-not $Quiet) {
            if ($tier3Result.passed) {
                Write-Host "  ✓ Deep diagnostics passed" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Deep diagnostics failed" -ForegroundColor Red
                foreach ($error in $tier3Result.errors) {
                    Write-Host "    - $error" -ForegroundColor Yellow
                }
            }
        }
    }

    return @{
        repoName = $RepoEntry.name
        shimCount = $RepoEntry.shims.Count
        passedCount = $passedCount
        failedCount = $failedCount
        results = $shimResults
        tier3 = $tier3Result
    }
}

#endregion
