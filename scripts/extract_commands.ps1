# Extract command functions from strap.ps1 into Commands.ps1

$strapPath = "P:\software\_strap\strap.ps1"
$commandsModulePath = "P:\software\_strap\modules\Commands.ps1"

# Read strap.ps1
$content = Get-Content $strapPath -Raw

# Function names to extract
$functions = @(
    "Invoke-Clone",
    "Invoke-List",
    "Invoke-SyncChinvex",
    "Invoke-Open",
    "Invoke-Move",
    "Invoke-Rename",
    "Invoke-Uninstall",
    "Invoke-Shim",
    "Invoke-Setup",
    "Invoke-Update",
    "Invoke-Adopt"
)

# Extract function helper
function Extract-FunctionCode {
    param($Content, $FunctionName)

    $startIndex = $Content.IndexOf("function $FunctionName")
    if ($startIndex -eq -1) {
        Write-Warning "Could not find $FunctionName"
        return $null
    }

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

# Build module content
$moduleContent = @"
# Commands.ps1
# Main command implementations for strap

# Dot-source dependencies
. "`$PSScriptRoot\Core.ps1"
. "`$PSScriptRoot\Utils.ps1"
. "`$PSScriptRoot\Path.ps1"
. "`$PSScriptRoot\Config.ps1"
. "`$PSScriptRoot\Chinvex.ps1"
. "`$PSScriptRoot\CLI.ps1"

# ============================================================================
# COMMAND FUNCTIONS
# ============================================================================

"@

foreach ($funcName in $functions) {
    Write-Host "Extracting $funcName..."
    $funcCode = Extract-FunctionCode $content $funcName
    if ($funcCode) {
        $moduleContent += "`n$funcCode`n"
    }
}

$moduleContent += "`n# Functions are automatically available when dot-sourced`n"

# Write module file
Set-Content -Path $commandsModulePath -Value $moduleContent -NoNewline

Write-Host "`nCommands.ps1 created successfully!"
$lines = ($moduleContent -split "`n").Count
Write-Host "Module size: $lines lines"
