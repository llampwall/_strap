BeforeAll {
    . "$PSScriptRoot/../../modules/Core.ps1"
    . "$PSScriptRoot/../../modules/Config.ps1"
}

Describe "Config v3.1 Schema" {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive "strap-test"
        New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
        $script:ConfigPath = Join-Path $TestRoot "config.json"
    }

    It "loads config with shims, nodeTools, and defaults fields" {
        $configContent = @{
            roots = @{
                software = "P:\software"
                tools = "P:\software\_scripts"
                shims = "P:\software\bin"
                nodeTools = "P:\software\_node-tools"
                archive = "P:\software\_archive"
            }
            defaults = @{
                pwshExe = "C:\Program Files\PowerShell\7\pwsh.exe"
                nodeExe = "C:\nvm4w\nodejs\node.exe"
            }
            registry = Join-Path $TestRoot "registry.json"
        } | ConvertTo-Json -Depth 10
        $configContent | Set-Content $ConfigPath -NoNewline

        $config = Load-Config $TestRoot

        $config.roots.shims | Should -Be "P:\software\bin"
        $config.roots.nodeTools | Should -Be "P:\software\_node-tools"
        $config.defaults.pwshExe | Should -Be "C:\Program Files\PowerShell\7\pwsh.exe"
        $config.defaults.nodeExe | Should -Be "C:\nvm4w\nodejs\node.exe"
    }

    It "applies defaults for missing shim fields" {
        $configContent = @{
            roots = @{
                software = "P:\software"
                tools = "P:\software\_scripts"
            }
            registry = Join-Path $TestRoot "registry.json"
        } | ConvertTo-Json -Depth 10
        $configContent | Set-Content $ConfigPath -NoNewline

        $config = Load-Config $TestRoot

        $config.roots.shims | Should -Not -BeNullOrEmpty
        $config.defaults | Should -Not -BeNullOrEmpty
        $config.defaults.pwshExe | Should -Not -BeNullOrEmpty
    }
}

Describe "Registry v2 Format" {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive "strap-test"
        New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
        $script:ConfigPath = Join-Path $TestRoot "config.json"
        $script:RegistryPath = Join-Path $TestRoot "registry.json"

        $configContent = @{
            roots = @{ software = "P:\software"; tools = "P:\software\_scripts" }
            registry = $RegistryPath
        } | ConvertTo-Json
        $configContent | Set-Content $ConfigPath -NoNewline
    }

    It "saves registry in v2 format with version field" {
        $config = Load-Config $TestRoot
        $entries = @(
            @{
                name = "test-repo"
                repoPath = "P:\software\test-repo"
                scope = "software"
                shims = @()
            }
        )

        Save-Registry $config $entries

        $saved = Get-Content $RegistryPath -Raw | ConvertFrom-Json
        $saved.version | Should -Be 2
        $saved.repos | Should -Not -BeNullOrEmpty
        $saved.repos[0].name | Should -Be "test-repo"
        $saved.repos[0].repoPath | Should -Be "P:\software\test-repo"
    }

    It "loads v2 registry format" {
        $registryContent = @{
            version = 2
            repos = @(
                @{
                    name = "chinvex"
                    repoPath = "P:\software\chinvex"
                    scope = "software"
                    shims = @()
                }
            )
        } | ConvertTo-Json -Depth 10
        $registryContent | Set-Content $RegistryPath -NoNewline

        $config = Load-Config $TestRoot
        $registry = Load-Registry $config

        $registry.Count | Should -Be 1
        $registry[0].name | Should -Be "chinvex"
        $registry[0].repoPath | Should -Be "P:\software\chinvex"
    }

    It "errors on unsupported registry version" {
        $registryContent = @{
            version = 99
            repos = @()
        } | ConvertTo-Json
        $registryContent | Set-Content $RegistryPath -NoNewline

        $config = Load-Config $TestRoot
        { Load-Registry $config } | Should -Throw "*version 99*"
    }

    It "migrates legacy v1 array format" {
        # Legacy format: bare array
        $legacyContent = @(
            @{ name = "old-repo"; path = "P:\software\old-repo"; scope = "software" }
        ) | ConvertTo-Json -Depth 10
        $legacyContent | Set-Content $RegistryPath -NoNewline

        $config = Load-Config $TestRoot
        $registry = Load-Registry $config

        $registry.Count | Should -Be 1
        $registry[0].name | Should -Be "old-repo"
    }
}
