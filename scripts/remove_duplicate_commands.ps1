# Remove duplicate command functions from strap.ps1

$strapPath = "P:\software\_strap\strap.ps1"
$content = Get-Content $strapPath -Raw

# Functions to remove
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

function Get-FunctionBounds {
    param($Content, $FunctionName)

    $startIndex = $Content.IndexOf("function $FunctionName")
    if ($startIndex -eq -1) {
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
                # Include trailing newlines
                while ($endIndex -lt $Content.Length -and $Content[$endIndex] -match '[\r\n]') {
                    $endIndex++
                }
                break
            }
        }
    }

    return @{Start = $startIndex; End = $endIndex}
}

# Collect all function ranges (in reverse order to remove from end first)
$ranges = @()
foreach ($funcName in $functions) {
    $bounds = Get-FunctionBounds $content $funcName
    if ($bounds) {
        $ranges += [PSCustomObject]@{
            Name = $funcName
            Start = $bounds.Start
            End = $bounds.End
        }
    }
}

# Sort by start position (descending) to remove from end first
$ranges = $ranges | Sort-Object -Property Start -Descending

# Remove each function and replace with comment
foreach ($range in $ranges) {
    $before = $content.Substring(0, $range.Start)
    $after = $content.Substring($range.End)
    $comment = "# NOTE: $($range.Name) moved to modules\Commands.ps1`n"
    $content = $before + $comment + $after
    Write-Host "Removed $($range.Name)"
}

# Write back
Set-Content -Path $strapPath -Value $content -NoNewline

Write-Host "`nDone! Removed $($ranges.Count) command functions"
