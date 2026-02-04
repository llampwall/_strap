# migrate-to-pester5.ps1
param([switch]$WhatIf)

$testFiles = Get-ChildItem -Path "tests\powershell" -Filter "*.Tests.ps1"

$replacements = @(
    # Handle "Should Not" patterns first (order matters!)
    @{ Pattern = '\|\s*Should\s+Not\s+BeNullOrEmpty'; Replacement = '| Should -Not -BeNullOrEmpty' }
    @{ Pattern = '\|\s*Should\s+Not\s+BeGreaterThan'; Replacement = '| Should -Not -BeGreaterThan' }
    @{ Pattern = '\|\s*Should\s+Not\s+BeLessThan'; Replacement = '| Should -Not -BeLessThan' }
    @{ Pattern = '\|\s*Should\s+Not\s+BeExactly'; Replacement = '| Should -Not -BeExactly' }
    @{ Pattern = '\|\s*Should\s+Not\s+BeOfType'; Replacement = '| Should -Not -BeOfType' }
    @{ Pattern = '\|\s*Should\s+Not\s+Contain'; Replacement = '| Should -Not -Contain' }
    @{ Pattern = '\|\s*Should\s+Not\s+Match'; Replacement = '| Should -Not -Match' }
    @{ Pattern = '\|\s*Should\s+Not\s+Throw'; Replacement = '| Should -Not -Throw' }
    @{ Pattern = '\|\s*Should\s+Not\s+Exist'; Replacement = '| Should -Not -Exist' }
    @{ Pattern = '\|\s*Should\s+Not\s+BeIn'; Replacement = '| Should -Not -BeIn' }
    @{ Pattern = '\|\s*Should\s+Not\s+Be\s'; Replacement = '| Should -Not -Be ' }

    # Positive assertions
    @{ Pattern = '\|\s*Should\s+BeNullOrEmpty'; Replacement = '| Should -BeNullOrEmpty' }
    @{ Pattern = '\|\s*Should\s+BeGreaterThan'; Replacement = '| Should -BeGreaterThan' }
    @{ Pattern = '\|\s*Should\s+BeLessThan'; Replacement = '| Should -BeLessThan' }
    @{ Pattern = '\|\s*Should\s+BeExactly'; Replacement = '| Should -BeExactly' }
    @{ Pattern = '\|\s*Should\s+BeOfType'; Replacement = '| Should -BeOfType' }
    @{ Pattern = '\|\s*Should\s+Contain'; Replacement = '| Should -Contain' }
    @{ Pattern = '\|\s*Should\s+Match'; Replacement = '| Should -Match' }
    @{ Pattern = '\|\s*Should\s+Throw'; Replacement = '| Should -Throw' }
    @{ Pattern = '\|\s*Should\s+Exist'; Replacement = '| Should -Exist' }
    @{ Pattern = '\|\s*Should\s+BeIn'; Replacement = '| Should -BeIn' }
    @{ Pattern = '\|\s*Should\s+Be\s'; Replacement = '| Should -Be ' }

    # Mock assertions
    @{ Pattern = 'Assert-MockCalled\s+'; Replacement = 'Should -Invoke ' }
)

$changesLog = @()

foreach ($file in $testFiles) {
    $content = Get-Content $file.FullName -Raw
    $originalContent = $content
    $fileChanges = 0

    foreach ($replacement in $replacements) {
        $matches = [regex]::Matches($content, $replacement.Pattern)
        if ($matches.Count -gt 0) {
            $content = $content -replace $replacement.Pattern, $replacement.Replacement
            $fileChanges += $matches.Count
        }
    }

    if ($fileChanges -gt 0) {
        $changesLog += [PSCustomObject]@{
            File = $file.Name
            Changes = $fileChanges
        }

        if (-not $WhatIf) {
            Set-Content -Path $file.FullName -Value $content -NoNewline
            Write-Host "Updated $($file.Name): $fileChanges changes" -ForegroundColor Green
        } else {
            Write-Host "Would update $($file.Name): $fileChanges changes" -ForegroundColor Yellow
        }
    }
}

$changesLog | Format-Table -AutoSize
Write-Host "`nTotal files modified: $($changesLog.Count)" -ForegroundColor Cyan
Write-Host "Total changes: $(($changesLog | Measure-Object -Property Changes -Sum).Sum)" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "`nRun without -WhatIf to apply changes" -ForegroundColor Yellow
}
