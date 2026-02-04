# tests/powershell/ChinvexDocs.Tests.ps1
Describe "Chinvex Integration Documentation" -Tag "Task14" {
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

        $script:docsRoot = "$PSScriptRoot\..\..\docs"
        $script:projectRoot = "$PSScriptRoot\..\.."
    }

    Context "Documentation file existence" {
        It "should have chinvex-integration.md in docs folder" {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            (Test-Path $docPath) | Should Be $true
        }

        It "should have non-empty chinvex-integration.md" {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            $content = Get-Content $docPath -Raw -ErrorAction SilentlyContinue
            ($content.Length -gt 500) | Should Be $true
        }
    }

    Context "Documentation content - Overview section" {
        BeforeAll {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            $script:docContent = Get-Content $docPath -Raw -ErrorAction SilentlyContinue
        }

        It "should explain strap as source of truth" {
            $script:docContent | Should Match "source of truth"
        }

        It "should explain scope mapping" {
            $script:docContent | Should Match "software.*individual"
            $script:docContent | Should Match "tool.*shared.*tools"
        }
    }

    Context "Documentation content - Command reference" {
        BeforeAll {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            $script:docContent = Get-Content $docPath -Raw -ErrorAction SilentlyContinue
        }

        It "should document strap clone with chinvex behavior" {
            $script:docContent | Should Match "clone.*chinvex"
        }

        It "should document strap adopt with chinvex behavior" {
            $script:docContent | Should Match "adopt.*chinvex"
        }

        It "should document strap move with chinvex behavior" {
            $script:docContent | Should Match "move.*chinvex"
        }

        It "should document strap rename with chinvex behavior" {
            $script:docContent | Should Match "rename.*chinvex"
        }

        It "should document strap uninstall with chinvex behavior" {
            $script:docContent | Should Match "uninstall.*archive"
        }

        It "should document strap contexts command" {
            $script:docContent | Should Match "strap contexts"
        }

        It "should document strap sync-chinvex command" {
            $script:docContent | Should Match "sync-chinvex"
            $script:docContent | Should Match "reconcile"
        }
    }

    Context "Documentation content - Opt-out mechanisms" {
        BeforeAll {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            $script:docContent = Get-Content $docPath -Raw -ErrorAction SilentlyContinue
        }

        It "should document --no-chinvex flag" {
            $script:docContent | Should Match "--no-chinvex"
        }

        It "should document config.json chinvex_integration setting" {
            $script:docContent | Should Match "chinvex_integration"
            $script:docContent | Should Match "config\.json"
        }

        It "should explain precedence (flag > config > default)" {
            $script:docContent | Should Match "precedence|override"
        }
    }

    Context "Documentation content - Troubleshooting" {
        BeforeAll {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            $script:docContent = Get-Content $docPath -Raw -ErrorAction SilentlyContinue
        }

        It "should have troubleshooting section" {
            $script:docContent | Should Match "[Tt]roubleshooting"
        }

        It "should explain what to do when chinvex not found" {
            $script:docContent | Should Match "chinvex.*not (found|installed|available)"
        }

        It "should explain drift recovery with sync-chinvex" {
            $script:docContent | Should Match "drift|reconcil"
        }
    }

    Context "README.md reference" {
        BeforeAll {
            $readmePath = Join-Path $script:projectRoot "README.md"
            $script:readmeContent = Get-Content $readmePath -Raw -ErrorAction SilentlyContinue
        }

        It "should mention chinvex integration in README" {
            $script:readmeContent | Should Match "[Cc]hinvex"
        }

        It "should link to chinvex-integration.md from README" {
            $script:readmeContent | Should Match "chinvex-integration\.md|docs/chinvex"
        }
    }
}
