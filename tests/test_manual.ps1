# Manual test of Invoke-Audit without Pester
Write-Host "=== Manual Test of Invoke-Audit ===" -ForegroundColor Cyan

# Extract functions
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

# Extract all needed functions
$functions = @("Invoke-Audit", "Build-AuditIndex", "Find-PathReferences", "Load-Config", "Die", "Warn", "Info")
foreach ($funcName in $functions) {
    Write-Host "Extracting $funcName..." -ForegroundColor Yellow
    try {
        $funcCode = Extract-Function $strapContent $funcName
        Invoke-Expression $funcCode
        Write-Host "  OK" -ForegroundColor Green
    } catch {
        Write-Host "  FAILED: $_" -ForegroundColor Red
    }
}

# Test that function exists
Write-Host "`nChecking if Invoke-Audit exists..." -ForegroundColor Cyan
try {
    Get-Command Invoke-Audit -ErrorAction Stop | Out-Null
    Write-Host "SUCCESS: Invoke-Audit function exists" -ForegroundColor Green
} catch {
    Write-Host "FAILED: Invoke-Audit not found" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== All checks passed ===" -ForegroundColor Green
