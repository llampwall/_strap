# tests/powershell/ChinvexMove.Tests.ps1
Describe "Invoke-Move Chinvex Integration" -Tag "Task7" {
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
            "Detect-RepoScope", "Get-ContextName", "Sync-ChinvexForEntry",
            "Invoke-Move"
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

    Context "Move within same scope (software to software)" {
        BeforeEach {
            # Clean up any existing test folders
            Get-ChildItem $script:testSoftwareRoot | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            # Create source repo
            $script:sourceRepo = Join-Path $script:testSoftwareRoot "moverepo"
            Create-TestRepo $script:sourceRepo

            # Create registry
            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                registry_version = 1
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "moverepo"
                        name = "moverepo"
                        path = $script:sourceRepo
                        scope = "software"
                        chinvex_context = "moverepo"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

            # Create subdir for destination
            $script:destDir = Join-Path $script:testSoftwareRoot "subdir"
            New-Item -ItemType Directory -Path $script:destDir -Force | Out-Null
        }

        It "should update chinvex path when moved within software root" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $script:chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $script:chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Move -NameToMove "moverepo" -DestPath $script:destDir -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should call ingest with new path, then remove-repo with old path
            $script:chinvexCalls.Count | Should Be 2

            # First call: add new path
            $ingestCall = $script:chinvexCalls | Where-Object { $_[0] -eq "ingest" }
            $ingestCall | Should Not Be $null
            $ingestCall -contains "--register-only" | Should Be $true

            # Second call: remove old path
            $removeCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "remove-repo" }
            $removeCall | Should Not Be $null
        }

        It "should keep same chinvex_context when scope unchanged" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "moverepo" -DestPath $script:destDir -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "moverepo" }
            $entry.chinvex_context | Should Be "moverepo"
            $entry.scope | Should Be "software"
        }
    }

    Context "Move with scope change (software to tool)" {
        BeforeEach {
            # Clean up any existing test folders
            Get-ChildItem $script:testSoftwareRoot | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Get-ChildItem $script:testToolsRoot | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            # Create source repo in software root
            $script:sourceRepo = Join-Path $script:testSoftwareRoot "scopechange"
            Create-TestRepo $script:sourceRepo

            # Create registry
            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                registry_version = 1
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "scopechange"
                        name = "scopechange"
                        path = $script:sourceRepo
                        scope = "software"
                        chinvex_context = "scopechange"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should update scope to tool when moved to tools_root" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "scopechange" -DestPath $script:testToolsRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "scopechange" }
            $entry.scope | Should Be "tool"
        }

        It "should update chinvex_context to 'tools' when scope changes to tool" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "scopechange" -DestPath $script:testToolsRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "scopechange" }
            $entry.chinvex_context | Should Be "tools"
        }

        It "should archive old context and create tools context on scope change" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $script:chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $script:chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Move -NameToMove "scopechange" -DestPath $script:testToolsRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should: create tools context, add to tools, archive old context
            $createCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "create" -and $_[2] -eq "tools" }
            $createCall | Should Not Be $null

            $archiveCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "archive" }
            $archiveCall | Should Not Be $null
        }
    }

    Context "Move with scope change (tool to software)" {
        BeforeEach {
            # Clean up any existing test folders
            Get-ChildItem $script:testSoftwareRoot | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Get-ChildItem $script:testToolsRoot | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            # Create source repo in tools root
            $script:sourceRepo = Join-Path $script:testToolsRoot "toolrepo"
            Create-TestRepo $script:sourceRepo

            # Create registry
            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                registry_version = 1
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "toolrepo"
                        name = "toolrepo"
                        path = $script:sourceRepo
                        scope = "tool"
                        chinvex_context = "tools"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should update scope to software when moved to software_root" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "toolrepo" -DestPath $script:testSoftwareRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "toolrepo" }
            $entry.scope | Should Be "software"
        }

        It "should update chinvex_context to repo name when scope changes to software" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "toolrepo" -DestPath $script:testSoftwareRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "toolrepo" }
            $entry.chinvex_context | Should Be "toolrepo"
        }

        It "should remove from tools context and create individual context on scope change" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $script:chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $script:chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Move -NameToMove "toolrepo" -DestPath $script:testSoftwareRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should: create individual context, add to it, remove from tools
            $createCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "create" -and $_[2] -eq "toolrepo" }
            $createCall | Should Not Be $null

            $removeCall = $script:chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "remove-repo" }
            $removeCall | Should Not Be $null
        }
    }

    Context "Chinvex failure handling" {
        BeforeEach {
            # Clean up any existing test folders
            Get-ChildItem $script:testSoftwareRoot | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            $script:sourceRepo = Join-Path $script:testSoftwareRoot "failmove"
            Create-TestRepo $script:sourceRepo

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                registry_version = 1
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "failmove"
                        name = "failmove"
                        path = $script:sourceRepo
                        scope = "software"
                        chinvex_context = "failmove"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

            $script:destDir = Join-Path $script:testSoftwareRoot "failsubdir"
            New-Item -ItemType Directory -Path $script:destDir -Force | Out-Null
        }

        It "should set chinvex_context to null when chinvex ingest fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }  # All chinvex calls fail

            Invoke-Move -NameToMove "failmove" -DestPath $script:destDir -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "failmove" }
            $entry.chinvex_context | Should Be $null
        }

        It "should still complete move even when chinvex fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }

            Invoke-Move -NameToMove "failmove" -DestPath $script:destDir -NonInteractive -StrapRootPath $script:testStrapRoot

            # Verify move completed
            $expectedPath = Join-Path $script:destDir "failmove"
            Test-Path $expectedPath | Should Be $true

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "failmove" }
            $entry.path | Should Be $expectedPath
        }
    }

    Context "--no-chinvex flag" {
        BeforeEach {
            # Clean up any existing test folders
            Get-ChildItem $script:testSoftwareRoot | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

            $script:sourceRepo = Join-Path $script:testSoftwareRoot "nochxmove"
            Create-TestRepo $script:sourceRepo

            $timestamp = (Get-Date).ToUniversalTime().ToString("o")
            @{
                registry_version = 1
                updated_at = $timestamp
                entries = @(
                    @{
                        id = "nochxmove"
                        name = "nochxmove"
                        path = $script:sourceRepo
                        scope = "software"
                        chinvex_context = "nochxmove"
                        shims = @()
                        created_at = $timestamp
                        updated_at = $timestamp
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

            $script:destDir = Join-Path $script:testSoftwareRoot "nochxsubdir"
            New-Item -ItemType Directory -Path $script:destDir -Force | Out-Null
        }

        It "should skip chinvex operations when --no-chinvex flag is set" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "nochxmove" -DestPath $script:destDir -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            # Chinvex should not have been called
            Assert-MockCalled Invoke-Chinvex -Times 0
        }

        It "should preserve existing chinvex_context when --no-chinvex is used" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            Invoke-Move -NameToMove "nochxmove" -DestPath $script:destDir -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "nochxmove" }
            # Context preserved (but may be stale - that's expected with --no-chinvex)
            $entry.chinvex_context | Should Be "nochxmove"
        }
    }
}
