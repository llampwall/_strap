BeforeAll {
    . "$PSScriptRoot/../../modules/Core.ps1"
    . "$PSScriptRoot/../../modules/FnmIntegration.ps1"
}

Describe "Get-VendoredFnmPath" {
    It "returns the vendored fnm path" {
        $path = Get-VendoredFnmPath
        $path | Should -Be "P:\software\_node-tools\fnm"
    }
}

Describe "Get-NodeVersionsPath" {
    It "returns the node-versions subdirectory" {
        $path = Get-NodeVersionsPath
        $path | Should -Be "P:\software\_node-tools\fnm\node-versions"
    }
}

Describe "Test-FnmInstalled" {
    Context "when fnm is vendored" {
        BeforeEach {
            $script:VendorPath = Get-VendoredFnmPath
            $script:VendorBin = Join-Path $VendorPath "fnm.exe"

            # Create mock fnm.exe
            if (-not (Test-Path $VendorPath)) {
                New-Item -Path $VendorPath -ItemType Directory -Force | Out-Null
            }
            if (-not (Test-Path $VendorBin)) {
                New-Item -Path $VendorBin -ItemType File -Force | Out-Null
            }
        }

        AfterEach {
            # Cleanup is handled by system - vendored fnm is real
        }

        It "returns true when fnm.exe exists in vendored location" {
            Test-FnmInstalled | Should -Be $true
        }
    }

    Context "when fnm is not installed" {
        It "returns false when fnm.exe does not exist and not in PATH" {
            # This test would require removing fnm from both vendored location and PATH
            # which is destructive during CI/local dev, so we skip it
            Set-ItResult -Skipped -Because "would require removing fnm from system"
        }
    }
}

Describe "Get-FnmCommand" {
    Context "when fnm is vendored" {
        It "returns the vendored fnm.exe path" {
            $vendorBin = Join-Path (Get-VendoredFnmPath) "fnm.exe"
            if (Test-Path $vendorBin) {
                $cmd = Get-FnmCommand
                $cmd | Should -Be $vendorBin
            } else {
                Set-ItResult -Skipped -Because "fnm not installed yet"
            }
        }
    }
}

Describe "Get-NodeVersionFromFile" {
    BeforeEach {
        $script:TestRepoPath = Join-Path $TestDrive "test-repo"
        New-Item -Path $TestRepoPath -ItemType Directory -Force | Out-Null
    }

    Context "when .nvmrc exists" {
        It "detects exact version from .nvmrc" {
            $nvmrcPath = Join-Path $TestRepoPath ".nvmrc"
            "18.17.0" | Set-Content $nvmrcPath -NoNewline

            $version = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            $version | Should -Be "18.17.0"
        }

        It "detects version with 'v' prefix from .nvmrc" {
            $nvmrcPath = Join-Path $TestRepoPath ".nvmrc"
            "v20.19.0" | Set-Content $nvmrcPath -NoNewline

            $version = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            $version | Should -Be "20.19.0"
        }

        It "handles major.minor version from .nvmrc" {
            $nvmrcPath = Join-Path $TestRepoPath ".nvmrc"
            "18.17" | Set-Content $nvmrcPath -NoNewline

            $version = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            # Should resolve to latest patch or fallback to .0
            $version | Should -Match '^\d+\.\d+\.\d+$'
        }

        It "handles LTS alias from .nvmrc" {
            $nvmrcPath = Join-Path $TestRepoPath ".nvmrc"
            "lts/hydrogen" | Set-Content $nvmrcPath -NoNewline

            $version = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            $version | Should -Be "lts/hydrogen"
        }
    }

    Context "when .node-version exists" {
        It "detects version from .node-version" {
            $nodeVersionPath = Join-Path $TestRepoPath ".node-version"
            "22.15.1" | Set-Content $nodeVersionPath -NoNewline

            $version = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            $version | Should -Be "22.15.1"
        }

        It "prefers .nvmrc over .node-version" {
            $nvmrcPath = Join-Path $TestRepoPath ".nvmrc"
            $nodeVersionPath = Join-Path $TestRepoPath ".node-version"
            "18.17.0" | Set-Content $nvmrcPath -NoNewline
            "20.19.0" | Set-Content $nodeVersionPath -NoNewline

            $version = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            $version | Should -Be "18.17.0"
        }
    }

    Context "when package.json exists" {
        It "detects exact version from engines.node" {
            $packageJsonPath = Join-Path $TestRepoPath "package.json"
            $packageJson = @{
                name = "test-package"
                engines = @{
                    node = "18.17.0"
                }
            } | ConvertTo-Json -Depth 10
            $packageJson | Set-Content $packageJsonPath -NoNewline

            $version = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            $version | Should -Be "18.17.0"
        }

        It "detects version from >= range in engines.node" {
            $packageJsonPath = Join-Path $TestRepoPath "package.json"
            $packageJson = @{
                name = "test-package"
                engines = @{
                    node = ">=20.19.0"
                }
            } | ConvertTo-Json -Depth 10
            $packageJson | Set-Content $packageJsonPath -NoNewline

            $version = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            $version | Should -Be "20.19.0"
        }

        It "detects version from caret range in engines.node" {
            $packageJsonPath = Join-Path $TestRepoPath "package.json"
            $packageJson = @{
                name = "test-package"
                engines = @{
                    node = "^18.17.0"
                }
            } | ConvertTo-Json -Depth 10
            $packageJson | Set-Content $packageJsonPath -NoNewline

            $version = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            $version | Should -Be "18.17.0"
        }

        It "prefers .nvmrc over package.json" {
            $nvmrcPath = Join-Path $TestRepoPath ".nvmrc"
            $packageJsonPath = Join-Path $TestRepoPath "package.json"
            "18.17.0" | Set-Content $nvmrcPath -NoNewline

            $packageJson = @{
                name = "test-package"
                engines = @{ node = "20.19.0" }
            } | ConvertTo-Json -Depth 10
            $packageJson | Set-Content $packageJsonPath -NoNewline

            $version = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            $version | Should -Be "18.17.0"
        }
    }

    Context "when no version files exist" {
        It "returns null" {
            $version = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            $version | Should -BeNullOrEmpty
        }
    }
}

Describe "Get-FnmVersions" {
    It "returns array of installed versions" {
        if (-not (Test-FnmInstalled)) {
            Set-ItResult -Skipped -Because "fnm not installed"
            return
        }

        $versions = Get-FnmVersions

        # If fnm is installed, there should be at least system or some versions
        $versions | Should -Not -BeNullOrEmpty

        # Versions can be a string (single version) or array (multiple)
        # Both are valid - PowerShell unwraps single-element arrays
        ($versions -is [string]) -or ($versions -is [array]) | Should -Be $true
    }

    It "returns empty array when fnm not installed" {
        # Mock scenario tested by removing fnm temporarily
        # This is hard to test without actually removing fnm, so skip
        Set-ItResult -Skipped -Because "requires fnm to be uninstalled"
    }
}

Describe "Get-FnmNodePath" {
    It "returns path to node.exe for installed version" {
        if (-not (Test-FnmInstalled)) {
            Set-ItResult -Skipped -Because "fnm not installed"
            return
        }

        $installedVersions = Get-FnmVersions
        if ($installedVersions.Count -eq 0) {
            Set-ItResult -Skipped -Because "no Node versions installed"
            return
        }

        # Test with first installed version
        $version = $installedVersions[0]
        $nodePath = Get-FnmNodePath -Version $version

        $nodePath | Should -Not -BeNullOrEmpty
        $nodePath | Should -Match 'node\.exe$'
    }

    It "returns null for non-existent version" {
        if (-not (Test-FnmInstalled)) {
            Set-ItResult -Skipped -Because "fnm not installed"
            return
        }

        $nodePath = Get-FnmNodePath -Version "99.99.99"
        $nodePath | Should -BeNullOrEmpty
    }
}

Describe "Integration Tests" -Tag "Integration" {
    Context "Full version detection and installation workflow" {
        BeforeAll {
            $script:TestRepoPath = Join-Path $TestDrive "integration-test-repo"
            New-Item -Path $TestRepoPath -ItemType Directory -Force | Out-Null
        }

        It "detects version, installs if missing, and returns path" {
            if (-not (Test-FnmInstalled)) {
                Set-ItResult -Skipped -Because "fnm not installed"
                return
            }

            # Create .nvmrc with a specific version
            $nvmrcPath = Join-Path $TestRepoPath ".nvmrc"
            "20.19.0" | Set-Content $nvmrcPath -NoNewline

            # Detect version
            $detectedVersion = Get-NodeVersionFromFile -RepoPath $TestRepoPath
            $detectedVersion | Should -Be "20.19.0"

            # Check if already installed
            $installedVersions = Get-FnmVersions

            # Get Node path (should work if installed)
            if ($installedVersions -contains "20.19.0") {
                $nodePath = Get-FnmNodePath -Version "20.19.0"
                $nodePath | Should -Not -BeNullOrEmpty
                Test-Path $nodePath | Should -Be $true
            }
        }
    }
}
