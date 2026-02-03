# tests/powershell/ChinvexAdopt.Tests.ps1
Describe "Invoke-Adopt Chinvex Integration" -Tag "Task5" {
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
            "Has-Command", "Ensure-Command",
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex", "Invoke-ChinvexQuery",
            "Detect-RepoScope", "Get-ContextName", "Test-ReservedContextName", "Sync-ChinvexForEntry",
            "Invoke-Adopt"
        )
        foreach ($funcName in $functions) {
            $funcCode = Extract-Function $strapContent $funcName
            if ($null -eq $funcCode -or $funcCode.Length -eq 0) {
                throw "Failed to extract function: $funcName"
            }
            Invoke-Expression $funcCode
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

    function Create-TestRepo {
        param([string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path ".git") -Force | Out-Null
    }

    Context "Auto-detect scope from path" {
        It "should auto-detect 'software' scope for repo under software_root" {
            $repoPath = Join-Path $script:testSoftwareRoot "autosoftware"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "autosoftware" }
            $entry.scope | Should Be "software"
        }

        It "should auto-detect 'tool' scope for repo under tools_root" {
            $repoPath = Join-Path $script:testToolsRoot "autotool"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "autotool" }
            $entry.scope | Should Be "tool"
        }
    }

    Context "Explicit scope override" {
        It "should use 'tool' scope when --tool flag provided" {
            $repoPath = Join-Path $script:testSoftwareRoot "forcedtool"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -ForceTool -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "forcedtool" }
            $entry.scope | Should Be "tool"
        }

        It "should use 'software' scope when --software flag provided" {
            $repoPath = Join-Path $script:testToolsRoot "forcedsoftware"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -ForceSoftware -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "forcedsoftware" }
            $entry.scope | Should Be "software"
        }
    }

    Context "Chinvex context field" {
        It "should set chinvex_context to repo name for software scope" {
            $repoPath = Join-Path $script:testSoftwareRoot "softwarectx"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "softwarectx" }
            $entry.chinvex_context | Should Be "softwarectx"
        }

        It "should set chinvex_context to 'tools' for tool scope" {
            $repoPath = Join-Path $script:testToolsRoot "toolctx"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "toolctx" }
            $entry.chinvex_context | Should Be "tools"
        }

        It "should set chinvex_context to null when --no-chinvex flag used" {
            $repoPath = Join-Path $script:testSoftwareRoot "nochxadopt"
            Create-TestRepo $repoPath

            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "nochxadopt" }
            $entry.chinvex_context | Should Be $null
        }

        It "should set chinvex_context to null when chinvex unavailable" {
            $repoPath = Join-Path $script:testSoftwareRoot "unavailchx"
            Create-TestRepo $repoPath

            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "unavailchx" }
            $entry.chinvex_context | Should Be $null
        }
    }

    Context "Reserved name validation" {
        It "should reject 'tools' as software repo name" {
            $repoPath = Join-Path $script:testSoftwareRoot "tools"
            Create-TestRepo $repoPath

            Mock git { $global:LASTEXITCODE = 0 }

            { Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot } |
                Should Throw "*reserved*"
        }

        It "should reject 'archive' as software repo name" {
            $repoPath = Join-Path $script:testSoftwareRoot "archive"
            Create-TestRepo $repoPath

            Mock git { $global:LASTEXITCODE = 0 }

            { Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot } |
                Should Throw "*reserved*"
        }

        It "should allow adopting repo named 'tools' as tool scope" {
            $repoPath = Join-Path $script:testToolsRoot "tools"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            { Invoke-Adopt -TargetPath $repoPath -ForceTool -NonInteractive -StrapRootPath $script:testStrapRoot } |
                Should Not Throw
        }
    }
}
