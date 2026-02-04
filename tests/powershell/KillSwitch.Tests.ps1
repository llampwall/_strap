# KillSwitch.Tests.ps1
# Verifies all kill-switched functions warn and exit without executing

Describe "Kill Switch" {
    BeforeAll {
        # Dot-source all strap modules (includes UNSAFE_COMMANDS and Assert-CommandSafe)
        $modulesPath = "$PSScriptRoot\..\..\modules"
        . "$modulesPath\Core.ps1"
        . "$modulesPath\Utils.ps1"
        . "$modulesPath\Path.ps1"
        . "$modulesPath\Config.ps1"
        . "$modulesPath\Chinvex.ps1"
        . "$modulesPath\CLI.ps1"
        . "$modulesPath\References.ps1"
        . "$modulesPath\Audit.ps1"
        . "$modulesPath\Consolidate.ps1"
        $commandsPath = Join-Path $modulesPath "Commands"
        Get-ChildItem -Path $commandsPath -Filter "*.ps1" | ForEach-Object {
            . $_.FullName
        }

        # Source strap.ps1 to get the kill-switched functions
        . "$PSScriptRoot\..\..\strap.ps1"
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
