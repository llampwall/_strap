# tests/powershell/Build-AuditIndex.Tests.ps1
Describe "Find-PathReferences" {
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

        # Create test repository with files containing path references
        $testRepo = Join-Path $TestDrive "TestRepo"
        New-Item -ItemType Directory -Path $testRepo -Force | Out-Null

        # Create test files with path references
        $scriptContent = @"
`$configPath = "C:\Code\chinvex\config\settings.json"
. C:\Code\chinvex\scripts\utils.ps1
# No path here
"@
        Set-Content -Path (Join-Path $testRepo "script.ps1") -Value $scriptContent

        $configContent = @"
{
  "dataPath": "C:\Code\chinvex\data",
  "logPath": "C:\Logs\app.log"
}
"@
        Set-Content -Path (Join-Path $testRepo "config.json") -Value $configContent

        $readmeContent = @"
# Project README
No paths in this file.
"@
        Set-Content -Path (Join-Path $testRepo "README.md") -Value $readmeContent
    }

    It "should find path references in repository files" {
        # Arrange
        $repoPath = Join-Path $TestDrive "TestRepo"

        # Act
        $result = Find-PathReferences -RepoPath $repoPath

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -BeGreaterThan 2  # At least 3 path references (script.ps1 has 2, config.json has 2)

        # Verify line number format: filepath:linenum
        $result[0] | Should -Match ":\d+$"
    }

    It "should scan common file types (ps1, json, yml, md, etc.)" {
        # Arrange
        $repoPath = Join-Path $TestDrive "TestRepo"

        # Act
        $result = Find-PathReferences -RepoPath $repoPath

        # Assert
        $psFiles = $result | Where-Object { $_ -like "*.ps1:*" }
        $jsonFiles = $result | Where-Object { $_ -like "*.json:*" }

        $psFiles | Should -Not -BeNullOrEmpty
        $jsonFiles | Should -Not -BeNullOrEmpty
    }

    It "should return empty array for repo with no path references" {
        # Arrange
        $cleanRepo = Join-Path $TestDrive "CleanRepo"
        New-Item -ItemType Directory -Path $cleanRepo -Force | Out-Null
        Set-Content -Path (Join-Path $cleanRepo "file.txt") -Value "No paths here"

        # Act
        $result = Find-PathReferences -RepoPath $cleanRepo

        # Assert
        $result | Should -BeNullOrEmpty
    }

    It "should handle non-existent repository gracefully" {
        # Arrange
        $nonExistentRepo = "C:\NonExistent\Repo"

        # Act
        $result = Find-PathReferences -RepoPath $nonExistentRepo

        # Assert
        $result | Should -BeNullOrEmpty
    }
}

Describe "Build-AuditIndex" {
    BeforeAll {
        # Functions are already loaded from modules at the top of the file

        # Create test registry entries
        $script:testRegistry = @(
            @{
                name = "chinvex"
                path = "C:\Code\chinvex"
                last_commit = "abc123"
            },
            @{
                name = "strap"
                path = "C:\Code\strap"
                last_commit = "def456"
            }
        )

        # Create mock repos
        $chinvexRepo = "C:\Code\chinvex"
        $strapRepo = "C:\Code\strap"

        New-Item -ItemType Directory -Path $chinvexRepo -Force | Out-Null
        New-Item -ItemType Directory -Path $strapRepo -Force | Out-Null

        Set-Content -Path (Join-Path $chinvexRepo "script.ps1") -Value "`$path = 'C:\Code\chinvex\data'"
        Set-Content -Path (Join-Path $strapRepo "config.json") -Value '{"root": "C:\Code\strap"}'
    }

    AfterAll {
        # Clean up test repos
        Remove-Item -Path "C:\Code\chinvex" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Code\strap" -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "should build audit index on first run" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index.json"
        $registryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Act
        $result = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.built_at | Should -Not -BeNullOrEmpty
        $result.registry_updated_at | Should -Be $registryUpdatedAt
        $result.repo_count | Should -Be 2
        $result.repos.Keys.Count | Should -Be 2

        # Verify index was written to disk
        Test-Path $indexPath | Should -Be $true
    }

    It "should include references array for each repository" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index-refs.json"
        $registryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Act
        $result = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        # Assert
        $chinvexEntry = $result.repos["C:\Code\chinvex"]
        $chinvexEntry | Should -Not -BeNullOrEmpty
        $chinvexEntry.references | Should -Not -BeNullOrEmpty
        $chinvexEntry.references.Count | Should -BeGreaterThan 0
    }

    It "should reuse existing index when metadata is fresh" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index-cached.json"
        $registryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Build initial index
        $firstResult = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        $firstBuiltAt = $firstResult.built_at

        Start-Sleep -Milliseconds 100

        # Act - build again without forcing rebuild
        $secondResult = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        # Assert - should be cached (same built_at timestamp)
        $secondResult.built_at | Should -Be $firstBuiltAt
    }

    It "should force rebuild when -RebuildIndex is true" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index-rebuild.json"
        $registryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Build initial index
        $firstResult = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        $firstBuiltAt = $firstResult.built_at

        Start-Sleep -Milliseconds 100

        # Act - force rebuild
        $secondResult = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $true `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        # Assert - should be rebuilt (different built_at timestamp)
        $secondResult.built_at | Should -Not -Be $firstBuiltAt
    }

    It "should rebuild when registry_updated_at changes" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index-stale.json"
        $oldRegistryUpdatedAt = "2026-02-01T10:00:00.000Z"
        $newRegistryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Build initial index
        Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $oldRegistryUpdatedAt -Registry $script:testRegistry

        # Act - build with new registry timestamp
        $result = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $newRegistryUpdatedAt -Registry $script:testRegistry

        # Assert - should be rebuilt
        $result.registry_updated_at | Should -Be $newRegistryUpdatedAt
    }

    It "should rebuild when repo count changes" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index-count.json"
        $registryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Build initial index with 2 repos
        Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        # Add third repo
        $expandedRegistry = $script:testRegistry + @(@{
            name = "newrepo"
            path = "C:\Code\newrepo"
            last_commit = "ghi789"
        })

        New-Item -ItemType Directory -Path "C:\Code\newrepo" -Force | Out-Null

        # Act - build with 3 repos
        $result = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $expandedRegistry

        # Assert - should be rebuilt
        $result.repo_count | Should -Be 3

        # Clean up
        Remove-Item -Path "C:\Code\newrepo" -Recurse -Force -ErrorAction SilentlyContinue
    }
}


