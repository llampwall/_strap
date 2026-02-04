# Remove functions from strap.ps1 that were extracted to modules

$strapPath = "P:\software\_strap\strap.ps1"
$strapContent = Get-Content $strapPath -Raw

# Functions that were extracted to modules
$functionsToRemove = @(
    # Core.ps1
    "Ensure-Command",
    # Chinvex.ps1
    "Test-ChinvexAvailable",
    "Test-ChinvexEnabled",
    "Invoke-Chinvex",
    "Invoke-ChinvexQuery",
    "Detect-RepoScope",
    "Get-ContextName",
    "Test-ReservedContextName",
    "Sync-ChinvexForEntry",
    # Config.ps1
    "Load-Registry",
    "Save-Registry",
    "Get-RegistryVersion",
    "Validate-RegistrySchema"
)

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
    }
}

# Collect all function boundaries
$removals = @()
foreach ($funcName in $functionsToRemove) {
    $boundaries = Find-FunctionBoundaries $strapContent $funcName
    if ($boundaries) {
        $removals += @{
            Name = $funcName
            Start = $boundaries.Start
            End = $boundaries.End
        }
        Write-Host "Found $funcName at $($boundaries.Start)-$($boundaries.End)" -ForegroundColor Yellow
    } else {
        Write-Host "Function $funcName not found (may already be removed)" -ForegroundColor Gray
    }
}

# Sort by start index descending (remove from end first to maintain indices)
$removals = $removals | Sort-Object -Property Start -Descending

# Remove each function
foreach ($removal in $removals) {
    $before = $strapContent.Substring(0, $removal.Start)
    $after = $strapContent.Substring($removal.End)
    $strapContent = $before + $after
    Write-Host "Removed $($removal.Name)" -ForegroundColor Green
}

# Write back
Set-Content -Path $strapPath -Value $strapContent -NoNewline

Write-Host "`nRemoved $($removals.Count) functions from strap.ps1" -ForegroundColor Cyan

# Show new line count
$newLines = ($strapContent -split "`n").Count
Write-Host "New line count: $newLines" -ForegroundColor Cyan
