BeforeAll {
    . "$PSScriptRoot/../../modules/Core.ps1"
    . "$PSScriptRoot/../../modules/Commands/Doctor.ps1"
}

Describe "Doctor Shim Checks" {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive "doctor-test"
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
        }
    }

    It "SHIM001: detects shims directory not on PATH" {
        $env:PATH = "C:\Windows\System32"

        $results = Invoke-DoctorShimChecks -Config $Config -Registry @()

        $shim001 = $results | Where-Object { $_.id -eq "SHIM001" }
        $shim001.passed | Should -BeFalse
        $shim001.severity | Should -Be "critical"
    }

    It "SHIM001: passes when shims directory on PATH" {
        $env:PATH = "$ShimsDir;C:\Windows\System32"

        $results = Invoke-DoctorShimChecks -Config $Config -Registry @()

        $shim001 = $results | Where-Object { $_.id -eq "SHIM001" }
        $shim001.passed | Should -BeTrue
    }

    It "SHIM002: detects missing shim file" {
        $registry = @(
            @{
                name = "test-repo"
                repoPath = Join-Path $TestRoot "test-repo"
                shims = @(
                    @{ name = "missing"; ps1Path = Join-Path $ShimsDir "missing.ps1" }
                )
            }
        )

        $results = Invoke-DoctorShimChecks -Config $Config -Registry $registry

        $shim002 = $results | Where-Object { $_.id -eq "SHIM002" }
        $shim002.passed | Should -BeFalse
    }

    It "SHIM008: detects incomplete launcher pair" {
        # Create .ps1 but not .cmd
        "" | Set-Content (Join-Path $ShimsDir "incomplete.ps1")

        $registry = @(
            @{
                name = "test-repo"
                repoPath = Join-Path $TestRoot "test-repo"
                shims = @(
                    @{ name = "incomplete"; ps1Path = Join-Path $ShimsDir "incomplete.ps1" }
                )
            }
        )

        $results = Invoke-DoctorShimChecks -Config $Config -Registry $registry

        $shim008 = $results | Where-Object { $_.id -eq "SHIM008" }
        $shim008.passed | Should -BeFalse
    }
}
