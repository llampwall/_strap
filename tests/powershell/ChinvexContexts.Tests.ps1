# tests/powershell/ChinvexContexts.Tests.ps1
Describe "Invoke-Contexts Command" -Tag "Task10" {
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
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    Context "Basic functionality" {
        BeforeEach {
            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            # Create registry with entries
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "project1"
                        name = "project1"
                        path = (Join-Path $script:testSoftwareRoot "project1")
                        scope = "software"
                        chinvex_context = "project1"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    },
                    @{
                        id = "tool1"
                        name = "tool1"
                        path = (Join-Path $script:testToolsRoot "tool1")
                        scope = "tool"
                        chinvex_context = "tools"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    },
                    @{
                        id = "unsynced"
                        name = "unsynced"
                        path = (Join-Path $script:testSoftwareRoot "unsynced")
                        scope = "software"
                        chinvex_context = $null
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should return context list object" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "project1"; repo_count = 1; last_ingest = "2026-01-30T10:00:00Z" },
                    @{ name = "tools"; repo_count = 2; last_ingest = "2026-01-29T10:00:00Z" },
                    @{ name = "orphan-context"; repo_count = 1; last_ingest = "2026-01-28T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $result | Should -Not -Be $null
            ($result.Count -gt 0) | Should -Be $true
        }

        It "should identify synced contexts" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "project1"; repo_count = 1; last_ingest = "2026-01-30T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $syncedEntry = $result | Where-Object { $_.Name -eq "project1" }
            $syncedEntry | Should -Not -Be $null
            $syncedEntry.SyncStatus | Should -Be "synced"
        }

        It "should identify unsynced contexts" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "project1"; repo_count = 1; last_ingest = "2026-01-30T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $unsyncedEntry = $result | Where-Object { $_.Name -eq "unsynced" }
            $unsyncedEntry | Should -Not -Be $null
            $unsyncedEntry.SyncStatus | Should -Be "not synced"
        }

        It "should identify orphaned chinvex contexts" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "project1"; repo_count = 1; last_ingest = "2026-01-30T10:00:00Z" },
                    @{ name = "orphan-context"; repo_count = 1; last_ingest = "2026-01-28T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $orphanEntry = $result | Where-Object { $_.Name -eq "orphan-context" }
            $orphanEntry | Should -Not -Be $null
            $orphanEntry.SyncStatus | Should -Be "no strap entry"
        }
    }

    Context "When chinvex is unavailable" {
        BeforeEach {
            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "project1"
                        name = "project1"
                        path = (Join-Path $script:testSoftwareRoot "project1")
                        scope = "software"
                        chinvex_context = "project1"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should show registry-only view with warning" {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }
            Mock Test-ChinvexAvailable { return $false }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            # Should still return registry entries
            $result | Should -Not -Be $null
            ($result.Count -gt 0) | Should -Be $true

            # Entry should show unknown sync status since chinvex unavailable
            $entry = $result | Where-Object { $_.Name -eq "project1" }
            $entry.SyncStatus | Should -Be "unknown (chinvex unavailable)"
        }
    }

    Context "Tools context handling" {
        BeforeEach {
            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "tool1"
                        name = "tool1"
                        path = (Join-Path $script:testToolsRoot "tool1")
                        scope = "tool"
                        chinvex_context = "tools"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    },
                    @{
                        id = "tool2"
                        name = "tool2"
                        path = (Join-Path $script:testToolsRoot "tool2")
                        scope = "tool"
                        chinvex_context = "tools"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should show tools context as a single entry with repo count" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "tools"; repo_count = 2; last_ingest = "2026-01-29T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $toolsEntry = $result | Where-Object { $_.Name -eq "tools" }
            $toolsEntry | Should -Not -Be $null
            $toolsEntry.Type | Should -Be "tool"
            ($toolsEntry.RepoCount -eq 2) | Should -Be $true
        }
    }

    Context "Output format" {
        BeforeEach {
            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "project1"
                        name = "project1"
                        path = (Join-Path $script:testSoftwareRoot "project1")
                        scope = "software"
                        chinvex_context = "project1"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should return structured object with expected properties" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "project1"; repo_count = 1; last_ingest = "2026-01-30T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $entry = $result | Select-Object -First 1
            ($entry.PSObject.Properties.Name -contains "Name") | Should -Be $true
            ($entry.PSObject.Properties.Name -contains "Type") | Should -Be $true
            ($entry.PSObject.Properties.Name -contains "RepoCount") | Should -Be $true
            ($entry.PSObject.Properties.Name -contains "SyncStatus") | Should -Be $true
        }
    }
}
