# tests/powershell/ChinvexClone.Tests.ps1
Describe "Invoke-Clone Chinvex Integration" -Tag "Task4" {
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

        # Create a script-scoped git function for testing
        function script:git {
            param([Parameter(ValueFromRemainingArguments=$true)]$Arguments)
            # Default implementation: create directories for clone
            if ($Arguments -and $Arguments.Count -ge 3 -and $Arguments[0] -eq "clone") {
                $dest = $Arguments[2]
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $dest ".git") -Force | Out-Null
            }
            $global:LASTEXITCODE = 0
        }

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        $script:testSoftwareRoot = Join-Path $TestDrive "software"
        $script:testToolsRoot = Join-Path $TestDrive "tools"
        $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"

        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testSoftwareRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testToolsRoot -Force | Out-Null
    }

    BeforeEach {
        # Reset config
        @{
            registry = $script:testRegistryPath
            roots = @{
                software = $script:testSoftwareRoot
                tools = $script:testToolsRoot
                shims = Join-Path $script:testToolsRoot "shims"
            }
            chinvex_integration = $true
            software_root = $script:testSoftwareRoot
            tools_root = $script:testToolsRoot
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Reset registry
        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @()
        } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    Context "Registry entry fields" {
        It "should add 'scope' field with value 'software' for default clone" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Clone -GitUrl "https://github.com/user/testrepo" -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "testrepo" }
            $entry.scope | Should Be "software"
        }

        It "should add 'scope' field with value 'tool' for --tool clone" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Clone -GitUrl "https://github.com/user/mytool" -IsTool -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "mytool" }
            $entry.scope | Should Be "tool"
        }

        It "should add 'chinvex_context' field with repo name for software scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Clone -GitUrl "https://github.com/user/myproject" -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "myproject" }
            $entry.chinvex_context | Should Be "myproject"
        }

        It "should add 'chinvex_context' field with 'tools' for tool scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Clone -GitUrl "https://github.com/user/sometool" -IsTool -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "sometool" }
            $entry.chinvex_context | Should Be "tools"
        }
    }

    Context "Chinvex sync behavior" {
        It "should set chinvex_context to null when --no-chinvex flag used" {

            Invoke-Clone -GitUrl "https://github.com/user/nochx" -NoChinvex -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "nochx" }
            $entry.chinvex_context | Should Be $null
        }

        It "should set chinvex_context to null when chinvex unavailable" {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }

            Invoke-Clone -GitUrl "https://github.com/user/noavail" -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "noavail" }
            $entry.chinvex_context | Should Be $null
        }

        It "should set chinvex_context to null when chinvex sync fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }  # Chinvex fails

            Invoke-Clone -GitUrl "https://github.com/user/failsync" -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "failsync" }
            $entry.chinvex_context | Should Be $null
        }
    }

    Context "Reserved name validation" {
        It "should reject 'tools' as software repo name" {
            { Invoke-Clone -GitUrl "https://github.com/user/tools" -StrapRootPath $script:testStrapRoot } |
                Should Throw
        }

        It "should reject 'archive' as software repo name" {
            { Invoke-Clone -GitUrl "https://github.com/user/archive" -StrapRootPath $script:testStrapRoot } |
                Should Throw
        }

        It "should allow 'tools' as tool repo name (name ignored for tool scope)" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            # Should not throw - tool repos can have any name
            { Invoke-Clone -GitUrl "https://github.com/user/tools" -IsTool -StrapRootPath $script:testStrapRoot } |
                Should Not Throw
        }
    }
}
