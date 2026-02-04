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
