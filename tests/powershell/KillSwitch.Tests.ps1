# KillSwitch.Tests.ps1
# Verifies all kill-switched functions warn and exit without executing

Describe "Kill Switch" {
    BeforeAll {
        # Read strap.ps1 and extract all function definitions
        $strapPath = "$PSScriptRoot\..\..\strap.ps1"
        $strapContent = Get-Content $strapPath -Raw

        # Remove the param block and main script execution
        # Keep only function definitions by finding functions and extracting them

        # First, get the UNSAFE_COMMANDS array and Assert-CommandSafe
        $killSwitchPattern = '(?s)\$UNSAFE_COMMANDS = @\([^)]+\)\s*function Assert-CommandSafe \{[^}]+\{[^}]+\}[^}]+\}'
        if ($strapContent -match $killSwitchPattern) {
            Invoke-Expression $Matches[0]
        }

        # Now extract each function we need to test
        $functionsToExtract = @(
            'Invoke-Snapshot',
            'Invoke-Audit',
            'Invoke-Migrate',
            'Invoke-Migration-0-to-1',
            'Should-ExcludePath',
            'Copy-RepoSnapshot',
            'Invoke-ConsolidateExecuteMove',
            'Invoke-ConsolidateRollbackMove',
            'Invoke-ConsolidateTransaction',
            'Invoke-ConsolidateMigrationWorkflow',
            'Test-ConsolidateArgs',
            'Test-ConsolidateRegistryDisk',
            'Test-ConsolidateEdgeCaseGuards'
        )

        foreach ($funcName in $functionsToExtract) {
            # Find function start
            $pattern = "function $funcName"
            $startIndex = $strapContent.IndexOf($pattern)
            if ($startIndex -eq -1) {
                Write-Warning "Could not find function $funcName"
                continue
            }

            # Find matching closing brace
            $braceCount = 0
            $inFunction = $false
            $endIndex = $startIndex

            for ($i = $startIndex; $i -lt $strapContent.Length; $i++) {
                $char = $strapContent[$i]
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

            $funcCode = $strapContent.Substring($startIndex, $endIndex - $startIndex)
            try {
                Invoke-Expression $funcCode
            } catch {
                Write-Warning "Failed to load $funcName : $_"
            }
        }
    }

    It "Invoke-Snapshot should be disabled" {
        $warnings = @()
        $result = Invoke-Snapshot -OutputPath "test.json" -StrapRootPath "C:\fake" -WarningVariable warnings 3>&1
        ($warnings -join ' ') | Should Match "DISABLED"
    }

    It "Invoke-Audit should be disabled" {
        $result = Invoke-Audit -StrapRootPath "C:\fake" 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }

    It "Invoke-Migrate should be disabled" {
        $result = Invoke-Migrate -StrapRootPath "C:\fake" 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }

    It "Invoke-Migration-0-to-1 should be disabled" {
        $report = @{}
        $result = Invoke-Migration-0-to-1 -RegistryData @{} -Report ([ref]$report) 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }

    It "Should-ExcludePath should be disabled" {
        $result = Should-ExcludePath "C:\test\path" "C:\test" 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }

    It "Copy-RepoSnapshot should be disabled" {
        $result = Copy-RepoSnapshot "C:\fake\src" "C:\fake\dest" 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }

    It "Invoke-ConsolidateExecuteMove should be disabled" {
        $result = Invoke-ConsolidateExecuteMove -Name "test" -FromPath "C:\fake" -ToPath "C:\fake2" 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }

    It "Invoke-ConsolidateRollbackMove should be disabled" {
        $result = Invoke-ConsolidateRollbackMove -Name "test" -FromPath "C:\fake" -ToPath "C:\fake2" 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }

    It "Invoke-ConsolidateTransaction should be disabled" {
        $result = Invoke-ConsolidateTransaction -Plans @() -Config @{} -Registry @() -StrapRootPath "C:\fake" 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }

    It "Invoke-ConsolidateMigrationWorkflow should be disabled" {
        $result = Invoke-ConsolidateMigrationWorkflow -FromPath "C:\fake" -StrapRootPath "C:\fake" 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }

    It "Test-ConsolidateArgs should be disabled" {
        $result = Test-ConsolidateArgs -FromPath "C:\fake" -TrustMode "registry-first" 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }

    It "Test-ConsolidateRegistryDisk should be disabled" {
        $result = Test-ConsolidateRegistryDisk -RegisteredMoves @() -DiscoveredCandidates @() 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }

    It "Test-ConsolidateEdgeCaseGuards should be disabled" {
        $result = Test-ConsolidateEdgeCaseGuards -MovePlans @() 3>&1
        ($result -join ' ') | Should Match "DISABLED"
    }
}
