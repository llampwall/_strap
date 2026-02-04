Describe "Chinvex CLI Wrapper" -Tag "Task2" {
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
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")
    }

    It "Test-ChinvexAvailable returns false when chinvex not found" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }
        $result = Test-ChinvexAvailable
        $result | Should -Be $false
    }

    It "Test-ChinvexAvailable returns true when chinvex exists" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        $result = Test-ChinvexAvailable
        $result | Should -Be $true
    }

    It "Test-ChinvexAvailable caches result on subsequent calls" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        $result1 = Test-ChinvexAvailable
        $result2 = Test-ChinvexAvailable

        $result1 | Should -Be $true
        $result2 | Should -Be $true
        Should -Invoke Get-Command -Times 1
    }

    It "Test-ChinvexEnabled returns false with -NoChinvex flag" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        $result = Test-ChinvexEnabled -NoChinvex -StrapRootPath $script:testStrapRoot
        $result | Should -Be $false
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
        $result | Should -Be $false
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
        $result | Should -Be $true
    }

    It "Invoke-Chinvex returns false when chinvex not available" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }
        $result = Invoke-Chinvex -Arguments @("context", "list")
        $result | Should -Be $false
    }

    It "Invoke-Chinvex returns true when command succeeds" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        Mock Invoke-Expression { $global:LASTEXITCODE = 0 } -ParameterFilter { $Command -like "*chinvex*" }

        $result = Invoke-Chinvex -Arguments @("context", "list")
        $result | Should -Be $true
    }

    It "Invoke-Chinvex returns false when command fails" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        Mock Invoke-Expression { $global:LASTEXITCODE = 1 } -ParameterFilter { $Command -like "*chinvex*" }

        $result = Invoke-Chinvex -Arguments @("context", "create", "test")
        $result | Should -Be $false
    }

    It "Invoke-ChinvexQuery returns null when chinvex not available" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }
        $result = Invoke-ChinvexQuery -Arguments @("context", "list", "--json")
        $result | Should -Be $null
    }

    It "Invoke-ChinvexQuery does not throw when called" {
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false

        Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
        { Invoke-ChinvexQuery -Arguments @("context", "list", "--json") } | Should -Not -Throw
    }
}
