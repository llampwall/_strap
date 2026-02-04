# Extract Invoke-Audit from strap.ps1
$strapContent = Get-Content "P:\software\_strap\strap.ps1" -Raw

function Extract-Function {
    param($Content, $FunctionName)
    $startIndex = $Content.IndexOf("function $FunctionName {")
    if ($startIndex -eq -1) {
        $startIndex = $Content.IndexOf("function $FunctionName(")
        if ($startIndex -eq -1) {
            throw "Could not find $FunctionName function in strap.ps1"
        }
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

Write-Host "Extracting Invoke-Audit..." -ForegroundColor Cyan
try {
    $funcCode = Extract-Function $strapContent "Invoke-Audit"
    Write-Host "SUCCESS: Invoke-Audit function extracted" -ForegroundColor Green
    Write-Host "Function length: $($funcCode.Length) characters"
} catch {
    Write-Host "FAILED: $_" -ForegroundColor Red
    exit 1
}
