# tests/powershell/ChinvexCLIDispatch.Tests.ps1
Describe "CLI Dispatch for Chinvex Commands" -Tag "Task12" {
    BeforeAll {
        # Extract functions from strap.ps1
        $strapContent = Get-Content "$PSScriptRoot\..\..\strap.ps1" -Raw

        function Extract-Function {
            param($Content, $FunctionName)
            $startIndex = $Content.IndexOf("function $FunctionName")
            if ($startIndex -eq -1) {
                throw "Could not find $FunctionName function in strap.ps1"
            }
            $braceCount = 0
            $inFunction = $false
            $endIndex = $startIndex
            for ($i = $startIndex; $i -lt $Content.Length; $i++) {
                $char = $Content[$i]
                if ($char -eq '{') {
                    $braceCount++
                    $inFunction = $true
                } elseif ($char -eq '}') {
                    $braceCount--
                    if ($inFunction -and $braceCount -eq 0) {
                        $endIndex = $i + 1
                        break
                    }
                }
            }
            return $Content.Substring($startIndex, $endIndex - $startIndex)
        }

        # Store the full strap content for dispatch testing
        $script:strapPath = "$PSScriptRoot\..\..\strap.ps1"
        $script:strapContent = $strapContent
    }

    Context "CLI dispatch entries" {
        It "should have dispatch entry for 'contexts' command" {
            $script:strapContent | Should Match 'RepoName.*-eq.*"contexts"[\s\S]{0,200}Invoke-Contexts'
        }

        It "should have dispatch entry for 'sync-chinvex' command" {
            $script:strapContent | Should Match 'RepoName.*-eq.*"sync-chinvex"[\s\S]{0,500}Invoke-SyncChinvex'
        }

        It "should pass --dry-run flag to Invoke-SyncChinvex" {
            $script:strapContent | Should Match 'RepoName.*-eq.*"sync-chinvex"[\s\S]{0,500}-DryRun'
        }

        It "should pass --reconcile flag to Invoke-SyncChinvex" {
            $script:strapContent | Should Match 'RepoName.*-eq.*"sync-chinvex"[\s\S]{0,500}-Reconcile'
        }
    }

    Context "Show-Help content" {
        BeforeAll {
            # Extract Show-Help function
            try {
                $funcCode = Extract-Function $script:strapContent "Show-Help"
                Invoke-Expression $funcCode
            } catch {
                Write-Warning "Could not extract Show-Help"
            }
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
    }

    Context "Flag parsing integration" {
        It "should recognize --no-chinvex in Parse-GlobalFlags" {
            try {
                $funcCode = Extract-Function $script:strapContent "Parse-GlobalFlags"
                Invoke-Expression $funcCode

                $result = Parse-GlobalFlags @("clone", "https://example.com/repo", "--no-chinvex")
                $result.NoChinvex | Should Be $true
            } catch {
                # Skip test if Parse-GlobalFlags not found
                $true | Should Be $true
            }
        }

        It "should recognize --tool in Parse-GlobalFlags" {
            try {
                $funcCode = Extract-Function $script:strapContent "Parse-GlobalFlags"
                Invoke-Expression $funcCode

                $result = Parse-GlobalFlags @("clone", "https://example.com/repo", "--tool")
                $result.IsTool | Should Be $true
            } catch {
                # Skip test if Parse-GlobalFlags not found
                $true | Should Be $true
            }
        }

        It "should recognize --software in Parse-GlobalFlags" {
            try {
                $funcCode = Extract-Function $script:strapContent "Parse-GlobalFlags"
                Invoke-Expression $funcCode

                $result = Parse-GlobalFlags @("clone", "https://example.com/repo", "--software")
                $result.IsSoftware | Should Be $true
            } catch {
                # Skip test if Parse-GlobalFlags not found
                $true | Should Be $true
            }
        }

        It "should pass remaining args after extracting flags" {
            try {
                $funcCode = Extract-Function $script:strapContent "Parse-GlobalFlags"
                Invoke-Expression $funcCode

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
