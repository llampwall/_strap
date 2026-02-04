# Remove redundant dependency loading from command files

$commandsFolder = "P:\software\_strap\commands"
$commandFiles = Get-ChildItem -Path $commandsFolder -Filter "*.ps1"

foreach ($file in $commandFiles) {
    $content = Get-Content $file.FullName -Raw

    # Find the end of the dependency block (last ". (" line)
    $lines = $content -split "`n"
    $lastDependencyIndex = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\.\s+\(Join-Path\s+\$ModulesPath\s+"[^"]+\.ps1"\)\s*$') {
            $lastDependencyIndex = $i
        }
    }

    if ($lastDependencyIndex -ge 0) {
        # Remove everything from the beginning through the last dependency line
        # Find the first line after the header comments that starts the dependency block
        $firstDependencyIndex = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*#\s+Dot-source dependencies\s*$') {
                $firstDependencyIndex = $i
                break
            }
        }

        if ($firstDependencyIndex -ge 0) {
            # Remove lines from firstDependencyIndex through lastDependencyIndex+1 (including blank line)
            $newLines = @()

            # Keep header comment and command comment
            for ($i = 0; $i -lt $firstDependencyIndex; $i++) {
                $newLines += $lines[$i]
            }

            # Skip dependency block (firstDependencyIndex through lastDependencyIndex)
            # Also skip following blank line if present
            $skipTo = $lastDependencyIndex + 1
            if ($skipTo -lt $lines.Count -and $lines[$skipTo] -match '^\s*$') {
                $skipTo++
            }

            # Add remaining lines (the actual function)
            for ($i = $skipTo; $i -lt $lines.Count; $i++) {
                $newLines += $lines[$i]
            }

            $newContent = $newLines -join "`n"
            Set-Content -Path $file.FullName -Value $newContent -NoNewline
            Write-Host "Fixed $($file.Name)" -ForegroundColor Green
        } else {
            Write-Host "Could not find dependency block start in $($file.Name)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No dependencies found in $($file.Name)" -ForegroundColor Gray
    }
}

Write-Host "`nDone. Command files no longer load dependencies." -ForegroundColor Cyan
