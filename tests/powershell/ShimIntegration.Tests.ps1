BeforeAll {
    $script:StrapRoot = $PSScriptRoot | Split-Path | Split-Path
    . "$StrapRoot/modules/Core.ps1"
    . "$StrapRoot/modules/Config.ps1"
    . "$StrapRoot/modules/Commands/Shim.ps1"
    . "$StrapRoot/modules/Commands/Doctor.ps1"
}

Describe "Shim v3.1 Integration" {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive "integration"
        $script:ShimsDir = Join-Path $TestRoot "bin"
        $script:RepoDir = Join-Path $TestRoot "test-repo"
        $script:RegistryPath = Join-Path $TestRoot "registry.json"
        $script:ConfigPath = Join-Path $TestRoot "config.json"

        New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $ShimsDir -Force | Out-Null
        New-Item -ItemType Directory -Path $RepoDir -Force | Out-Null

        # Create config
        @{
            roots = @{
                software = $TestRoot
                shims = $ShimsDir
            }
            defaults = @{
                pwshExe = "C:\Program Files\PowerShell\7\pwsh.exe"
                nodeExe = "C:\nvm4w\nodejs\node.exe"
            }
            registry = $RegistryPath
        } | ConvertTo-Json -Depth 10 | Set-Content $ConfigPath

        # Create registry
        @{
            version = 2
            repos = @(
                @{
                    name = "test-repo"
                    repoPath = $RepoDir
                    scope = "software"
                    shims = @()
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content $RegistryPath

        Mock Test-Path { $true } -ParameterFilter { $Path -eq "C:\Program Files\PowerShell\7\pwsh.exe" }
    }

    It "full workflow: create -> verify -> regen" {
        $config = Load-Config $TestRoot
        $registry = Load-Registry $config

        # Create shim
        $shimEntry = Invoke-Shim -ShimName "mytool" `
            -Cmd "mytool.exe --verbose" `
            -ShimType "simple" `
            -RegistryEntryName "test-repo" `
            -Config $config `
            -Registry $registry

        # Verify files created
        Test-Path (Join-Path $ShimsDir "mytool.ps1") | Should -BeTrue
        Test-Path (Join-Path $ShimsDir "mytool.cmd") | Should -BeTrue

        # Verify content
        $ps1Content = Get-Content (Join-Path $ShimsDir "mytool.ps1") -Raw
        $ps1Content | Should -Match "mytool.exe"
        $ps1Content | Should -Match "--verbose"

        # Update registry
        $repoEntry = $registry | Where-Object { $_.name -eq "test-repo" }
        $repoEntry.shims += $shimEntry
        Save-Registry $config $registry

        # Reload and regen
        $registry2 = Load-Registry $config
        Invoke-ShimRegen -RepoName "test-repo" -Config $config -Registry $registry2

        # Files still exist
        Test-Path (Join-Path $ShimsDir "mytool.ps1") | Should -BeTrue
    }

    It "venv shim with auto-detect" {
        # Create fake venv
        $venvDir = Join-Path $RepoDir ".venv\Scripts"
        New-Item -ItemType Directory -Path $venvDir -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $venvDir "python.exe") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $venvDir "mytool.exe") -Force | Out-Null

        $config = Load-Config $TestRoot
        $registry = Load-Registry $config

        $shimEntry = Invoke-Shim -ShimName "mytool" `
            -Cmd "mytool" `
            -ShimType "venv" `
            -RegistryEntryName "test-repo" `
            -Config $config `
            -Registry $registry

        $shimEntry.venv | Should -Be (Join-Path $RepoDir ".venv")
        $shimEntry.exe | Should -Match "\.venv\\Scripts\\.*\.exe$"
    }

    It "doctor detects issues" {
        $config = Load-Config $TestRoot

        # Registry with missing shim file
        $registry = @(
            @{
                name = "test-repo"
                repoPath = $RepoDir
                shims = @(
                    @{ name = "ghost"; ps1Path = Join-Path $ShimsDir "ghost.ps1"; exe = "ghost.exe" }
                )
            }
        )

        $results = Invoke-DoctorShimChecks -Config $config -Registry $registry

        $shim002 = $results | Where-Object { $_.id -eq "SHIM002" }
        $shim002.passed | Should -BeFalse
    }
}
