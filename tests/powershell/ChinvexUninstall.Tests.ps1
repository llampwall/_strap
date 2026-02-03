# tests/powershell/ChinvexUninstall.Tests.ps1
Describe "Invoke-Uninstall Chinvex Integration" -Tag "Task9" {
    BeforeAll {
        # Extract functions from strap.ps1
        $strapContent = Get-Content "$PSScriptRoot\..\..\strap.ps1" -Raw

        function Extract-Function {
            param($Content, $FunctionName)
            $startIndex = $Content.IndexOf("function $FunctionName")
            if ($startIndex -eq -1) {
                throw "Could not find $FunctionName function in strap.ps1"
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
        $functions = @(
            "Die", "Warn", "Info", "Ok", "Load-Config", "Load-Registry", "Save-Registry",
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex",
            "Detect-RepoScope", "Get-ContextName",
            "Invoke-Uninstall"
        )
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                Write-Warning "Could not extract $funcName"
            }
        }

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        $script:testSoftwareRoot = Join-Path $TestDrive "software"
        $script:testToolsRoot = Join-Path $TestDrive "tools"
        $script:testShimsRoot = Join-Path $script:testToolsRoot "shims"
        $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"

        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testSoftwareRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testToolsRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testShimsRoot -Force | Out-Null
    }

    BeforeEach {
        # Reset config
        @{
            registry = $script:testRegistryPath
            roots = @{
                software = $script:testSoftwareRoot
                tools = $script:testToolsRoot
                shims = $script:testShimsRoot
            }
            chinvex_integration = $true
            software_root = $script:testSoftwareRoot
            tools_root = $script:testToolsRoot
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    function Create-TestRepo {
        param([string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path ".git") -Force | Out-Null
    }

    Context "Uninstall software repo" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "uninstallsoft"
            Create-TestRepo $script:repoPath

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "uninstallsoft"
                        name = "uninstallsoft"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "uninstallsoft"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should call chinvex context archive for software scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $script:chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $script:chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Uninstall -NameToRemove "uninstallsoft" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should call context archive
            $archiveCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "archive" }
            $archiveCall | Should Not Be $null
            ($archiveCall -contains "uninstallsoft") | Should Be $true
        }

        It "should remove entry from registry after uninstall" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Uninstall -NameToRemove "uninstallsoft" -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "uninstallsoft" }
            $entry | Should Be $null
        }

        It "should delete folder on uninstall" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Uninstall -NameToRemove "uninstallsoft" -NonInteractive -StrapRootPath $script:testStrapRoot

            (Test-Path $script:repoPath) | Should Be $false
        }
    }

    Context "Uninstall tool repo" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testToolsRoot "uninstalltool"
            Create-TestRepo $script:repoPath

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "uninstalltool"
                        name = "uninstalltool"
                        path = $script:repoPath
                        scope = "tool"
                        chinvex_context = "tools"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should call chinvex context remove-repo for tool scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $script:chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $script:chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Uninstall -NameToRemove "uninstalltool" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should call remove-repo on tools context
            $removeCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "remove-repo" }
            $removeCall | Should Not Be $null
            ($removeCall -contains "tools") | Should Be $true
            ($removeCall -contains "--repo") | Should Be $true
        }

        It "should NOT archive tools context when uninstalling a tool" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $script:chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $script:chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Uninstall -NameToRemove "uninstalltool" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should NOT call archive for tools
            $archiveCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "archive" -and $_[2] -eq "tools" }
            $archiveCall | Should Be $null
        }
    }

    Context "Chinvex failure handling" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "failuninstall"
            Create-TestRepo $script:repoPath

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "failuninstall"
                        name = "failuninstall"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "failuninstall"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should complete uninstall even when chinvex archive fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }  # Fail

            Invoke-Uninstall -NameToRemove "failuninstall" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Entry should still be removed
            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "failuninstall" }
            $entry | Should Be $null

            # Folder should still be deleted
            (Test-Path $script:repoPath) | Should Be $false
        }
    }

    Context "--no-chinvex flag" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "nochxuninstall"
            Create-TestRepo $script:repoPath

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "nochxuninstall"
                        name = "nochxuninstall"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "nochxuninstall"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should skip chinvex operations when --no-chinvex is set" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Uninstall -NameToRemove "nochxuninstall" -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            Assert-MockCalled Invoke-Chinvex -Times 0
        }

        It "should still complete uninstall when --no-chinvex is used" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            Invoke-Uninstall -NameToRemove "nochxuninstall" -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "nochxuninstall" }
            $entry | Should Be $null
        }
    }

    Context "--keep-folder flag" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "keepfolderuninstall"
            Create-TestRepo $script:repoPath

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "keepfolderuninstall"
                        name = "keepfolderuninstall"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "keepfolderuninstall"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should still archive chinvex context even with --keep-folder" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $script:chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $script:chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Uninstall -NameToRemove "keepfolderuninstall" -PreserveFolder -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should still archive
            $archiveCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "archive" }
            $archiveCall | Should Not Be $null
        }
    }
}
