# Remove extracted functions from strap.ps1

$strapPath = "P:\software\_strap\strap.ps1"
$strapContent = Get-Content $strapPath -Raw

$functionsToRemove = @(
    # References.ps1
    "Get-ScheduledTaskReferences",
    "Get-ShimReferences",
    "Get-PathReferences",
    "Get-ProfileReferences",
    # Audit.ps1
    "Find-PathReferences",
    "Build-AuditIndex",
    "Invoke-Snapshot",
    "Invoke-Audit",
    "Should-ExcludePath",
    "Copy-RepoSnapshot",
    # Consolidate.ps1
    "Test-ConsolidateArgs",
    "Test-ConsolidateRegistryDisk",
    "Test-ConsolidateEdgeCaseGuards",
    "Invoke-ConsolidateExecuteMove",
    "Invoke-ConsolidateRollbackMove",
    "Invoke-ConsolidateTransaction",
    "Invoke-ConsolidateMigrationWorkflow"
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
        Write-Host "Found $funcName at $($boundaries.Start)-$($boundaries.End)"
    } else {
        Write-Host "Function $funcName not found (may already be removed)" -ForegroundColor Yellow
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

Write-Host "`nRemoved $($removals.Count) functions from strap.ps1" -ForegroundColor Green

# Show new line count
$newLines = ($strapContent -split "`n").Count
Write-Host "New line count: $newLines" -ForegroundColor Cyan
