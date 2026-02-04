# Extract remaining critical functions from strap.ps1 to appropriate modules

$strapPath = "P:\software\_strap\strap.ps1"
$strapContent = Get-Content $strapPath -Raw

# Define functions to extract and their destination modules
$extractionMap = @{
    "Core.ps1" = @("Ensure-Command")
    "Chinvex.ps1" = @(
        "Test-ChinvexAvailable",
        "Test-ChinvexEnabled",
        "Invoke-Chinvex",
        "Invoke-ChinvexQuery",
        "Detect-RepoScope",
        "Get-ContextName",
        "Test-ReservedContextName",
        "Sync-ChinvexForEntry"
    )
    "Config.ps1" = @(
        "Load-Registry",
        "Save-Registry",
        "Get-RegistryVersion",
        "Validate-RegistrySchema"
    )
}

function Find-FunctionBoundaries {
    param($Content, $FunctionName)

    $pattern = "function $FunctionName"
    $startIndex = $Content.IndexOf($pattern)

    if ($startIndex -eq -1) {
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

    # Include trailing newlines
    while ($endIndex -lt $Content.Length -and $Content[$endIndex] -match '[\r\n]') {
        $endIndex++
    }

    return @{
        Start = $startIndex
        End = $endIndex
        Content = $Content.Substring($startIndex, $endIndex - $startIndex)
    }
}

# Extract and append functions to modules
foreach ($moduleName in $extractionMap.Keys) {
    $modulePath = "P:\software\_strap\modules\$moduleName"
    $functions = $extractionMap[$moduleName]

    $functionsToAdd = @()
    foreach ($funcName in $functions) {
        $boundaries = Find-FunctionBoundaries $strapContent $funcName
        if ($boundaries) {
            $functionsToAdd += $boundaries.Content
            Write-Host "Found $funcName for $moduleName" -ForegroundColor Green
        } else {
            Write-Host "Function $funcName not found in strap.ps1" -ForegroundColor Yellow
        }
    }

    if ($functionsToAdd.Count -gt 0) {
        # Append functions to module
        $moduleContent = Get-Content $modulePath -Raw
        $newModuleContent = $moduleContent.TrimEnd() + "`n`n# Functions extracted from strap.ps1`n" + ($functionsToAdd -join "`n")
        Set-Content -Path $modulePath -Value $newModuleContent -NoNewline
        Write-Host "Added $($functionsToAdd.Count) functions to $moduleName" -ForegroundColor Cyan
    }
}

Write-Host "`nExtraction complete. Functions added to modules." -ForegroundColor Green
Write-Host "NOTE: Functions are still in strap.ps1. You may want to remove them manually or keep them for compatibility." -ForegroundColor Yellow
