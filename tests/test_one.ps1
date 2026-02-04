# Simple one-test check
$ErrorActionPreference = "Stop"

# Extract functions
$strapContent = Get-Content "P:\software\_strap\strap.ps1" -Raw

function Extract-Function {
    param($Content, $FunctionName)
    $startIndex = $Content.IndexOf("function $FunctionName {")
    if ($startIndex -eq -1) {
        $startIndex = $Content.IndexOf("function $FunctionName(")
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

foreach ($funcName in @("Invoke-Audit", "Build-AuditIndex", "Find-PathReferences", "Load-Config", "Die")) {
    Invoke-Expression (Extract-Function $strapContent $funcName)
}

Write-Host "TEST 1: Function exists" -ForegroundColor Cyan
Get-Command Invoke-Audit -ErrorAction Stop | Out-Null
Write-Host "  PASS" -ForegroundColor Green

Write-Host "TEST 2: Function has correct parameters" -ForegroundColor Cyan
$cmd = Get-Command Invoke-Audit
$paramNames = $cmd.Parameters.Keys
if ($paramNames -contains "TargetName" -and $paramNames -contains "AllRepos" -and $paramNames -contains "OutputJson") {
    Write-Host "  PASS" -ForegroundColor Green
} else {
    Write-Host "  FAIL: Missing expected parameters" -ForegroundColor Red
    exit 1
}

Write-Host "`nAll basic tests passed!" -ForegroundColor Green
