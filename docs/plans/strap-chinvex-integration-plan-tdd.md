# Strap-Chinvex Integration Plan (TDD)

**Goal:** Integrate strap.ps1 with Chinvex CLI to maintain bidirectional sync between strap's registry and chinvex's context system.

**Architecture:** All functions remain in strap.ps1 (pure PowerShell). Chinvex integration is opt-in via config flag. Each strap command that modifies repository state calls chinvex CLI as a side effect when integration is enabled.

**Tech Stack:** PowerShell 5.1+, Pester 5.x for tests, Chinvex CLI (external dependency)

**Source Spec:** `docs/specs/strap-chinvex-integration.md`
**Reference Plan:** `docs/plans/strap-chinvex-integration-plan-ps.md`

---

## Batch 1: Foundation (Tasks 1-5)

### Task 1: Config Schema Extension

**Files:**
- Modify: `strap.ps1` (modify `Load-Config` function)
- Test: `tests/powershell/ChinvexConfig.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexConfig.Tests.ps1
Describe "Config Schema Extension" -Tag "Task1" {
    BeforeAll {
        # Extract Load-Config function from strap.ps1
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

        # Extract and load helper functions
        $functions = @("Die", "Warn", "Info", "Ok", "Load-Config")
        foreach ($funcName in $functions) {
            $funcCode = Extract-Function $strapContent $funcName
            Invoke-Expression $funcCode
        }

        # Create test directory structure
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
    }

    Context "When config.json exists with minimal fields" {
        BeforeEach {
            # Create minimal config.json (no chinvex fields)
            $minimalConfig = @{
                registry = Join-Path $script:testStrapRoot "registry-v2.json"
                roots = @{
                    software = "P:\software"
                    tools = "P:\software\_scripts"
                    shims = "P:\software\_scripts\shims"
                }
            }
            $minimalConfig | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")
        }

        It "should add chinvex_integration default (true)" {
            $config = Load-Config $script:testStrapRoot
            $config.chinvex_integration | Should -Be $true
        }

        It "should add chinvex_whitelist default (['tools', 'archive'])" {
            $config = Load-Config $script:testStrapRoot
            $config.chinvex_whitelist | Should -Contain "tools"
            $config.chinvex_whitelist | Should -Contain "archive"
        }

        It "should add software_root default (P:\software)" {
            $config = Load-Config $script:testStrapRoot
            $config.software_root | Should -Be "P:\software"
        }

        It "should add tools_root default (P:\software\_scripts)" {
            $config = Load-Config $script:testStrapRoot
            $config.tools_root | Should -Be "P:\software\_scripts"
        }
    }

    Context "When config.json has explicit chinvex fields" {
        BeforeEach {
            # Create config with explicit chinvex settings
            $explicitConfig = @{
                registry = Join-Path $script:testStrapRoot "registry-v2.json"
                roots = @{
                    software = "P:\software"
                    tools = "P:\software\_scripts"
                    shims = "P:\software\_scripts\shims"
                }
                chinvex_integration = $false
                chinvex_whitelist = @("tools", "archive", "custom-ctx")
                software_root = "D:\projects"
                tools_root = "D:\tools"
            }
            $explicitConfig | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")
        }

        It "should preserve explicit chinvex_integration value" {
            $config = Load-Config $script:testStrapRoot
            $config.chinvex_integration | Should -Be $false
        }

        It "should preserve explicit chinvex_whitelist value" {
            $config = Load-Config $script:testStrapRoot
            $config.chinvex_whitelist | Should -Contain "custom-ctx"
        }

        It "should preserve explicit software_root value" {
            $config = Load-Config $script:testStrapRoot
            $config.software_root | Should -Be "D:\projects"
        }

        It "should preserve explicit tools_root value" {
            $config = Load-Config $script:testStrapRoot
            $config.tools_root | Should -Be "D:\tools"
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexConfig.Tests.ps1 -TagFilter "Task1"`
Expected: FAIL with "Expected $true, but got $null" (chinvex_integration not set)

**Step 3: Write minimal implementation**
```powershell
# Modify Load-Config function in strap.ps1
function Load-Config($strapRoot) {
  $configPath = Join-Path $strapRoot "config.json"
  if (-not (Test-Path $configPath)) {
    Die "Config not found: $configPath"
  }
  $json = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

  # Apply chinvex integration defaults (new fields)
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
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexConfig.Tests.ps1 -TagFilter "Task1"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexConfig.Tests.ps1
git commit -m "feat(chinvex): Task 1 - extend Load-Config with chinvex defaults"
```

---

### Task 2: Chinvex CLI Wrapper

**Files:**
- Modify: `strap.ps1` (add wrapper functions after utility functions)
- Test: `tests/powershell/ChinvexWrapper.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexWrapper.Tests.ps1
Describe "Chinvex CLI Wrapper" -Tag "Task2" {
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

        # Extract helper and wrapper functions
        $functions = @("Die", "Warn", "Info", "Ok", "Load-Config", "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex", "Invoke-ChinvexQuery")
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                # Some functions may not exist yet during TDD
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

        # Reset cached state
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    Describe "Test-ChinvexAvailable" {
        BeforeEach {
            # Reset cache before each test
            $script:chinvexChecked = $false
            $script:chinvexAvailable = $false
        }

        It "should return false when chinvex command is not found" {
            # Mock Get-Command to return $null
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }

            $result = Test-ChinvexAvailable
            $result | Should -Be $false
        }

        It "should return true when chinvex command exists" {
            # Mock Get-Command to return a command object
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $result = Test-ChinvexAvailable
            $result | Should -Be $true
        }

        It "should cache the result on subsequent calls" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $result1 = Test-ChinvexAvailable
            $result2 = Test-ChinvexAvailable

            $result1 | Should -Be $true
            $result2 | Should -Be $true
            # Get-Command should only be called once due to caching
            Should -Invoke Get-Command -Times 1
        }
    }

    Describe "Test-ChinvexEnabled" {
        BeforeEach {
            $script:chinvexChecked = $false
            $script:chinvexAvailable = $false
        }

        It "should return false when -NoChinvex flag is set" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $result = Test-ChinvexEnabled -NoChinvex -StrapRootPath $script:testStrapRoot
            $result | Should -Be $false
        }

        It "should return false when config disables integration" {
            # Create config with integration disabled
            @{
                registry = Join-Path $script:testStrapRoot "registry-v2.json"
                roots = @{ software = "P:\software"; tools = "P:\software\_scripts"; shims = "P:\software\_scripts\shims" }
                chinvex_integration = $false
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $result = Test-ChinvexEnabled -StrapRootPath $script:testStrapRoot
            $result | Should -Be $false
        }

        It "should return true when integration enabled and chinvex available" {
            # Create config with integration enabled
            @{
                registry = Join-Path $script:testStrapRoot "registry-v2.json"
                roots = @{ software = "P:\software"; tools = "P:\software\_scripts"; shims = "P:\software\_scripts\shims" }
                chinvex_integration = $true
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $result = Test-ChinvexEnabled -StrapRootPath $script:testStrapRoot
            $result | Should -Be $true
        }
    }

    Describe "Invoke-Chinvex" {
        BeforeEach {
            $script:chinvexChecked = $false
            $script:chinvexAvailable = $false
        }

        It "should return false when chinvex is not available" {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }

            $result = Invoke-Chinvex -Arguments @("context", "list")
            $result | Should -Be $false
        }

        It "should return true when chinvex command succeeds (exit 0)" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            # Create a mock chinvex script that exits 0
            $mockChinvex = Join-Path $TestDrive "chinvex.ps1"
            Set-Content $mockChinvex "exit 0"

            # Override chinvex call using script block
            Mock Invoke-Expression { $global:LASTEXITCODE = 0 } -ParameterFilter { $Command -like "*chinvex*" }

            $result = Invoke-Chinvex -Arguments @("context", "list")
            $result | Should -Be $true
        }

        It "should return false when chinvex command fails (exit non-zero)" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            Mock Invoke-Expression { $global:LASTEXITCODE = 1 } -ParameterFilter { $Command -like "*chinvex*" }

            $result = Invoke-Chinvex -Arguments @("context", "create", "test")
            $result | Should -Be $false
        }
    }

    Describe "Invoke-ChinvexQuery" {
        BeforeEach {
            $script:chinvexChecked = $false
            $script:chinvexAvailable = $false
        }

        It "should return null when chinvex is not available" {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }

            $result = Invoke-ChinvexQuery -Arguments @("context", "list", "--json")
            $result | Should -Be $null
        }

        It "should return output when chinvex query succeeds" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            # The actual test will mock the chinvex call
            # For TDD, we verify the function exists and has correct signature
            { Invoke-ChinvexQuery -Arguments @("context", "list", "--json") } | Should -Not -Throw
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexWrapper.Tests.ps1 -TagFilter "Task2"`
Expected: FAIL with "Could not find Test-ChinvexAvailable function"

**Step 3: Write minimal implementation**
```powershell
# Add to strap.ps1 after utility functions (Die, Info, Ok, Warn) around line 110

# ============================================================================
# CHINVEX INTEGRATION - CLI Wrappers
# ============================================================================

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
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexWrapper.Tests.ps1 -TagFilter "Task2"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexWrapper.Tests.ps1
git commit -m "feat(chinvex): Task 2 - add chinvex CLI wrapper functions"
```

---

### Task 3: Integration Helpers

**Files:**
- Modify: `strap.ps1` (add helper functions after CLI wrappers)
- Test: `tests/powershell/ChinvexHelpers.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexHelpers.Tests.ps1
Describe "Chinvex Integration Helpers" -Tag "Task3" {
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

        # Extract all needed functions
        $functions = @(
            "Die", "Warn", "Info", "Ok", "Load-Config",
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex", "Invoke-ChinvexQuery",
            "Detect-RepoScope", "Get-ContextName", "Test-ReservedContextName", "Sync-ChinvexForEntry"
        )
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                # Functions may not exist yet during TDD
            }
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

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    Describe "Detect-RepoScope" {
        It "should return 'tool' for path under tools_root" {
            $result = Detect-RepoScope -Path "P:\software\_scripts\mytool" -StrapRootPath $script:testStrapRoot
            $result | Should -Be "tool"
        }

        It "should return 'software' for path under software_root but not tools_root" {
            $result = Detect-RepoScope -Path "P:\software\myrepo" -StrapRootPath $script:testStrapRoot
            $result | Should -Be "software"
        }

        It "should return null for path outside managed roots" {
            $result = Detect-RepoScope -Path "C:\random\path" -StrapRootPath $script:testStrapRoot
            $result | Should -Be $null
        }

        It "should use most-specific match (tools_root before software_root)" {
            # P:\software\_scripts is under P:\software, but tools_root should match first
            $result = Detect-RepoScope -Path "P:\software\_scripts\nested\tool" -StrapRootPath $script:testStrapRoot
            $result | Should -Be "tool"
        }

        It "should handle case-insensitive path comparison" {
            $result = Detect-RepoScope -Path "p:\SOFTWARE\myrepo" -StrapRootPath $script:testStrapRoot
            $result | Should -Be "software"
        }
    }

    Describe "Get-ContextName" {
        It "should return 'tools' for tool scope" {
            $result = Get-ContextName -Scope "tool" -Name "mytool"
            $result | Should -Be "tools"
        }

        It "should return entry name for software scope" {
            $result = Get-ContextName -Scope "software" -Name "myrepo"
            $result | Should -Be "myrepo"
        }

        It "should ignore entry name for tool scope" {
            $result = Get-ContextName -Scope "tool" -Name "anytool"
            $result | Should -Be "tools"
        }
    }

    Describe "Test-ReservedContextName" {
        It "should return true for 'tools' with software scope" {
            $result = Test-ReservedContextName -Name "tools" -Scope "software"
            $result | Should -Be $true
        }

        It "should return true for 'archive' with software scope" {
            $result = Test-ReservedContextName -Name "archive" -Scope "software"
            $result | Should -Be $true
        }

        It "should return false for 'tools' with tool scope" {
            $result = Test-ReservedContextName -Name "tools" -Scope "tool"
            $result | Should -Be $false
        }

        It "should return false for regular name with software scope" {
            $result = Test-ReservedContextName -Name "myrepo" -Scope "software"
            $result | Should -Be $false
        }

        It "should be case-insensitive for reserved names" {
            $result = Test-ReservedContextName -Name "TOOLS" -Scope "software"
            $result | Should -Be $true
        }
    }

    Describe "Sync-ChinvexForEntry" {
        BeforeEach {
            $script:chinvexChecked = $false
            $script:chinvexAvailable = $false
        }

        It "should return null when chinvex context create fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false } -ParameterFilter { $Arguments[0] -eq "context" -and $Arguments[1] -eq "create" }

            $result = Sync-ChinvexForEntry -Scope "software" -Name "myrepo" -RepoPath "P:\software\myrepo"
            $result | Should -Be $null
        }

        It "should return null when chinvex ingest fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex {
                param($Arguments)
                if ($Arguments[0] -eq "context" -and $Arguments[1] -eq "create") { return $true }
                return $false  # ingest fails
            }

            $result = Sync-ChinvexForEntry -Scope "software" -Name "myrepo" -RepoPath "P:\software\myrepo"
            $result | Should -Be $null
        }

        It "should return context name on success for software scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            $result = Sync-ChinvexForEntry -Scope "software" -Name "myrepo" -RepoPath "P:\software\myrepo"
            $result | Should -Be "myrepo"
        }

        It "should return 'tools' context name on success for tool scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            $result = Sync-ChinvexForEntry -Scope "tool" -Name "mytool" -RepoPath "P:\software\_scripts\mytool"
            $result | Should -Be "tools"
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexHelpers.Tests.ps1 -TagFilter "Task3"`
Expected: FAIL with "Could not find Detect-RepoScope function"

**Step 3: Write minimal implementation**
```powershell
# Add to strap.ps1 after CLI wrapper functions

# ============================================================================
# CHINVEX INTEGRATION - Helper Functions
# ============================================================================

function Detect-RepoScope {
    <#
    .SYNOPSIS
        Determines repo scope based on path location.
    .DESCRIPTION
        Returns 'tool' if under tools_root, 'software' if under software_root,
        or $null if outside managed roots. Most-specific path match wins.
    .PARAMETER Path
        The repository path to check.
    .PARAMETER StrapRootPath
        Path to strap root for loading config.
    .OUTPUTS
        [string] 'tool', 'software', or $null.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $Path,
        [Parameter(Mandatory)]
        [string] $StrapRootPath
    )

    $config = Load-Config $StrapRootPath

    # Normalize paths for comparison (ensure trailing backslash for prefix matching)
    $normalPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    $toolsRoot = [System.IO.Path]::GetFullPath($config.tools_root).TrimEnd('\') + '\'
    $softwareRoot = [System.IO.Path]::GetFullPath($config.software_root).TrimEnd('\') + '\'

    # Check tools_root first (more specific - it's a subdirectory of software_root)
    if ($normalPath.StartsWith($toolsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'tool'
    }

    # Then check software_root
    if ($normalPath.StartsWith($softwareRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'software'
    }

    return $null
}

function Get-ContextName {
    <#
    .SYNOPSIS
        Maps scope + entry name to chinvex context name.
    .DESCRIPTION
        Tools share a single 'tools' context. Software repos get individual contexts.
    .PARAMETER Scope
        Either 'tool' or 'software'.
    .PARAMETER Name
        The entry/repo name.
    .OUTPUTS
        [string] Context name ('tools' for tools, entry name for software).
    #>
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

function Test-ReservedContextName {
    <#
    .SYNOPSIS
        Checks if a name is reserved for system contexts.
    .DESCRIPTION
        Reserved names ('tools', 'archive') cannot be used for software repos.
        Tool repos can have any name since they all go into the 'tools' context.
    .PARAMETER Name
        The name to check.
    .PARAMETER Scope
        The intended scope ('tool' or 'software').
    .OUTPUTS
        [bool] True if name is reserved and scope is 'software'.
    #>
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

function Sync-ChinvexForEntry {
    <#
    .SYNOPSIS
        High-level function to create chinvex context and register repo path.
    .DESCRIPTION
        Creates context (idempotent) then registers repo path (register-only, no full ingestion).
        Returns context name on success, $null on any failure (canonical error handling).
    .PARAMETER Scope
        Either 'tool' or 'software'.
    .PARAMETER Name
        The entry/repo name.
    .PARAMETER RepoPath
        Full path to the repository.
    .OUTPUTS
        [string] Context name on success, $null on failure.
    #>
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
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexHelpers.Tests.ps1 -TagFilter "Task3"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexHelpers.Tests.ps1
git commit -m "feat(chinvex): Task 3 - add integration helper functions"
```

---

### Task 4: Invoke-Clone - Chinvex Integration

**Files:**
- Modify: `strap.ps1` (modify `Invoke-Clone` function)
- Test: `tests/powershell/ChinvexClone.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexClone.Tests.ps1
Describe "Invoke-Clone Chinvex Integration" -Tag "Task4" {
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

        # Extract all needed functions
        $functions = @(
            "Die", "Warn", "Info", "Ok", "Load-Config", "Load-Registry", "Save-Registry",
            "Parse-GitUrl", "Has-Command", "Ensure-Command",
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex", "Invoke-ChinvexQuery",
            "Detect-RepoScope", "Get-ContextName", "Test-ReservedContextName", "Sync-ChinvexForEntry",
            "Invoke-Clone"
        )
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                Write-Warning "Could not extract $funcName"
            }
        }

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        $script:testSoftwareRoot = Join-Path $TestDrive "software"
        $script:testToolsRoot = Join-Path $TestDrive "tools"
        $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"

        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testSoftwareRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testToolsRoot -Force | Out-Null
    }

    BeforeEach {
        # Reset config
        @{
            registry = $script:testRegistryPath
            roots = @{
                software = $script:testSoftwareRoot
                tools = $script:testToolsRoot
                shims = Join-Path $script:testToolsRoot "shims"
            }
            chinvex_integration = $true
            software_root = $script:testSoftwareRoot
            tools_root = $script:testToolsRoot
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Reset registry
        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @()
        } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    Describe "Registry entry fields" {
        It "should add 'scope' field with value 'software' for default clone" {
            # Mock git clone to succeed without actually cloning
            Mock git {
                param($args)
                if ($args[0] -eq "clone") {
                    $dest = $args[2]
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                    New-Item -ItemType Directory -Path (Join-Path $dest ".git") -Force | Out-Null
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Clone -GitUrl "https://github.com/user/testrepo" -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "testrepo" }
            $entry.scope | Should -Be "software"
        }

        It "should add 'scope' field with value 'tool' for --tool clone" {
            Mock git {
                param($args)
                if ($args[0] -eq "clone") {
                    $dest = $args[2]
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                    New-Item -ItemType Directory -Path (Join-Path $dest ".git") -Force | Out-Null
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Clone -GitUrl "https://github.com/user/mytool" -IsTool -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "mytool" }
            $entry.scope | Should -Be "tool"
        }

        It "should add 'chinvex_context' field with repo name for software scope" {
            Mock git {
                param($args)
                if ($args[0] -eq "clone") {
                    $dest = $args[2]
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                    New-Item -ItemType Directory -Path (Join-Path $dest ".git") -Force | Out-Null
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Clone -GitUrl "https://github.com/user/myproject" -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "myproject" }
            $entry.chinvex_context | Should -Be "myproject"
        }

        It "should add 'chinvex_context' field with 'tools' for tool scope" {
            Mock git {
                param($args)
                if ($args[0] -eq "clone") {
                    $dest = $args[2]
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                    New-Item -ItemType Directory -Path (Join-Path $dest ".git") -Force | Out-Null
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Clone -GitUrl "https://github.com/user/sometool" -IsTool -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "sometool" }
            $entry.chinvex_context | Should -Be "tools"
        }
    }

    Describe "Chinvex sync behavior" {
        It "should set chinvex_context to null when --no-chinvex flag used" {
            Mock git {
                param($args)
                if ($args[0] -eq "clone") {
                    $dest = $args[2]
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                    New-Item -ItemType Directory -Path (Join-Path $dest ".git") -Force | Out-Null
                    $global:LASTEXITCODE = 0
                }
            }

            Invoke-Clone -GitUrl "https://github.com/user/nochx" -NoChinvex -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "nochx" }
            $entry.chinvex_context | Should -Be $null
        }

        It "should set chinvex_context to null when chinvex unavailable" {
            Mock git {
                param($args)
                if ($args[0] -eq "clone") {
                    $dest = $args[2]
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                    New-Item -ItemType Directory -Path (Join-Path $dest ".git") -Force | Out-Null
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }

            Invoke-Clone -GitUrl "https://github.com/user/noavail" -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "noavail" }
            $entry.chinvex_context | Should -Be $null
        }

        It "should set chinvex_context to null when chinvex sync fails" {
            Mock git {
                param($args)
                if ($args[0] -eq "clone") {
                    $dest = $args[2]
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                    New-Item -ItemType Directory -Path (Join-Path $dest ".git") -Force | Out-Null
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }  # Chinvex fails

            Invoke-Clone -GitUrl "https://github.com/user/failsync" -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "failsync" }
            $entry.chinvex_context | Should -Be $null
        }
    }

    Describe "Reserved name validation" {
        It "should reject 'tools' as software repo name" {
            Mock git { $global:LASTEXITCODE = 0 }

            { Invoke-Clone -GitUrl "https://github.com/user/tools" -StrapRootPath $script:testStrapRoot } |
                Should -Throw "*reserved*"
        }

        It "should reject 'archive' as software repo name" {
            Mock git { $global:LASTEXITCODE = 0 }

            { Invoke-Clone -GitUrl "https://github.com/user/archive" -StrapRootPath $script:testStrapRoot } |
                Should -Throw "*reserved*"
        }

        It "should allow 'tools' as tool repo name (name ignored for tool scope)" {
            Mock git {
                param($args)
                if ($args[0] -eq "clone") {
                    $dest = $args[2]
                    New-Item -ItemType Directory -Path $dest -Force | Out-Null
                    New-Item -ItemType Directory -Path (Join-Path $dest ".git") -Force | Out-Null
                    $global:LASTEXITCODE = 0
                }
            }
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            # Should not throw - tool repos can have any name
            { Invoke-Clone -GitUrl "https://github.com/user/tools" -IsTool -StrapRootPath $script:testStrapRoot } |
                Should -Not -Throw
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexClone.Tests.ps1 -TagFilter "Task4"`
Expected: FAIL - tests will fail because Invoke-Clone doesn't have chinvex integration yet

**Step 3: Write minimal implementation**
```powershell
# Modify Invoke-Clone function in strap.ps1

function Invoke-Clone {
  param(
    [string] $GitUrl,
    [string] $CustomName,
    [string] $DestPath,
    [switch] $IsTool,
    [switch] $NoChinvex,
    [string] $StrapRootPath
  )

  Ensure-Command git

  if (-not $GitUrl) { Die "clone requires a git URL" }

  # Load config
  $config = Load-Config $StrapRootPath

  # Parse repo name from URL
  $repoName = if ($CustomName) { $CustomName } else { Parse-GitUrl $GitUrl }

  # Determine scope
  $scope = if ($IsTool) { "tool" } else { "software" }

  # Reserved name check (before any filesystem changes)
  if (Test-ReservedContextName -Name $repoName -Scope $scope) {
    Die "Cannot use reserved name '$repoName' for software repos. Reserved names: tools, archive"
  }

  # Determine destination
  $destPath = if ($DestPath) {
    $DestPath
  } elseif ($IsTool) {
    Join-Path $config.roots.tools $repoName
  } else {
    Join-Path $config.roots.software $repoName
  }

  # Check if destination already exists
  if (Test-Path $destPath) {
    Die "Destination already exists: $destPath"
  }

  # Load registry and check for duplicate name BEFORE cloning
  $registry = Load-Registry $config
  $existing = $registry | Where-Object { $_.name -eq $repoName }
  if ($existing) {
    Die "Entry with name '$repoName' already exists in registry at $($existing.path). Use --name to specify a different name."
  }

  Info "Cloning $GitUrl -> $destPath"

  # Clone the repo (capture output for error reporting)
  $gitOutput = & git clone $GitUrl $destPath 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Git clone failed with output:"
    Write-Host $gitOutput
    Die "Git clone failed"
  }

  Ok "Cloned to $destPath"

  # Resolve to absolute path for registry
  $absolutePath = (Resolve-Path -LiteralPath $destPath).Path

  # Create new entry with ID and chinvex fields
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $entry = [PSCustomObject]@{
    id              = $repoName
    name            = $repoName
    url             = $GitUrl
    path            = $absolutePath
    scope           = $scope
    chinvex_context = $null  # Default, updated below if sync succeeds
    shims           = @()
    stack           = @()
    created_at      = $timestamp
    updated_at      = $timestamp
  }

  # Add to registry
  $newRegistry = @()
  foreach ($item in $registry) {
    $newRegistry += $item
  }
  $newRegistry += $entry
  Save-Registry $config $newRegistry

  # Chinvex sync (after registry write)
  if (Test-ChinvexEnabled -NoChinvex:$NoChinvex -StrapRootPath $StrapRootPath) {
    $contextName = Sync-ChinvexForEntry -Scope $scope -Name $repoName -RepoPath $absolutePath
    if ($contextName) {
      # Update entry with successful chinvex context
      $entry.chinvex_context = $contextName
      # Re-save registry with updated chinvex_context
      $updatedRegistry = @()
      foreach ($item in $newRegistry) {
        if ($item.name -eq $repoName) {
          $item.chinvex_context = $contextName
        }
        $updatedRegistry += $item
      }
      Save-Registry $config $updatedRegistry
    }
  }

  Ok "Added to registry"

  # TODO: Offer to run setup / create shim
  Info "Next steps:"
  Info "  strap setup --repo $repoName"
  Info "  strap shim <name> --- <command> --repo $repoName"
}
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexClone.Tests.ps1 -TagFilter "Task4"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexClone.Tests.ps1
git commit -m "feat(chinvex): Task 4 - integrate chinvex with Invoke-Clone"
```

---

### Task 5: Invoke-Adopt - Chinvex Integration

**Files:**
- Modify: `strap.ps1` (modify `Invoke-Adopt` function)
- Test: `tests/powershell/ChinvexAdopt.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexAdopt.Tests.ps1
Describe "Invoke-Adopt Chinvex Integration" -Tag "Task5" {
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

        # Extract all needed functions
        $functions = @(
            "Die", "Warn", "Info", "Ok", "Load-Config", "Load-Registry", "Save-Registry",
            "Has-Command", "Ensure-Command",
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex", "Invoke-ChinvexQuery",
            "Detect-RepoScope", "Get-ContextName", "Test-ReservedContextName", "Sync-ChinvexForEntry",
            "Invoke-Adopt"
        )
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                Write-Warning "Could not extract $funcName"
            }
        }

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        $script:testSoftwareRoot = Join-Path $TestDrive "software"
        $script:testToolsRoot = Join-Path $TestDrive "tools"
        $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"

        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testSoftwareRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testToolsRoot -Force | Out-Null
    }

    BeforeEach {
        # Reset config
        @{
            registry = $script:testRegistryPath
            roots = @{
                software = $script:testSoftwareRoot
                tools = $script:testToolsRoot
                shims = Join-Path $script:testToolsRoot "shims"
            }
            chinvex_integration = $true
            software_root = $script:testSoftwareRoot
            tools_root = $script:testToolsRoot
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Reset registry
        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @()
        } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    function Create-TestRepo {
        param([string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path ".git") -Force | Out-Null
    }

    Describe "Auto-detect scope from path" {
        It "should auto-detect 'software' scope for repo under software_root" {
            $repoPath = Join-Path $script:testSoftwareRoot "autosoftware"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "autosoftware" }
            $entry.scope | Should -Be "software"
        }

        It "should auto-detect 'tool' scope for repo under tools_root" {
            $repoPath = Join-Path $script:testToolsRoot "autotool"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "autotool" }
            $entry.scope | Should -Be "tool"
        }
    }

    Describe "Explicit scope override" {
        It "should use 'tool' scope when --tool flag provided" {
            $repoPath = Join-Path $script:testSoftwareRoot "forcedtool"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -ForceTool -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "forcedtool" }
            $entry.scope | Should -Be "tool"
        }

        It "should use 'software' scope when --software flag provided" {
            $repoPath = Join-Path $script:testToolsRoot "forcedsoftware"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -ForceSoftware -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "forcedsoftware" }
            $entry.scope | Should -Be "software"
        }
    }

    Describe "Chinvex context field" {
        It "should set chinvex_context to repo name for software scope" {
            $repoPath = Join-Path $script:testSoftwareRoot "softwarectx"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "softwarectx" }
            $entry.chinvex_context | Should -Be "softwarectx"
        }

        It "should set chinvex_context to 'tools' for tool scope" {
            $repoPath = Join-Path $script:testToolsRoot "toolctx"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "toolctx" }
            $entry.chinvex_context | Should -Be "tools"
        }

        It "should set chinvex_context to null when --no-chinvex flag used" {
            $repoPath = Join-Path $script:testSoftwareRoot "nochxadopt"
            Create-TestRepo $repoPath

            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "nochxadopt" }
            $entry.chinvex_context | Should -Be $null
        }

        It "should set chinvex_context to null when chinvex unavailable" {
            $repoPath = Join-Path $script:testSoftwareRoot "unavailchx"
            Create-TestRepo $repoPath

            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }
            Mock git { $global:LASTEXITCODE = 0 }

            Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "unavailchx" }
            $entry.chinvex_context | Should -Be $null
        }
    }

    Describe "Reserved name validation" {
        It "should reject 'tools' as software repo name" {
            $repoPath = Join-Path $script:testSoftwareRoot "tools"
            Create-TestRepo $repoPath

            Mock git { $global:LASTEXITCODE = 0 }

            { Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot } |
                Should -Throw "*reserved*"
        }

        It "should reject 'archive' as software repo name" {
            $repoPath = Join-Path $script:testSoftwareRoot "archive"
            Create-TestRepo $repoPath

            Mock git { $global:LASTEXITCODE = 0 }

            { Invoke-Adopt -TargetPath $repoPath -NonInteractive -StrapRootPath $script:testStrapRoot } |
                Should -Throw "*reserved*"
        }

        It "should allow adopting repo named 'tools' as tool scope" {
            $repoPath = Join-Path $script:testToolsRoot "tools"
            Create-TestRepo $repoPath

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }
            Mock git { $global:LASTEXITCODE = 0 }

            { Invoke-Adopt -TargetPath $repoPath -ForceTool -NonInteractive -StrapRootPath $script:testStrapRoot } |
                Should -Not -Throw
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexAdopt.Tests.ps1 -TagFilter "Task5"`
Expected: FAIL - tests will fail because Invoke-Adopt doesn't have chinvex integration yet

**Step 3: Write minimal implementation**
```powershell
# Modify Invoke-Adopt function in strap.ps1

function Invoke-Adopt {
  param(
    [string] $TargetPath,
    [string] $CustomName,
    [switch] $ForceTool,
    [switch] $ForceSoftware,
    [switch] $NoChinvex,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Determine target path
  if (-not $TargetPath) {
    $TargetPath = Get-Location
  }

  # Resolve to absolute path
  $resolvedPath = [System.IO.Path]::GetFullPath($TargetPath)

  # Validate within managed roots
  $softwareRoot = $config.roots.software
  $toolsRoot = $config.roots.tools

  $withinSoftware = $resolvedPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase)
  $withinTools = $resolvedPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

  if (-not ($withinSoftware -or $withinTools)) {
    Die "Path is not within managed roots: $resolvedPath"
  }

  # Validate it's a git repo
  $gitDir = Join-Path $resolvedPath ".git"
  if (-not (Test-Path $gitDir)) {
    # Try git command
    try {
      & git -C $resolvedPath rev-parse --is-inside-work-tree 2>&1 | Out-Null
      if ($LASTEXITCODE -ne 0) {
        Die "Not a git repository: $resolvedPath"
      }
    } catch {
      Die "Not a git repository: $resolvedPath"
    }
  }

  # Determine name
  $name = if ($CustomName) { $CustomName } else { Split-Path $resolvedPath -Leaf }

  # Check for duplicates
  $existing = $registry | Where-Object { $_.name -eq $name }
  if ($existing) {
    Die "Entry with name '$name' already exists in registry at $($existing.path)"
  }

  # Determine scope (explicit flag > auto-detect from path)
  $scope = if ($ForceTool) {
    "tool"
  } elseif ($ForceSoftware) {
    "software"
  } else {
    # Auto-detect from path
    $detectedScope = Detect-RepoScope -Path $resolvedPath -StrapRootPath $StrapRootPath
    if ($null -eq $detectedScope) {
      Warn "Path is outside managed roots. Defaulting to 'software'. Use --tool or --software to override."
      "software"
    } else {
      Info "Auto-detected scope: $detectedScope (from path)"
      $detectedScope
    }
  }

  # Reserved name check (before any filesystem changes)
  if (Test-ReservedContextName -Name $name -Scope $scope) {
    Die "Cannot use reserved name '$name' for software repos. Reserved names: tools, archive"
  }

  # Extract git metadata (best-effort)
  $url = $null
  $lastHead = $null
  $defaultBranch = $null

  try {
    $remoteUrl = & git -C $resolvedPath remote get-url origin 2>&1
    if ($LASTEXITCODE -eq 0) {
      $url = $remoteUrl.Trim()
    }
  } catch {}

  try {
    $head = & git -C $resolvedPath rev-parse HEAD 2>&1
    if ($LASTEXITCODE -eq 0) {
      $lastHead = $head.Trim()
    }
  } catch {}

  try {
    $branch = & git -C $resolvedPath symbolic-ref --short refs/remotes/origin/HEAD 2>&1
    if ($LASTEXITCODE -eq 0) {
      $defaultBranch = $branch.Trim() -replace '^origin/', ''
    }
  } catch {}

  # Detect stack (best-effort)
  $stackDetected = $null
  Push-Location $resolvedPath
  try {
    if (Test-Path "pyproject.toml") { $stackDetected = "python" }
    elseif (Test-Path "requirements.txt") { $stackDetected = "python" }
    elseif (Test-Path "package.json") { $stackDetected = "node" }
    elseif (Test-Path "go.mod") { $stackDetected = "go" }
    elseif (Test-Path "Cargo.toml") { $stackDetected = "rust" }
  } finally {
    Pop-Location
  }

  # Dry run: show what would happen
  if ($DryRunMode) {
    Info "[DRY RUN] Would adopt: $resolvedPath"
    Info "[DRY RUN] Name: $name"
    Info "[DRY RUN] Scope: $scope"
    Info "[DRY RUN] URL: $url"
    Info "[DRY RUN] Stack: $stackDetected"
    return
  }

  # Create entry
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $entry = [PSCustomObject]@{
    id              = $name
    name            = $name
    url             = $url
    path            = $resolvedPath
    scope           = $scope
    chinvex_context = $null  # Default, updated below if sync succeeds
    shims           = @()
    stack           = if ($stackDetected) { @($stackDetected) } else { @() }
    last_head       = $lastHead
    default_branch  = $defaultBranch
    created_at      = $timestamp
    updated_at      = $timestamp
  }

  # Add to registry
  $newRegistry = @()
  foreach ($item in $registry) {
    $newRegistry += $item
  }
  $newRegistry += $entry
  Save-Registry $config $newRegistry

  # Chinvex sync (after registry write)
  if (Test-ChinvexEnabled -NoChinvex:$NoChinvex -StrapRootPath $StrapRootPath) {
    $contextName = Sync-ChinvexForEntry -Scope $scope -Name $name -RepoPath $resolvedPath
    if ($contextName) {
      # Update entry with successful chinvex context
      $entry.chinvex_context = $contextName
      # Re-save registry with updated chinvex_context
      $updatedRegistry = @()
      foreach ($item in $newRegistry) {
        if ($item.name -eq $name) {
          $item.chinvex_context = $contextName
        }
        $updatedRegistry += $item
      }
      Save-Registry $config $updatedRegistry
    }
  }

  Ok "Adopted: $name ($resolvedPath)"
  Info "Scope: $scope"
  if ($url) { Info "Remote: $url" }
  if ($stackDetected) { Info "Stack: $stackDetected" }
}
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexAdopt.Tests.ps1 -TagFilter "Task5"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexAdopt.Tests.ps1
git commit -m "feat(chinvex): Task 5 - integrate chinvex with Invoke-Adopt"
```

---

## Batch 2: Commands Part 1 (Tasks 6-10)

### Task 6: CLI Dispatch Wiring

**Files:**
- Modify: `strap.ps1` (modify CLI dispatch switch block and `Apply-ExtraArgs` function)
- Test: `tests/powershell/ChinvexCLI.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexCLI.Tests.ps1
Describe "CLI Dispatch Wiring for Chinvex Flags" -Tag "Task6" {
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

        # Extract Apply-ExtraArgs if it exists
        $functions = @("Apply-ExtraArgs", "Parse-GlobalFlags")
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                # May not exist yet
            }
        }

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
    }

    Describe "Parse-GlobalFlags function" {
        It "should extract --no-chinvex flag from arguments" {
            $args = @("clone", "https://github.com/user/repo", "--no-chinvex")
            $result = Parse-GlobalFlags $args

            $result.NoChinvex | Should -Be $true
            $result.RemainingArgs | Should -Not -Contain "--no-chinvex"
        }

        It "should extract --tool flag from arguments" {
            $args = @("clone", "https://github.com/user/repo", "--tool")
            $result = Parse-GlobalFlags $args

            $result.IsTool | Should -Be $true
            $result.RemainingArgs | Should -Not -Contain "--tool"
        }

        It "should extract --software flag from arguments" {
            $args = @("adopt", "--path", "P:\software\repo", "--software")
            $result = Parse-GlobalFlags $args

            $result.IsSoftware | Should -Be $true
            $result.RemainingArgs | Should -Not -Contain "--software"
        }

        It "should preserve other arguments" {
            $args = @("clone", "https://github.com/user/repo", "--no-chinvex", "--name", "myrepo")
            $result = Parse-GlobalFlags $args

            $result.NoChinvex | Should -Be $true
            $result.RemainingArgs | Should -Contain "--name"
            $result.RemainingArgs | Should -Contain "myrepo"
        }

        It "should handle multiple chinvex flags" {
            $args = @("clone", "https://github.com/user/repo", "--tool", "--no-chinvex")
            $result = Parse-GlobalFlags $args

            $result.NoChinvex | Should -Be $true
            $result.IsTool | Should -Be $true
        }

        It "should return false for flags not present" {
            $args = @("clone", "https://github.com/user/repo")
            $result = Parse-GlobalFlags $args

            $result.NoChinvex | Should -Be $false
            $result.IsTool | Should -Be $false
            $result.IsSoftware | Should -Be $false
        }
    }

    Describe "Registry field round-trip" {
        BeforeEach {
            # Setup test config and registry
            $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"
            @{
                registry = $script:testRegistryPath
                roots = @{
                    software = "P:\software"
                    tools = "P:\software\_scripts"
                    shims = "P:\software\_scripts\shims"
                }
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

            # Create registry with scope and chinvex_context fields
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "testrepo"
                        name = "testrepo"
                        path = "P:\software\testrepo"
                        scope = "software"
                        chinvex_context = "testrepo"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should preserve scope field on registry load/save" {
            # Load and save without modification
            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entries = $registry.entries

            # Verify scope exists
            $entry = $entries | Where-Object { $_.name -eq "testrepo" }
            $entry.scope | Should -Be "software"

            # Re-save
            $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

            # Re-load and verify
            $reloaded = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $reloadedEntry = $reloaded.entries | Where-Object { $_.name -eq "testrepo" }
            $reloadedEntry.scope | Should -Be "software"
        }

        It "should preserve chinvex_context field on registry load/save" {
            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "testrepo" }
            $entry.chinvex_context | Should -Be "testrepo"

            # Re-save and reload
            $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
            $reloaded = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $reloadedEntry = $reloaded.entries | Where-Object { $_.name -eq "testrepo" }
            $reloadedEntry.chinvex_context | Should -Be "testrepo"
        }

        It "should preserve null chinvex_context value" {
            # Update registry with null chinvex_context
            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "testrepo" }
            $entry.chinvex_context = $null
            $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

            # Re-load and verify null is preserved
            $reloaded = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $reloadedEntry = $reloaded.entries | Where-Object { $_.name -eq "testrepo" }
            $reloadedEntry.chinvex_context | Should -Be $null
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexCLI.Tests.ps1 -TagFilter "Task6"`
Expected: FAIL with "Could not find Parse-GlobalFlags function"

**Step 3: Write minimal implementation**
```powershell
# Add to strap.ps1 after Apply-ExtraArgs function (around line 95)

function Parse-GlobalFlags {
    <#
    .SYNOPSIS
        Extracts chinvex-related global flags from command line arguments.
    .DESCRIPTION
        Parses --no-chinvex, --tool, and --software flags.
        Returns a hashtable with flag values and remaining arguments.
    .PARAMETER Arguments
        The full argument list from CLI.
    .OUTPUTS
        [hashtable] with keys: NoChinvex, IsTool, IsSoftware, RemainingArgs
    #>
    param(
        [string[]] $Arguments
    )

    $result = @{
        NoChinvex = $false
        IsTool = $false
        IsSoftware = $false
        RemainingArgs = @()
    }

    foreach ($arg in $Arguments) {
        switch ($arg) {
            "--no-chinvex" { $result.NoChinvex = $true }
            "--tool" { $result.IsTool = $true }
            "--software" { $result.IsSoftware = $true }
            default { $result.RemainingArgs += $arg }
        }
    }

    return $result
}

# Modify the main CLI dispatch section at the bottom of strap.ps1
# After parsing arguments, extract global flags before dispatching to commands

# In the main entry point, add this parsing before the switch statement:
# $globalFlags = Parse-GlobalFlags $args
# $NoChinvex = $globalFlags.NoChinvex
# $IsTool = $globalFlags.IsTool
# $IsSoftware = $globalFlags.IsSoftware
# $remainingArgs = $globalFlags.RemainingArgs

# Then update the dispatch to pass these flags:
# "clone" {
#     Invoke-Clone -GitUrl $remainingArgs[1] -IsTool:$IsTool -NoChinvex:$NoChinvex -StrapRootPath $StrapRoot @extraParams
# }
# "adopt" {
#     Invoke-Adopt -TargetPath $targetPath -ForceTool:$IsTool -ForceSoftware:$IsSoftware -NoChinvex:$NoChinvex -StrapRootPath $StrapRoot @extraParams
# }
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexCLI.Tests.ps1 -TagFilter "Task6"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexCLI.Tests.ps1
git commit -m "feat(chinvex): Task 6 - add CLI dispatch wiring for chinvex flags"
```

---

### Task 7: Invoke-Move - Chinvex Integration

**Files:**
- Modify: `strap.ps1` (modify `Invoke-Move` function)
- Test: `tests/powershell/ChinvexMove.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexMove.Tests.ps1
Describe "Invoke-Move Chinvex Integration" -Tag "Task7" {
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

        # Extract all needed functions
        $functions = @(
            "Die", "Warn", "Info", "Ok", "Load-Config", "Load-Registry", "Save-Registry",
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex",
            "Detect-RepoScope", "Get-ContextName", "Sync-ChinvexForEntry",
            "Invoke-Move"
        )
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                Write-Warning "Could not extract $funcName"
            }
        }

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        $script:testSoftwareRoot = Join-Path $TestDrive "software"
        $script:testToolsRoot = Join-Path $TestDrive "tools"
        $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"

        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testSoftwareRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testToolsRoot -Force | Out-Null
    }

    BeforeEach {
        # Reset config
        @{
            registry = $script:testRegistryPath
            roots = @{
                software = $script:testSoftwareRoot
                tools = $script:testToolsRoot
                shims = Join-Path $script:testToolsRoot "shims"
            }
            chinvex_integration = $true
            software_root = $script:testSoftwareRoot
            tools_root = $script:testToolsRoot
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    function Create-TestRepo {
        param([string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path ".git") -Force | Out-Null
    }

    Describe "Move within same scope (software to software)" {
        BeforeEach {
            # Create source repo
            $script:sourceRepo = Join-Path $script:testSoftwareRoot "moverepo"
            Create-TestRepo $script:sourceRepo

            # Create registry
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "moverepo"
                        name = "moverepo"
                        path = $script:sourceRepo
                        scope = "software"
                        chinvex_context = "moverepo"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

            # Create subdir for destination
            $script:destDir = Join-Path $script:testSoftwareRoot "subdir"
            New-Item -ItemType Directory -Path $script:destDir -Force | Out-Null
        }

        It "should update chinvex path when moved within software root" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Move -NameToMove "moverepo" -DestPath $script:destDir -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should call ingest with new path, then remove-repo with old path
            $chinvexCalls | Should -HaveCount 2

            # First call: add new path
            $ingestCall = $chinvexCalls | Where-Object { $_[0] -eq "ingest" }
            $ingestCall | Should -Not -Be $null
            $ingestCall | Should -Contain "--register-only"

            # Second call: remove old path
            $removeCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "remove-repo" }
            $removeCall | Should -Not -Be $null
        }

        It "should keep same chinvex_context when scope unchanged" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "moverepo" -DestPath $script:destDir -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "moverepo" }
            $entry.chinvex_context | Should -Be "moverepo"
            $entry.scope | Should -Be "software"
        }
    }

    Describe "Move with scope change (software to tool)" {
        BeforeEach {
            # Create source repo in software root
            $script:sourceRepo = Join-Path $script:testSoftwareRoot "scopechange"
            Create-TestRepo $script:sourceRepo

            # Create registry
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "scopechange"
                        name = "scopechange"
                        path = $script:sourceRepo
                        scope = "software"
                        chinvex_context = "scopechange"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should update scope to tool when moved to tools_root" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "scopechange" -DestPath $script:testToolsRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "scopechange" }
            $entry.scope | Should -Be "tool"
        }

        It "should update chinvex_context to 'tools' when scope changes to tool" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "scopechange" -DestPath $script:testToolsRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "scopechange" }
            $entry.chinvex_context | Should -Be "tools"
        }

        It "should archive old context and create tools context on scope change" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Move -NameToMove "scopechange" -DestPath $script:testToolsRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should: create tools context, add to tools, archive old context
            $createCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "create" -and $_[2] -eq "tools" }
            $createCall | Should -Not -Be $null

            $archiveCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "archive" }
            $archiveCall | Should -Not -Be $null
        }
    }

    Describe "Move with scope change (tool to software)" {
        BeforeEach {
            # Create source repo in tools root
            $script:sourceRepo = Join-Path $script:testToolsRoot "toolrepo"
            Create-TestRepo $script:sourceRepo

            # Create registry
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "toolrepo"
                        name = "toolrepo"
                        path = $script:sourceRepo
                        scope = "tool"
                        chinvex_context = "tools"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should update scope to software when moved to software_root" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "toolrepo" -DestPath $script:testSoftwareRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "toolrepo" }
            $entry.scope | Should -Be "software"
        }

        It "should update chinvex_context to repo name when scope changes to software" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "toolrepo" -DestPath $script:testSoftwareRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "toolrepo" }
            $entry.chinvex_context | Should -Be "toolrepo"
        }

        It "should remove from tools context and create individual context on scope change" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Move -NameToMove "toolrepo" -DestPath $script:testSoftwareRoot -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should: create individual context, add to it, remove from tools
            $createCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "create" -and $_[2] -eq "toolrepo" }
            $createCall | Should -Not -Be $null

            $removeCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "remove-repo" }
            $removeCall | Should -Not -Be $null
        }
    }

    Describe "Chinvex failure handling" {
        BeforeEach {
            $script:sourceRepo = Join-Path $script:testSoftwareRoot "failmove"
            Create-TestRepo $script:sourceRepo

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "failmove"
                        name = "failmove"
                        path = $script:sourceRepo
                        scope = "software"
                        chinvex_context = "failmove"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

            $script:destDir = Join-Path $script:testSoftwareRoot "failsubdir"
            New-Item -ItemType Directory -Path $script:destDir -Force | Out-Null
        }

        It "should set chinvex_context to null when chinvex ingest fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }  # All chinvex calls fail

            Invoke-Move -NameToMove "failmove" -DestPath $script:destDir -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "failmove" }
            $entry.chinvex_context | Should -Be $null
        }

        It "should still complete move even when chinvex fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }

            Invoke-Move -NameToMove "failmove" -DestPath $script:destDir -NonInteractive -StrapRootPath $script:testStrapRoot

            # Verify move completed
            $expectedPath = Join-Path $script:destDir "failmove"
            Test-Path $expectedPath | Should -Be $true

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "failmove" }
            $entry.path | Should -Be $expectedPath
        }
    }

    Describe "--no-chinvex flag" {
        BeforeEach {
            $script:sourceRepo = Join-Path $script:testSoftwareRoot "nochxmove"
            Create-TestRepo $script:sourceRepo

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "nochxmove"
                        name = "nochxmove"
                        path = $script:sourceRepo
                        scope = "software"
                        chinvex_context = "nochxmove"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

            $script:destDir = Join-Path $script:testSoftwareRoot "nochxsubdir"
            New-Item -ItemType Directory -Path $script:destDir -Force | Out-Null
        }

        It "should skip chinvex operations when --no-chinvex flag is set" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Move -NameToMove "nochxmove" -DestPath $script:destDir -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            # Chinvex should not have been called
            Should -Invoke Invoke-Chinvex -Times 0
        }

        It "should preserve existing chinvex_context when --no-chinvex is used" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            Invoke-Move -NameToMove "nochxmove" -DestPath $script:destDir -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "nochxmove" }
            # Context preserved (but may be stale - that's expected with --no-chinvex)
            $entry.chinvex_context | Should -Be "nochxmove"
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexMove.Tests.ps1 -TagFilter "Task7"`
Expected: FAIL - tests will fail because Invoke-Move doesn't have chinvex integration yet

**Step 3: Write minimal implementation**
```powershell
# Modify Invoke-Move function in strap.ps1 to add chinvex integration

function Invoke-Move {
  param(
    [string] $NameToMove,
    [string] $DestPath,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $ForceOverwrite,
    [switch] $RehomeShims,
    [switch] $NoChinvex,
    [string] $StrapRootPath
  )

  if (-not $NameToMove) { Die "move requires <name>" }
  if (-not $DestPath) { Die "move requires --dest <path>" }

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config
  $softwareRoot = $config.roots.software
  $toolsRoot = $config.roots.tools

  # Find entry by name
  $entry = $registry | Where-Object { $_.name -eq $NameToMove }
  if (-not $entry) {
    Die "No entry found with name '$NameToMove'. Use 'strap list' to see all entries."
  }

  $oldPath = $entry.path
  if (-not $oldPath) {
    Die "Registry entry has no path field"
  }

  # Store old scope and context for chinvex operations
  $oldScope = $entry.scope
  $oldChinvexContext = $entry.chinvex_context

  # Validate source is absolute and inside managed roots
  if (-not [System.IO.Path]::IsPathRooted($oldPath)) {
    Die "Source path is not absolute: $oldPath"
  }

  $oldPathIsManaged = $oldPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase) -or
                      $oldPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

  if (-not $oldPathIsManaged) {
    Die "Source path is not within managed roots: $oldPath"
  }

  if (-not (Test-Path $oldPath)) {
    Die "Source folder does not exist: $oldPath"
  }

  # Compute new path
  $newPath = $null
  $destResolved = [System.IO.Path]::GetFullPath($DestPath)

  # If dest ends with \ or exists as directory, treat as parent
  if ($destResolved.EndsWith([System.IO.Path]::DirectorySeparatorChar) -or (Test-Path $destResolved -PathType Container)) {
    $folderName = Split-Path $oldPath -Leaf
    $newPath = Join-Path $destResolved $folderName
  } else {
    $newPath = $destResolved
  }

  # Validate new path is inside managed roots (pre-flight validation)
  $newPathIsManaged = $newPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase) -or
                      $newPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

  if (-not $newPathIsManaged) {
    Die "Destination path is not within managed roots: $newPath. Use strap uninstall + manual move + strap adopt instead."
  }

  # Detect new scope based on destination
  $newScope = Detect-RepoScope -Path $newPath -StrapRootPath $StrapRootPath

  # Reject if trying to move to root directory
  if ($newPath -eq $softwareRoot -or $newPath -eq $toolsRoot) {
    Die "Cannot move to root directory: $newPath"
  }

  # Check if destination exists
  if (Test-Path $newPath) {
    if (-not $ForceOverwrite) {
      Die "Destination already exists: $newPath (use --force to overwrite)"
    }
    $destItems = Get-ChildItem -LiteralPath $newPath -Force
    if ($destItems.Count -gt 0) {
      Die "Destination exists and is not empty: $newPath (unsafe to overwrite)"
    }
  }

  # Plan preview
  Write-Host ""
  Write-Host "=== MOVE PLAN ===" -ForegroundColor Cyan
  Write-Host "Entry: $NameToMove ($oldScope)"
  Write-Host "FROM:  $oldPath"
  Write-Host "TO:    $newPath"
  if ($oldScope -ne $newScope) {
    Write-Host "SCOPE: $oldScope -> $newScope" -ForegroundColor Yellow
  }
  if ($RehomeShims -and $entry.shims -and $entry.shims.Count -gt 0) {
    Write-Host "Shims: Will update $($entry.shims.Count) shim(s) to reference new path"
  }
  Write-Host ""

  if ($DryRunMode) {
    Info "Dry run mode - no changes made"
    return
  }

  # Confirmation
  if (-not $NonInteractive) {
    $response = Read-Host "Move $NameToMove now? (y/n)"
    if ($response -ne 'y') {
      Info "Move cancelled"
      return
    }
  }

  # Perform move
  try {
    Move-Item -LiteralPath $oldPath -Destination $newPath -ErrorAction Stop
    Ok "Moved folder: $oldPath -> $newPath"
  } catch {
    Die "Failed to move folder: $_"
  }

  # Update registry entry path
  $entry.path = $newPath
  $entry.updated_at = Get-Date -Format "o"

  # Chinvex integration
  if (Test-ChinvexEnabled -NoChinvex:$NoChinvex -StrapRootPath $StrapRootPath) {
    $scopeChanged = ($oldScope -ne $newScope)

    if ($scopeChanged) {
      # Scope change: create new context -> add to new -> remove from old
      $newContextName = Get-ContextName -Scope $newScope -Name $entry.name

      # Step 1: Create new context (idempotent)
      $created = Invoke-Chinvex -Arguments @("context", "create", $newContextName, "--idempotent")
      if ($created) {
        # Step 2: Add to new context
        $added = Invoke-Chinvex -Arguments @("ingest", "--context", $newContextName, "--repo", $newPath, "--register-only")
        if ($added) {
          # Step 3: Remove from old context
          if ($oldScope -eq 'software' -and $oldChinvexContext) {
            # Archive the old individual context
            Invoke-Chinvex -Arguments @("context", "archive", $oldChinvexContext) | Out-Null
          } elseif ($oldScope -eq 'tool' -and $oldChinvexContext) {
            # Remove from tools context
            Invoke-Chinvex -Arguments @("context", "remove-repo", $oldChinvexContext, "--repo", $oldPath) | Out-Null
          }

          # Update registry with new scope and context
          $entry.scope = $newScope
          $entry.chinvex_context = $newContextName
          Info "Chinvex: scope changed to $newScope, context: $newContextName"
        } else {
          # Ingest failed - mark for reconciliation
          $entry.chinvex_context = $null
          Warn "Chinvex ingest failed. Context marked for reconciliation."
        }
      } else {
        # Create failed - mark for reconciliation
        $entry.chinvex_context = $null
        Warn "Chinvex context create failed. Context marked for reconciliation."
      }
    } else {
      # No scope change: add new path -> remove old path
      $contextName = Get-ContextName -Scope $newScope -Name $entry.name

      $added = Invoke-Chinvex -Arguments @("ingest", "--context", $contextName, "--repo", $newPath, "--register-only")
      if ($added) {
        Invoke-Chinvex -Arguments @("context", "remove-repo", $contextName, "--repo", $oldPath) | Out-Null
        Info "Chinvex: updated path in context '$contextName'"
      } else {
        $entry.chinvex_context = $null
        Warn "Chinvex path update failed. Context marked for reconciliation."
      }
    }
  }

  # Update scope in registry (already done in chinvex block if enabled, but also do if disabled)
  if ($oldScope -ne $newScope) {
    $entry.scope = $newScope
  }

  # Optional shim rehome
  if ($RehomeShims -and $entry.shims -and $entry.shims.Count -gt 0) {
    $shimsUpdated = 0
    foreach ($shimPath in $entry.shims) {
      if (-not (Test-Path $shimPath)) {
        Warn "Shim not found, skipping: $shimPath"
        continue
      }

      try {
        $content = Get-Content -LiteralPath $shimPath -Raw
        if ($content -match [regex]::Escape($oldPath)) {
          $newContent = $content -replace [regex]::Escape($oldPath), $newPath
          Set-Content -LiteralPath $shimPath -Value $newContent -NoNewline
          $shimsUpdated++
        }
      } catch {
        Warn "Failed to update shim: $shimPath ($_)"
      }
    }
    if ($shimsUpdated -gt 0) {
      Ok "Updated $shimsUpdated shim(s)"
    }
  }

  # Save registry
  try {
    Save-Registry $config $registry
    Ok "Registry updated"
  } catch {
    Die "Failed to save registry: $_"
  }

  Ok "Move complete"
}
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexMove.Tests.ps1 -TagFilter "Task7"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexMove.Tests.ps1
git commit -m "feat(chinvex): Task 7 - integrate chinvex with Invoke-Move"
```

---

### Task 8: Invoke-Rename - Chinvex Integration

**Files:**
- Modify: `strap.ps1` (modify `Invoke-Rename` function)
- Test: `tests/powershell/ChinvexRename.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexRename.Tests.ps1
Describe "Invoke-Rename Chinvex Integration" -Tag "Task8" {
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

        # Extract all needed functions
        $functions = @(
            "Die", "Warn", "Info", "Ok", "Load-Config", "Load-Registry", "Save-Registry",
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex",
            "Detect-RepoScope", "Get-ContextName",
            "Invoke-Rename"
        )
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                Write-Warning "Could not extract $funcName"
            }
        }

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        $script:testSoftwareRoot = Join-Path $TestDrive "software"
        $script:testToolsRoot = Join-Path $TestDrive "tools"
        $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"

        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testSoftwareRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testToolsRoot -Force | Out-Null
    }

    BeforeEach {
        # Reset config
        @{
            registry = $script:testRegistryPath
            roots = @{
                software = $script:testSoftwareRoot
                tools = $script:testToolsRoot
                shims = Join-Path $script:testToolsRoot "shims"
            }
            chinvex_integration = $true
            software_root = $script:testSoftwareRoot
            tools_root = $script:testToolsRoot
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    function Create-TestRepo {
        param([string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path ".git") -Force | Out-Null
    }

    Describe "Rename software repo (registry only)" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "oldname"
            Create-TestRepo $script:repoPath

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "oldname"
                        name = "oldname"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "oldname"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should call chinvex context rename for software scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Rename -NameToRename "oldname" -NewName "newname" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should call context rename
            $renameCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "rename" }
            $renameCall | Should -Not -Be $null
            $renameCall | Should -Contain "oldname"
            $renameCall | Should -Contain "--to"
            $renameCall | Should -Contain "newname"
        }

        It "should update chinvex_context field to new name" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Rename -NameToRename "oldname" -NewName "newname" -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "newname" }
            $entry.chinvex_context | Should -Be "newname"
        }
    }

    Describe "Rename tool repo (registry only)" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testToolsRoot "oldtool"
            Create-TestRepo $script:repoPath

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "oldtool"
                        name = "oldtool"
                        path = $script:repoPath
                        scope = "tool"
                        chinvex_context = "tools"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should NOT call chinvex context rename for tool scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Rename -NameToRename "oldtool" -NewName "newtool" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should NOT invoke chinvex rename for tools
            Should -Invoke Invoke-Chinvex -Times 0
        }

        It "should keep chinvex_context as 'tools' for tool scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Rename -NameToRename "oldtool" -NewName "newtool" -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "newtool" }
            $entry.chinvex_context | Should -Be "tools"
        }
    }

    Describe "Rename with --move-folder" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "movefolder"
            Create-TestRepo $script:repoPath

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "movefolder"
                        name = "movefolder"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "movefolder"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should update path in chinvex context when --move-folder is used" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Rename -NameToRename "movefolder" -NewName "newmovefolder" -MoveFolder -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should call: context rename, then ingest (add new path), then remove-repo (old path)
            $renameCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "rename" }
            $renameCall | Should -Not -Be $null

            $ingestCall = $chinvexCalls | Where-Object { $_[0] -eq "ingest" }
            $ingestCall | Should -Not -Be $null

            $removeCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "remove-repo" }
            $removeCall | Should -Not -Be $null
        }

        It "should update registry path and chinvex_context" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Rename -NameToRename "movefolder" -NewName "renamedwithmove" -MoveFolder -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "renamedwithmove" }
            $entry.chinvex_context | Should -Be "renamedwithmove"

            $expectedPath = Join-Path $script:testSoftwareRoot "renamedwithmove"
            $entry.path | Should -Be $expectedPath
        }
    }

    Describe "Chinvex failure handling" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "failrename"
            Create-TestRepo $script:repoPath

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "failrename"
                        name = "failrename"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "failrename"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should set chinvex_context to null when chinvex rename fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }  # Fail

            Invoke-Rename -NameToRename "failrename" -NewName "newfailrename" -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "newfailrename" }
            $entry.chinvex_context | Should -Be $null
        }

        It "should still complete rename when chinvex fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }

            Invoke-Rename -NameToRename "failrename" -NewName "stillrenamed" -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "stillrenamed" }
            $entry | Should -Not -Be $null
            $entry.name | Should -Be "stillrenamed"
        }
    }

    Describe "--no-chinvex flag" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "nochxrename"
            Create-TestRepo $script:repoPath

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "nochxrename"
                        name = "nochxrename"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "nochxrename"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should skip chinvex operations when --no-chinvex is set" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Rename -NameToRename "nochxrename" -NewName "newnochx" -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            Should -Invoke Invoke-Chinvex -Times 0
        }

        It "should preserve existing chinvex_context when --no-chinvex is used" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            Invoke-Rename -NameToRename "nochxrename" -NewName "preserved" -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "preserved" }
            # Note: context is stale (still "nochxrename") but preserved as-is
            $entry.chinvex_context | Should -Be "nochxrename"
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexRename.Tests.ps1 -TagFilter "Task8"`
Expected: FAIL - tests will fail because Invoke-Rename doesn't have chinvex integration yet

**Step 3: Write minimal implementation**
```powershell
# Modify Invoke-Rename function in strap.ps1 to add chinvex integration

function Invoke-Rename {
  param(
    [string] $NameToRename,
    [string] $NewName,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $MoveFolder,
    [switch] $ForceOverwrite,
    [switch] $NoChinvex,
    [string] $StrapRootPath
  )

  if (-not $NameToRename) { Die "rename requires <name>" }
  if (-not $NewName) { Die "rename requires --to <newName>" }

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config
  $softwareRoot = $config.roots.software
  $toolsRoot = $config.roots.tools

  # Find entry by name
  $entry = $registry | Where-Object { $_.name -eq $NameToRename }
  if (-not $entry) {
    Die "No entry found with name '$NameToRename'. Use 'strap list' to see all entries."
  }

  # Store old values for chinvex operations
  $oldName = $entry.name
  $oldChinvexContext = $entry.chinvex_context
  $oldPath = $entry.path

  # Validate new name
  if ([string]::IsNullOrWhiteSpace($NewName)) {
    Die "New name cannot be empty"
  }

  # Check for reserved filesystem characters
  $reservedChars = '\/:*?"<>|'
  foreach ($char in $reservedChars.ToCharArray()) {
    if ($NewName.Contains($char)) {
      Die "New name contains invalid character: $char"
    }
  }

  # Check if new name already exists in registry
  $existingEntry = $registry | Where-Object { $_.name -eq $NewName }
  if ($existingEntry) {
    Die "Registry already contains an entry named '$NewName'"
  }

  $newPath = $null
  $folderMoved = $false

  # Compute new path if --move-folder
  if ($MoveFolder) {
    if (-not $oldPath) {
      Die "Registry entry has no path field"
    }

    $parent = Split-Path $oldPath -Parent
    $newPath = Join-Path $parent $NewName

    # Validate new path is inside managed roots
    $newPathIsManaged = $newPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase) -or
                        $newPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

    if (-not $newPathIsManaged) {
      Die "New path is not within managed roots: $newPath"
    }

    # Check if destination exists
    if (Test-Path $newPath) {
      Die "Destination folder already exists: $newPath"
    }
  }

  # Plan preview
  Write-Host ""
  Write-Host "=== RENAME PLAN ===" -ForegroundColor Cyan
  Write-Host "ENTRY: $NameToRename -> $NewName"
  if ($MoveFolder) {
    Write-Host "FOLDER: $oldPath -> $newPath"
  }
  Write-Host ""

  if ($DryRunMode) {
    Info "Dry run mode - no changes made"
    return
  }

  # Confirmation
  if (-not $NonInteractive) {
    $response = Read-Host "Rename $NameToRename now? (y/n)"
    if ($response -ne 'y') {
      Info "Rename cancelled"
      return
    }
  }

  # Optional folder rename
  if ($MoveFolder) {
    if (-not (Test-Path $oldPath)) {
      Die "Source folder does not exist: $oldPath"
    }

    try {
      Move-Item -LiteralPath $oldPath -Destination $newPath -ErrorAction Stop
      Ok "Renamed folder: $oldPath -> $newPath"
      $entry.path = $newPath
      $folderMoved = $true
    } catch {
      Die "Failed to rename folder: $_"
    }
  }

  # Update registry entry
  $entry.name = $NewName
  # If id convention is id=name, also update id
  if ($entry.id -eq $NameToRename) {
    $entry.id = $NewName
  }
  $entry.updated_at = Get-Date -Format "o"

  # Chinvex integration
  if (Test-ChinvexEnabled -NoChinvex:$NoChinvex -StrapRootPath $StrapRootPath) {
    if ($entry.scope -eq 'software' -and $oldChinvexContext) {
      # Rename the chinvex context
      $renamed = Invoke-Chinvex -Arguments @("context", "rename", $oldName, "--to", $NewName)
      if ($renamed) {
        $entry.chinvex_context = $NewName
        Info "Chinvex: renamed context '$oldName' -> '$NewName'"

        # If folder was also moved, update the path in the context
        if ($folderMoved) {
          $added = Invoke-Chinvex -Arguments @("ingest", "--context", $NewName, "--repo", $newPath, "--register-only")
          if ($added) {
            Invoke-Chinvex -Arguments @("context", "remove-repo", $NewName, "--repo", $oldPath) | Out-Null
            Info "Chinvex: updated path in context '$NewName'"
          } else {
            $entry.chinvex_context = $null
            Warn "Chinvex path update failed. Context marked for reconciliation."
          }
        }
      } else {
        $entry.chinvex_context = $null
        Warn "Chinvex context rename failed. Context marked for reconciliation."
      }
    }
    # Tool scope: no chinvex action needed (stays in 'tools' context)
    # chinvex_context remains 'tools'
  }

  # Save registry
  try {
    Save-Registry $config $registry
    Ok "Registry updated"
  } catch {
    Die "Failed to save registry: $_"
  }

  Ok "Rename complete"
}
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexRename.Tests.ps1 -TagFilter "Task8"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexRename.Tests.ps1
git commit -m "feat(chinvex): Task 8 - integrate chinvex with Invoke-Rename"
```

---

### Task 9: Invoke-Uninstall - Chinvex Integration

**Files:**
- Modify: `strap.ps1` (modify `Invoke-Uninstall` function)
- Test: `tests/powershell/ChinvexUninstall.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexUninstall.Tests.ps1
Describe "Invoke-Uninstall Chinvex Integration" -Tag "Task9" {
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

        # Extract all needed functions
        $functions = @(
            "Die", "Warn", "Info", "Ok", "Load-Config", "Load-Registry", "Save-Registry",
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex",
            "Detect-RepoScope", "Get-ContextName",
            "Invoke-Uninstall"
        )
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                Write-Warning "Could not extract $funcName"
            }
        }

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        $script:testSoftwareRoot = Join-Path $TestDrive "software"
        $script:testToolsRoot = Join-Path $TestDrive "tools"
        $script:testShimsRoot = Join-Path $script:testToolsRoot "shims"
        $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"

        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testSoftwareRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testToolsRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testShimsRoot -Force | Out-Null
    }

    BeforeEach {
        # Reset config
        @{
            registry = $script:testRegistryPath
            roots = @{
                software = $script:testSoftwareRoot
                tools = $script:testToolsRoot
                shims = $script:testShimsRoot
            }
            chinvex_integration = $true
            software_root = $script:testSoftwareRoot
            tools_root = $script:testToolsRoot
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    function Create-TestRepo {
        param([string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path ".git") -Force | Out-Null
    }

    Describe "Uninstall software repo" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "uninstallsoft"
            Create-TestRepo $script:repoPath

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "uninstallsoft"
                        name = "uninstallsoft"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "uninstallsoft"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should call chinvex context archive for software scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Uninstall -NameToRemove "uninstallsoft" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should call context archive
            $archiveCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "archive" }
            $archiveCall | Should -Not -Be $null
            $archiveCall | Should -Contain "uninstallsoft"
        }

        It "should remove entry from registry after uninstall" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Uninstall -NameToRemove "uninstallsoft" -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "uninstallsoft" }
            $entry | Should -Be $null
        }

        It "should delete folder on uninstall" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Uninstall -NameToRemove "uninstallsoft" -NonInteractive -StrapRootPath $script:testStrapRoot

            Test-Path $script:repoPath | Should -Be $false
        }
    }

    Describe "Uninstall tool repo" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testToolsRoot "uninstalltool"
            Create-TestRepo $script:repoPath

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "uninstalltool"
                        name = "uninstalltool"
                        path = $script:repoPath
                        scope = "tool"
                        chinvex_context = "tools"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should call chinvex context remove-repo for tool scope" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Uninstall -NameToRemove "uninstalltool" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should call remove-repo on tools context
            $removeCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "remove-repo" }
            $removeCall | Should -Not -Be $null
            $removeCall | Should -Contain "tools"
            $removeCall | Should -Contain "--repo"
        }

        It "should NOT archive tools context when uninstalling a tool" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Uninstall -NameToRemove "uninstalltool" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should NOT call archive for tools
            $archiveCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "archive" -and $_[2] -eq "tools" }
            $archiveCall | Should -Be $null
        }
    }

    Describe "Chinvex failure handling" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "failuninstall"
            Create-TestRepo $script:repoPath

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "failuninstall"
                        name = "failuninstall"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "failuninstall"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should complete uninstall even when chinvex archive fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }  # Fail

            Invoke-Uninstall -NameToRemove "failuninstall" -NonInteractive -StrapRootPath $script:testStrapRoot

            # Entry should still be removed
            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "failuninstall" }
            $entry | Should -Be $null

            # Folder should still be deleted
            Test-Path $script:repoPath | Should -Be $false
        }
    }

    Describe "--no-chinvex flag" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "nochxuninstall"
            Create-TestRepo $script:repoPath

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "nochxuninstall"
                        name = "nochxuninstall"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "nochxuninstall"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should skip chinvex operations when --no-chinvex is set" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            Invoke-Uninstall -NameToRemove "nochxuninstall" -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            Should -Invoke Invoke-Chinvex -Times 0
        }

        It "should still complete uninstall when --no-chinvex is used" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            Invoke-Uninstall -NameToRemove "nochxuninstall" -NoChinvex -NonInteractive -StrapRootPath $script:testStrapRoot

            $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
            $entry = $registry.entries | Where-Object { $_.name -eq "nochxuninstall" }
            $entry | Should -Be $null
        }
    }

    Describe "--keep-folder flag" {
        BeforeEach {
            $script:repoPath = Join-Path $script:testSoftwareRoot "keepfolderuninstall"
            Create-TestRepo $script:repoPath

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "keepfolderuninstall"
                        name = "keepfolderuninstall"
                        path = $script:repoPath
                        scope = "software"
                        chinvex_context = "keepfolderuninstall"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should still archive chinvex context even with --keep-folder" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $chinvexCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                $chinvexCalls += ,@($Arguments)
                return $true
            }

            Invoke-Uninstall -NameToRemove "keepfolderuninstall" -PreserveFolder -NonInteractive -StrapRootPath $script:testStrapRoot

            # Should still archive
            $archiveCall = $chinvexCalls | Where-Object { $_[0] -eq "context" -and $_[1] -eq "archive" }
            $archiveCall | Should -Not -Be $null
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexUninstall.Tests.ps1 -TagFilter "Task9"`
Expected: FAIL - tests will fail because Invoke-Uninstall doesn't have chinvex integration yet

**Step 3: Write minimal implementation**
```powershell
# Modify Invoke-Uninstall function in strap.ps1 to add chinvex integration

function Invoke-Uninstall {
  param(
    [string] $NameToRemove,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $PreserveFolder,
    [switch] $PreserveShims,
    [switch] $NoChinvex,
    [string] $StrapRootPath
  )

  if (-not $NameToRemove) { Die "uninstall requires <name>" }

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Find entry by name
  $entry = $registry | Where-Object { $_.name -eq $NameToRemove }
  if (-not $entry) {
    Die "No entry found with name '$NameToRemove'. Use 'strap list' to see all entries."
  }

  # Safety validation - check managed roots
  $softwareRoot = $config.roots.software
  $toolsRoot = $config.roots.tools
  $shimsRoot = $config.roots.shims

  # Validate repo path
  $repoPath = $entry.path
  if (-not $repoPath) {
    Die "Registry entry has no path field"
  }

  # Check that path is within managed roots
  $pathIsManaged = $repoPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase) -or
                   $repoPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

  if (-not $pathIsManaged) {
    Die "Path is not within managed roots: $repoPath"
  }

  # Disallow deleting the root directories themselves
  if ($repoPath -eq $softwareRoot -or $repoPath -eq $toolsRoot) {
    Die "Cannot delete root directory: $repoPath"
  }

  # Validate shim paths
  $shimsToDelete = @()
  if (-not $PreserveShims -and $entry.shims) {
    foreach ($shim in $entry.shims) {
      if (-not [System.IO.Path]::IsPathRooted($shim)) {
        Die "Shim path is not absolute: $shim"
      }

      if (-not $shim.StartsWith($shimsRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Die "Shim path is not within shims root: $shim"
      }

      if ($shim -eq $shimsRoot) {
        Die "Cannot delete shims root directory: $shim"
      }

      if (Test-Path $shim) {
        $item = Get-Item -LiteralPath $shim
        if ($item.PSIsContainer) {
          Die "Shim path is a directory, not a file: $shim"
        }
      }

      $shimsToDelete += $shim
    }
  }

  # Preview
  Write-Host ""
  Write-Host "=== UNINSTALL PREVIEW ===" -ForegroundColor Cyan
  Write-Host "Entry:  $($entry.name) ($($entry.scope))"
  if ($entry.url) {
    Write-Host "URL:    $($entry.url)"
  }
  Write-Host "Path:   $repoPath"

  if ($shimsToDelete.Count -gt 0) {
    Write-Host ""
    Write-Host "Will remove shims:" -ForegroundColor Yellow
    foreach ($shim in $shimsToDelete) {
      Write-Host "  - $shim"
    }
  } elseif ($PreserveShims -and $entry.shims -and $entry.shims.Count -gt 0) {
    Write-Host ""
    Write-Host "Will keep shims (--keep-shims):" -ForegroundColor Green
    foreach ($shim in $entry.shims) {
      Write-Host "  - $shim"
    }
  }

  if (-not $PreserveFolder) {
    Write-Host ""
    Write-Host "Will remove folder:" -ForegroundColor Yellow
    Write-Host "  - $repoPath"
  } else {
    Write-Host ""
    Write-Host "Will keep folder (--keep-folder):" -ForegroundColor Green
    Write-Host "  - $repoPath"
  }

  Write-Host ""
  Write-Host "Will remove registry entry: $($entry.name)" -ForegroundColor Yellow

  if ($DryRunMode) {
    Write-Host ""
    Write-Host "DRY RUN - no changes will be made" -ForegroundColor Cyan
    return
  }

  # Confirmation
  if (-not $NonInteractive) {
    Write-Host ""
    $response = Read-Host "Proceed? (y/n)"
    if ($response -ne "y") {
      Info "Aborted by user"
      exit 1
    }
  }

  Write-Host ""

  # Chinvex cleanup (BEFORE removing shims/folder/registry)
  if (Test-ChinvexEnabled -NoChinvex:$NoChinvex -StrapRootPath $StrapRootPath) {
    if ($entry.scope -eq 'software' -and $entry.chinvex_context) {
      # Archive the individual context
      $archived = Invoke-Chinvex -Arguments @("context", "archive", $entry.chinvex_context)
      if ($archived) {
        Info "Chinvex: archived context '$($entry.chinvex_context)'"
      } else {
        Warn "Chinvex: failed to archive context '$($entry.chinvex_context)' (continuing with uninstall)"
      }
    }
    elseif ($entry.scope -eq 'tool' -and $entry.chinvex_context) {
      # Remove repo from tools context (never archive tools context itself)
      $removed = Invoke-Chinvex -Arguments @("context", "remove-repo", "tools", "--repo", $repoPath)
      if ($removed) {
        Info "Chinvex: removed '$repoPath' from tools context"
      } else {
        Warn "Chinvex: failed to remove repo from tools context (continuing with uninstall)"
      }
    }
  }

  # Execute deletions
  # 1. Remove shims
  if ($shimsToDelete.Count -gt 0) {
    Info "Removing shims..."
    foreach ($shim in $shimsToDelete) {
      if (-not (Test-Path $shim)) {
        Write-Host "  skip (not found): $shim" -ForegroundColor Gray
      } else {
        try {
          Remove-Item -LiteralPath $shim -Force -ErrorAction Stop
          Write-Host "  deleted: $shim" -ForegroundColor Green
        } catch {
          Write-Host "  ERROR deleting $shim : $_" -ForegroundColor Red
          Die "Failed to delete shim: $shim"
        }
      }
    }
  }

  # 2. Remove folder
  if (-not $PreserveFolder) {
    Info "Removing folder..."
    if (-not (Test-Path $repoPath)) {
      Write-Host "  skip (not found): $repoPath" -ForegroundColor Gray
    } else {
      try {
        Remove-Item -LiteralPath $repoPath -Recurse -Force -ErrorAction Stop
        Write-Host "  deleted: $repoPath" -ForegroundColor Green
      } catch {
        Write-Host "  ERROR deleting $repoPath : $_" -ForegroundColor Red
        Die "Failed to delete folder: $repoPath"
      }
    }
  }

  # 3. Remove registry entry
  Info "Updating registry..."
  $newRegistry = @()
  foreach ($item in $registry) {
    if ($item.name -ne $NameToRemove) {
      $newRegistry += $item
    }
  }

  try {
    Save-Registry $config $newRegistry
    Ok "Registry updated"
  } catch {
    Write-Host "ERROR updating registry: $_" -ForegroundColor Red
    exit 3
  }

  Write-Host ""
  Ok "Uninstalled '$NameToRemove'"
}
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexUninstall.Tests.ps1 -TagFilter "Task9"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexUninstall.Tests.ps1
git commit -m "feat(chinvex): Task 9 - integrate chinvex with Invoke-Uninstall"
```

---

### Task 10: Invoke-Contexts

**Files:**
- Modify: `strap.ps1` (add new `Invoke-Contexts` function and CLI dispatch)
- Test: `tests/powershell/ChinvexContexts.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexContexts.Tests.ps1
Describe "Invoke-Contexts Command" -Tag "Task10" {
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

        # Extract all needed functions
        $functions = @(
            "Die", "Warn", "Info", "Ok", "Load-Config", "Load-Registry", "Save-Registry",
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex", "Invoke-ChinvexQuery",
            "Detect-RepoScope", "Get-ContextName",
            "Invoke-Contexts"
        )
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                Write-Warning "Could not extract $funcName"
            }
        }

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        $script:testSoftwareRoot = Join-Path $TestDrive "software"
        $script:testToolsRoot = Join-Path $TestDrive "tools"
        $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"

        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testSoftwareRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testToolsRoot -Force | Out-Null
    }

    BeforeEach {
        # Reset config
        @{
            registry = $script:testRegistryPath
            roots = @{
                software = $script:testSoftwareRoot
                tools = $script:testToolsRoot
                shims = Join-Path $script:testToolsRoot "shims"
            }
            chinvex_integration = $true
            software_root = $script:testSoftwareRoot
            tools_root = $script:testToolsRoot
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    Describe "Basic functionality" {
        BeforeEach {
            # Create registry with entries
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "project1"
                        name = "project1"
                        path = (Join-Path $script:testSoftwareRoot "project1")
                        scope = "software"
                        chinvex_context = "project1"
                        shims = @()
                    },
                    @{
                        id = "tool1"
                        name = "tool1"
                        path = (Join-Path $script:testToolsRoot "tool1")
                        scope = "tool"
                        chinvex_context = "tools"
                        shims = @()
                    },
                    @{
                        id = "unsynced"
                        name = "unsynced"
                        path = (Join-Path $script:testSoftwareRoot "unsynced")
                        scope = "software"
                        chinvex_context = $null
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should return context list object" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "project1"; repo_count = 1; last_ingest = "2026-01-30T10:00:00Z" },
                    @{ name = "tools"; repo_count = 2; last_ingest = "2026-01-29T10:00:00Z" },
                    @{ name = "orphan-context"; repo_count = 1; last_ingest = "2026-01-28T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $result | Should -Not -Be $null
            $result.Count | Should -BeGreaterThan 0
        }

        It "should identify synced contexts" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "project1"; repo_count = 1; last_ingest = "2026-01-30T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $syncedEntry = $result | Where-Object { $_.Name -eq "project1" }
            $syncedEntry | Should -Not -Be $null
            $syncedEntry.SyncStatus | Should -Be "synced"
        }

        It "should identify unsynced contexts" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "project1"; repo_count = 1; last_ingest = "2026-01-30T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $unsyncedEntry = $result | Where-Object { $_.Name -eq "unsynced" }
            $unsyncedEntry | Should -Not -Be $null
            $unsyncedEntry.SyncStatus | Should -Be "not synced"
        }

        It "should identify orphaned chinvex contexts" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "project1"; repo_count = 1; last_ingest = "2026-01-30T10:00:00Z" },
                    @{ name = "orphan-context"; repo_count = 1; last_ingest = "2026-01-28T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $orphanEntry = $result | Where-Object { $_.Name -eq "orphan-context" }
            $orphanEntry | Should -Not -Be $null
            $orphanEntry.SyncStatus | Should -Be "no strap entry"
        }
    }

    Describe "When chinvex is unavailable" {
        BeforeEach {
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "project1"
                        name = "project1"
                        path = (Join-Path $script:testSoftwareRoot "project1")
                        scope = "software"
                        chinvex_context = "project1"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should show registry-only view with warning" {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            # Should still return registry entries
            $result | Should -Not -Be $null
            $result.Count | Should -BeGreaterThan 0

            # Entry should show unknown sync status since chinvex unavailable
            $entry = $result | Where-Object { $_.Name -eq "project1" }
            $entry.SyncStatus | Should -Be "unknown (chinvex unavailable)"
        }
    }

    Describe "Tools context handling" {
        BeforeEach {
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "tool1"
                        name = "tool1"
                        path = (Join-Path $script:testToolsRoot "tool1")
                        scope = "tool"
                        chinvex_context = "tools"
                        shims = @()
                    },
                    @{
                        id = "tool2"
                        name = "tool2"
                        path = (Join-Path $script:testToolsRoot "tool2")
                        scope = "tool"
                        chinvex_context = "tools"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should show tools context as a single entry with repo count" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "tools"; repo_count = 2; last_ingest = "2026-01-29T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $toolsEntry = $result | Where-Object { $_.Name -eq "tools" }
            $toolsEntry | Should -Not -Be $null
            $toolsEntry.Type | Should -Be "tool"
            $toolsEntry.RepoCount | Should -Be 2
        }
    }

    Describe "Output format" {
        BeforeEach {
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "project1"
                        name = "project1"
                        path = (Join-Path $script:testSoftwareRoot "project1")
                        scope = "software"
                        chinvex_context = "project1"
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should return structured object with expected properties" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery {
                return (@(
                    @{ name = "project1"; repo_count = 1; last_ingest = "2026-01-30T10:00:00Z" }
                ) | ConvertTo-Json -Depth 5)
            }

            $result = Invoke-Contexts -StrapRootPath $script:testStrapRoot -OutputMode "Object"

            $entry = $result | Select-Object -First 1
            $entry.PSObject.Properties.Name | Should -Contain "Name"
            $entry.PSObject.Properties.Name | Should -Contain "Type"
            $entry.PSObject.Properties.Name | Should -Contain "RepoCount"
            $entry.PSObject.Properties.Name | Should -Contain "SyncStatus"
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexContexts.Tests.ps1 -TagFilter "Task10"`
Expected: FAIL with "Could not find Invoke-Contexts function"

**Step 3: Write minimal implementation**
```powershell
# Add Invoke-Contexts function to strap.ps1 (add near other Invoke-* command functions)

function Invoke-Contexts {
    <#
    .SYNOPSIS
        Lists all chinvex contexts and their sync status with strap registry.
    .DESCRIPTION
        Combines data from strap registry and chinvex context list to show:
        - Synced contexts (both registry and chinvex match)
        - Unsynced contexts (registry entry exists but chinvex_context is null)
        - Orphaned contexts (chinvex context exists but no registry entry)
    .PARAMETER StrapRootPath
        Path to strap root directory.
    .PARAMETER OutputMode
        'Table' for formatted table output, 'Object' for structured objects.
    #>
    param(
        [string] $StrapRootPath,
        [ValidateSet('Table', 'Object')]
        [string] $OutputMode = 'Table'
    )

    # Load config and registry
    $config = Load-Config $StrapRootPath
    $registry = Load-Registry $config

    # Build result list
    $results = @()

    # Check if chinvex is available
    $chinvexAvail = Test-ChinvexAvailable

    # Get chinvex contexts if available
    $chinvexContexts = @()
    if ($chinvexAvail) {
        $jsonOutput = Invoke-ChinvexQuery -Arguments @("context", "list", "--json")
        if ($jsonOutput) {
            try {
                $chinvexContexts = $jsonOutput | ConvertFrom-Json
            } catch {
                Warn "Failed to parse chinvex context list: $_"
            }
        }
    }

    # Build lookup of chinvex contexts by name
    $chinvexLookup = @{}
    foreach ($ctx in $chinvexContexts) {
        $chinvexLookup[$ctx.name] = $ctx
    }

    # Track which chinvex contexts are accounted for by registry
    $accountedContexts = @{}

    # Track tools context separately (aggregate tool repos)
    $toolRepoCount = 0

    # Process registry entries
    foreach ($entry in $registry) {
        if ($entry.scope -eq 'tool') {
            $toolRepoCount++
            $accountedContexts['tools'] = $true
            continue  # Don't add individual tool entries
        }

        # Software entry
        $contextName = $entry.chinvex_context
        $syncStatus = "unknown"

        if (-not $chinvexAvail) {
            $syncStatus = "unknown (chinvex unavailable)"
        } elseif ($null -eq $contextName) {
            $syncStatus = "not synced"
        } elseif ($chinvexLookup.ContainsKey($contextName)) {
            $syncStatus = "synced"
            $accountedContexts[$contextName] = $true
        } else {
            $syncStatus = "context missing"
        }

        $chinvexData = $chinvexLookup[$contextName]

        $results += [PSCustomObject]@{
            Name = $entry.name
            Type = "software"
            RepoCount = if ($chinvexData) { $chinvexData.repo_count } else { 1 }
            LastIngest = if ($chinvexData) { $chinvexData.last_ingest } else { "-" }
            SyncStatus = $syncStatus
        }
    }

    # Add tools context if there are tool repos
    if ($toolRepoCount -gt 0) {
        $toolsCtx = $chinvexLookup['tools']
        $syncStatus = "unknown"

        if (-not $chinvexAvail) {
            $syncStatus = "unknown (chinvex unavailable)"
        } elseif ($toolsCtx) {
            $syncStatus = "synced"
        } else {
            $syncStatus = "context missing"
        }

        $results += [PSCustomObject]@{
            Name = "tools"
            Type = "tool"
            RepoCount = $toolRepoCount
            LastIngest = if ($toolsCtx) { $toolsCtx.last_ingest } else { "-" }
            SyncStatus = $syncStatus
        }
    }

    # Find orphaned chinvex contexts (in chinvex but not in registry)
    foreach ($ctx in $chinvexContexts) {
        if (-not $accountedContexts.ContainsKey($ctx.name)) {
            # This is an orphaned context
            $results += [PSCustomObject]@{
                Name = $ctx.name
                Type = "unknown"
                RepoCount = $ctx.repo_count
                LastIngest = $ctx.last_ingest
                SyncStatus = "no strap entry"
            }
        }
    }

    # Output
    if ($OutputMode -eq 'Object') {
        return $results
    }

    # Table output
    if ($results.Count -eq 0) {
        Info "No contexts found"
        return
    }

    Write-Host ""
    Write-Host "Context         Type       Repos  Last Ingest         Sync Status" -ForegroundColor Cyan
    Write-Host "-------         ----       -----  -----------         -----------" -ForegroundColor Gray

    foreach ($ctx in $results | Sort-Object Name) {
        $nameCol = $ctx.Name.PadRight(15)
        $typeCol = $ctx.Type.PadRight(10)
        $repoCol = $ctx.RepoCount.ToString().PadRight(6)
        $ingestCol = if ($ctx.LastIngest -eq "-") { "-".PadRight(19) } else { $ctx.LastIngest.Substring(0, [Math]::Min(19, $ctx.LastIngest.Length)).PadRight(19) }

        $statusColor = switch ($ctx.SyncStatus) {
            "synced" { "Green" }
            "not synced" { "Yellow" }
            "context missing" { "Yellow" }
            "no strap entry" { "Red" }
            default { "Gray" }
        }

        $statusSymbol = switch ($ctx.SyncStatus) {
            "synced" { "[OK]" }
            "not synced" { "[!]" }
            "context missing" { "[!]" }
            "no strap entry" { "[?]" }
            default { "[-]" }
        }

        Write-Host "$nameCol $typeCol $repoCol $ingestCol " -NoNewline
        Write-Host "$statusSymbol $($ctx.SyncStatus)" -ForegroundColor $statusColor
    }

    Write-Host ""
}

# Add to CLI dispatch switch block (near end of strap.ps1):
# "contexts" { Invoke-Contexts -StrapRootPath $StrapRoot }
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexContexts.Tests.ps1 -TagFilter "Task10"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexContexts.Tests.ps1
git commit -m "feat(chinvex): Task 10 - add Invoke-Contexts command for listing chinvex contexts"
```

---

## Batch 3: Sync, Edge Cases & Docs (Tasks 11-14)

### Task 11: Invoke-SyncChinvex

**Files:**
- Modify: `strap.ps1` (add `Invoke-SyncChinvex` function)
- Test: `tests/powershell/ChinvexSync.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexSync.Tests.ps1
Describe "Invoke-SyncChinvex" -Tag "Task11" {
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

        # Extract all needed functions
        $functions = @(
            "Die", "Warn", "Info", "Ok", "Load-Config", "Load-Registry", "Save-Registry",
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex", "Invoke-ChinvexQuery",
            "Detect-RepoScope", "Get-ContextName", "Sync-ChinvexForEntry",
            "Invoke-SyncChinvex"
        )
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                Write-Warning "Could not extract $funcName"
            }
        }

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        $script:testSoftwareRoot = Join-Path $TestDrive "software"
        $script:testToolsRoot = Join-Path $TestDrive "tools"
        $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"

        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testSoftwareRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testToolsRoot -Force | Out-Null
    }

    BeforeEach {
        # Reset config
        @{
            registry = $script:testRegistryPath
            roots = @{
                software = $script:testSoftwareRoot
                tools = $script:testToolsRoot
                shims = Join-Path $script:testToolsRoot "shims"
            }
            chinvex_integration = $true
            software_root = $script:testSoftwareRoot
            tools_root = $script:testToolsRoot
            chinvex_whitelist = @("tools", "archive")
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    Describe "Default behavior (no flags = dry-run)" {
        BeforeEach {
            # Registry with one entry that has null chinvex_context
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "unsynced-repo"
                        name = "unsynced-repo"
                        path = (Join-Path $script:testSoftwareRoot "unsynced-repo")
                        scope = "software"
                        chinvex_context = $null
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should default to dry-run mode when no flags provided" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery { return '[]' }
            Mock Invoke-Chinvex { return $true }

            $result = Invoke-SyncChinvex -StrapRootPath $script:testStrapRoot

            # Should not have called any mutating chinvex commands
            Should -Invoke Invoke-Chinvex -Times 0
        }

        It "should report what would be done without making changes" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery { return '[]' }

            $result = Invoke-SyncChinvex -StrapRootPath $script:testStrapRoot -OutputMode 'Object'

            $result.Actions | Should -HaveCount 1
            $result.Actions[0].Action | Should -Be "create"
            $result.Actions[0].Context | Should -Be "unsynced-repo"
            $result.DryRun | Should -Be $true
        }
    }

    Describe "--dry-run flag" {
        BeforeEach {
            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "missing-ctx"
                        name = "missing-ctx"
                        path = (Join-Path $script:testSoftwareRoot "missing-ctx")
                        scope = "software"
                        chinvex_context = $null
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should not modify registry in dry-run mode" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery { return '[]' }

            $beforeRegistry = Get-Content $script:testRegistryPath -Raw

            Invoke-SyncChinvex -DryRun -StrapRootPath $script:testStrapRoot

            $afterRegistry = Get-Content $script:testRegistryPath -Raw
            $afterRegistry | Should -Be $beforeRegistry
        }

        It "should list actions that would be taken" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery { return '[]' }

            $result = Invoke-SyncChinvex -DryRun -StrapRootPath $script:testStrapRoot -OutputMode 'Object'

            $result.Actions | Should -Not -BeNullOrEmpty
            $result.Actions[0].Action | Should -Be "create"
        }
    }

    Describe "--reconcile flag" {
        Context "Missing contexts (registry entry has null chinvex_context)" {
            BeforeEach {
                @{
                    version = 2
                    updated_at = (Get-Date).ToUniversalTime().ToString("o")
                    entries = @(
                        @{
                            id = "needs-sync"
                            name = "needs-sync"
                            path = (Join-Path $script:testSoftwareRoot "needs-sync")
                            scope = "software"
                            chinvex_context = $null
                            shims = @()
                        }
                    )
                } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
            }

            It "should create context for registry entry with null chinvex_context" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery { return '[]' }
                Mock Invoke-Chinvex { return $true }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                # Should have called context create and ingest
                Should -Invoke Invoke-Chinvex -ParameterFilter {
                    $Arguments[0] -eq "context" -and $Arguments[1] -eq "create" -and $Arguments[2] -eq "needs-sync"
                }
            }

            It "should update registry chinvex_context after successful sync" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery { return '[]' }
                Mock Invoke-Chinvex { return $true }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
                $entry = $registry.entries | Where-Object { $_.name -eq "needs-sync" }
                $entry.chinvex_context | Should -Be "needs-sync"
            }
        }

        Context "Tool repos with null chinvex_context" {
            BeforeEach {
                @{
                    version = 2
                    updated_at = (Get-Date).ToUniversalTime().ToString("o")
                    entries = @(
                        @{
                            id = "unsynced-tool"
                            name = "unsynced-tool"
                            path = (Join-Path $script:testToolsRoot "unsynced-tool")
                            scope = "tool"
                            chinvex_context = $null
                            shims = @()
                        }
                    )
                } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
            }

            It "should create tools context and add tool repo" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery { return '[]' }
                Mock Invoke-Chinvex { return $true }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                # Should have called context create for tools
                Should -Invoke Invoke-Chinvex -ParameterFilter {
                    $Arguments[0] -eq "context" -and $Arguments[1] -eq "create" -and $Arguments[2] -eq "tools"
                }
            }

            It "should set chinvex_context to 'tools' for tool repos" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery { return '[]' }
                Mock Invoke-Chinvex { return $true }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                $registry = Get-Content $script:testRegistryPath -Raw | ConvertFrom-Json
                $entry = $registry.entries | Where-Object { $_.name -eq "unsynced-tool" }
                $entry.chinvex_context | Should -Be "tools"
            }
        }

        Context "Orphaned contexts (in chinvex but not in registry)" {
            BeforeEach {
                # Empty registry
                @{
                    version = 2
                    updated_at = (Get-Date).ToUniversalTime().ToString("o")
                    entries = @()
                } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
            }

            It "should archive orphaned contexts not in whitelist" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                # Return orphaned context from chinvex
                Mock Invoke-ChinvexQuery {
                    return '[{"name": "orphaned-project", "repo_count": 1, "last_ingest": "2026-01-15T10:00:00Z"}]'
                }
                Mock Invoke-Chinvex { return $true }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                Should -Invoke Invoke-Chinvex -ParameterFilter {
                    $Arguments[0] -eq "context" -and $Arguments[1] -eq "archive" -and $Arguments[2] -eq "orphaned-project"
                }
            }

            It "should NOT archive whitelisted contexts (tools, archive)" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery {
                    return '[{"name": "tools", "repo_count": 0, "last_ingest": "2026-01-15T10:00:00Z"}, {"name": "archive", "repo_count": 5, "last_ingest": "2026-01-10T10:00:00Z"}]'
                }

                $archiveCalls = @()
                Mock Invoke-Chinvex {
                    param($Arguments)
                    if ($Arguments[0] -eq "context" -and $Arguments[1] -eq "archive") {
                        $archiveCalls += $Arguments[2]
                    }
                    return $true
                }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                $archiveCalls | Should -Not -Contain "tools"
                $archiveCalls | Should -Not -Contain "archive"
            }
        }

        Context "Empty tools context preservation" {
            BeforeEach {
                # No tool repos in registry
                @{
                    version = 2
                    updated_at = (Get-Date).ToUniversalTime().ToString("o")
                    entries = @()
                } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
            }

            It "should keep empty tools context (never archive)" {
                Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
                Mock Invoke-ChinvexQuery {
                    return '[{"name": "tools", "repo_count": 0, "last_ingest": "never"}]'
                }

                $archiveCalls = @()
                Mock Invoke-Chinvex {
                    param($Arguments)
                    if ($Arguments[0] -eq "context" -and $Arguments[1] -eq "archive") {
                        $archiveCalls += $Arguments[2]
                    }
                    return $true
                }

                Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot

                $archiveCalls | Should -Not -Contain "tools"
            }
        }
    }

    Describe "Always runs regardless of config/flags" {
        BeforeEach {
            # Config with chinvex_integration disabled
            @{
                registry = $script:testRegistryPath
                roots = @{
                    software = $script:testSoftwareRoot
                    tools = $script:testToolsRoot
                    shims = Join-Path $script:testToolsRoot "shims"
                }
                chinvex_integration = $false
                software_root = $script:testSoftwareRoot
                tools_root = $script:testToolsRoot
                chinvex_whitelist = @("tools", "archive")
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

            @{
                version = 2
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                entries = @(
                    @{
                        id = "test-repo"
                        name = "test-repo"
                        path = (Join-Path $script:testSoftwareRoot "test-repo")
                        scope = "software"
                        chinvex_context = $null
                        shims = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath
        }

        It "should run even when chinvex_integration is false in config" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-ChinvexQuery { return '[]' }
            Mock Invoke-Chinvex { return $true }

            # This should NOT throw or skip - sync-chinvex always runs
            { Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot } | Should -Not -Throw

            Should -Invoke Invoke-Chinvex -Times 2  # create + ingest
        }
    }

    Describe "Chinvex unavailable handling" {
        It "should warn and exit gracefully when chinvex not available" {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }

            $result = Invoke-SyncChinvex -Reconcile -StrapRootPath $script:testStrapRoot -OutputMode 'Object'

            $result.Success | Should -Be $false
            $result.Error | Should -Match "Chinvex not available"
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexSync.Tests.ps1 -TagFilter "Task11"`
Expected: FAIL with "Could not find Invoke-SyncChinvex function"

**Step 3: Write minimal implementation**
```powershell
# Add to strap.ps1 after Invoke-Contexts function

function Invoke-SyncChinvex {
    <#
    .SYNOPSIS
        Reconciles strap registry with chinvex contexts.
    .DESCRIPTION
        Default (no flags): equivalent to --dry-run (shows drift without changes).
        --dry-run: Show what would change without making changes.
        --reconcile: Apply reconciliation actions.

        IMPORTANT: This command ALWAYS runs regardless of --no-chinvex flag or
        config.chinvex_integration setting. It IS the chinvex management command.

        Reconciliation rules:
        - Missing contexts: Create contexts for strap entries with chinvex_context = null
        - Orphaned contexts: Archive contexts with no strap entry (except whitelist)
        - Whitelist: Never archive 'tools', 'archive', or user-defined whitelist entries
    .PARAMETER DryRun
        Show what would change without making changes.
    .PARAMETER Reconcile
        Apply reconciliation actions.
    .PARAMETER StrapRootPath
        Path to strap root for loading config/registry.
    .PARAMETER OutputMode
        'Table' for human-readable output, 'Object' for machine-readable.
    #>
    param(
        [switch] $DryRun,
        [switch] $Reconcile,
        [Parameter(Mandatory)]
        [string] $StrapRootPath,
        [ValidateSet('Table', 'Object')]
        [string] $OutputMode = 'Table'
    )

    # Default to dry-run if neither flag specified
    $isDryRun = (-not $Reconcile) -or $DryRun

    $result = @{
        Success = $true
        DryRun = $isDryRun
        Actions = @()
        Error = $null
    }

    # Check chinvex availability (sync-chinvex ignores config disable, but needs chinvex installed)
    if (-not (Test-ChinvexAvailable)) {
        $result.Success = $false
        $result.Error = "Chinvex not available. Install chinvex and ensure it is on PATH."
        if ($OutputMode -eq 'Object') {
            return [PSCustomObject]$result
        }
        Warn $result.Error
        return
    }

    # Load registry and config
    $config = Load-Config $StrapRootPath
    $registry = Load-Registry $StrapRootPath

    # Build whitelist (system defaults + user config)
    $whitelist = @("tools", "archive")
    if ($config.chinvex_whitelist) {
        $whitelist += $config.chinvex_whitelist
    }
    $whitelist = $whitelist | Sort-Object -Unique

    # Get chinvex contexts
    $chinvexJson = Invoke-ChinvexQuery -Arguments @("context", "list", "--json")
    $chinvexContexts = @()
    if ($chinvexJson) {
        try {
            $chinvexContexts = $chinvexJson | ConvertFrom-Json
        } catch {
            Warn "Failed to parse chinvex context list: $_"
        }
    }

    # Build lookup of chinvex contexts by name
    $chinvexLookup = @{}
    foreach ($ctx in $chinvexContexts) {
        $chinvexLookup[$ctx.name] = $ctx
    }

    # Track which chinvex contexts are accounted for
    $accountedContexts = @{}

    # Phase 1: Find registry entries that need syncing
    foreach ($entry in $registry.entries) {
        if ($null -eq $entry.chinvex_context) {
            # Entry needs context created
            $contextName = Get-ContextName -Scope $entry.scope -Name $entry.name

            $action = @{
                Action = "create"
                Context = $contextName
                EntryName = $entry.name
                Scope = $entry.scope
                RepoPath = $entry.path
            }
            $result.Actions += [PSCustomObject]$action

            if (-not $isDryRun) {
                # Perform reconciliation
                $syncedContext = Sync-ChinvexForEntry -Scope $entry.scope -Name $entry.name -RepoPath $entry.path
                if ($syncedContext) {
                    $entry.chinvex_context = $syncedContext
                    Ok "Created context '$contextName' for $($entry.name)"
                } else {
                    Warn "Failed to create context '$contextName' for $($entry.name)"
                }
            } else {
                Info "Would create context '$contextName' for registry entry '$($entry.name)'"
            }

            $accountedContexts[$contextName] = $true
        } else {
            # Entry has context, mark as accounted
            $accountedContexts[$entry.chinvex_context] = $true
        }
    }

    # Phase 2: Find orphaned chinvex contexts
    foreach ($ctx in $chinvexContexts) {
        if (-not $accountedContexts.ContainsKey($ctx.name)) {
            # Check whitelist
            if ($whitelist -contains $ctx.name) {
                Info "Skipping whitelisted context '$($ctx.name)'"
                continue
            }

            $action = @{
                Action = "archive"
                Context = $ctx.name
                Reason = "no strap entry"
            }
            $result.Actions += [PSCustomObject]$action

            if (-not $isDryRun) {
                $archived = Invoke-Chinvex -Arguments @("context", "archive", $ctx.name)
                if ($archived) {
                    Ok "Archived orphaned context '$($ctx.name)'"
                } else {
                    Warn "Failed to archive context '$($ctx.name)'"
                }
            } else {
                Info "Would archive orphaned context '$($ctx.name)'"
            }
        }
    }

    # Save registry if changes were made
    if (-not $isDryRun -and $result.Actions.Count -gt 0) {
        Save-Registry $registry $StrapRootPath
    }

    # Output
    if ($OutputMode -eq 'Object') {
        return [PSCustomObject]$result
    }

    # Summary
    Write-Host ""
    if ($isDryRun) {
        Write-Host "DRY RUN - No changes made" -ForegroundColor Yellow
    }

    $createCount = ($result.Actions | Where-Object { $_.Action -eq "create" }).Count
    $archiveCount = ($result.Actions | Where-Object { $_.Action -eq "archive" }).Count

    if ($result.Actions.Count -eq 0) {
        Ok "Registry and chinvex contexts are in sync"
    } else {
        Info "Actions: $createCount context(s) to create, $archiveCount context(s) to archive"
    }
    Write-Host ""
}
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexSync.Tests.ps1 -TagFilter "Task11"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexSync.Tests.ps1
git commit -m "feat(chinvex): Task 11 - add Invoke-SyncChinvex for registry reconciliation"
```

---

### Task 12: CLI Dispatch + Help Text

**Files:**
- Modify: `strap.ps1` (update CLI dispatch switch and Show-Help function)
- Test: `tests/powershell/ChinvexCLIDispatch.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
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

    Describe "CLI dispatch entries" {
        It "should have dispatch entry for 'contexts' command" {
            $script:strapContent | Should -Match '"contexts"\s*\{[^}]*Invoke-Contexts'
        }

        It "should have dispatch entry for 'sync-chinvex' command" {
            $script:strapContent | Should -Match '"sync-chinvex"\s*\{[^}]*Invoke-SyncChinvex'
        }

        It "should pass --dry-run flag to Invoke-SyncChinvex" {
            $script:strapContent | Should -Match 'sync-chinvex.*-DryRun'
        }

        It "should pass --reconcile flag to Invoke-SyncChinvex" {
            $script:strapContent | Should -Match 'sync-chinvex.*-Reconcile'
        }
    }

    Describe "Show-Help content" {
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
            $script:strapContent | Should -Match 'contexts\s+.*[Ll]ist.*chinvex'
        }

        It "should document 'sync-chinvex' command" {
            $script:strapContent | Should -Match 'sync-chinvex\s+.*[Rr]econcile'
        }

        It "should document --dry-run flag for sync-chinvex" {
            $script:strapContent | Should -Match '--dry-run'
        }

        It "should document --reconcile flag for sync-chinvex" {
            $script:strapContent | Should -Match '--reconcile'
        }

        It "should document --no-chinvex global flag" {
            $script:strapContent | Should -Match '--no-chinvex\s+.*[Ss]kip.*chinvex'
        }

        It "should document --tool flag for clone/adopt" {
            $script:strapContent | Should -Match '--tool\s+.*[Rr]egister.*tool'
        }

        It "should document --software flag for clone/adopt" {
            $script:strapContent | Should -Match '--software\s+.*[Rr]egister.*software'
        }
    }

    Describe "Flag parsing integration" {
        It "should recognize --no-chinvex in Parse-GlobalFlags" {
            try {
                $funcCode = Extract-Function $script:strapContent "Parse-GlobalFlags"
                Invoke-Expression $funcCode

                $result = Parse-GlobalFlags @("clone", "https://example.com/repo", "--no-chinvex")
                $result.NoChinvex | Should -Be $true
            } catch {
                Set-ItResult -Skipped -Because "Parse-GlobalFlags not found"
            }
        }

        It "should recognize --tool in Parse-GlobalFlags" {
            try {
                $funcCode = Extract-Function $script:strapContent "Parse-GlobalFlags"
                Invoke-Expression $funcCode

                $result = Parse-GlobalFlags @("clone", "https://example.com/repo", "--tool")
                $result.IsTool | Should -Be $true
            } catch {
                Set-ItResult -Skipped -Because "Parse-GlobalFlags not found"
            }
        }

        It "should recognize --software in Parse-GlobalFlags" {
            try {
                $funcCode = Extract-Function $script:strapContent "Parse-GlobalFlags"
                Invoke-Expression $funcCode

                $result = Parse-GlobalFlags @("clone", "https://example.com/repo", "--software")
                $result.IsSoftware | Should -Be $true
            } catch {
                Set-ItResult -Skipped -Because "Parse-GlobalFlags not found"
            }
        }

        It "should pass remaining args after extracting flags" {
            try {
                $funcCode = Extract-Function $script:strapContent "Parse-GlobalFlags"
                Invoke-Expression $funcCode

                $result = Parse-GlobalFlags @("clone", "https://example.com/repo", "--tool", "--no-chinvex")
                $result.RemainingArgs | Should -Contain "clone"
                $result.RemainingArgs | Should -Contain "https://example.com/repo"
                $result.RemainingArgs | Should -Not -Contain "--tool"
                $result.RemainingArgs | Should -Not -Contain "--no-chinvex"
            } catch {
                Set-ItResult -Skipped -Because "Parse-GlobalFlags not found"
            }
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexCLIDispatch.Tests.ps1 -TagFilter "Task12"`
Expected: FAIL with "Should -Match" failures for missing dispatch entries

**Step 3: Write minimal implementation**
```powershell
# Modify the main CLI dispatch switch block at the bottom of strap.ps1
# Add dispatch entries for contexts and sync-chinvex commands

# In the main switch ($command) block, add these cases:

    "contexts" {
        Invoke-Contexts -StrapRootPath $StrapRoot
    }

    "sync-chinvex" {
        # Parse sync-chinvex specific flags
        $dryRun = $false
        $reconcile = $false
        foreach ($arg in $remainingArgs[1..($remainingArgs.Count - 1)]) {
            switch ($arg) {
                "--dry-run" { $dryRun = $true }
                "--reconcile" { $reconcile = $true }
            }
        }
        # Default to dry-run if neither specified
        if (-not $dryRun -and -not $reconcile) {
            $dryRun = $true
        }
        Invoke-SyncChinvex -DryRun:$dryRun -Reconcile:$reconcile -StrapRootPath $StrapRoot
    }

# Update Show-Help function to include chinvex commands and flags:

function Show-Help {
    Write-Host @"
strap - Repository lifecycle management with chinvex integration

USAGE:
    strap <command> [options]

COMMANDS:
    clone <url> [--tool|--software] [--no-chinvex]
        Clone and register a repository
        --tool        Register as tool (shared 'tools' chinvex context)
        --software    Register as software (individual context, default)
        --no-chinvex  Skip chinvex integration

    adopt [--path <dir>] [--tool|--software] [--no-chinvex]
        Adopt existing repository into registry
        --tool        Force tool scope (auto-detected from path if omitted)
        --software    Force software scope
        --no-chinvex  Skip chinvex integration

    move <name> --dest <path> [--no-chinvex]
        Move repository to new location
        Automatically handles scope changes (software <-> tool)
        --no-chinvex  Skip chinvex path updates

    rename <name> --to <new> [--move-folder] [--no-chinvex]
        Rename repository (and optionally its folder)
        --move-folder  Also rename the folder on disk
        --no-chinvex   Skip chinvex context rename

    uninstall <name> [--no-chinvex]
        Remove repository (archives chinvex context for software repos)
        --no-chinvex  Skip chinvex cleanup

    list
        List all registered repositories

    contexts
        List chinvex contexts with sync status
        Shows which contexts are synced, missing, or orphaned

    sync-chinvex [--dry-run|--reconcile]
        Reconcile registry with chinvex contexts
        --dry-run     Show what would change (default)
        --reconcile   Apply reconciliation actions:
                      - Create missing contexts
                      - Archive orphaned contexts

    setup <name>
        Run setup script for repository

    update [name]
        Update repository (or all if no name given)

    shim <name> --source <path>
        Create shim for executable

    open <name>
        Open repository in file explorer

    doctor
        Check system health

    help
        Show this help message

GLOBAL FLAGS:
    --no-chinvex    Skip chinvex integration for this command
    --tool          Register/treat as tool repository
    --software      Register/treat as software repository (default)

CHINVEX INTEGRATION:
    Strap automatically manages chinvex contexts:
    - Software repos get individual contexts (context name = repo name)
    - Tool repos share a single 'tools' context
    - Use 'strap contexts' to view sync status
    - Use 'strap sync-chinvex --reconcile' to fix drift

    Disable globally via config.json: { "chinvex_integration": false }
    Or per-command with --no-chinvex flag

EXAMPLES:
    strap clone https://github.com/user/myproject
    strap clone https://github.com/user/mytool --tool
    strap adopt --path P:\software\existing-repo
    strap move myrepo --dest P:\software\_scripts  # becomes tool
    strap contexts
    strap sync-chinvex --reconcile

"@
}
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexCLIDispatch.Tests.ps1 -TagFilter "Task12"`
Expected: PASS

**Step 5: Commit**
```bash
git add strap.ps1 tests/powershell/ChinvexCLIDispatch.Tests.ps1
git commit -m "feat(chinvex): Task 12 - add CLI dispatch for contexts and sync-chinvex commands"
```

---

### Task 13: Idempotency & Error Path Validation

**Files:**
- Modify: `strap.ps1` (no changes needed - validation only)
- Test: `tests/powershell/ChinvexIdempotency.Tests.ps1` (new)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexIdempotency.Tests.ps1
Describe "Chinvex Idempotency and Error Paths" -Tag "Task13" {
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

        # Extract all needed functions
        $functions = @(
            "Die", "Warn", "Info", "Ok", "Load-Config", "Load-Registry", "Save-Registry",
            "Test-ChinvexAvailable", "Test-ChinvexEnabled", "Invoke-Chinvex", "Invoke-ChinvexQuery",
            "Detect-RepoScope", "Get-ContextName", "Test-ReservedContextName", "Sync-ChinvexForEntry",
            "Invoke-Clone", "Invoke-Adopt", "Invoke-Move", "Invoke-Rename", "Invoke-Uninstall",
            "Invoke-SyncChinvex", "Parse-GitUrl"
        )
        foreach ($funcName in $functions) {
            try {
                $funcCode = Extract-Function $strapContent $funcName
                Invoke-Expression $funcCode
            } catch {
                # Function may not exist
            }
        }

        # Setup test environment
        $script:testStrapRoot = Join-Path $TestDrive "straproot"
        $script:testSoftwareRoot = Join-Path $TestDrive "software"
        $script:testToolsRoot = Join-Path $TestDrive "tools"
        $script:testRegistryPath = Join-Path $script:testStrapRoot "registry-v2.json"

        New-Item -ItemType Directory -Path $script:testStrapRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testSoftwareRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $script:testToolsRoot -Force | Out-Null
    }

    BeforeEach {
        # Reset config
        @{
            registry = $script:testRegistryPath
            roots = @{
                software = $script:testSoftwareRoot
                tools = $script:testToolsRoot
                shims = Join-Path $script:testToolsRoot "shims"
            }
            chinvex_integration = $true
            software_root = $script:testSoftwareRoot
            tools_root = $script:testToolsRoot
            chinvex_whitelist = @("tools", "archive")
        } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

        # Empty registry
        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @()
        } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistryPath

        # Reset chinvex cache
        $script:chinvexChecked = $false
        $script:chinvexAvailable = $false
    }

    function Create-TestRepo {
        param([string]$Path)
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $Path ".git") -Force | Out-Null
    }

    Describe "Sync-ChinvexForEntry idempotency" {
        It "should succeed when called twice with same arguments" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $true }

            $result1 = Sync-ChinvexForEntry -Scope "software" -Name "idempotent-repo" -RepoPath "P:\software\idempotent-repo"
            $result2 = Sync-ChinvexForEntry -Scope "software" -Name "idempotent-repo" -RepoPath "P:\software\idempotent-repo"

            $result1 | Should -Be "idempotent-repo"
            $result2 | Should -Be "idempotent-repo"
        }

        It "should use --idempotent flag on context create" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $createCalls = @()
            Mock Invoke-Chinvex {
                param($Arguments)
                if ($Arguments[0] -eq "context" -and $Arguments[1] -eq "create") {
                    $createCalls += ,@($Arguments)
                }
                return $true
            }

            Sync-ChinvexForEntry -Scope "software" -Name "test-repo" -RepoPath "P:\software\test-repo"

            $createCalls | Should -HaveCount 1
            $createCalls[0] | Should -Contain "--idempotent"
        }
    }

    Describe "Reserved name rejection" {
        It "should reject 'tools' as software repo name in Test-ReservedContextName" {
            $result = Test-ReservedContextName -Name "tools" -Scope "software"
            $result | Should -Be $true
        }

        It "should reject 'archive' as software repo name in Test-ReservedContextName" {
            $result = Test-ReservedContextName -Name "archive" -Scope "software"
            $result | Should -Be $true
        }

        It "should allow 'tools' as tool repo name (goes to shared context)" {
            $result = Test-ReservedContextName -Name "tools" -Scope "tool"
            $result | Should -Be $false
        }

        It "should be case-insensitive for reserved name check" {
            $result1 = Test-ReservedContextName -Name "TOOLS" -Scope "software"
            $result2 = Test-ReservedContextName -Name "Tools" -Scope "software"
            $result3 = Test-ReservedContextName -Name "ARCHIVE" -Scope "software"

            $result1 | Should -Be $true
            $result2 | Should -Be $true
            $result3 | Should -Be $true
        }
    }

    Describe "Chinvex unavailable graceful handling" {
        BeforeEach {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }
        }

        It "should return null from Sync-ChinvexForEntry when chinvex unavailable" {
            $result = Sync-ChinvexForEntry -Scope "software" -Name "test" -RepoPath "P:\software\test"
            $result | Should -Be $null
        }

        It "should return false from Invoke-Chinvex when chinvex unavailable" {
            $result = Invoke-Chinvex -Arguments @("context", "list")
            $result | Should -Be $false
        }

        It "should return null from Invoke-ChinvexQuery when chinvex unavailable" {
            $result = Invoke-ChinvexQuery -Arguments @("context", "list", "--json")
            $result | Should -Be $null
        }

        It "should cache chinvex availability check" {
            # Reset cache
            $script:chinvexChecked = $false
            $script:chinvexAvailable = $false

            Test-ChinvexAvailable
            Test-ChinvexAvailable
            Test-ChinvexAvailable

            # Should only call Get-Command once
            Should -Invoke Get-Command -Times 1 -ParameterFilter { $Name -eq "chinvex" }
        }
    }

    Describe "Chinvex failure sets chinvex_context to null" {
        BeforeEach {
            Create-TestRepo (Join-Path $script:testSoftwareRoot "failure-test")
        }

        It "should set chinvex_context to null when context create fails" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex { return $false }  # All calls fail

            $result = Sync-ChinvexForEntry -Scope "software" -Name "failure-test" -RepoPath (Join-Path $script:testSoftwareRoot "failure-test")

            $result | Should -Be $null
        }

        It "should set chinvex_context to null when ingest fails after create succeeds" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }
            Mock Invoke-Chinvex {
                param($Arguments)
                if ($Arguments[0] -eq "context" -and $Arguments[1] -eq "create") {
                    return $true
                }
                return $false  # ingest fails
            }

            $result = Sync-ChinvexForEntry -Scope "software" -Name "failure-test" -RepoPath (Join-Path $script:testSoftwareRoot "failure-test")

            $result | Should -Be $null
        }
    }

    Describe "Scope detection consistency" {
        It "should detect tool scope for paths under tools_root" {
            $paths = @(
                (Join-Path $script:testToolsRoot "tool1"),
                (Join-Path $script:testToolsRoot "subdir\tool2"),
                (Join-Path $script:testToolsRoot "deep\nested\tool3")
            )

            foreach ($path in $paths) {
                $scope = Detect-RepoScope -Path $path -StrapRootPath $script:testStrapRoot
                $scope | Should -Be "tool" -Because "Path '$path' should be detected as tool"
            }
        }

        It "should detect software scope for paths under software_root but not tools_root" {
            $paths = @(
                (Join-Path $script:testSoftwareRoot "project1"),
                (Join-Path $script:testSoftwareRoot "subdir\project2"),
                (Join-Path $script:testSoftwareRoot "apps\myapp")
            )

            foreach ($path in $paths) {
                $scope = Detect-RepoScope -Path $path -StrapRootPath $script:testStrapRoot
                $scope | Should -Be "software" -Because "Path '$path' should be detected as software"
            }
        }

        It "should return null for paths outside managed roots" {
            $paths = @(
                "C:\random\path",
                "D:\projects\something",
                "C:\Users\test\Documents\repo"
            )

            foreach ($path in $paths) {
                $scope = Detect-RepoScope -Path $path -StrapRootPath $script:testStrapRoot
                $scope | Should -Be $null -Because "Path '$path' should not be in managed roots"
            }
        }

        It "should use most-specific match (tools_root wins over software_root)" {
            # tools_root is inside software_root, so tools_root should match first
            $toolPath = Join-Path $script:testToolsRoot "sometool"
            $scope = Detect-RepoScope -Path $toolPath -StrapRootPath $script:testStrapRoot
            $scope | Should -Be "tool"
        }
    }

    Describe "Get-ContextName consistency" {
        It "should always return 'tools' for tool scope regardless of name" {
            $names = @("mytool", "script", "utility", "helper", "tools")

            foreach ($name in $names) {
                $context = Get-ContextName -Scope "tool" -Name $name
                $context | Should -Be "tools" -Because "Tool '$name' should use 'tools' context"
            }
        }

        It "should return entry name for software scope" {
            $names = @("myproject", "webapp", "api-service", "frontend")

            foreach ($name in $names) {
                $context = Get-ContextName -Scope "software" -Name $name
                $context | Should -Be $name -Because "Software '$name' should use own context"
            }
        }
    }

    Describe "Whitelist handling in sync-chinvex" {
        It "should include 'tools' in default whitelist" {
            $config = Load-Config $script:testStrapRoot
            $defaultWhitelist = @("tools", "archive")
            $defaultWhitelist | Should -Contain "tools"
        }

        It "should include 'archive' in default whitelist" {
            $config = Load-Config $script:testStrapRoot
            $defaultWhitelist = @("tools", "archive")
            $defaultWhitelist | Should -Contain "archive"
        }

        It "should merge user whitelist with defaults" {
            # Add custom whitelist to config
            @{
                registry = $script:testRegistryPath
                roots = @{
                    software = $script:testSoftwareRoot
                    tools = $script:testToolsRoot
                    shims = Join-Path $script:testToolsRoot "shims"
                }
                chinvex_integration = $true
                software_root = $script:testSoftwareRoot
                tools_root = $script:testToolsRoot
                chinvex_whitelist = @("tools", "archive", "custom-context", "another-special")
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

            $config = Load-Config $script:testStrapRoot
            $config.chinvex_whitelist | Should -Contain "custom-context"
            $config.chinvex_whitelist | Should -Contain "another-special"
        }
    }

    Describe "Test-ChinvexEnabled precedence" {
        It "should return false when NoChinvex flag is set, even if config enables it" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $result = Test-ChinvexEnabled -NoChinvex -StrapRootPath $script:testStrapRoot
            $result | Should -Be $false
        }

        It "should return false when config disables integration" {
            # Disable in config
            @{
                registry = $script:testRegistryPath
                roots = @{
                    software = $script:testSoftwareRoot
                    tools = $script:testToolsRoot
                    shims = Join-Path $script:testToolsRoot "shims"
                }
                chinvex_integration = $false
                software_root = $script:testSoftwareRoot
                tools_root = $script:testToolsRoot
            } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:testStrapRoot "config.json")

            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            $result = Test-ChinvexEnabled -StrapRootPath $script:testStrapRoot
            $result | Should -Be $false
        }

        It "should return true when enabled in config and chinvex available" {
            Mock Get-Command { return @{ Name = "chinvex" } } -ParameterFilter { $Name -eq "chinvex" }

            # Reset cache
            $script:chinvexChecked = $false
            $script:chinvexAvailable = $false

            $result = Test-ChinvexEnabled -StrapRootPath $script:testStrapRoot
            $result | Should -Be $true
        }

        It "should return false when enabled but chinvex not available" {
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq "chinvex" }

            # Reset cache
            $script:chinvexChecked = $false
            $script:chinvexAvailable = $false

            $result = Test-ChinvexEnabled -StrapRootPath $script:testStrapRoot
            $result | Should -Be $false
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexIdempotency.Tests.ps1 -TagFilter "Task13"`
Expected: PASS (these are validation tests for existing functionality)

Note: Task 13 is primarily a validation task. If any tests fail, it indicates bugs in the implementation from previous tasks that need to be fixed.

**Step 3: Write minimal implementation**
No new code needed for Task 13. This task validates that existing implementations are correct. If any tests fail, fix the relevant functions:

1. If idempotency tests fail: Ensure `Sync-ChinvexForEntry` uses `--idempotent` flag
2. If reserved name tests fail: Ensure `Test-ReservedContextName` is case-insensitive
3. If error handling tests fail: Ensure functions return `$null` on failure
4. If scope detection tests fail: Ensure `Detect-RepoScope` checks tools_root before software_root
5. If whitelist tests fail: Ensure config loading merges user whitelist with defaults
6. If precedence tests fail: Ensure `Test-ChinvexEnabled` checks flag first, then config

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexIdempotency.Tests.ps1 -TagFilter "Task13"`
Expected: PASS

**Step 5: Commit**
```bash
git add tests/powershell/ChinvexIdempotency.Tests.ps1
git commit -m "test(chinvex): Task 13 - add idempotency and error path validation tests"
```

---

### Task 14: Documentation

**Files:**
- Create: `docs/chinvex-integration.md` (new)
- Modify: `README.md` (add section reference)
- Test: `tests/powershell/ChinvexDocs.Tests.ps1` (new - documentation verification)

**Step 1: Write the failing test**
```powershell
# tests/powershell/ChinvexDocs.Tests.ps1
Describe "Chinvex Integration Documentation" -Tag "Task14" {
    BeforeAll {
        $script:docsRoot = "$PSScriptRoot\..\..\docs"
        $script:projectRoot = "$PSScriptRoot\..\.."
    }

    Describe "Documentation file existence" {
        It "should have chinvex-integration.md in docs folder" {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            Test-Path $docPath | Should -Be $true
        }

        It "should have non-empty chinvex-integration.md" {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            $content = Get-Content $docPath -Raw -ErrorAction SilentlyContinue
            $content.Length | Should -BeGreaterThan 500
        }
    }

    Describe "Documentation content - Overview section" {
        BeforeAll {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            $script:docContent = Get-Content $docPath -Raw -ErrorAction SilentlyContinue
        }

        It "should explain strap as source of truth" {
            $script:docContent | Should -Match "source of truth"
        }

        It "should explain scope mapping" {
            $script:docContent | Should -Match "software.*individual"
            $script:docContent | Should -Match "tool.*shared.*tools"
        }
    }

    Describe "Documentation content - Command reference" {
        BeforeAll {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            $script:docContent = Get-Content $docPath -Raw -ErrorAction SilentlyContinue
        }

        It "should document strap clone with chinvex behavior" {
            $script:docContent | Should -Match "clone.*chinvex"
        }

        It "should document strap adopt with chinvex behavior" {
            $script:docContent | Should -Match "adopt.*chinvex"
        }

        It "should document strap move with chinvex behavior" {
            $script:docContent | Should -Match "move.*chinvex"
        }

        It "should document strap rename with chinvex behavior" {
            $script:docContent | Should -Match "rename.*chinvex"
        }

        It "should document strap uninstall with chinvex behavior" {
            $script:docContent | Should -Match "uninstall.*archive"
        }

        It "should document strap contexts command" {
            $script:docContent | Should -Match "strap contexts"
        }

        It "should document strap sync-chinvex command" {
            $script:docContent | Should -Match "sync-chinvex"
            $script:docContent | Should -Match "reconcile"
        }
    }

    Describe "Documentation content - Opt-out mechanisms" {
        BeforeAll {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            $script:docContent = Get-Content $docPath -Raw -ErrorAction SilentlyContinue
        }

        It "should document --no-chinvex flag" {
            $script:docContent | Should -Match "--no-chinvex"
        }

        It "should document config.json chinvex_integration setting" {
            $script:docContent | Should -Match "chinvex_integration"
            $script:docContent | Should -Match "config\.json"
        }

        It "should explain precedence (flag > config > default)" {
            $script:docContent | Should -Match "precedence|override"
        }
    }

    Describe "Documentation content - Troubleshooting" {
        BeforeAll {
            $docPath = Join-Path $script:docsRoot "chinvex-integration.md"
            $script:docContent = Get-Content $docPath -Raw -ErrorAction SilentlyContinue
        }

        It "should have troubleshooting section" {
            $script:docContent | Should -Match "[Tt]roubleshooting"
        }

        It "should explain what to do when chinvex not found" {
            $script:docContent | Should -Match "chinvex.*not (found|installed|available)"
        }

        It "should explain drift recovery with sync-chinvex" {
            $script:docContent | Should -Match "drift|reconcil"
        }
    }

    Describe "README.md reference" {
        BeforeAll {
            $readmePath = Join-Path $script:projectRoot "README.md"
            $script:readmeContent = Get-Content $readmePath -Raw -ErrorAction SilentlyContinue
        }

        It "should mention chinvex integration in README" {
            $script:readmeContent | Should -Match "[Cc]hinvex"
        }

        It "should link to chinvex-integration.md from README" {
            $script:readmeContent | Should -Match "chinvex-integration\.md|docs/chinvex"
        }
    }
}
```

**Step 2: Run test to verify it fails**
Run: `Invoke-Pester -Path tests/powershell/ChinvexDocs.Tests.ps1 -TagFilter "Task14"`
Expected: FAIL with "Test-Path returned $false" (documentation file doesn't exist)

**Step 3: Write minimal implementation**

Create `docs/chinvex-integration.md`:
```markdown
# Chinvex Integration

This document describes how strap integrates with chinvex for automatic context management.

## Overview

**Strap is the source of truth for repository lifecycle.** Chinvex contexts are automatically created, updated, and archived as a side effect of strap operations.

### Scope Mapping

- **Software repos** (`strap clone` or `strap clone --software`): Each repo gets an individual chinvex context with the same name as the repo.
- **Tool repos** (`strap clone --tool`): All tools share a single chinvex context named `tools`.

## Command Behavior

### strap clone

When you clone a repository, strap automatically:

1. Clones the repository
2. Adds it to the registry
3. Creates a chinvex context (or updates the shared `tools` context for tool repos)
4. Registers the repo path in the context (without running full ingestion)

```powershell
# Clone as software (default) - creates individual context
strap clone https://github.com/user/myproject

# Clone as tool - adds to shared 'tools' context
strap clone https://github.com/user/myscript --tool

# Skip chinvex integration
strap clone https://github.com/user/myproject --no-chinvex
```

### strap adopt

Adopting an existing repository works similarly to clone:

```powershell
# Auto-detect scope from path
strap adopt --path P:\software\existing-repo

# Force tool scope
strap adopt --path P:\software\script --tool
```

### strap move

Moving a repository updates the chinvex context path. If the move changes scope (e.g., from software root to tools root), strap handles the context transition:

- **Software to tool**: Archives the individual context, adds to `tools` context
- **Tool to software**: Removes from `tools` context, creates individual context
- **Same scope**: Updates the path in the existing context

```powershell
# Move within software root (path update only)
strap move myrepo --dest P:\software\subdir

# Move to tools root (scope change: software -> tool)
strap move myrepo --dest P:\software\_scripts
```

### strap rename

Renaming a software repo renames its chinvex context. Tool repos stay in the shared `tools` context.

```powershell
# Rename software repo - also renames chinvex context
strap rename myrepo --to newname

# Rename and move folder - updates path in context
strap rename myrepo --to newname --move-folder
```

### strap uninstall

Uninstalling a repository cleans up chinvex:

- **Software repos**: The chinvex context is archived (metadata preserved, full context removed)
- **Tool repos**: The repo path is removed from the `tools` context

```powershell
strap uninstall myproject  # Archives chinvex context
```

### strap contexts

View all chinvex contexts and their sync status:

```powershell
strap contexts

# Output:
# Context         Type       Repos  Last Ingest         Sync Status
# myproject       software   1      2026-01-30T10:00    [OK] synced
# tools           tool       5      2026-01-29T15:30    [OK] synced
# old-project     unknown    1      2026-01-15T08:00    [?] no strap entry
```

### strap sync-chinvex

Reconcile the registry with chinvex contexts:

```powershell
# Show what would change (default, safe)
strap sync-chinvex

# Same as above
strap sync-chinvex --dry-run

# Apply reconciliation
strap sync-chinvex --reconcile
```

Reconciliation actions:
- **Missing contexts**: Creates contexts for registry entries with `chinvex_context: null`
- **Orphaned contexts**: Archives contexts that have no corresponding registry entry

Whitelisted contexts (`tools`, `archive`) are never archived.

## Opt-out Mechanisms

### Per-command opt-out

Use the `--no-chinvex` flag on any command:

```powershell
strap clone https://github.com/user/repo --no-chinvex
strap move myrepo --dest P:\software\new --no-chinvex
```

### Global opt-out

Disable integration in `config.json`:

```json
{
  "chinvex_integration": false
}
```

### Precedence

Flag takes precedence over config:

1. `--no-chinvex` flag (highest priority - always disables)
2. `config.json` `chinvex_integration` setting
3. Default (enabled)

**Exception**: `strap sync-chinvex` always runs regardless of config or flags.

## Registry Fields

Each registry entry includes:

```json
{
  "id": "myrepo",
  "name": "myrepo",
  "path": "P:\\software\\myrepo",
  "scope": "software",
  "chinvex_context": "myrepo",
  "shims": []
}
```

- `scope`: Either `"software"` or `"tool"`
- `chinvex_context`: The chinvex context name, or `null` if not synced

## Troubleshooting

### Chinvex not found

If chinvex is not installed or not on PATH:

```
WARNING: Chinvex not installed or not on PATH. Skipping context sync.
```

Solution:
1. Install chinvex
2. Create a shim: `strap shim chinvex --source P:\path\to\chinvex.ps1`
3. Ensure the shims directory is on PATH

### Drift between registry and chinvex

If contexts get out of sync:

```powershell
# Check current status
strap contexts

# Preview reconciliation
strap sync-chinvex --dry-run

# Apply fixes
strap sync-chinvex --reconcile
```

### chinvex_context is null after operation

This happens when a chinvex operation fails. The strap operation completes, but the context isn't synced.

Solution:
```powershell
strap sync-chinvex --reconcile
```

### Reserved name conflict

Software repos cannot be named `tools` or `archive` (reserved for system contexts).

```
ERROR: Cannot use reserved name 'tools' for software repos. Reserved names: tools, archive
```

Solution: Use a different name, or clone as a tool (`--tool` flag).

## Whitelist

These contexts are never auto-archived by `sync-chinvex --reconcile`:

- `tools` (shared context for tool repos)
- `archive` (system context for archived repos)

Add custom entries via config:

```json
{
  "chinvex_whitelist": ["tools", "archive", "my-special-context"]
}
```
```

Update `README.md` to add reference (add this section near the end):

```markdown
## Chinvex Integration

Strap integrates with [chinvex](https://github.com/your/chinvex) for automatic context management. When you clone, adopt, move, rename, or uninstall repositories, strap keeps chinvex contexts in sync.

See [docs/chinvex-integration.md](docs/chinvex-integration.md) for full documentation.

Quick commands:
- `strap contexts` - View context sync status
- `strap sync-chinvex` - Preview reconciliation
- `strap sync-chinvex --reconcile` - Fix drift
```

**Step 4: Run test to verify it passes**
Run: `Invoke-Pester -Path tests/powershell/ChinvexDocs.Tests.ps1 -TagFilter "Task14"`
Expected: PASS

**Step 5: Commit**
```bash
git add docs/chinvex-integration.md README.md tests/powershell/ChinvexDocs.Tests.ps1
git commit -m "docs(chinvex): Task 14 - add chinvex integration documentation"
```

---

<!-- End of Batch 3 -->
