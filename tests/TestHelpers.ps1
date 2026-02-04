# TestHelpers.ps1
# Shared test utilities for loading strap functions

function Import-StrapModules {
    <#
    .SYNOPSIS
        Loads all strap modules for testing
    #>
    $modulesPath = "$PSScriptRoot\..\modules"
    . "$modulesPath\Core.ps1"
    . "$modulesPath\Utils.ps1"
    . "$modulesPath\Path.ps1"
    . "$modulesPath\Config.ps1"
    . "$modulesPath\Chinvex.ps1"
}

function Extract-StrapFunction {
    <#
    .SYNOPSIS
        Extracts a function from strap.ps1 for testing
    .PARAMETER FunctionName
        Name of the function to extract
    #>
    param([string]$FunctionName)

    $strapPath = "$PSScriptRoot\..\strap.ps1"
    $content = Get-Content $strapPath -Raw

    $startIndex = $content.IndexOf("function $FunctionName")
    if ($startIndex -eq -1) {
        Write-Warning "Could not find $FunctionName function in strap.ps1 - may already be in modules"
        return
    }

    $braceCount = 0
    $inFunction = $false
    $endIndex = $startIndex

    for ($i = $startIndex; $i -lt $content.Length; $i++) {
        $char = $content[$i]
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

    $funcCode = $content.Substring($startIndex, $endIndex - $startIndex)

    # Create a scriptblock and invoke it at script scope
    $sb = [scriptblock]::Create($funcCode)
    & $sb
}

function Import-StrapFunctions {
    <#
    .SYNOPSIS
        Imports all modules and extracts additional functions from strap.ps1
    .PARAMETER AdditionalFunctions
        Array of function names to extract from strap.ps1
    #>
    param([string[]]$AdditionalFunctions = @())

    # Import all modules first
    Import-StrapModules

    # Extract any additional functions needed
    foreach ($funcName in $AdditionalFunctions) {
        Extract-StrapFunction $funcName
    }
}
