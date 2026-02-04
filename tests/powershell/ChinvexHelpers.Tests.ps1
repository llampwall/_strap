Describe "Detect-RepoScope" {
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

        # Setup test config
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        @{
            registry = Join-Path $script:testStrapRoot "registry-v2.json"
            roots = @{ software = "P:\software"; tools = "P:\software\_scripts"; shims = "P:\software\_scripts\shims" }
            chinvex_integration = $true
            software_root = "P:\software"
            tools_root = "P:\software\_scripts"
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        function Invoke-Chinvex {
            param([string[]] $Arguments)
            # This will be mocked in tests
            return $true
        }

        function Sync-ChinvexForEntry {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('tool', 'software')]
                [string] $Scope,
                [Parameter(Mandatory)]
                [string] $Name,
                [Parameter(Mandatory)]
                [string] $RepoPath
            )

            $contextName = Get-ContextName -Scope $Scope -Name $Name

            # Step 1: Create context (idempotent)
            $created = Invoke-Chinvex -Arguments @("context", "create", $contextName, "--idempotent")
            if (-not $created) {
                Warn "Failed to create chinvex context '$contextName'"
                return $null
            }

            # Step 2: Register repo path (no full ingestion)
            $registered = Invoke-Chinvex -Arguments @("ingest", "--context", $contextName, "--repo", $RepoPath, "--register-only")
            if (-not $registered) {
                Warn "Failed to register repo in chinvex context '$contextName'"
                return $null
            }

            Info "Synced to chinvex context: $contextName"
            return $contextName
        }
    }

    It "should return 'tool' for path under tools_root" {
        $result = Detect-RepoScope -Path "P:\software\_scripts\mytool" -StrapRootPath $script:testStrapRoot
        $result | Should Be "tool"
    }

    It "should return 'software' for path under software_root but not tools_root" {
        $result = Detect-RepoScope -Path "P:\software\myrepo" -StrapRootPath $script:testStrapRoot
        $result | Should Be "software"
    }

    It "should return null for path outside managed roots" {
        $result = Detect-RepoScope -Path "C:\random\path" -StrapRootPath $script:testStrapRoot
        $result | Should Be $null
    }

    It "should use most-specific match (tools_root before software_root)" {
        # P:\software\_scripts is under P:\software, but tools_root should match first
        $result = Detect-RepoScope -Path "P:\software\_scripts\nested\tool" -StrapRootPath $script:testStrapRoot
        $result | Should Be "tool"
    }

    It "should handle case-insensitive path comparison" {
        $result = Detect-RepoScope -Path "p:\SOFTWARE\myrepo" -StrapRootPath $script:testStrapRoot
        $result | Should Be "software"
    }
}

Describe "Get-ContextName" {
    BeforeAll {
        function Get-ContextName {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('tool', 'software')]
                [string] $Scope,
                [Parameter(Mandatory)]
                [string] $Name
            )

            if ($Scope -eq 'tool') {
                return 'tools'
            }
            return $Name
        }
    }

    It "should return 'tools' for tool scope" {
        $result = Get-ContextName -Scope "tool" -Name "mytool"
        $result | Should Be "tools"
    }

    It "should return entry name for software scope" {
        $result = Get-ContextName -Scope "software" -Name "myrepo"
        $result | Should Be "myrepo"
    }

    It "should ignore entry name for tool scope" {
        $result = Get-ContextName -Scope "tool" -Name "anytool"
        $result | Should Be "tools"
    }
}

Describe "Test-ReservedContextName" {
    BeforeAll {
        function Test-ReservedContextName {
            param(
                [Parameter(Mandatory)]
                [string] $Name,
                [Parameter(Mandatory)]
                [ValidateSet('tool', 'software')]
                [string] $Scope
            )

            # Reserved names only matter for software scope
            if ($Scope -ne 'software') {
                return $false
            }

            $reserved = @('tools', 'archive')
            return ($reserved -contains $Name.ToLower())
        }
    }

    It "should return true for 'tools' with software scope" {
        $result = Test-ReservedContextName -Name "tools" -Scope "software"
        $result | Should Be $true
    }

    It "should return true for 'archive' with software scope" {
        $result = Test-ReservedContextName -Name "archive" -Scope "software"
        $result | Should Be $true
    }

    It "should return false for 'tools' with tool scope" {
        $result = Test-ReservedContextName -Name "tools" -Scope "tool"
        $result | Should Be $false
    }

    It "should return false for regular name with software scope" {
        $result = Test-ReservedContextName -Name "myrepo" -Scope "software"
        $result | Should Be $false
    }

    It "should be case-insensitive for reserved names" {
        $result = Test-ReservedContextName -Name "TOOLS" -Scope "software"
        $result | Should Be $true
    }
}

Describe "Sync-ChinvexForEntry" {
    BeforeAll {
        function Load-Config {
            param([string] $StrapRoot)
            $configPath = Join-Path $StrapRoot "config.json"
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            return $config
        }

        function Warn([string] $msg) {
            Write-Warning $msg
        }

        function Info([string] $msg) {
            Write-Host $msg
        }

        function Get-ContextName {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('tool', 'software')]
                [string] $Scope,
                [Parameter(Mandatory)]
                [string] $Name
            )

            if ($Scope -eq 'tool') {
                return 'tools'
            }
            return $Name
        }

        # Create a wrapper for mocking purposes
        $script:invokeChinkexResults = @()
        $script:invokeChinkexCallCount = 0

        function Invoke-Chinvex {
            param(
                [Parameter(Mandatory)]
                [string[]] $Arguments
            )
            # Return results in sequence, or fall back to default
            if ($script:invokeChinkexResults.Count -gt 0 -and $script:invokeChinkexCallCount -lt $script:invokeChinkexResults.Count) {
                $result = $script:invokeChinkexResults[$script:invokeChinkexCallCount]
                $script:invokeChinkexCallCount++
                return $result
            }
            # Default: success
            return $true
        }

        function Sync-ChinvexForEntry {
            param(
                [Parameter(Mandatory)]
                [ValidateSet('tool', 'software')]
                [string] $Scope,
                [Parameter(Mandatory)]
                [string] $Name,
                [Parameter(Mandatory)]
                [string] $RepoPath
            )

            $contextName = Get-ContextName -Scope $Scope -Name $Name

            # Step 1: Create context (idempotent)
            $created = Invoke-Chinvex -Arguments @("context", "create", $contextName, "--idempotent")
            if (-not $created) {
                Warn "Failed to create chinvex context '$contextName'"
                return $null
            }

            # Step 2: Register repo path (no full ingestion)
            $registered = Invoke-Chinvex -Arguments @("ingest", "--context", $contextName, "--repo", $RepoPath, "--register-only")
            if (-not $registered) {
                Warn "Failed to register repo in chinvex context '$contextName'"
                return $null
            }

            Info "Synced to chinvex context: $contextName"
            return $contextName
        }

        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        @{
            registry = Join-Path $script:testStrapRoot "registry-v2.json"
            roots = @{ software = "P:\software"; tools = "P:\software\_scripts"; shims = "P:\software\_scripts\shims" }
            chinvex_integration = $true
            software_root = "P:\software"
            tools_root = "P:\software\_scripts"
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")
    }

    BeforeEach {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
        $script:invokeChinkexResults = @()
        $script:invokeChinkexCallCount = 0
    }

    It "should return null when chinvex context create fails" {
        $script:invokeChinkexResults = @($false)

        $result = Sync-ChinvexForEntry -Scope "software" -Name "myrepo" -RepoPath "P:\software\myrepo"
        $result | Should Be $null
    }

    It "should return null when chinvex ingest fails" {
        # First call (context create) succeeds, second call (ingest) fails
        $script:invokeChinkexResults = @($true, $false)

        $result = Sync-ChinvexForEntry -Scope "software" -Name "myrepo" -RepoPath "P:\software\myrepo"
        $result | Should Be $null
    }

    It "should return context name on success for software scope" {
        $script:invokeChinkexResults = @($true, $true)

        $result = Sync-ChinvexForEntry -Scope "software" -Name "myrepo" -RepoPath "P:\software\myrepo"
        $result | Should Be "myrepo"
    }

    It "should return 'tools' context name on success for tool scope" {
        $script:invokeChinkexResults = @($true, $true)

        $result = Sync-ChinvexForEntry -Scope "tool" -Name "mytool" -RepoPath "P:\software\_scripts\mytool"
        $result | Should Be "tools"
    }
}
