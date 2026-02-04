# tests/powershell/Invoke-Snapshot.Tests.ps1
Describe "Invoke-Snapshot" {
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

        # Create test scan directories with repos
        $testScanRoot = Join-Path $TestDrive "ScanTest"
        New-Item -ItemType Directory -Path $testScanRoot -Force | Out-Null

        # Create git repo
        $testRepo = Join-Path $testScanRoot "testproject"
        New-Item -ItemType Directory -Path (Join-Path $testRepo ".git") -Force | Out-Null
        Set-Content -Path (Join-Path $testRepo "README.md") -Value "# Test Project"

        # Create regular directory
        $testDir = Join-Path $testScanRoot "notes"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        # Create file
        $testFile = Join-Path $testScanRoot "helper.ps1"
        Set-Content -Path $testFile -Value "Write-Host 'Helper'"

        # Create minimal config.json for all tests
        $script:testConfigPath = Join-Path $TestDrive "config.json"
        $script:testRegistryPath = Join-Path $TestDrive "registry-v2.json"
        @{
            registry = $script:testRegistryPath
            roots = @{
                software = Join-Path $TestDrive "software"
                tools = Join-Path $TestDrive "tools"
                shims = Join-Path $TestDrive "shims"
            }
        } | ConvertTo-Json -Depth 10 | Set-Content $script:testConfigPath

        # Create empty registry
        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @()
        } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
    }

    It "should scan directories and classify items as file/directory" {
        # Arrange
        $scanDirs = @(Join-Path $TestDrive "ScanTest")
        $outputPath = Join-Path $TestDrive "snapshot-classify.json"
        $strapRoot = $TestDrive

        # Act
        $result = Invoke-Snapshot -ScanDirs $scanDirs -OutputPath $outputPath -StrapRootPath $strapRoot

        # Assert
        $result | Should Not BeNullOrEmpty
        $result.discovered | Should Not BeNullOrEmpty
        $result.discovered.Count | Should Be 3  # repo, dir, file
    }

    It "should detect git repositories with metadata" {
        # Arrange - the BeforeAll already created a git repo at testproject
        $scanDirs = @(Join-Path $TestDrive "ScanTest")
        $outputPath = Join-Path $TestDrive "snapshot-git.json"
        $strapRoot = $TestDrive

        # Act
        $result = Invoke-Snapshot -ScanDirs $scanDirs -OutputPath $outputPath -StrapRootPath $strapRoot

        # Assert
        # Should have discovered some items
        $result.discovered | Should Not BeNullOrEmpty
        $result.discovered.Count | Should BeGreaterThan 0

        # Should detect at least one item named testproject
        $testprojectItem = $result.discovered | Where-Object { $_.name -eq "testproject" }
        $testprojectItem | Should Not BeNullOrEmpty
        # It should be detected as a git repo (has .git subdirectory)
        $testprojectItem.type | Should Be "git"
    }

    It "should write snapshot manifest to output file" {
        # Arrange
        $scanDirs = @(Join-Path $TestDrive "ScanTest")
        $outputPath = Join-Path $TestDrive "snapshot-output.json"
        $strapRoot = $TestDrive

        # Act
        Invoke-Snapshot -ScanDirs $scanDirs -OutputPath $outputPath -StrapRootPath $strapRoot

        # Assert
        Test-Path $outputPath | Should Be $true

        $content = Get-Content $outputPath -Raw | ConvertFrom-Json
        $content.timestamp | Should Not BeNullOrEmpty
        $content.discovered | Should Not BeNullOrEmpty
        $content.registry | Should Not BeNullOrEmpty
    }

    It "should include registry snapshot and external references" {
        # Arrange
        $scanDirs = @(Join-Path $TestDrive "ScanTest")
        $outputPath = Join-Path $TestDrive "snapshot-full.json"
        $strapRoot = $TestDrive

        # Create mock registry
        $registryPath = Join-Path $strapRoot "registry-v2.json"
        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @()
        } | ConvertTo-Json -Depth 10 | Set-Content $registryPath

        # Act
        $result = Invoke-Snapshot -ScanDirs $scanDirs -OutputPath $outputPath -StrapRootPath $strapRoot

        # Assert
        $result.registry | Should Not BeNullOrEmpty
        $result.registry.version | Should Be 2
        $result.external_refs | Should Not BeNullOrEmpty
        # Check that external_refs has the expected properties (arrays, may be empty)
        $result.external_refs.pm2.GetType().Name | Should Match "Object"
        $result.external_refs.scheduled_tasks.GetType().Name | Should Match "Object"
    }

    It "should default to standard scan directories when none specified" {
        # Arrange
        $outputPath = Join-Path $TestDrive "snapshot-default.json"
        $strapRoot = $TestDrive

        # Act
        $result = Invoke-Snapshot -ScanDirs @() -OutputPath $outputPath -StrapRootPath $strapRoot

        # Assert - should use default dirs (C:\Code, P:\software, etc.)
        $result | Should Not BeNullOrEmpty
    }
}
