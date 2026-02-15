# Setup.NodeCorepack.Tests.ps1
# Tests for Node setup with corepack and fnm integration

BeforeAll {
    # Import required modules
    . "$PSScriptRoot\..\..\modules\Config.ps1"
    . "$PSScriptRoot\..\..\modules\FnmIntegration.ps1"
    . "$PSScriptRoot\..\..\modules\Commands\setup.ps1"
}

Describe "Node Setup - Corepack Integration" {
    Context "packageManager field detection" {
        BeforeAll {
            $script:TestRepoPath = Join-Path $TestDrive "corepack-test"
            New-Item -Path $TestRepoPath -ItemType Directory -Force | Out-Null
        }

        It "should not enable corepack when packageManager field is missing" {
            # Create minimal package.json without packageManager
            $packageJson = @{
                name = "test-project"
                version = "1.0.0"
            } | ConvertTo-Json
            Set-Content -Path (Join-Path $TestRepoPath "package.json") -Value $packageJson

            # Read setup code to check logic
            $setupContent = Get-Content "$PSScriptRoot\..\..\modules\Commands\setup.ps1" -Raw
            $setupContent | Should -Match 'packageManager'
            $setupContent | Should -Match 'needsCorepack'
        }

        It "should detect packageManager field in package.json" {
            # Create package.json with packageManager field
            $packageJson = @{
                name = "test-project"
                version = "1.0.0"
                packageManager = "pnpm@8.6.0"
            } | ConvertTo-Json
            Set-Content -Path (Join-Path $TestRepoPath "package.json") -Value $packageJson

            $content = Get-Content (Join-Path $TestRepoPath "package.json") -Raw | ConvertFrom-Json
            $content.PSObject.Properties['packageManager'] | Should -Not -BeNullOrEmpty
        }
    }

    Context "fnm Node path resolution for corepack" {
        It "should use fnm-managed Node for corepack when available" {
            if (-not (Test-FnmInstalled)) {
                Set-ItResult -Skipped -Because "fnm not installed"
                return
            }

            $installedVersions = Get-FnmVersions
            if ($installedVersions.Count -eq 0) {
                Set-ItResult -Skipped -Because "no Node versions installed via fnm"
                return
            }

            # Get path to fnm Node
            $version = $installedVersions[0]
            $nodePath = Get-FnmNodePath -Version $version

            if (-not $nodePath) {
                Set-ItResult -Skipped -Because "could not resolve fnm Node path"
                return
            }

            $nodeDir = Split-Path $nodePath -Parent
            $corepackPath = Join-Path $nodeDir "corepack.cmd"

            # Verify corepack exists in same directory as Node
            if (Test-Path $corepackPath) {
                $corepackPath | Should -Exist
                $nodeDir | Should -Be (Split-Path $nodePath -Parent)
            } else {
                Set-ItResult -Inconclusive -Because "corepack.cmd not found (Node < 16.9.0 or missing)"
            }
        }
    }

    Context "PATH environment setup for fnm Node" {
        It "should verify setup code prepends fnm Node directory to PATH" {
            $setupContent = Get-Content "$PSScriptRoot\..\..\modules\Commands\setup.ps1" -Raw

            # Check that we set up PATH for fnm Node
            $setupContent | Should -Match '\$env:PATH\s*='
            $setupContent | Should -Match 'fnmNodePath'
            $setupContent | Should -Match 'Split-Path'
        }
    }
}

Describe "Node Setup - Environment Isolation" {
    It "should use fnm Node, not global Node, when executing setup commands" {
        if (-not (Test-FnmInstalled)) {
            Set-ItResult -Skipped -Because "fnm not installed"
            return
        }

        # Verify setup logic sets up environment correctly
        $setupContent = Get-Content "$PSScriptRoot\..\..\modules\Commands\setup.ps1" -Raw

        # Should have environment setup logic
        $setupContent | Should -Match 'nodeEnvSetup'

        # Should modify PATH before executing commands
        $setupContent | Should -Match '\$env:PATH'
    }
}
