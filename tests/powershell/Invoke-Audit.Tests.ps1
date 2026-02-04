# tests/powershell/Invoke-Audit.Tests.ps1
Describe "Invoke-Audit" {
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

        # Create test registry
        $testRegistry = Join-Path $TestDrive "registry-v2.json"

        # Create test repo
        $testRepo = Join-Path $TestDrive "testproject"
        New-Item -ItemType Directory -Path $testRepo -Force | Out-Null
        Set-Content -Path (Join-Path $testRepo "config.ps1") -Value "`$path = 'C:\Code\testproject\data'"

        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @(
                @{
                    name = "testproject"
                    path = $testRepo
                    scope = "software"
                    last_commit = "abc123"
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content $testRegistry

        # Create config.json
        $configPath = Join-Path $TestDrive "config.json"
        @{
            registry = $testRegistry
            roots = @{
                software = $TestDrive
                tools = $TestDrive
                shims = Join-Path $TestDrive "shims"
            }
        } | ConvertTo-Json -Depth 10 | Set-Content $configPath
    }

    It "should scan specific repository and report path references" {
        # Arrange
        $targetName = "testproject"
        $strapRoot = $TestDrive
        $outputJson = $false

        # Act
        $result = Invoke-Audit -TargetName $targetName -StrapRootPath $strapRoot -OutputJson $outputJson

        # Assert
        $result | Should Not BeNullOrEmpty
        $result.references | Should Not BeNullOrEmpty
        $result.references.Count | Should BeGreaterThan 0
    }

    It "should scan all repositories when --all flag is used" {
        # Arrange
        $allFlag = $true
        $strapRoot = $TestDrive
        $outputJson = $false

        # Act
        $result = Invoke-Audit -AllRepos $allFlag -StrapRootPath $strapRoot -OutputJson $outputJson

        # Assert
        $result | Should Not BeNullOrEmpty
        $result.Count | Should BeGreaterThan 0
    }

    It "should build and cache audit index" {
        # Arrange
        $targetName = "testproject"
        $strapRoot = $TestDrive
        $indexPath = Join-Path $strapRoot "build\audit-index.json"
        $rebuildIndex = $false

        # Act
        Invoke-Audit -TargetName $targetName -StrapRootPath $strapRoot -RebuildIndex $rebuildIndex -OutputJson $false

        # Assert
        Test-Path $indexPath | Should Be $true
    }

    It "should force rebuild when --rebuild-index flag is used" {
        # Arrange
        $targetName = "testproject"
        $strapRoot = $TestDrive
        $indexPath = Join-Path $strapRoot "build\audit-index.json"

        # Build initial index
        Invoke-Audit -TargetName $targetName -StrapRootPath $strapRoot -RebuildIndex $false -OutputJson $false
        $firstIndex = Get-Content $indexPath | ConvertFrom-Json
        $firstBuiltAt = $firstIndex.built_at

        Start-Sleep -Milliseconds 100

        # Act - rebuild
        Invoke-Audit -TargetName $targetName -StrapRootPath $strapRoot -RebuildIndex $true -OutputJson $false

        # Assert
        $secondIndex = Get-Content $indexPath | ConvertFrom-Json
        $secondIndex.built_at | Should Not Be $firstBuiltAt
    }

    It "should output JSON when --json flag is used" {
        # Arrange
        $targetName = "testproject"
        $strapRoot = $TestDrive
        $outputJson = $true

        # Act
        $result = Invoke-Audit -TargetName $targetName -StrapRootPath $strapRoot -OutputJson $outputJson

        # Assert
        $result | Should Not BeNullOrEmpty
        $result.PSObject.Properties.Name -contains "repository" | Should Be $true
        $result.PSObject.Properties.Name -contains "references" | Should Be $true
    }

    It "should filter by --tool or --software scope" {
        # Arrange
        # Add tool-scoped repo to registry
        $registryPath = Join-Path $TestDrive "registry-v2.json"
        $registry = Get-Content $registryPath | ConvertFrom-Json

        $toolRepo = Join-Path $TestDrive "tooltool"
        New-Item -ItemType Directory -Path $toolRepo -Force | Out-Null

        $registry.entries += @{
            name = "tooltool"
            path = $toolRepo
            scope = "tool"
            last_commit = "def456"
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath

        $strapRoot = $TestDrive

        # Act - audit with --tool filter
        $result = Invoke-Audit -AllRepos $true -ToolScope $true -StrapRootPath $strapRoot -OutputJson $false

        # Assert
        $result | Should Not BeNullOrEmpty
        $result.Count | Should Be 1
        $result[0].repository | Should Be "tooltool"
    }
}
