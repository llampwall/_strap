# Extract command functions from Commands.ps1 into individual command files

$commandsModulePath = "P:\software\_strap\modules\Commands.ps1"
$commandsFolderPath = "P:\software\_strap\commands"
$content = Get-Content $commandsModulePath -Raw

# Create commands folder
if (-not (Test-Path $commandsFolderPath)) {
    New-Item -ItemType Directory -Path $commandsFolderPath | Out-Null
    Write-Host "Created commands folder" -ForegroundColor Green
}

# Define commands to extract (function name -> file name)
$commands = @{
    "Invoke-Clone" = "clone.ps1"
    "Invoke-List" = "list.ps1"
    "Invoke-SyncChinvex" = "sync-chinvex.ps1"
    "Invoke-Open" = "open.ps1"
    "Invoke-Move" = "move.ps1"
    "Invoke-Rename" = "rename.ps1"
    "Invoke-Uninstall" = "uninstall.ps1"
    "Invoke-Shim" = "shim.ps1"
    "Invoke-Setup" = "setup.ps1"
    "Invoke-Update" = "update.ps1"
    "Invoke-Adopt" = "adopt.ps1"
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
    }
}

# Extract each command
foreach ($funcName in $commands.Keys) {
    $fileName = $commands[$funcName]
    $filePath = Join-Path $commandsFolderPath $fileName

    $boundaries = Find-FunctionBoundaries $content $funcName
    if ($boundaries) {
        $functionContent = $content.Substring($boundaries.Start, $boundaries.End - $boundaries.Start)

        # Create file with header comment
        $fileContent = @"
# $fileName
# Command: $funcName

# Dot-source dependencies
`$ModulesPath = Join-Path `$PSScriptRoot ".." "modules"
. (Join-Path `$ModulesPath "Core.ps1")
. (Join-Path `$ModulesPath "Utils.ps1")
. (Join-Path `$ModulesPath "Path.ps1")
. (Join-Path `$ModulesPath "Config.ps1")
. (Join-Path `$ModulesPath "Chinvex.ps1")
. (Join-Path `$ModulesPath "CLI.ps1")
. (Join-Path `$ModulesPath "References.ps1")

$functionContent
"@

        Set-Content -Path $filePath -Value $fileContent -NoNewline
        Write-Host "Extracted $funcName -> $fileName" -ForegroundColor Green
    } else {
        Write-Host "Function $funcName not found" -ForegroundColor Yellow
    }
}

Write-Host "`nExtracted $($commands.Count) commands to $commandsFolderPath" -ForegroundColor Cyan
