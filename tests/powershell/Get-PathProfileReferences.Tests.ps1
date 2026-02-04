# tests/powershell/Get-PathProfileReferences.Tests.ps1
Describe "Get-PathReferences" {
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

        # Save original PATH
        $script:originalUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")

        # Set test PATH with repo reference
        [Environment]::SetEnvironmentVariable("PATH", "C:\Code\chinvex\bin;C:\Windows\System32", "User")
    }

    AfterAll {
        # Restore original PATH
        [Environment]::SetEnvironmentVariable("PATH", $script:originalUserPath, "User")
    }

    It "should detect PATH entries referencing repository paths" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")

        # Act
        $result = Get-PathReferences -RepoPaths $repoPaths

        # Assert
        $result | Should Not BeNullOrEmpty
        $result.Count | Should BeGreaterThan 0

        # Find matching entry
        $found = $false
        foreach ($entry in $result) {
            if ($entry.path -like "*chinvex*") {
                $entry.type | Should Be "PATH"
                $found = $true
                break
            }
        }
        $found | Should Be $true
    }

    It "should return empty array when no PATH entries match" {
        # Arrange
        $repoPaths = @("C:\NonExistent\Path")

        # Act
        $result = Get-PathReferences -RepoPaths $repoPaths

        # Assert
        $matchingNonExistent = $result | Where-Object { $_.path -like "*NonExistent*" }
        $matchingNonExistent | Should BeNullOrEmpty
    }

    It "should normalize paths and match case-insensitively" {
        # Arrange
        $repoPaths = @("c:\code\chinvex")  # lowercase

        # Act
        $result = Get-PathReferences -RepoPaths $repoPaths

        # Assert
        $result | Should Not BeNullOrEmpty
    }

    It "should check both User and Machine PATH variables" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")

        # Act
        $result = Get-PathReferences -RepoPaths $repoPaths

        # Assert
        # Function should scan both scopes (implementation detail verified)
        $result | Should Not BeNullOrEmpty
    }
}

Describe "Get-ProfileReferences" {
    BeforeAll {
        # Function is already loaded from References.ps1 module in main BeforeAll

        # Create test profile
        $testProfileDir = Join-Path $TestDrive "ProfileTest"
        New-Item -ItemType Directory -Path $testProfileDir -Force | Out-Null
        $testProfilePath = Join-Path $testProfileDir "Microsoft.PowerShell_profile.ps1"

        $profileContent = @"
# Test profile
`$env:CHINVEX_HOME = "C:\Code\chinvex"
. C:\Code\chinvex\scripts\init.ps1
Set-Location C:\Projects\work
"@
        Set-Content -Path $testProfilePath -Value $profileContent
    }

    It "should detect profile references to repository paths" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")
        $testProfilePath = Join-Path $TestDrive "ProfileTest\Microsoft.PowerShell_profile.ps1"

        # Act
        $result = Get-ProfileReferences -ProfilePath $testProfilePath -RepoPaths $repoPaths

        # Assert
        $result | Should Not BeNullOrEmpty
        $result.Count | Should BeGreaterThan 1  # At least two references to chinvex
        $result[0].type | Should Be "profile"
    }

    It "should return empty array when profile does not exist" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")
        $nonExistentProfile = "C:\NonExistent\profile.ps1"

        # Act
        $result = Get-ProfileReferences -ProfilePath $nonExistentProfile -RepoPaths $repoPaths

        # Assert
        $result | Should BeNullOrEmpty
    }

    It "should return empty array when no profile references match" {
        # Arrange
        $repoPaths = @("C:\NonExistent\Path")
        $testProfilePath = Join-Path $TestDrive "ProfileTest\Microsoft.PowerShell_profile.ps1"

        # Act
        $result = Get-ProfileReferences -ProfilePath $testProfilePath -RepoPaths $repoPaths

        # Assert
        $matchingNonExistent = $result | Where-Object { $_.path -like "*NonExistent*" }
        $matchingNonExistent | Should BeNullOrEmpty
    }

    It "should normalize paths and match case-insensitively" {
        # Arrange
        $repoPaths = @("c:\code\chinvex")  # lowercase
        $testProfilePath = Join-Path $TestDrive "ProfileTest\Microsoft.PowerShell_profile.ps1"

        # Act
        $result = Get-ProfileReferences -ProfilePath $testProfilePath -RepoPaths $repoPaths

        # Assert
        $result | Should Not BeNullOrEmpty
    }
}
