# Run a single test with timeout
$testCode = @'
Describe "Invoke-Audit Quick Test" {
    BeforeAll {
        # Extract functions from strap.ps1
        $strapContent = Get-Content "$PSScriptRoot\strap.ps1" -Raw

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

        # Extract Invoke-Audit
        $funcCode = Extract-Function $strapContent "Invoke-Audit"
        Invoke-Expression $funcCode
    }

    It "should have Invoke-Audit function" {
        { Get-Command Invoke-Audit -ErrorAction Stop } | Should -Not -Throw
    }
}
'@

$testFile = Join-Path $PWD "temp_test.ps1"
$testCode | Set-Content $testFile

Write-Host "Running quick test..." -ForegroundColor Cyan

$config = New-PesterConfiguration
$config.Run.Path = $testFile
$config.Output.Verbosity = 'Detailed'

Invoke-Pester -Configuration $config

Remove-Item $testFile
