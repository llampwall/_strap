BeforeAll {
    . "$PSScriptRoot/../../modules/Core.ps1"
    . "$PSScriptRoot/../../modules/Commands/Shim.ps1"
}

Describe "Parse-ShimCommandLine" {
    Context "JSON array parsing" {
        It "parses simple JSON array" {
            $result = Parse-ShimCommandLine '["python", "-m", "mytool"]'
            $result.exe | Should -Be "python"
            $result.baseArgs | Should -HaveCount 2
            $result.baseArgs[0] | Should -Be "-m"
            $result.baseArgs[1] | Should -Be "mytool"
        }

        It "handles paths with spaces in JSON" {
            $result = Parse-ShimCommandLine '["C:\\Program Files\\tool.exe", "--flag"]'
            $result.exe | Should -Be "C:\Program Files\tool.exe"
            $result.baseArgs | Should -HaveCount 1
        }

        It "errors on empty JSON array" {
            { Parse-ShimCommandLine '[]' } | Should -Throw "*Empty*"
        }
    }

    Context "Tokenizer parsing" {
        It "parses simple command" {
            $result = Parse-ShimCommandLine "python -m mytool"
            $result.exe | Should -Be "python"
            $result.baseArgs | Should -HaveCount 2
        }

        It "handles quoted arguments" {
            $result = Parse-ShimCommandLine 'python -m "my tool"'
            $result.baseArgs[1] | Should -Be "my tool"
        }

        It "handles paths with spaces" {
            $result = Parse-ShimCommandLine '"C:\Program Files\tool.exe" --flag'
            $result.exe | Should -Be "C:\Program Files\tool.exe"
        }

        It "blocks pipe operators" {
            { Parse-ShimCommandLine "python | grep" } | Should -Throw "*direct exec*"
        }

        It "blocks redirects" {
            { Parse-ShimCommandLine "python > out.txt" } | Should -Throw "*direct exec*"
        }

        It "blocks semicolons" {
            { Parse-ShimCommandLine "python; echo" } | Should -Throw "*direct exec*"
        }

        It "blocks && operators" {
            { Parse-ShimCommandLine "python && echo" } | Should -Throw "*direct exec*"
        }
    }
}

Describe "Resolve-ShimVenvPath" {
    It "returns explicit path when provided" {
        $testRepo = Join-Path $TestDrive "test-explicit"
        New-Item -ItemType Directory -Path $testRepo -Force | Out-Null

        $result = Resolve-ShimVenvPath -RepoPath $testRepo -ExplicitPath "C:\custom\venv"
        $result | Should -Be "C:\custom\venv"
    }

    It "auto-detects .venv" {
        $testRepo = Join-Path $TestDrive "test-dotvenv"
        New-Item -ItemType Directory -Path $testRepo -Force | Out-Null

        $venvPath = Join-Path $testRepo ".venv\Scripts"
        New-Item -ItemType Directory -Path $venvPath -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $venvPath "python.exe") -Force | Out-Null

        $result = Resolve-ShimVenvPath -RepoPath $testRepo
        $result | Should -Be (Join-Path $testRepo ".venv")
    }

    It "auto-detects venv" {
        $testRepo = Join-Path $TestDrive "test-venv"
        New-Item -ItemType Directory -Path $testRepo -Force | Out-Null

        $venvPath = Join-Path $testRepo "venv\Scripts"
        New-Item -ItemType Directory -Path $venvPath -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $venvPath "python.exe") -Force | Out-Null

        $result = Resolve-ShimVenvPath -RepoPath $testRepo
        $result | Should -Be (Join-Path $testRepo "venv")
    }

    It "errors when no venv found" {
        $testRepo = Join-Path $TestDrive "test-novenv"
        New-Item -ItemType Directory -Path $testRepo -Force | Out-Null

        { Resolve-ShimVenvPath -RepoPath $testRepo } | Should -Throw "*No venv found*"
    }
}

Describe "Resolve-ShimVenvExe" {
    BeforeEach {
        $script:TestVenv = Join-Path $TestDrive "test-venv"
        $script:ScriptsDir = Join-Path $TestVenv "Scripts"
        New-Item -ItemType Directory -Path $ScriptsDir -Force | Out-Null
    }

    It "resolves python to python.exe" {
        New-Item -ItemType File -Path (Join-Path $ScriptsDir "python.exe") -Force | Out-Null

        $result = Resolve-ShimVenvExe -Exe "python" -VenvPath $TestVenv
        $result.resolvedPath | Should -Be (Join-Path $ScriptsDir "python.exe")
        $result.exists | Should -BeTrue
    }

    It "resolves script name to .exe" {
        New-Item -ItemType File -Path (Join-Path $ScriptsDir "chinvex.exe") -Force | Out-Null

        $result = Resolve-ShimVenvExe -Exe "chinvex" -VenvPath $TestVenv
        $result.resolvedPath | Should -Be (Join-Path $ScriptsDir "chinvex.exe")
        $result.exists | Should -BeTrue
    }

    It "returns exists=false for missing exe" {
        $result = Resolve-ShimVenvExe -Exe "missing" -VenvPath $TestVenv
        $result.exists | Should -BeFalse
    }
}

Describe "Resolve-ShimNodeExe" {
    BeforeEach {
        $script:Config = [PSCustomObject]@{
            defaults = [PSCustomObject]@{
                nodeExe = "C:\nvm4w\nodejs\node.exe"
            }
        }
    }

    It "uses CLI override when provided" {
        Mock Test-Path { $true } -ParameterFilter { $Path -eq "C:\custom\node.exe" }

        $result = Resolve-ShimNodeExe -CliOverride "C:\custom\node.exe" -Config $Config
        $result | Should -Be "C:\custom\node.exe"
    }

    It "errors when CLI override not found" {
        Mock Test-Path { $false }

        { Resolve-ShimNodeExe -CliOverride "C:\missing\node.exe" -Config $Config } | Should -Throw "*not found*"
    }

    It "uses config default when no override" {
        Mock Test-Path { $true } -ParameterFilter { $Path -eq "C:\nvm4w\nodejs\node.exe" }

        $result = Resolve-ShimNodeExe -Config $Config
        $result | Should -Be "C:\nvm4w\nodejs\node.exe"
    }
}

Describe "New-ShimPs1Content" {
    It "generates simple type shim" {
        $meta = @{
            name = "mytool"
            repo = "test-repo"
            type = "simple"
            exe = "C:\tools\mytool.exe"
            baseArgs = @("--verbose")
            cwd = $null
        }

        $content = New-ShimPs1Content $meta

        $content | Should -Match "# Generated by strap shim"
        $content | Should -Match "# Repo: test-repo \| Type: simple"
        $content | Should -Match '\$exe = "C:\\tools\\mytool\.exe"'
        $content | Should -Match '\$baseArgs = @\("--verbose"\)'
        $content | Should -Match '& \$exe @baseArgs @args'
        $content | Should -Match '\$ec = if \(\$null -eq \$LASTEXITCODE\)'
    }

    It "generates venv type shim" {
        $meta = @{
            name = "chinvex"
            repo = "chinvex"
            type = "venv"
            exe = "P:\software\chinvex\.venv\Scripts\chinvex.exe"
            baseArgs = @()
            venv = "P:\software\chinvex\.venv"
            cwd = $null
        }

        $content = New-ShimPs1Content $meta

        $content | Should -Match "# Repo: chinvex \| Type: venv"
        $content | Should -Match 'Venv: P:\\software\\chinvex\\\.venv'
        $content | Should -Match '\$venv = "P:\\software\\chinvex\\\.venv"'
    }

    It "generates node type shim" {
        $meta = @{
            name = "pm2"
            repo = "pm2-local"
            type = "node"
            exe = "C:\nvm4w\nodejs\node.exe"
            baseArgs = @("P:\software\_node-tools\pm2\bin\pm2")
            cwd = $null
        }

        $content = New-ShimPs1Content $meta

        $content | Should -Match "# Repo: pm2-local \| Type: node"
        $content | Should -Match '\$exe = "C:\\nvm4w\\nodejs\\node\.exe"'
    }

    It "includes cwd handling when specified" {
        $meta = @{
            name = "mytool"
            repo = "test-repo"
            type = "simple"
            exe = "mytool.exe"
            baseArgs = @()
            cwd = "P:\software\myrepo"
        }

        $content = New-ShimPs1Content $meta

        $content | Should -Match 'Push-Location "P:\\software\\myrepo"'
        $content | Should -Match 'Pop-Location'
        $content | Should -Match 'finally'
    }
}

Describe "New-ShimCmdContent" {
    It "generates launcher with full pwsh path" {
        $content = New-ShimCmdContent -ShimName "chinvex" -PwshExe "C:\Program Files\PowerShell\7\pwsh.exe"

        $content | Should -Match '@echo off'
        $content | Should -Match '"C:\\Program Files\\PowerShell\\7\\pwsh\.exe"'
        $content | Should -Match '-NoLogo -NoProfile -ExecutionPolicy Bypass'
        $content | Should -Match 'chinvex\.ps1'
        $content | Should -Match '%\*'
        $content | Should -Match 'exit /b %errorlevel%'
    }
}

Describe "Invoke-Shim" {
    BeforeAll {
        . "$PSScriptRoot/../../modules/Config.ps1"
    }

    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive "strap-test"
        $script:ShimsDir = Join-Path $TestRoot "bin"
        $script:RegistryPath = Join-Path $TestRoot "registry.json"

        New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $ShimsDir -Force | Out-Null

        # Create test config
        $script:Config = [PSCustomObject]@{
            roots = [PSCustomObject]@{
                software = $TestRoot
                shims = $ShimsDir
            }
            defaults = [PSCustomObject]@{
                pwshExe = "C:\Program Files\PowerShell\7\pwsh.exe"
                nodeExe = "C:\nvm4w\nodejs\node.exe"
            }
            registry = $RegistryPath
        }

        # Create test registry with a repo
        $script:Registry = @(
            @{
                name = "test-repo"
                repoPath = Join-Path $TestRoot "test-repo"
                scope = "software"
                shims = @()
            }
        )

        # Create repo directory
        New-Item -ItemType Directory -Path $Registry[0].repoPath -Force | Out-Null
    }

    It "creates simple shim files" {
        Mock Test-Path { $true } -ParameterFilter { $Path -eq "C:\Program Files\PowerShell\7\pwsh.exe" }

        Invoke-Shim -ShimName "mytool" `
            -Cmd "mytool.exe --verbose" `
            -ShimType "simple" `
            -RegistryEntryName "test-repo" `
            -Config $Config `
            -Registry $Registry

        $ps1Path = Join-Path $ShimsDir "mytool.ps1"
        $cmdPath = Join-Path $ShimsDir "mytool.cmd"

        Test-Path $ps1Path | Should -BeTrue
        Test-Path $cmdPath | Should -BeTrue
    }

    It "errors on missing pwshExe" {
        Mock Test-Path { $false } -ParameterFilter { $Path -eq "C:\Program Files\PowerShell\7\pwsh.exe" }

        { Invoke-Shim -ShimName "mytool" `
            -Cmd "mytool.exe" `
            -ShimType "simple" `
            -RegistryEntryName "test-repo" `
            -Config $Config `
            -Registry $Registry } | Should -Throw "*pwshExe*"
    }

    It "errors on unknown repo" {
        { Invoke-Shim -ShimName "mytool" `
            -Cmd "mytool.exe" `
            -ShimType "simple" `
            -RegistryEntryName "nonexistent" `
            -Config $Config `
            -Registry $Registry } | Should -Throw "*not found*"
    }

    It "validates shim name format" {
        { Invoke-Shim -ShimName "my tool" `
            -Cmd "mytool.exe" `
            -ShimType "simple" `
            -RegistryEntryName "test-repo" `
            -Config $Config `
            -Registry $Registry } | Should -Throw "*Invalid shim name*"
    }

    It "detects collision with different repo" {
        Mock Test-Path { $true } -ParameterFilter { $Path -eq "C:\Program Files\PowerShell\7\pwsh.exe" }

        # Create existing shim owned by another repo
        $Registry += @{
            name = "other-repo"
            repoPath = Join-Path $TestRoot "other-repo"
            scope = "software"
            shims = @(
                @{ name = "mytool"; ps1Path = Join-Path $ShimsDir "mytool.ps1" }
            )
        }
        "" | Set-Content (Join-Path $ShimsDir "mytool.ps1")

        { Invoke-Shim -ShimName "mytool" `
            -Cmd "mytool.exe" `
            -ShimType "simple" `
            -RegistryEntryName "test-repo" `
            -Config $Config `
            -Registry $Registry } | Should -Throw "*already exists*other-repo*"
    }

    It "allows update when same repo owns shim" {
        Mock Test-Path { $true } -ParameterFilter { $Path -eq "C:\Program Files\PowerShell\7\pwsh.exe" }

        # Add existing shim to test-repo
        $Registry[0].shims = @(
            @{ name = "mytool"; ps1Path = Join-Path $ShimsDir "mytool.ps1" }
        )
        "" | Set-Content (Join-Path $ShimsDir "mytool.ps1")
        "" | Set-Content (Join-Path $ShimsDir "mytool.cmd")

        # Should not throw - same repo
        { Invoke-Shim -ShimName "mytool" `
            -Cmd "newtool.exe" `
            -ShimType "simple" `
            -RegistryEntryName "test-repo" `
            -Config $Config `
            -Registry $Registry } | Should -Not -Throw
    }
}

Describe "Invoke-ShimRegen" {
    BeforeAll {
        . "$PSScriptRoot/../../modules/Config.ps1"
    }

    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive "strap-test"
        $script:ShimsDir = Join-Path $TestRoot "bin"

        New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $ShimsDir -Force | Out-Null

        $script:Config = [PSCustomObject]@{
            roots = [PSCustomObject]@{
                software = $TestRoot
                shims = $ShimsDir
            }
            defaults = [PSCustomObject]@{
                pwshExe = "C:\Program Files\PowerShell\7\pwsh.exe"
                nodeExe = "C:\nvm4w\nodejs\node.exe"
            }
            registry = Join-Path $TestRoot "registry.json"
        }

        # Mock pwshExe exists
        Mock Test-Path { $true } -ParameterFilter { $Path -eq "C:\Program Files\PowerShell\7\pwsh.exe" }
    }

    It "regenerates all shims for a repo" {
        $registry = @(
            @{
                name = "test-repo"
                repoPath = Join-Path $TestRoot "test-repo"
                scope = "software"
                shims = @(
                    @{
                        name = "tool1"
                        ps1Path = Join-Path $ShimsDir "tool1.ps1"
                        type = "simple"
                        exe = "tool1.exe"
                        baseArgs = @()
                    }
                    @{
                        name = "tool2"
                        ps1Path = Join-Path $ShimsDir "tool2.ps1"
                        type = "simple"
                        exe = "tool2.exe"
                        baseArgs = @("--flag")
                    }
                )
            }
        )

        Invoke-ShimRegen -RepoName "test-repo" -Config $Config -Registry $registry

        Test-Path (Join-Path $ShimsDir "tool1.ps1") | Should -BeTrue
        Test-Path (Join-Path $ShimsDir "tool1.cmd") | Should -BeTrue
        Test-Path (Join-Path $ShimsDir "tool2.ps1") | Should -BeTrue
        Test-Path (Join-Path $ShimsDir "tool2.cmd") | Should -BeTrue
    }

    It "errors on unknown repo" {
        $registry = @(
            @{
                name = "other-repo"
                repoPath = Join-Path $TestRoot "other-repo"
                scope = "software"
                shims = @()
            }
        )

        { Invoke-ShimRegen -RepoName "nonexistent" -Config $Config -Registry $registry } | Should -Throw "*not found*"
    }

    It "handles repo with no shims" {
        $registry = @(
            @{
                name = "empty-repo"
                repoPath = Join-Path $TestRoot "empty-repo"
                scope = "software"
                shims = @()
            }
        )

        { Invoke-ShimRegen -RepoName "empty-repo" -Config $Config -Registry $registry } | Should -Not -Throw
    }
}
