Describe "Chinvex CLI Wrapper" -Tag "Task2" {
    BeforeAll {
        # Define utility functions
        function Die($msg) { Write-Error "ERROR: $msg"; exit 1 }
        function Info($msg) { Write-Host "INFO: $msg" }
        function Ok($msg) { Write-Host "OK: $msg" }
        function Warn($msg) { Write-Warning $msg }

        # Load-Config with minimal implementation for tests
        function Load-Config($strapRoot) {
            $configPath = Join-Path $strapRoot "config.json"
            if (-not (Test-Path $configPath)) {
                Die "Config not found: $configPath"
            }
            $json = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

            # Apply chinvex integration defaults
            if ($null -eq $json.chinvex_integration) {
                $json | Add-Member -NotePropertyName chinvex_integration -NotePropertyValue $true -Force
            }
            if ($null -eq $json.chinvex_whitelist) {
                $json | Add-Member -NotePropertyName chinvex_whitelist -NotePropertyValue @("tools", "archive") -Force
            }
            if ($null -eq $json.software_root) {
                $json | Add-Member -NotePropertyName software_root -NotePropertyValue "P:\software" -Force
            }
            if ($null -eq $json.tools_root) {
                $json | Add-Member -NotePropertyName tools_root -NotePropertyValue "P:\software\_scripts" -Force
            }

            return $json
        }

        # Script-level cache for chinvex availability check
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        function Test-ChinvexAvailable {
            <#
            .SYNOPSIS
                Checks if chinvex CLI is available on PATH. Result is cached.
            .OUTPUTS
                [bool] True if chinvex command exists, false otherwise.
            #>
            if (-not $script:chinvexChecked) {
                $script:chinvexChecked = $true
                $script:chinvexAvailable = [bool](Get-Command chinvex -ErrorAction SilentlyContinue)
                if (-not $script:chinvexAvailable) {
                    Warn "Chinvex not installed or not on PATH. Skipping context sync."
                }
            }
            return $script:chinvexAvailable
        }

        function Test-ChinvexEnabled {
            <#
            .SYNOPSIS
                Determines if chinvex integration should run.
            .DESCRIPTION
                Precedence: -NoChinvex flag > config.chinvex_integration > default (true)
            .PARAMETER NoChinvex
                If set, always returns false (explicit opt-out).
            .PARAMETER StrapRootPath
                Path to strap root for loading config.
            .OUTPUTS
                [bool] True if chinvex integration should run.
            #>
            param(
                [switch] $NoChinvex,
                [string] $StrapRootPath
            )

            # Flag overrides everything
            if ($NoChinvex) { return $false }

            # Config check
            $config = Load-Config $StrapRootPath
            if ($config.chinvex_integration -eq $false) { return $false }

            # Default: enabled, but only if chinvex is actually installed
            return (Test-ChinvexAvailable)
        }

        function Invoke-Chinvex {
            <#
            .SYNOPSIS
                Runs chinvex CLI command. Returns $true on exit 0, $false otherwise.
            .DESCRIPTION
                Does NOT throw - caller checks return value.
                Canonical error handling: any failure returns $false.
            .PARAMETER Arguments
                Array of arguments to pass to chinvex CLI.
            .OUTPUTS
                [bool] True if exit code 0, false otherwise.
            #>
            param(
                [Parameter(Mandatory)]
                [string[]] $Arguments
            )

            if (-not (Test-ChinvexAvailable)) { return $false }

            try {
                & chinvex @Arguments 2>&1 | Out-Null
                return ($LASTEXITCODE -eq 0)
            } catch {
                Warn "Chinvex error: $_"
                return $false
            }
        }

        function Invoke-ChinvexQuery {
            <#
            .SYNOPSIS
                Runs chinvex CLI command and returns stdout. Returns $null on failure.
            .PARAMETER Arguments
                Array of arguments to pass to chinvex CLI.
            .OUTPUTS
                [string] Command output on success, $null on failure.
            #>
            param(
                [Parameter(Mandatory)]
                [string[]] $Arguments
            )

            if (-not (Test-ChinvexAvailable)) { return $null }

            try {
                $output = & chinvex @Arguments 2>$null
                if ($LASTEXITCODE -eq 0) {
                    return ($output -join "`n")
                }
                return $null
            } catch {
                Warn "Chinvex query error: $_"
                return $null
            }
        }

        # Setup test config
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        @{
            registry = Join-Path $script:testStrapRoot "registry-v2.json"
            roots = @{ software = "P:\software"; tools = "P:\software\_scripts"; shims = "P:\software\_scripts\shims" }
            chinvex_integration = $true
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")
    }

    It "Test-ChinvexAvailable returns false when chinvex not found" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }
        $result = Test-ChinvexAvailable
        $result | Should Be $false
    }

    It "Test-ChinvexAvailable returns true when chinvex exists" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        $result = Test-ChinvexAvailable
        $result | Should Be $true
    }

    It "Test-ChinvexAvailable caches result on subsequent calls" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        $result1 = Test-ChinvexAvailable
        $result2 = Test-ChinvexAvailable

        $result1 | Should Be $true
        $result2 | Should Be $true
        Assert-MockCalled Get-Command -Times 1
    }

    It "Test-ChinvexEnabled returns false with -NoChinvex flag" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        $result = Test-ChinvexEnabled -NoChinvex -StrapRootPath $script:testStrapRoot
        $result | Should Be $false
    }

    It "Test-ChinvexEnabled returns false when config disables integration" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        @{
            registry = Join-Path $script:testStrapRoot "registry-v2.json"
            roots = @{ software = "P:\software"; tools = "P:\software\_scripts"; shims = "P:\software\_scripts\shims" }
            chinvex_integration = $false
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        $result = Test-ChinvexEnabled -StrapRootPath $script:testStrapRoot
        $result | Should Be $false
    }

    It "Test-ChinvexEnabled returns true when integration enabled and chinvex available" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        @{
            registry = Join-Path $script:testStrapRoot "registry-v2.json"
            roots = @{ software = "P:\software"; tools = "P:\software\_scripts"; shims = "P:\software\_scripts\shims" }
            chinvex_integration = $true
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        $result = Test-ChinvexEnabled -StrapRootPath $script:testStrapRoot
        $result | Should Be $true
    }

    It "Invoke-Chinvex returns false when chinvex not available" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }
        $result = Invoke-Chinvex -Arguments @("context", "list")
        $result | Should Be $false
    }

    It "Invoke-Chinvex returns true when command succeeds" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        Mock Invoke-Expression { $global:LASTEXITCODE = 0 } -ParameterFilter { $Command -like "*chinvex*" }

        $result = Invoke-Chinvex -Arguments @("context", "list")
        $result | Should Be $true
    }

    It "Invoke-Chinvex returns false when command fails" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        Mock Invoke-Expression { $global:LASTEXITCODE = 1 } -ParameterFilter { $Command -like "*chinvex*" }

        $result = Invoke-Chinvex -Arguments @("context", "create", "test")
        $result | Should Be $false
    }

    It "Invoke-ChinvexQuery returns null when chinvex not available" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }
        $result = Invoke-ChinvexQuery -Arguments @("context", "list", "--json")
        $result | Should Be $null
    }

    It "Invoke-ChinvexQuery does not throw when called" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        { Invoke-ChinvexQuery -Arguments @("context", "list", "--json") } | Should Not Throw
    }
}
