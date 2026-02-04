# tests/powershell/Get-ShimReferences.Tests.ps1
Describe "Get-ShimReferences" {
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

        # Create test shim directory
        $testShimDir = Join-Path $TestDrive "shims"
        New-Item -ItemType Directory -Path $testShimDir -Force | Out-Null

        # Create test shim file
        $shimContent = @"
@echo off
set "TARGET=C:\Code\chinvex\scripts\cli.ps1"
powershell -File "%TARGET%" %*
"@
        Set-Content -Path (Join-Path $testShimDir "chinvex.cmd") -Value $shimContent

        # Create shim with no path reference
        $noPathShim = @"
@echo off
echo "No path here"
"@
        Set-Content -Path (Join-Path $testShimDir "nopath.cmd") -Value $noPathShim

        # Create shim with non-matching path
        $otherPathShim = @"
@echo off
set "TARGET=D:\Other\Project\script.ps1"
powershell -File "%TARGET%" %*
"@
        Set-Content -Path (Join-Path $testShimDir "other.cmd") -Value $otherPathShim
    }

    It "should detect shims referencing repository paths" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")
        $shimDir = Join-Path $TestDrive "shims"

        # Act
        $result = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -Be 1
        $result[0].name | Should -Be "chinvex"
        $result[0].target | Should -Match "C:\\Code\\chinvex"
    }

    It "should return empty array when no shims match repo paths" {
        # Arrange
        $repoPaths = @("C:\NonExistent\Path")
        $shimDir = Join-Path $TestDrive "shims"

        # Act
        $result = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # Assert
        $result | Should -BeNullOrEmpty
    }

    It "should normalize paths and match case-insensitively" {
        # Arrange
        $repoPaths = @("c:\code\chinvex")  # lowercase
        $shimDir = Join-Path $TestDrive "shims"

        # Act
        $result = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result[0].name | Should -Be "chinvex"
    }

    It "should handle missing shim directory gracefully" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")
        $shimDir = "C:\NonExistent\Shims"

        # Act
        $result = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # Assert
        $result | Should -BeNullOrEmpty
    }

    It "should only process .cmd files" {
        # Arrange
        $shimDir = Join-Path $TestDrive "shims"
        # Create non-.cmd file
        Set-Content -Path (Join-Path $shimDir "test.txt") -Value "C:\Code\chinvex\file.ps1"
        $repoPaths = @("C:\Code\chinvex")

        # Act
        $result = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # Assert
        # Should only find chinvex.cmd, not test.txt
        $result.Count | Should -Be 1
    }
}
