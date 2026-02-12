# migrate-node-to-fnm.ps1
# Migrates all Node projects to use fnm-managed Node

param(
    [switch]$DryRun,
    [string]$DefaultNodeVersion = "20.19.0"
)

$ErrorActionPreference = "Stop"

# Load modules
$StrapRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $StrapRoot "modules\Core.ps1")
. (Join-Path $StrapRoot "modules\Config.ps1")
. (Join-Path $StrapRoot "modules\FnmIntegration.ps1")

$config = Load-Config $StrapRoot
$registry = Load-Registry $config

Write-Host "=== MIGRATING NODE PROJECTS TO FNM ===" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE - No changes will be made]" -ForegroundColor Yellow
    Write-Host ""
}

# Check fnm is installed
if (-not (Test-FnmInstalled)) {
    Die "fnm not installed. Run 'strap doctor --install-fnm' first."
}

# Get all Node projects
$nodeProjects = $registry | Where-Object { $_.stack -eq 'node' }

if ($nodeProjects.Count -eq 0) {
    Write-Host "No Node projects found in registry." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($nodeProjects.Count) Node project(s):" -ForegroundColor Cyan
foreach ($project in $nodeProjects) {
    $hasVersion = $project.PSObject.Properties['node_version'] -and $project.node_version
    $versionText = if ($hasVersion) { "node_version: $($project.node_version)" } else { "no version" }
    Write-Host "  - $($project.name) ($versionText)" -ForegroundColor Gray
}
Write-Host ""

$migratedCount = 0
$skippedCount = 0
$failedCount = 0

foreach ($project in $nodeProjects) {
    Write-Host "Processing: $($project.name)" -ForegroundColor Cyan

    # Check if version file already exists
    $nvmrcPath = Join-Path $project.path ".nvmrc"
    $nodeVersionPath = Join-Path $project.path ".node-version"
    $packageJsonPath = Join-Path $project.path "package.json"

    $detectedVersion = Get-NodeVersionFromFile -RepoPath $project.path

    if ($detectedVersion) {
        Write-Host "  Version already detected: $detectedVersion" -ForegroundColor Green
        Write-Host "  Skipping .nvmrc creation" -ForegroundColor Gray
        $skippedCount++
    } else {
        Write-Host "  No version file found" -ForegroundColor Yellow

        # Determine version to use
        $versionToUse = $DefaultNodeVersion

        # Check if package.json has engines field that we missed
        if (Test-Path $packageJsonPath) {
            try {
                $packageJson = Get-Content $packageJsonPath -Raw | ConvertFrom-Json
                if ($packageJson.engines -and $packageJson.engines.node) {
                    Write-Host "  Found engines.node in package.json but failed to parse earlier" -ForegroundColor Yellow
                    Write-Host "  Using default: $versionToUse" -ForegroundColor Gray
                }
            } catch {
                # Ignore JSON errors
            }
        }

        if ($DryRun) {
            Write-Host "  [DRY RUN] Would create .nvmrc with version: $versionToUse" -ForegroundColor Yellow
        } else {
            Write-Host "  Creating .nvmrc with version: $versionToUse" -ForegroundColor Cyan
            $versionToUse | Set-Content $nvmrcPath -NoNewline
            $detectedVersion = $versionToUse
        }
    }

    # Run setup to install Node version and update registry
    if ($detectedVersion -and -not $DryRun) {
        Write-Host "  Running setup..." -ForegroundColor Cyan
        try {
            Push-Location $project.path
            & "$StrapRoot\strap.ps1" setup --yes 2>&1 | Out-Null
            Pop-Location

            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] Setup completed" -ForegroundColor Green
            } else {
                Write-Host "  [!] Setup failed (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
                $failedCount++
                continue
            }
        } catch {
            Write-Host "  [X] Setup error: $_" -ForegroundColor Red
            Pop-Location
            $failedCount++
            continue
        }
    }

    # Regenerate shims if they exist
    if ($project.shims -and $project.shims.Count -gt 0 -and -not $DryRun) {
        Write-Host "  Regenerating shims..." -ForegroundColor Cyan
        & "$StrapRoot\strap.ps1" shim --regen $project.name 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [OK] Shims regenerated" -ForegroundColor Green
        } else {
            Write-Host "  [!] Shim regeneration failed" -ForegroundColor Yellow
        }
    }

    if (-not $DryRun) {
        $migratedCount++
    }

    Write-Host ""
}

Write-Host "=== MIGRATION SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total projects: $($nodeProjects.Count)"
if ($DryRun) {
    Write-Host "  Would migrate: $($nodeProjects.Count - $skippedCount)"
    Write-Host "  Already have version: $skippedCount"
} else {
    Write-Host "  Migrated: $migratedCount" -ForegroundColor Green
    Write-Host "  Skipped: $skippedCount" -ForegroundColor Yellow
    Write-Host "  Failed: $failedCount" -ForegroundColor Red
}
Write-Host ""

if (-not $DryRun) {
    Write-Host "Run 'strap list' to verify node_version is set for all projects." -ForegroundColor Gray
}
