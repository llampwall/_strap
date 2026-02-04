# Extract remaining functions into new modules

$strapPath = "P:\software\_strap\strap.ps1"
$modulesDir = "P:\software\_strap\modules"

$strapContent = Get-Content $strapPath -Raw

function Extract-Function {
    param($Content, $FunctionName)

    $pattern = "function $FunctionName"
    $startIndex = $Content.IndexOf($pattern)

    if ($startIndex -eq -1) {
        Write-Host "  Function $FunctionName not found" -ForegroundColor Yellow
        return $null
    }

    # Find matching closing brace
    $braceCount = 0
    $inFunction = $false
    $endIndex = $startIndex

    for ($i = $startIndex; $i -lt $Content.Length; $i++) {
        $char = $Content[$i]
        if ($char -eq '{') {
            $braceCount++
            $inFunction = $true
        } elseif ($char -eq '}') {
            $braceCount--
            if ($inFunction -and $braceCount -eq 0) {
                $endIndex = $i + 1
                break
            }
        }
    }

    return $Content.Substring($startIndex, $endIndex - $startIndex)
}

# References.ps1 - Get-*References functions
Write-Host "Creating References.ps1..." -ForegroundColor Cyan
$referencesFunctions = @(
    "Get-ScheduledTaskReferences",
    "Get-ShimReferences",
    "Get-PathReferences",
    "Get-ProfileReferences"
)

$referencesContent = @"
# modules/References.ps1
# Functions for finding external references to repositories

# Dependencies
`$ModulesPath = `$PSScriptRoot
. (Join-Path `$ModulesPath "Core.ps1")
. (Join-Path `$ModulesPath "Utils.ps1")
. (Join-Path `$ModulesPath "Path.ps1")
. (Join-Path `$ModulesPath "Config.ps1")

"@

foreach ($funcName in $referencesFunctions) {
    Write-Host "  Extracting $funcName..."
    $funcCode = Extract-Function $strapContent $funcName
    if ($funcCode) {
        $referencesContent += "`n$funcCode`n"
    }
}

Set-Content -Path (Join-Path $modulesDir "References.ps1") -Value $referencesContent
Write-Host "  Created References.ps1" -ForegroundColor Green

# Audit.ps1 - audit and snapshot functions
Write-Host "`nCreating Audit.ps1..." -ForegroundColor Cyan
$auditFunctions = @(
    "Find-PathReferences",
    "Build-AuditIndex",
    "Invoke-Snapshot",
    "Invoke-Audit",
    "Should-ExcludePath",
    "Copy-RepoSnapshot"
)

$auditContent = @"
# modules/Audit.ps1
# Functions for auditing repositories and creating snapshots

# Dependencies
`$ModulesPath = `$PSScriptRoot
. (Join-Path `$ModulesPath "Core.ps1")
. (Join-Path `$ModulesPath "Utils.ps1")
. (Join-Path `$ModulesPath "Path.ps1")
. (Join-Path `$ModulesPath "Config.ps1")
. (Join-Path `$ModulesPath "References.ps1")

"@

foreach ($funcName in $auditFunctions) {
    Write-Host "  Extracting $funcName..."
    $funcCode = Extract-Function $strapContent $funcName
    if ($funcCode) {
        $auditContent += "`n$funcCode`n"
    }
}

Set-Content -Path (Join-Path $modulesDir "Audit.ps1") -Value $auditContent
Write-Host "  Created Audit.ps1" -ForegroundColor Green

# Consolidate.ps1 - consolidate workflow functions
Write-Host "`nCreating Consolidate.ps1..." -ForegroundColor Cyan
$consolidateFunctions = @(
    "Test-ConsolidateArgs",
    "Test-ConsolidateRegistryDisk",
    "Test-ConsolidateEdgeCaseGuards",
    "Invoke-ConsolidateExecuteMove",
    "Invoke-ConsolidateRollbackMove",
    "Invoke-ConsolidateTransaction",
    "Invoke-ConsolidateMigrationWorkflow"
)

$consolidateContent = @"
# modules/Consolidate.ps1
# Functions for the consolidate workflow

# Dependencies
`$ModulesPath = `$PSScriptRoot
. (Join-Path `$ModulesPath "Core.ps1")
. (Join-Path `$ModulesPath "Utils.ps1")
. (Join-Path `$ModulesPath "Path.ps1")
. (Join-Path `$ModulesPath "Config.ps1")
. (Join-Path `$ModulesPath "Audit.ps1")

"@

foreach ($funcName in $consolidateFunctions) {
    Write-Host "  Extracting $funcName..."
    $funcCode = Extract-Function $strapContent $funcName
    if ($funcCode) {
        $consolidateContent += "`n$funcCode`n"
    }
}

Set-Content -Path (Join-Path $modulesDir "Consolidate.ps1") -Value $consolidateContent
Write-Host "  Created Consolidate.ps1" -ForegroundColor Green

Write-Host "`nDone! Created 3 new modules." -ForegroundColor Green
