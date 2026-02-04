# tests/powershell/ChinvexConfig.Tests.ps1
Describe "Config Schema Extension" -Tag "Task1" {
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

        # Create test directory structure
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
    }

    Context "When config.json exists with minimal fields" {
        BeforeEach {
            # Create minimal config.json (no chinvex fields)
            $minimalConfig = @{
                registry = Join-Path $script:testStrapRoot "registry-v2.json"
                roots = @{
                    software = "P:\software"
                    tools = "P:\software\_scripts"
                    shims = "P:\software\_scripts\shims"
                }
            }
            $minimalConfig | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")
        }

        It "should add chinvex_integration default (true)" {
            $config = Load-Config $script:testStrapRoot
            $config.chinvex_integration | Should Be $true
        }

        It "should add chinvex_whitelist default (['tools', 'archive'])" {
            $config = Load-Config $script:testStrapRoot
            ("tools" -in $config.chinvex_whitelist) | Should Be $true
            ("archive" -in $config.chinvex_whitelist) | Should Be $true
        }

        It "should add software_root default (P:\software)" {
            $config = Load-Config $script:testStrapRoot
            $config.software_root | Should Be "P:\software"
        }

        It "should add tools_root default (P:\software\_scripts)" {
            $config = Load-Config $script:testStrapRoot
            $config.tools_root | Should Be "P:\software\_scripts"
        }
    }

    Context "When config.json has explicit chinvex fields" {
        BeforeEach {
            # Create config with explicit chinvex settings
            $explicitConfig = @{
                registry = Join-Path $script:testStrapRoot "registry-v2.json"
                roots = @{
                    software = "P:\software"
                    tools = "P:\software\_scripts"
                    shims = "P:\software\_scripts\shims"
                }
                chinvex_integration = $false
                chinvex_whitelist = @("tools", "archive", "custom-ctx")
                software_root = "D:\projects"
                tools_root = "D:\tools"
            }
            $explicitConfig | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")
        }

        It "should preserve explicit chinvex_integration value" {
            $config = Load-Config $script:testStrapRoot
            $config.chinvex_integration | Should Be $false
        }

        It "should preserve explicit chinvex_whitelist value" {
            $config = Load-Config $script:testStrapRoot
            ("custom-ctx" -in $config.chinvex_whitelist) | Should Be $true
        }

        It "should preserve explicit software_root value" {
            $config = Load-Config $script:testStrapRoot
            $config.software_root | Should Be "D:\projects"
        }

        It "should preserve explicit tools_root value" {
            $config = Load-Config $script:testStrapRoot
            $config.tools_root | Should Be "D:\tools"
        }
    }
}
