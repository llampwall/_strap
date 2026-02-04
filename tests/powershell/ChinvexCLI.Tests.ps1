# tests/powershell/ChinvexCLI.Tests.ps1
Describe "CLI Dispatch Wiring for Chinvex Flags" -Tag "Task6" {
    BeforeAll {
        # Dot-source all strap modules
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

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
    }

    Context "Parse-GlobalFlags function" {
        It "should extract --no-chinvex flag from arguments" {
            $args = @("clone", "https://github.com/user/repo", "--no-chinvex")
            $result = Parse-GlobalFlags $args

            $result.NoChinvex | Should -Be $true
            $result.RemainingArgs -contains "--no-chinvex" | Should -Be $false
        }

        It "should extract --tool flag from arguments" {
            $args = @("clone", "https://github.com/user/repo", "--tool")
            $result = Parse-GlobalFlags $args

            $result.IsTool | Should -Be $true
            $result.RemainingArgs -contains "--tool" | Should -Be $false
        }

        It "should extract --software flag from arguments" {
            $args = @("adopt", "--path", "P:\software\repo", "--software")
            $result = Parse-GlobalFlags $args

            $result.IsSoftware | Should -Be $true
            $result.RemainingArgs -contains "--software" | Should -Be $false
        }

        It "should preserve other arguments" {
            $args = @("clone", "https://github.com/user/repo", "--no-chinvex", "--name", "myrepo")
            $result = Parse-GlobalFlags $args

            $result.NoChinvex | Should -Be $true
            $result.RemainingArgs -contains "--name" | Should -Be $true
            $result.RemainingArgs -contains "myrepo" | Should -Be $true
        }

        It "should handle multiple chinvex flags" {
            $args = @("clone", "https://github.com/user/repo", "--tool", "--no-chinvex")
            $result = Parse-GlobalFlags $args

            $result.NoChinvex | Should -Be $true
            $result.IsTool | Should -Be $true
        }

        It "should return false for flags not present" {
            $args = @("clone", "https://github.com/user/repo")
            $result = Parse-GlobalFlags $args

            $result.NoChinvex | Should -Be $false
            $result.IsTool | Should -Be $false
            $result.IsSoftware | Should -Be $false
        }
    }

    Context "Registry field round-trip" {
        BeforeEach {
            # Setup test config and registry
            $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"
            @{
                registry = $script:testRegistryPath
                roots = @{
                    software = "P:\software"
                    tools = "P:\software\_scripts"
                    shims = "P:\software\_scripts\shims"
                }
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

            # Create registry with scope and chinvex_context fields
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "testrepo"
                        name = "testrepo"
                        path = "P:\software\testrepo"
                        scope = "software"
                        chinvex_context = "testrepo"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should preserve scope field on registry load/save" {
            # Load and save without modification
            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entries = $registry.entries

            # Verify scope exists
            $entry = $entries | Where-Object { $_.name -eq "testrepo" }
            $entry.scope | Should -Be "software"

            # Re-save
            $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

            # Re-load and verify
            $reloaded = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $reloadedEntry = $reloaded.entries | Where-Object { $_.name -eq "testrepo" }
            $reloadedEntry.scope | Should -Be "software"
        }

        It "should preserve chinvex_context field on registry load/save" {
            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "testrepo" }
            $entry.chinvex_context | Should -Be "testrepo"

            # Re-save and reload
            $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
            $reloaded = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $reloadedEntry = $reloaded.entries | Where-Object { $_.name -eq "testrepo" }
            $reloadedEntry.chinvex_context | Should -Be "testrepo"
        }

        It "should preserve null chinvex_context value" {
            # Update registry with null chinvex_context
            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "testrepo" }
            $entry.chinvex_context = $null
            $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

            # Re-load and verify null is preserved
            $reloaded = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $reloadedEntry = $reloaded.entries | Where-Object { $_.name -eq "testrepo" }
            $reloadedEntry.chinvex_context | Should -Be $null
        }
    }
}
