# tests/powershell/ChinvexSync.Tests.ps1
Describe "Invoke-SyncChinvex" -Tag "Task11" {
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
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex", "Invoke-ChinvexQuery",
            "Detect-RepoScope", "Get-ContextName", "Sync-ChinvexForEntry",
            "Invoke-SyncChinvex"
        )
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                Write-Warning "Could not extract ${funcName}"
            }
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

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    Context "Default behavior (no flags = dry-run)" {
        BeforeEach {
            # Registry with one entry that has null chinvex_context
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "unsynced-repo"
                        name = "unsynced-repo"
                        path = (Join-Path $script:testSoftwareRoot "unsynced-repo")
                        scope = "software"
                        chinvex_context = $null
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should default to dry-run mode when no flags provided" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery { return '[]' }
            Mock Invoke-Chinvex { return $true }

            $result = Invoke-SyncChinvex -StrapRootPath $script:testStrapRoot

            # Should not have called any mutating chinvex commands
            Assert-MockCalled Invoke-Chinvex -Times 0
        }

        It "should report what would be done without making changes" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery { return '[]' }

            $result = Invoke-SyncChinvex -StrapRootPath $script:testStrapRoot -OutputMode 'Object'

            $result.Actions.Count | Should Be 1
            $result.Actions[0].Action | Should Be "create"
            $result.Actions[0].Context | Should Be "unsynced-repo"
            $result.DryRun | Should Be $true
        }
    }

    Context "--dry-run flag" {
        BeforeEach {
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "missing-ctx"
                        name = "missing-ctx"
                        path = (Join-Path $script:testSoftwareRoot "missing-ctx")
                        scope = "software"
                        chinvex_context = $null
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should not modify registry in dry-run mode" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery { return '[]' }

            $beforeRegistry = Get-Content $script:testRegistryPath -Raw

            Invoke-SyncChinvex -DryRun -StrapRootPath $script:testStrapRoot

            $afterRegistry = Get-Content $script:testRegistryPath -Raw
            $afterRegistry | Should Be $beforeRegistry
        }

        It "should list actions that would be taken" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery { return '[]' }

            $result = Invoke-SyncChinvex -DryRun -StrapRootPath $script:testStrapRoot -OutputMode 'Object'

            $result.Actions | Should Not Be $null
            $result.Actions[0].Action | Should Be "create"
        }
    }

    Context "--reconcile flag - Missing contexts" {
            BeforeEach {
                @{
                    version = 2
                    updated_at = (Get-Date).ToUniversalTime().ToString("o")
                    entries = @(
                        @{
                            id = "needs-sync"
                            name = "needs-sync"
                            path = (Join-Path $script:testSoftwareRoot "needs-sync")
                            scope = "software"
                            chinvex_context = $null
                            shims = @()
                        }
                    )
                } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
            }

            It "should create context for registry entry with null chinvex_context" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery { return '[]' }
                Mock Invoke-Chinvex { return $true }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                # Should have called context create and ingest
                Assert-MockCalled Invoke-Chinvex -ParameterFilter {
                    $Arguments[0] -eq "context" -and $Arguments[1] -eq "create" -and $Arguments[2] -eq "needs-sync"
                }
            }

            It "should update registry chinvex_context after successful sync" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery { return '[]' }
                Mock Invoke-Chinvex { return $true }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
                $entry = $registry.entries | Where-Object { $_.name -eq "needs-sync" }
                $entry.chinvex_context | Should Be "needs-sync"
            }
    }

    Context "--reconcile flag - Tool repos" {
            BeforeEach {
                @{
                    version = 2
                    updated_at = (Get-Date).ToUniversalTime().ToString("o")
                    entries = @(
                        @{
                            id = "unsynced-tool"
                            name = "unsynced-tool"
                            path = (Join-Path $script:testToolsRoot "unsynced-tool")
                            scope = "tool"
                            chinvex_context = $null
                            shims = @()
                        }
                    )
                } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
            }

            It "should create tools context and add tool repo" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery { return '[]' }
                Mock Invoke-Chinvex { return $true }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                # Should have called context create for tools
                Assert-MockCalled Invoke-Chinvex -ParameterFilter {
                    $Arguments[0] -eq "context" -and $Arguments[1] -eq "create" -and $Arguments[2] -eq "tools"
                }
            }

            It "should set chinvex_context to 'tools' for tool repos" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery { return '[]' }
                Mock Invoke-Chinvex { return $true }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
                $entry = $registry.entries | Where-Object { $_.name -eq "unsynced-tool" }
                $entry.chinvex_context | Should Be "tools"
            }
    }

    Context "--reconcile flag - Orphaned contexts" {
            BeforeEach {
                # Empty registry
                @{
                    version = 2
                    updated_at = (Get-Date).ToUniversalTime().ToString("o")
                    entries = @()
                } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
            }

            It "should archive orphaned contexts not in whitelist" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                # Return orphaned context from chinvex
                Mock Invoke-ChinvexQuery {
                    return '[{"name": "orphaned-project", "repo_count": 1, "last_ingest": "2026-01-15T10:00:00Z"}]'
                }
                Mock Invoke-Chinvex { return $true }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                Assert-MockCalled Invoke-Chinvex -ParameterFilter {
                    $Arguments[0] -eq "context" -and $Arguments[1] -eq "archive" -and $Arguments[2] -eq "orphaned-project"
                }
            }

            It "should NOT archive whitelisted contexts (tools, archive)" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery {
                    return '[{"name": "tools", "repo_count": 0, "last_ingest": "2026-01-15T10:00:00Z"}, {"name": "archive", "repo_count": 5, "last_ingest": "2026-01-10T10:00:00Z"}]'
                }

                $script:archiveCalls = @()
                Mock Invoke-Chinvex {
                    param($Arguments)
                    if ($Arguments[0] -eq "context" -and $Arguments[1] -eq "archive") {
                        $script:archiveCalls += $Arguments[2]
                    }
                    return $true
                }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                ($script:archiveCalls -contains "tools") | Should Be $false
                ($script:archiveCalls -contains "archive") | Should Be $false
            }
    }

    Context "--reconcile flag - Empty tools context" {
            BeforeEach {
                # No tool repos in registry
                @{
                    version = 2
                    updated_at = (Get-Date).ToUniversalTime().ToString("o")
                    entries = @()
                } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
            }

            It "should keep empty tools context (never archive)" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery {
                    return '[{"name": "tools", "repo_count": 0, "last_ingest": "never"}]'
                }

                $script:archiveCalls = @()
                Mock Invoke-Chinvex {
                    param($Arguments)
                    if ($Arguments[0] -eq "context" -and $Arguments[1] -eq "archive") {
                        $script:archiveCalls += $Arguments[2]
                    }
                    return $true
                }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                ($script:archiveCalls -contains "tools") | Should Be $false
            }
    }

    Context "Always runs regardless of config/flags" {
        BeforeEach {
            # Config with chinvex_integration disabled
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
                chinvex_whitelist = @("tools", "archive")
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "test-repo"
                        name = "test-repo"
                        path = (Join-Path $script:testSoftwareRoot "test-repo")
                        scope = "software"
                        chinvex_context = $null
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should run even when chinvex_integration is false in config" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery { return '[]' }
            Mock Invoke-Chinvex { return $true }

            # This should NOT throw or skip - sync-chinvex always runs
            $error = $null
            try {
                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot
            } catch {
                $error = $_
            }
            $error | Should Be $null

            Assert-MockCalled Invoke-Chinvex -Times 2  # create + ingest
        }
    }

    Context "Chinvex unavailable handling" {
        It "should warn and exit gracefully when chinvex not available" {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }

            $result = Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot -OutputMode 'Object'

            $result.Success | Should Be $false
            $result.Error | Should Match "Chinvex not available"
        }
    }
}
