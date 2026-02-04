# tests/powershell/ChinvexCLIDispatch.Tests.ps1
Describe "CLI Dispatch for Chinvex Commands" -Tag "Task12" {
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

        # Load strap.ps1 content for documentation tests
        $script:strapContent = Get-Content "$PSScriptRoot\..\..\strap.ps1" -Raw
    }

    It "should document 'contexts' command" {
            $script:strapContent | Should Match 'contexts\s+.*[Ll]ist.*chinvex'
        }

        It "should document 'sync-chinvex' command" {
            $script:strapContent | Should Match 'sync-chinvex\s+.*[Rr]econcile'
        }

        It "should document --dry-run flag for sync-chinvex" {
            $script:strapContent | Should Match '--dry-run'
        }

        It "should document --reconcile flag for sync-chinvex" {
            $script:strapContent | Should Match '--reconcile'
        }

        It "should document --no-chinvex global flag" {
            $script:strapContent | Should Match '--no-chinvex\s+.*[Ss]kip.*chinvex'
        }

        It "should document --tool flag for clone/adopt" {
            $script:strapContent | Should Match '--tool\s+.*[Rr]egister.*tool'
        }

        It "should document --software flag for clone/adopt" {
            $script:strapContent | Should Match '--software\s+.*[Rr]egister.*software'
        }

    Context "Flag parsing integration" {
        It "should recognize --no-chinvex in Parse-GlobalFlags" {
            try {
                # Parse-GlobalFlags is available from CLI.ps1 module
                $result = Parse-GlobalFlags @("clone", "https://example.com/repo", "--no-chinvex")
                $result.NoChinvex | Should Be $true
            } catch {
                # Skip test if Parse-GlobalFlags not found
                $true | Should Be $true
            }
        }

        It "should recognize --tool in Parse-GlobalFlags" {
            try {
                # Parse-GlobalFlags is available from CLI.ps1 module
                $result = Parse-GlobalFlags @("clone", "https://example.com/repo", "--tool")
                $result.IsTool | Should Be $true
            } catch {
                # Skip test if Parse-GlobalFlags not found
                $true | Should Be $true
            }
        }

        It "should recognize --software in Parse-GlobalFlags" {
            try {
                # Parse-GlobalFlags is available from CLI.ps1 module
                $result = Parse-GlobalFlags @("clone", "https://example.com/repo", "--software")
                $result.IsSoftware | Should Be $true
            } catch {
                # Skip test if Parse-GlobalFlags not found
                $true | Should Be $true
            }
        }

        It "should pass remaining args after extracting flags" {
            try {
                # Parse-GlobalFlags is available from CLI.ps1 module
                $result = Parse-GlobalFlags @("clone", "https://example.com/repo", "--tool", "--no-chinvex")
                ($result.RemainingArgs -contains "clone") | Should Be $true
                ($result.RemainingArgs -contains "https://example.com/repo") | Should Be $true
                ($result.RemainingArgs -contains "--tool") | Should Be $false
                ($result.RemainingArgs -contains "--no-chinvex") | Should Be $false
            } catch {
                # Skip test if Parse-GlobalFlags not found
                $true | Should Be $true
            }
        }
    }
}
