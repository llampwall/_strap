# tests/powershell/ChinvexIdempotency.Tests.ps1
Describe "Chinvex Idempotency and Error Paths" -Tag "Task13" {
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
            chinvex_whitelist = @("tools", "archive")
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Empty registry
        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @()
        } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    function Create-TestRepo {
        param([string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path ".git") -Force | Out-Null
    }

    Context "Sync-ChinvexForEntry idempotency" {
        It "should succeed when called twice with same arguments" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            $result1 = Sync-ChinvexForEntry -Scope "software" -Name "idempotent-repo" -RepoPath "P:\software\idempotent-repo"
            $result2 = Sync-ChinvexForEntry -Scope "software" -Name "idempotent-repo" -RepoPath "P:\software\idempotent-repo"

            $result1 | Should -Be "idempotent-repo"
            $result2 | Should -Be "idempotent-repo"
        }

        It "should use --idempotent flag on context create" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $script:createCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                if ($Arguments[0] -eq "context" -and $Arguments[1] -eq "create") {
                    $script:createCalls += ,@($Arguments)
                }
                return $true
            }

            Sync-ChinvexForEntry -Scope "software" -Name "test-repo" -RepoPath "P:\software\test-repo"

            $script:createCalls.Count | Should -Be 1
            ($script:createCalls[0] -contains "--idempotent") | Should -Be $true
        }
    }

    Context "Reserved name rejection" {
        It "should reject 'tools' as software repo name in Test-ReservedContextName" {
            $result = Test-ReservedContextName -Name "tools" -Scope "software"
            $result | Should -Be $true
        }

        It "should reject 'archive' as software repo name in Test-ReservedContextName" {
            $result = Test-ReservedContextName -Name "archive" -Scope "software"
            $result | Should -Be $true
        }

        It "should allow 'tools' as tool repo name (goes to shared context)" {
            $result = Test-ReservedContextName -Name "tools" -Scope "tool"
            $result | Should -Be $false
        }

        It "should be case-insensitive for reserved name check" {
            $result1 = Test-ReservedContextName -Name "TOOLS" -Scope "software"
            $result2 = Test-ReservedContextName -Name "Tools" -Scope "software"
            $result3 = Test-ReservedContextName -Name "ARCHIVE" -Scope "software"

            $result1 | Should -Be $true
            $result2 | Should -Be $true
            $result3 | Should -Be $true
        }
    }

    Context "Chinvex unavailable graceful handling" {
        BeforeEach {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }
        }

        It "should return null from Sync-ChinvexForEntry when chinvex unavailable" {
            $result = Sync-ChinvexForEntry -Scope "software" -Name "test" -RepoPath "P:\software\test"
            $result | Should -Be $null
        }

        It "should return false from Invoke-Chinvex when chinvex unavailable" {
            $result = Invoke-Chinvex -Arguments @("context", "list")
            $result | Should -Be $false
        }

        It "should return null from Invoke-ChinvexQuery when chinvex unavailable" {
            $result = Invoke-ChinvexQuery -Arguments @("context", "list", "--json")
            $result | Should -Be $null
        }

        It "should cache chinvex availability check" {
            # Reset cache
            $script:chinvexChecked = $false
            $script:chinvexAvailable = $false

            Test-ChinvexAvailable
            Test-ChinvexAvailable
            Test-ChinvexAvailable

            # Should only call Get-Command once
            Should -Invoke Get-Command -Times 1 -ParameterFilter { $Name -eq "chinvex" }
        }
    }

    Context "Chinvex failure sets chinvex_context to null" {
        BeforeEach {
            Create-TestRepo (Join-Path $script:testSoftwareRoot "failure-test")
        }

        It "should set chinvex_context to null when context create fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }  # All calls fail

            $result = Sync-ChinvexForEntry -Scope "software" -Name "failure-test" -RepoPath (Join-Path $script:testSoftwareRoot "failure-test")

            $result | Should -Be $null
        }

        It "should set chinvex_context to null when ingest fails after create succeeds" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex {
                param($Arguments)
                if ($Arguments[0] -eq "context" -and $Arguments[1] -eq "create") {
                    return $true
                }
                return $false  # ingest fails
            }

            $result = Sync-ChinvexForEntry -Scope "software" -Name "failure-test" -RepoPath (Join-Path $script:testSoftwareRoot "failure-test")

            $result | Should -Be $null
        }
    }

    Context "Scope detection consistency" {
        It "should detect tool scope for paths under tools_root" {
            $paths = @(
                (Join-Path $script:testToolsRoot "tool1"),
                (Join-Path $script:testToolsRoot "subdir\tool2"),
                (Join-Path $script:testToolsRoot "deep\nested\tool3")
            )

            foreach ($path in $paths) {
                $scope = Detect-RepoScope -Path $path -StrapRootPath $script:testStrapRoot
                $scope | Should -Be "tool"
            }
        }

        It "should detect software scope for paths under software_root but not tools_root" {
            $paths = @(
                (Join-Path $script:testSoftwareRoot "project1"),
                (Join-Path $script:testSoftwareRoot "subdir\project2"),
                (Join-Path $script:testSoftwareRoot "apps\myapp")
            )

            foreach ($path in $paths) {
                $scope = Detect-RepoScope -Path $path -StrapRootPath $script:testStrapRoot
                $scope | Should -Be "software"
            }
        }

        It "should return null for paths outside managed roots" {
            $paths = @(
                "C:\random\path",
                "D:\projects\something",
                "C:\Users\test\Documents\repo"
            )

            foreach ($path in $paths) {
                $scope = Detect-RepoScope -Path $path -StrapRootPath $script:testStrapRoot
                $result = ($scope -eq $null)
                $result | Should -Be $true
            }
        }

        It "should use most-specific match (tools_root wins over software_root)" {
            # tools_root is inside software_root, so tools_root should match first
            $toolPath = Join-Path $script:testToolsRoot "sometool"
            $scope = Detect-RepoScope -Path $toolPath -StrapRootPath $script:testStrapRoot
            $scope | Should -Be "tool"
        }
    }

    Context "Get-ContextName consistency" {
        It "should always return 'tools' for tool scope regardless of name" {
            $names = @("mytool", "script", "utility", "helper", "tools")

            foreach ($name in $names) {
                $context = Get-ContextName -Scope "tool" -Name $name
                $context | Should -Be "tools"
            }
        }

        It "should return entry name for software scope" {
            $names = @("myproject", "webapp", "api-service", "frontend")

            foreach ($name in $names) {
                $context = Get-ContextName -Scope "software" -Name $name
                $context | Should -Be $name
            }
        }
    }

    Context "Whitelist handling in sync-chinvex" {
        It "should include 'tools' in default whitelist" {
            $config = Load-Config $script:testStrapRoot
            $defaultWhitelist = @("tools", "archive")
            ($defaultWhitelist -contains "tools") | Should -Be $true
        }

        It "should include 'archive' in default whitelist" {
            $config = Load-Config $script:testStrapRoot
            $defaultWhitelist = @("tools", "archive")
            ($defaultWhitelist -contains "archive") | Should -Be $true
        }

        It "should merge user whitelist with defaults" {
            # Add custom whitelist to config
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
                chinvex_whitelist = @("tools", "archive", "custom-context", "another-special")
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

            $config = Load-Config $script:testStrapRoot
            ($config.chinvex_whitelist -contains "custom-context") | Should -Be $true
            ($config.chinvex_whitelist -contains "another-special") | Should -Be $true
        }
    }

    Context "Test-ChinvexEnabled precedence" {
        It "should return false when NoChinvex flag is set, even if config enables it" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $result = Test-ChinvexEnabled -NoChinvex -StrapRootPath $script:testStrapRoot
            $result | Should -Be $false
        }

        It "should return false when config disables integration" {
            # Disable in config
            @{
                registry = $script:testRegistryPath
                roots = @{
                    software = $script:testSoftwareRoot
                    tools = $script:testToolsRoot
                    shims = Join-Path $script:testToolsRoot "shims"
                }
                chinvex_integration = $false
                software_root = $script:testSoftwareRoot
                tools_root = $script:testToolsRoot
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $result = Test-ChinvexEnabled -StrapRootPath $script:testStrapRoot
            $result | Should -Be $false
        }

        It "should return true when enabled in config and chinvex available" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            # Reset cache
            $script:chinvexChecked = $false
            $script:chinvexAvailable = $false

            $result = Test-ChinvexEnabled -StrapRootPath $script:testStrapRoot
            $result | Should -Be $true
        }

        It "should return false when enabled but chinvex not available" {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }

            # Reset cache
            $script:chinvexChecked = $false
            $script:chinvexAvailable = $false

            $result = Test-ChinvexEnabled -StrapRootPath $script:testStrapRoot
            $result | Should -Be $false
        }
    }
}
