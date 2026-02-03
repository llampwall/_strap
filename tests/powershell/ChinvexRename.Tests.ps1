# tests/powershell/ChinvexRename.Tests.ps1
Describe "Invoke-Rename Chinvex Integration" -Tag "Task8" {
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
            "Invoke-Rename"
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

    function Create-TestRepo {
        param([string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path ".git") -Force | Out-Null
    }

    Context "Rename software repo (registry only)" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "oldname"
            Create-TestRepo $script:repoPath

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "oldname"
                        name = "oldname"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "oldname"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should call chinvex context rename for software scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $script:chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $script:chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Rename -NameToRename "oldname" -NewName "newname" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should call context rename
            $renameCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "rename" }
            $renameCall | Should Not Be $null
            $renameCall -contains "oldname" | Should Be $true
            $renameCall -contains "--to" | Should Be $true
            $renameCall -contains "newname" | Should Be $true
        }

        It "should update chinvex_context field to new name" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Rename -NameToRename "oldname" -NewName "newname" -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "newname" }
            $entry.chinvex_context | Should Be "newname"
        }
    }

    Context "Rename tool repo (registry only)" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testToolsRoot "oldtool"
            Create-TestRepo $script:repoPath

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "oldtool"
                        name = "oldtool"
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

        It "should NOT call chinvex context rename for tool scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Rename -NameToRename "oldtool" -NewName "newtool" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should NOT invoke chinvex rename for tools
            Assert-MockCalled Invoke-Chinvex -Times 0
        }

        It "should keep chinvex_context as 'tools' for tool scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Rename -NameToRename "oldtool" -NewName "newtool" -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "newtool" }
            $entry.chinvex_context | Should Be "tools"
        }
    }

    Context "Rename with --move-folder" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "movefolder"
            Create-TestRepo $script:repoPath

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "movefolder"
                        name = "movefolder"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "movefolder"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should update path in chinvex context when --move-folder is used" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $script:chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $script:chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Rename -NameToRename "movefolder" -NewName "newmovefolder" -MoveFolder -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should call: context rename, then ingest (add new path), then remove-repo (old path)
            $renameCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "rename" }
            $renameCall | Should Not Be $null

            $ingestCall = $script:chinvexCalls | Where-Object { $_[0] -eq "ingest" }
            $ingestCall | Should Not Be $null

            $removeCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "remove-repo" }
            $removeCall | Should Not Be $null
        }

        It "should update registry path and chinvex_context" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Rename -NameToRename "movefolder" -NewName "renamedwithmove" -MoveFolder -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "renamedwithmove" }
            $entry.chinvex_context | Should Be "renamedwithmove"

            $expectedPath = Join-Path $script:testSoftwareRoot "renamedwithmove"
            $entry.path | Should Be $expectedPath
        }
    }

    Context "Chinvex failure handling" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "failrename"
            Create-TestRepo $script:repoPath

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "failrename"
                        name = "failrename"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "failrename"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should set chinvex_context to null when chinvex rename fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }  # Fail

            Invoke-Rename -NameToRename "failrename" -NewName "newfailrename" -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "newfailrename" }
            $entry.chinvex_context | Should Be $null
        }

        It "should still complete rename when chinvex fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }

            Invoke-Rename -NameToRename "failrename" -NewName "stillrenamed" -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "stillrenamed" }
            $entry | Should Not Be $null
            $entry.name | Should Be "stillrenamed"
        }
    }

    Context "--no-chinvex flag" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "nochxrename"
            Create-TestRepo $script:repoPath

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                version = 2
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "nochxrename"
                        name = "nochxrename"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "nochxrename"
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

            Invoke-Rename -NameToRename "nochxrename" -NewName "newnochx" -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            Assert-MockCalled Invoke-Chinvex -Times 0
        }

        It "should preserve existing chinvex_context when --no-chinvex is used" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            Invoke-Rename -NameToRename "nochxrename" -NewName "preserved" -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "preserved" }
            # Note: context is stale (still "nochxrename") but preserved as-is
            $entry.chinvex_context | Should Be "nochxrename"
        }
    }
}
