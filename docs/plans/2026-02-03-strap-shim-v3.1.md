# Strap Shim v3.1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement unified dual-file shim system (`.ps1` + `.cmd`) with venv/node/simple types, direct venv invocation, and comprehensive doctor checks.

**Architecture:** Generate paired `.ps1` (logic) + `.cmd` (launcher) files in `P:\software\bin`. Registry tracks shim metadata with resolved exe paths. Shims use direct venv binary invocation (no activation), pinned node executables, and full pwsh paths for Task Scheduler compatibility.

**Tech Stack:** PowerShell 7, JSON registry (v2), PowerShell AST tokenizer for command parsing

---

## Task 1: Update Config Schema and Registry Version

**Files:**
- Modify: `config.json:1-8`
- Modify: `modules/Config.ps1:7-32`
- Test: `tests/powershell/Config.Tests.ps1` (create)

**Step 1: Write failing tests for new config fields**

Create `tests/powershell/Config.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../../modules/Config.ps1"
    . "$PSScriptRoot/../../modules/Core.ps1"
}

Describe "Load-Config with v3.1 schema" {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive "strap-test"
        New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

        $script:ConfigPath = Join-Path $TestRoot "config.json"
    }

    It "loads config with new shims, nodeTools, and defaults fields" {
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

    It "applies defaults for missing fields" {
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
    }
}

Describe "Registry v2 format" {
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

        $savedContent = Get-Content $RegistryPath -Raw | ConvertFrom-Json
        $savedContent.version | Should -Be 2
        $savedContent.repos | Should -Not -BeNullOrEmpty
        $savedContent.repos[0].name | Should -Be "test-repo"
        $savedContent.repos[0].repoPath | Should -Be "P:\software\test-repo"
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
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/Config.Tests.ps1 -Output Detailed"`
Expected: Multiple FAILs - new config fields not implemented, v2 registry not implemented

**Step 3: Update config.json with new fields**

```json
{
  "roots": {
    "software": "P:\\software",
    "tools": "P:\\software\\_scripts",
    "shims": "P:\\software\\bin",
    "nodeTools": "P:\\software\\_node-tools",
    "archive": "P:\\software\\_archive"
  },
  "defaults": {
    "pwshExe": "C:\\Program Files\\PowerShell\\7\\pwsh.exe",
    "nodeExe": "C:\\nvm4w\\nodejs\\node.exe"
  },
  "registry": "P:\\software\\_strap\\build\\registry.json"
}
```

**Step 4: Update modules/Config.ps1**

Update registry version constant:
```powershell
$script:LATEST_REGISTRY_VERSION = 2
```

Update `Load-Config` to apply defaults:
```powershell
function Load-Config($strapRoot) {
  $configPath = Join-Path $strapRoot "config.json"
  if (-not (Test-Path $configPath)) {
    Die "Config not found: $configPath"
  }
  $json = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

  # Apply defaults for shims and nodeTools roots
  if ($null -eq $json.roots.shims) {
    $json.roots | Add-Member -NotePropertyName shims -NotePropertyValue "P:\software\bin" -Force
  }
  if ($null -eq $json.roots.nodeTools) {
    $json.roots | Add-Member -NotePropertyName nodeTools -NotePropertyValue "P:\software\_node-tools" -Force
  }
  if ($null -eq $json.roots.archive) {
    $json.roots | Add-Member -NotePropertyName archive -NotePropertyValue "P:\software\_archive" -Force
  }

  # Apply defaults for pwshExe and nodeExe
  if ($null -eq $json.defaults) {
    $json | Add-Member -NotePropertyName defaults -NotePropertyValue @{} -Force
  }
  if ($null -eq $json.defaults.pwshExe) {
    $json.defaults | Add-Member -NotePropertyName pwshExe -NotePropertyValue "C:\Program Files\PowerShell\7\pwsh.exe" -Force
  }
  if ($null -eq $json.defaults.nodeExe) {
    $json.defaults | Add-Member -NotePropertyName nodeExe -NotePropertyValue "C:\nvm4w\nodejs\node.exe" -Force
  }

  # Apply chinvex integration defaults (existing)
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

Update `Load-Registry` to handle v2 format and version check:
```powershell
function Load-Registry($configObj) {
  $registryPath = $configObj.registry
  if (-not (Test-Path $registryPath)) {
    # Create empty v2 registry if it doesn't exist
    $parentDir = Split-Path $registryPath -Parent
    if (-not (Test-Path $parentDir)) {
      New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    $emptyRegistry = @{
      version = $script:LATEST_REGISTRY_VERSION
      repos = @()
    } | ConvertTo-Json -Depth 10
    $emptyRegistry | Set-Content -LiteralPath $registryPath -NoNewline
    return @()
  }

  $content = Get-Content -LiteralPath $registryPath -Raw
  $json = $content | ConvertFrom-Json

  # Handle legacy array format (v1)
  if ($json -is [System.Array]) {
    # Auto-migrate: wrap in v2 structure
    return @($json)
  }

  # Check version
  if ($json.PSObject.Properties['version']) {
    $version = $json.version
    if ($version -gt $script:LATEST_REGISTRY_VERSION) {
      Die "Registry version $version requires newer strap version (current supports v$script:LATEST_REGISTRY_VERSION)"
    }
  }

  # V2 format: has repos array
  if ($json.PSObject.Properties['repos']) {
    return @($json.repos)
  }

  # Legacy v1 with entries field
  if ($json.PSObject.Properties['entries']) {
    return @($json.entries)
  }

  # Unknown format
  Die "Unrecognized registry format"
}
```

Update `Save-Registry` to write v2 format:
```powershell
function Save-Registry($configObj, $entries) {
  $registryPath = $configObj.registry
  $tmpPath = "$registryPath.tmp"

  # Write in v2 format
  $registryObj = [PSCustomObject]@{
    version = $script:LATEST_REGISTRY_VERSION
    repos = @($entries)
  }

  $json = $registryObj | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($tmpPath, $json, (New-Object System.Text.UTF8Encoding($false)))

  # Atomic move (overwrites destination)
  Move-Item -LiteralPath $tmpPath -Destination $registryPath -Force
}
```

**Step 5: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/Config.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

**Step 6: Commit**

```powershell
git add config.json modules/Config.ps1 tests/powershell/Config.Tests.ps1
git commit -m "feat(shim): add v3.1 config schema and registry v2 format

- Add shims, nodeTools, archive roots to config
- Add defaults.pwshExe and defaults.nodeExe
- Bump registry version to 2 with version check
- Change registry field: entries -> repos
- Add repoPath field (was 'path')
- Add migration for legacy formats

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Implement Command Parsing (Tokenizer + JSON)

**Files:**
- Create: `modules/ShimParser.ps1`
- Test: `tests/powershell/ShimParser.Tests.ps1` (create)

**Step 1: Write failing tests for command parsing**

Create `tests/powershell/ShimParser.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../../modules/ShimParser.ps1"
    . "$PSScriptRoot/../../modules/Core.ps1"
}

Describe "Parse-CommandLine" {
    Context "JSON array parsing" {
        It "parses simple JSON array" {
            $result = Parse-CommandLine '["python", "-m", "mytool"]'
            $result.exe | Should -Be "python"
            $result.baseArgs | Should -HaveCount 2
            $result.baseArgs[0] | Should -Be "-m"
            $result.baseArgs[1] | Should -Be "mytool"
        }

        It "handles paths with spaces in JSON" {
            $result = Parse-CommandLine '["C:\\Program Files\\tool.exe", "--flag", "value"]'
            $result.exe | Should -Be "C:\Program Files\tool.exe"
            $result.baseArgs | Should -HaveCount 2
        }

        It "errors on empty JSON array" {
            { Parse-CommandLine '[]' } | Should -Throw "*Empty command array*"
        }

        It "errors on invalid JSON" {
            { Parse-CommandLine '[invalid json' } | Should -Throw "*Invalid JSON array*"
        }
    }

    Context "Tokenizer parsing" {
        It "parses simple command" {
            $result = Parse-CommandLine "python -m mytool"
            $result.exe | Should -Be "python"
            $result.baseArgs | Should -HaveCount 2
            $result.baseArgs[0] | Should -Be "-m"
            $result.baseArgs[1] | Should -Be "mytool"
        }

        It "handles quoted arguments" {
            $result = Parse-CommandLine 'python -m "my tool"'
            $result.exe | Should -Be "python"
            $result.baseArgs | Should -HaveCount 2
            $result.baseArgs[1] | Should -Be "my tool"
        }

        It "handles paths with spaces" {
            $result = Parse-CommandLine '"C:\Program Files\tool.exe" --flag'
            $result.exe | Should -Be "C:\Program Files\tool.exe"
            $result.baseArgs[0] | Should -Be "--flag"
        }

        It "blocks pipe operators" {
            { Parse-CommandLine "python | grep" } | Should -Throw "*only support direct exec*"
        }

        It "blocks redirects" {
            { Parse-CommandLine "python > output.txt" } | Should -Throw "*only support direct exec*"
        }

        It "blocks semicolons" {
            { Parse-CommandLine "python; echo done" } | Should -Throw "*only support direct exec*"
        }

        It "blocks && operators" {
            { Parse-CommandLine "python && echo" } | Should -Throw "*only support direct exec*"
        }
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/ShimParser.Tests.ps1 -Output Detailed"`
Expected: FAIL - Parse-CommandLine not implemented

**Step 3: Implement ShimParser.ps1**

Create `modules/ShimParser.ps1`:

```powershell
# ShimParser.ps1
# Command line parsing for strap shim generation

# Dot-source Core for utility functions
. "$PSScriptRoot\Core.ps1"

function Parse-CommandLine {
  param([string] $CommandLine)

  if (-not $CommandLine) {
    Die "Command line cannot be empty"
  }

  $trimmed = $CommandLine.Trim()

  # Detect JSON array form
  if ($trimmed.StartsWith('[')) {
    try {
      $parts = $trimmed | ConvertFrom-Json
      if ($parts.Count -eq 0) {
        Die "Empty command array"
      }
      return @{
        exe = $parts[0]
        baseArgs = @($parts | Select-Object -Skip 1)
      }
    } catch {
      Die "Invalid JSON array: $CommandLine"
    }
  }

  # Use PowerShell tokenizer
  $tokens = $null
  $errors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseInput(
    "& $CommandLine",
    [ref]$tokens,
    [ref]$errors
  )

  # Safety: block shell operators
  $blocked = $tokens | Where-Object {
    $_.Kind -in @('Pipe', 'Semi', 'Redirection', 'AndAnd', 'OrOr')
  }
  if ($blocked) {
    Die "Shims only support direct exec + args. Use a wrapper script and shim that instead."
  }

  # Extract string tokens (skip '&' operator)
  # Prefer .Value (unquoted) over .Text (may include quotes)
  $parts = $tokens |
    Where-Object { $_.Kind -in @('StringLiteral', 'StringExpandable', 'Generic') -and $_.Text -ne '&' } |
    ForEach-Object {
      if ($null -ne $_.Value) { $_.Value } else { $_.Text }
    }

  if ($parts.Count -eq 0) {
    Die "Could not parse command: $CommandLine"
  }

  return @{
    exe = $parts[0]
    baseArgs = @($parts | Select-Object -Skip 1)
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/ShimParser.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

**Step 5: Commit**

```powershell
git add modules/ShimParser.ps1 tests/powershell/ShimParser.Tests.ps1
git commit -m "feat(shim): add command line parser with tokenizer and JSON support

- Implement Parse-CommandLine with PowerShell AST tokenizer
- Support JSON array format for complex args
- Block shell operators (pipes, redirects, semicolons)
- Extract unquoted values from tokens

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Implement Venv and Node Exe Resolution

**Files:**
- Create: `modules/ShimResolver.ps1`
- Test: `tests/powershell/ShimResolver.Tests.ps1` (create)

**Step 1: Write failing tests for exe resolution**

Create `tests/powershell/ShimResolver.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../../modules/ShimResolver.ps1"
    . "$PSScriptRoot/../../modules/Core.ps1"
}

Describe "Resolve-VenvPath" {
    BeforeEach {
        $script:TestRepoPath = Join-Path $TestDrive "test-repo"
        New-Item -ItemType Directory -Path $TestRepoPath -Force | Out-Null
    }

    It "detects .venv directory" {
        $venvPath = Join-Path $TestRepoPath ".venv\Scripts"
        New-Item -ItemType Directory -Path $venvPath -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $venvPath "python.exe") -Force | Out-Null

        $result = Resolve-VenvPath -RepoPath $TestRepoPath
        $result | Should -Be (Join-Path $TestRepoPath ".venv")
    }

    It "detects venv directory" {
        $venvPath = Join-Path $TestRepoPath "venv\Scripts"
        New-Item -ItemType Directory -Path $venvPath -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $venvPath "python.exe") -Force | Out-Null

        $result = Resolve-VenvPath -RepoPath $TestRepoPath
        $result | Should -Be (Join-Path $TestRepoPath "venv")
    }

    It "returns explicit path when provided" {
        $explicitPath = "P:\software\custom\.venv"
        $result = Resolve-VenvPath -RepoPath $TestRepoPath -ExplicitPath $explicitPath
        $result | Should -Be $explicitPath
    }

    It "errors when no venv found" {
        { Resolve-VenvPath -RepoPath $TestRepoPath } | Should -Throw "*No venv found*"
    }
}

Describe "Resolve-VenvExe" {
    BeforeEach {
        $script:VenvPath = Join-Path $TestDrive ".venv"
        $script:ScriptsPath = Join-Path $VenvPath "Scripts"
        New-Item -ItemType Directory -Path $ScriptsPath -Force | Out-Null
    }

    It "resolves python to Scripts\python.exe" {
        $pythonExe = Join-Path $ScriptsPath "python.exe"
        New-Item -ItemType File -Path $pythonExe -Force | Out-Null

        $result = Resolve-VenvExe -Exe "python" -VenvPath $VenvPath
        $result.resolvedPath | Should -Be $pythonExe
        $result.exists | Should -Be $true
    }

    It "resolves script name to Scripts\<name>.exe" {
        $chinvexExe = Join-Path $ScriptsPath "chinvex.exe"
        New-Item -ItemType File -Path $chinvexExe -Force | Out-Null

        $result = Resolve-VenvExe -Exe "chinvex" -VenvPath $VenvPath
        $result.resolvedPath | Should -Be $chinvexExe
        $result.exists | Should -Be $true
    }

    It "warns when exe not found but returns path" {
        $result = Resolve-VenvExe -Exe "missing" -VenvPath $VenvPath
        $result.resolvedPath | Should -Be (Join-Path $ScriptsPath "missing.exe")
        $result.exists | Should -Be $false
    }
}

Describe "Resolve-NodeExe" {
    BeforeEach {
        $script:Config = @{
            defaults = @{
                nodeExe = "C:\nvm4w\nodejs\node.exe"
            }
        }
    }

    It "uses CLI override when provided" {
        Mock Test-Path { $true }
        $result = Resolve-NodeExe -CliOverride "C:\custom\node.exe" -Config $Config
        $result | Should -Be "C:\custom\node.exe"
    }

    It "errors when CLI override not found" {
        Mock Test-Path { $false }
        { Resolve-NodeExe -CliOverride "C:\missing\node.exe" -Config $Config } | Should -Throw "*Node exe not found*"
    }

    It "uses config default when no override" {
        Mock Test-Path { $true } -ParameterFilter { $Path -eq "C:\nvm4w\nodejs\node.exe" }
        $result = Resolve-NodeExe -Config $Config
        $result | Should -Be "C:\nvm4w\nodejs\node.exe"
    }

    It "falls back to PATH with warning" {
        Mock Test-Path { $false }
        Mock Get-Command { @{ Source = "C:\somewhere\node.exe" } }
        Mock Warn {}

        $result = Resolve-NodeExe -Config $Config
        $result | Should -Be "C:\somewhere\node.exe"
        Should -Invoke Warn -Times 1
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/ShimResolver.Tests.ps1 -Output Detailed"`
Expected: FAIL - resolver functions not implemented

**Step 3: Implement ShimResolver.ps1**

Create `modules/ShimResolver.ps1`:

```powershell
# ShimResolver.ps1
# Venv and Node exe resolution for strap shims

# Dot-source Core for utility functions
. "$PSScriptRoot\Core.ps1"

function Resolve-VenvPath {
  param(
    [Parameter(Mandatory)]
    [string] $RepoPath,
    [string] $ExplicitPath
  )

  # If explicit path provided, use it
  if ($ExplicitPath) {
    return $ExplicitPath
  }

  # Auto-detect from repo
  $venvCandidates = @(".venv", "venv", ".virtualenv")

  foreach ($candidate in $venvCandidates) {
    $testPath = Join-Path $RepoPath $candidate
    $pythonExe = Join-Path $testPath "Scripts\python.exe"
    if (Test-Path $pythonExe) {
      return $testPath
    }
  }

  Die "No venv found in $RepoPath. Use --venv <path> to specify explicitly."
}

function Resolve-VenvExe {
  param(
    [Parameter(Mandatory)]
    [string] $Exe,
    [Parameter(Mandatory)]
    [string] $VenvPath
  )

  $scriptsDir = Join-Path $VenvPath "Scripts"

  # Special case: python
  if ($Exe -eq "python") {
    $resolved = Join-Path $scriptsDir "python.exe"
    return @{
      resolvedPath = $resolved
      exists = Test-Path $resolved
    }
  }

  # Try as script in venv
  $scriptExe = Join-Path $scriptsDir "$Exe.exe"
  return @{
    resolvedPath = $scriptExe
    exists = Test-Path $scriptExe
  }
}

function Resolve-NodeExe {
  param(
    [string] $CliOverride,
    [Parameter(Mandatory)]
    [object] $Config
  )

  # Priority: CLI override > config default > PATH lookup (with warning)
  if ($CliOverride) {
    if (-not (Test-Path $CliOverride)) {
      Die "Node exe not found: $CliOverride"
    }
    return $CliOverride
  }

  if ($Config.defaults.nodeExe -and (Test-Path $Config.defaults.nodeExe)) {
    return $Config.defaults.nodeExe
  }

  # Fallback to PATH (with warning)
  $found = Get-Command node -ErrorAction SilentlyContinue
  if ($found) {
    Warn "Using node from PATH: $($found.Source). Consider setting defaults.nodeExe in config."
    return $found.Source
  }

  Die "Node not found. Set defaults.nodeExe in strap config or provide --node-exe."
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/ShimResolver.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

**Step 5: Commit**

```powershell
git add modules/ShimResolver.ps1 tests/powershell/ShimResolver.Tests.ps1
git commit -m "feat(shim): add venv and node exe resolution

- Implement Resolve-VenvPath with auto-detection (.venv, venv, .virtualenv)
- Implement Resolve-VenvExe for direct venv binary invocation
- Implement Resolve-NodeExe with CLI/config/PATH priority
- Warn when exe not found at generation time

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Implement Shim Template Generation

**Files:**
- Create: `modules/ShimGenerator.ps1`
- Test: `tests/powershell/ShimGenerator.Tests.ps1` (create)

**Step 1: Write failing tests for shim generation**

Create `tests/powershell/ShimGenerator.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../../modules/ShimGenerator.ps1"
    . "$PSScriptRoot/../../modules/Core.ps1"
}

Describe "Generate-ShimPs1" {
    It "generates simple type shim" {
        $shimMeta = @{
            name = "mytool"
            repo = "test-repo"
            type = "simple"
            exe = "C:\tools\mytool.exe"
            baseArgs = @("--verbose")
            cwd = $null
        }

        $content = Generate-ShimPs1 $shimMeta

        $content | Should -Match "# Generated by strap shim - do not edit"
        $content | Should -Match "# Repo: test-repo \| Type: simple"
        $content | Should -Match '\$exe = "C:\\tools\\mytool.exe"'
        $content | Should -Match '\$baseArgs = @\("--verbose"\)'
        $content | Should -Match '& \$exe @baseArgs @args'
    }

    It "generates venv type shim" {
        $shimMeta = @{
            name = "chinvex"
            repo = "chinvex"
            type = "venv"
            exe = "P:\software\chinvex\.venv\Scripts\chinvex.exe"
            baseArgs = @()
            venv = "P:\software\chinvex\.venv"
            cwd = $null
        }

        $content = Generate-ShimPs1 $shimMeta

        $content | Should -Match "# Repo: chinvex \| Type: venv"
        $content | Should -Match 'Venv: P:\\software\\chinvex\\\.venv'
        $content | Should -Match '\$venv = "P:\\software\\chinvex\\\.venv"'
        $content | Should -Match '\$exe = "P:\\software\\chinvex\\\.venv\\Scripts\\chinvex.exe"'
    }

    It "generates node type shim" {
        $shimMeta = @{
            name = "pm2"
            repo = "pm2-local"
            type = "node"
            exe = "C:\nvm4w\nodejs\node.exe"
            baseArgs = @("P:\software\_node-tools\pm2\node_modules\pm2\bin\pm2")
            cwd = $null
        }

        $content = Generate-ShimPs1 $shimMeta

        $content | Should -Match "# Repo: pm2-local \| Type: node"
        $content | Should -Match '\$exe = "C:\\nvm4w\\nodejs\\node.exe"'
        $content | Should -Match 'baseArgs = @\("P:\\software\\_node-tools'
    }

    It "generates shim with working directory" {
        $shimMeta = @{
            name = "pm2-services"
            repo = "chinvex"
            type = "simple"
            exe = "pm2"
            baseArgs = @("start", "ecosystem.config.js")
            cwd = "P:\software\chinvex"
        }

        $content = Generate-ShimPs1 $shimMeta

        $content | Should -Match "Cwd: P:\\software\\chinvex"
        $content | Should -Match "Push-Location"
        $content | Should -Match "Pop-Location"
        $content | Should -Match "try \{"
    }
}

Describe "Generate-ShimCmd" {
    It "generates cmd launcher with full pwsh path" {
        $pwshExe = "C:\Program Files\PowerShell\7\pwsh.exe"
        $shimName = "chinvex"

        $content = Generate-ShimCmd -ShimName $shimName -PwshExe $pwshExe

        $content | Should -Match "@echo off"
        $content | Should -Match '"C:\\Program Files\\PowerShell\\7\\pwsh.exe"'
        $content | Should -Match "-NoLogo -NoProfile -ExecutionPolicy Bypass"
        $content | Should -Match "-File ""%~dp0chinvex.ps1"""
        $content | Should -Match "exit /b %errorlevel%"
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/ShimGenerator.Tests.ps1 -Output Detailed"`
Expected: FAIL - generation functions not implemented

**Step 3: Implement ShimGenerator.ps1**

Create `modules/ShimGenerator.ps1`:

```powershell
# ShimGenerator.ps1
# Shim file generation for .ps1 and .cmd

# Dot-source Core for utility functions
. "$PSScriptRoot\Core.ps1"

function Generate-ShimPs1 {
  param(
    [Parameter(Mandatory)]
    [hashtable] $ShimMeta
  )

  $name = $ShimMeta.name
  $repo = $ShimMeta.repo
  $type = $ShimMeta.type
  $exe = $ShimMeta.exe
  $baseArgs = $ShimMeta.baseArgs
  $cwd = $ShimMeta.cwd
  $venv = $ShimMeta.venv

  # Header comment
  $header = "# Generated by strap shim - do not edit`n"
  if ($type -eq "venv") {
    $header += "# Repo: $repo | Type: $type | Venv: $venv"
  } elseif ($cwd) {
    $header += "# Repo: $repo | Type: $type | Cwd: $cwd"
  } else {
    $header += "# Repo: $repo | Type: $type"
  }

  # Format baseArgs for PowerShell array literal
  $baseArgsStr = if ($baseArgs.Count -eq 0) {
    "@()"
  } else {
    $escaped = $baseArgs | ForEach-Object {
      $escaped = $_ -replace '\\', '\\' -replace '"', '`"'
      "`"$escaped`""
    }
    "@($($escaped -join ', '))"
  }

  # Build script body
  if ($cwd) {
    # With working directory
    $venvLine = if ($type -eq "venv") { "`$venv = `"$venv`"`n  " } else { "" }
    $body = @"
`$ErrorActionPreference = "Stop"
`$ec = 0
Push-Location "$cwd"
try {
  $venvLine`$exe = "$exe"
  `$baseArgs = $baseArgsStr
  & `$exe @baseArgs @args
  `$ec = if (`$null -eq `$LASTEXITCODE) { 0 } else { `$LASTEXITCODE }
} finally {
  Pop-Location
}
exit `$ec
"@
  } else {
    # Without working directory
    $venvLine = if ($type -eq "venv") { "`$venv = `"$venv`"`n" } else { "" }
    $body = @"
`$ErrorActionPreference = "Stop"
$venvLine`$exe = "$exe"
`$baseArgs = $baseArgsStr
& `$exe @baseArgs @args
`$ec = if (`$null -eq `$LASTEXITCODE) { 0 } else { `$LASTEXITCODE }
exit `$ec
"@
  }

  return "$header`n$body"
}

function Generate-ShimCmd {
  param(
    [Parameter(Mandatory)]
    [string] $ShimName,
    [Parameter(Mandatory)]
    [string] $PwshExe
  )

  return @"
@echo off
"$PwshExe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0$ShimName.ps1" %*
exit /b %errorlevel%
"@
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/ShimGenerator.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

**Step 5: Commit**

```powershell
git add modules/ShimGenerator.ps1 tests/powershell/ShimGenerator.Tests.ps1
git commit -m "feat(shim): add shim template generation for .ps1 and .cmd

- Implement Generate-ShimPs1 for simple/venv/node types
- Implement Generate-ShimCmd with full pwsh path
- Handle working directory with Push/Pop-Location
- Format baseArgs as PowerShell array literal

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Rewrite Invoke-Shim with New Signature

**Files:**
- Modify: `modules/Commands/shim.ps1`
- Test: `tests/powershell/InvokeShim.Tests.ps1` (create)

**Step 1: Write failing tests for new Invoke-Shim**

Create `tests/powershell/InvokeShim.Tests.ps1`:

```powershell
BeforeAll {
    $commandsPath = Join-Path "$PSScriptRoot\..\.." "modules\Commands"
    Get-ChildItem -Path $commandsPath -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
    . "$PSScriptRoot/../../modules/Config.ps1"
    . "$PSScriptRoot/../../modules/ShimParser.ps1"
    . "$PSScriptRoot/../../modules/ShimResolver.ps1"
    . "$PSScriptRoot/../../modules/ShimGenerator.ps1"
    . "$PSScriptRoot/../../modules/Core.ps1"
}

Describe "Invoke-Shim" {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive "strap-test"
        $script:ShimsRoot = Join-Path $TestRoot "bin"
        $script:RepoPath = Join-Path $TestRoot "test-repo"

        New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $ShimsRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $RepoPath -Force | Out-Null

        # Create test config
        $configContent = @{
            roots = @{
                software = $TestRoot
                tools = Join-Path $TestRoot "tools"
                shims = $ShimsRoot
            }
            defaults = @{
                pwshExe = "C:\Program Files\PowerShell\7\pwsh.exe"
                nodeExe = "C:\nvm4w\nodejs\node.exe"
            }
            registry = Join-Path $TestRoot "registry.json"
        } | ConvertTo-Json -Depth 10
        $configContent | Set-Content (Join-Path $TestRoot "config.json") -NoNewline

        # Create empty registry
        $registryContent = @{
            version = 2
            repos = @(
                @{
                    name = "test-repo"
                    repoPath = $RepoPath
                    scope = "test"
                    shims = @()
                }
            )
        } | ConvertTo-Json -Depth 10
        $registryContent | Set-Content (Join-Path $TestRoot "registry.json") -NoNewline

        Mock Test-Path { $true } -ParameterFilter { $Path -like "*pwsh.exe" }
    }

    It "creates simple shim with --cmd" {
        Invoke-Shim -ShimName "mytool" -Cmd "mytool --verbose" `
          -ShimType "simple" -RegistryEntryName "test-repo" `
          -StrapRootPath $TestRoot -NonInteractive

        $ps1Path = Join-Path $ShimsRoot "mytool.ps1"
        $cmdPath = Join-Path $ShimsRoot "mytool.cmd"

        Test-Path $ps1Path | Should -Be $true
        Test-Path $cmdPath | Should -Be $true

        $ps1Content = Get-Content $ps1Path -Raw
        $ps1Content | Should -Match "Type: simple"
        $ps1Content | Should -Match '\$exe = "mytool"'
    }

    It "creates venv shim with auto-detected venv" {
        # Create fake venv
        $venvPath = Join-Path $RepoPath ".venv\Scripts"
        New-Item -ItemType Directory -Path $venvPath -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $venvPath "python.exe") -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $venvPath "mytool.exe") -Force | Out-Null

        Invoke-Shim -ShimName "mytool" -Cmd "mytool" `
          -ShimType "venv" -RegistryEntryName "test-repo" `
          -StrapRootPath $TestRoot -NonInteractive

        $ps1Content = Get-Content (Join-Path $ShimsRoot "mytool.ps1") -Raw
        $ps1Content | Should -Match "Type: venv"
        $ps1Content | Should -Match "\.venv"
    }

    It "errors on unknown repo" {
        { Invoke-Shim -ShimName "mytool" -Cmd "mytool" `
            -RegistryEntryName "nonexistent" `
            -StrapRootPath $TestRoot -NonInteractive } | Should -Throw "*not found*"
    }

    It "errors when --cmd and --exe both provided" {
        { Invoke-Shim -ShimName "mytool" -Cmd "mytool" -Exe "mytool" `
            -RegistryEntryName "test-repo" `
            -StrapRootPath $TestRoot -NonInteractive } | Should -Throw "*Cannot use --cmd with --exe*"
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/InvokeShim.Tests.ps1 -Output Detailed"`
Expected: FAIL - new signature and logic not implemented

**Step 3: Rewrite Invoke-Shim in modules/Commands/shim.ps1**

Replace the existing `Invoke-Shim` function:

```powershell
function Invoke-Shim {
  param(
    [Parameter(Mandatory)]
    [string] $ShimName,

    # Command specification (mutually exclusive approaches)
    [string] $Cmd,
    [string] $Exe,
    [string[]] $BaseArgs,

    # Shim configuration
    [ValidateSet("simple", "venv", "node")]
    [string] $ShimType = "simple",
    [string] $VenvPath,
    [string] $NodeExe,
    [string] $WorkingDir,

    # Context
    [string] $RegistryEntryName,

    # Regeneration
    [switch] $Regen,

    # Behavior
    [switch] $ForceOverwrite,
    [switch] $DryRunMode,
    [switch] $NonInteractive,
    [string] $StrapRootPath
  )

  # Validate shim name
  if ($ShimName -notmatch '^[a-zA-Z0-9_-]+$') {
    Die "Invalid shim name: '$ShimName' (only alphanumeric, hyphen, underscore allowed)"
  }

  # Mutual exclusivity check
  if ($Cmd -and ($Exe -or $BaseArgs)) {
    Die "Cannot use --cmd with --exe/--args. Pick one."
  }
  if (-not $Cmd -and -not $Exe) {
    Die "Must provide --cmd or --exe."
  }

  # Load config
  $config = Load-Config $StrapRootPath
  $shimsRoot = $config.roots.shims

  # Validate pwshExe at creation time
  if (-not (Test-Path $config.defaults.pwshExe)) {
    Die "pwshExe not found: $($config.defaults.pwshExe). Update strap config before creating shims."
  }

  # Load registry
  $registry = Load-Registry $config

  # Find attached repo
  $attachedEntry = $registry | Where-Object { $_.name -eq $RegistryEntryName }
  if (-not $attachedEntry) {
    Die "Registry entry not found: '$RegistryEntryName'. Use 'strap list' to see all entries."
  }

  # Parse command
  if ($Cmd) {
    $parsed = Parse-CommandLine $Cmd
    $Exe = $parsed.exe
    $BaseArgs = $parsed.baseArgs
  }

  # Type-specific resolution
  switch ($ShimType) {
    "venv" {
      # Resolve venv path
      $resolvedVenv = Resolve-VenvPath -RepoPath $attachedEntry.repoPath -ExplicitPath $VenvPath

      # Resolve exe to full path in venv
      $resolved = Resolve-VenvExe -Exe $Exe -VenvPath $resolvedVenv
      if (-not $resolved.exists) {
        Warn "Warning: $($resolved.resolvedPath) not found in venv. Shim created but may not work until package is installed."
      }
      $Exe = $resolved.resolvedPath
      $venvMetadata = $resolvedVenv
    }
    "node" {
      # For node type, --cmd is the JS entrypoint, and exe is node
      $jsEntrypoint = if ($Cmd) { $Exe } else { $BaseArgs[0] }
      $Exe = Resolve-NodeExe -CliOverride $NodeExe -Config $config
      $BaseArgs = @($jsEntrypoint)
    }
    "simple" {
      # Reject relative paths
      if ($Exe -match '^\.\.?[/\\]') {
        Die "Simple shim exe must be absolute path or bare command name. Use --cwd if you need working directory context."
      }
    }
  }

  # Check collision
  $ps1Path = Join-Path $shimsRoot "$ShimName.ps1"
  $cmdPath = Join-Path $shimsRoot "$ShimName.cmd"

  if (Test-Path $ps1Path) {
    $existingShim = $null
    foreach ($entry in $registry) {
      $existingShim = $entry.shims | Where-Object { $_.name -eq $ShimName }
      if ($existingShim) {
        if ($entry.name -eq $RegistryEntryName) {
          # Same repo owns it - update in place
          break
        } else {
          # Different repo owns it
          if (-not $ForceOverwrite) {
            Die "Shim '$ShimName' already exists (owned by repo '$($entry.name)'). Use --force to overwrite and reassign to '$RegistryEntryName'."
          }
          # Remove from old repo
          $entry.shims = @($entry.shims | Where-Object { $_.name -ne $ShimName })
          break
        }
      }
    }
  }

  # Build shim metadata
  $shimMeta = @{
    name = $ShimName
    repo = $RegistryEntryName
    type = $ShimType
    exe = $Exe
    baseArgs = $BaseArgs
    cwd = $WorkingDir
    venv = if ($ShimType -eq "venv") { $venvMetadata } else { $null }
  }

  # Generate shim content
  $ps1Content = Generate-ShimPs1 $shimMeta
  $cmdContent = Generate-ShimCmd -ShimName $ShimName -PwshExe $config.defaults.pwshExe

  if ($DryRunMode) {
    Info "DRY RUN - no changes will be made`n"
    Info "Would create:`n  $ps1Path`n  $cmdPath`n"
    Info "Generated .ps1 content:`n---`n$ps1Content`n---"
    return
  }

  # Write shim files
  try {
    [System.IO.File]::WriteAllText($ps1Path, $ps1Content, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($cmdPath, $cmdContent, (New-Object System.Text.UTF8Encoding($false)))
  } catch {
    # Rollback on failure
    if (Test-Path $ps1Path) { Remove-Item $ps1Path -Force -ErrorAction SilentlyContinue }
    if (Test-Path $cmdPath) { Remove-Item $cmdPath -Force -ErrorAction SilentlyContinue }
    Die "Failed to write shim files: $_"
  }

  # Update registry
  $shimEntry = @{
    name = $ShimName
    ps1Path = $ps1Path
    type = $ShimType
    exe = $Exe
    baseArgs = $BaseArgs
    venv = if ($ShimType -eq "venv") { $venvMetadata } else { $null }
    cwd = $WorkingDir
  }

  # Add or update shim in repo
  $attachedEntry.shims = @($attachedEntry.shims | Where-Object { $_.name -ne $ShimName }) + $shimEntry

  try {
    Save-Registry $config $registry
  } catch {
    # Rollback on registry save failure
    Remove-Item $ps1Path -Force -ErrorAction SilentlyContinue
    Remove-Item $cmdPath -Force -ErrorAction SilentlyContinue
    Die "Failed to update registry: $_"
  }

  Ok "Created shim: $ShimName`n   $ps1Path`n   $cmdPath`n   Registered to: $RegistryEntryName ($ShimType)`n"
  Info "You can now run '$ShimName' from anywhere."
}
```

**Step 4: Update module imports in strap.ps1**

Add after existing module imports (around line 76):

```powershell
. (Join-Path $ModulesPath "ShimParser.ps1")
. (Join-Path $ModulesPath "ShimResolver.ps1")
. (Join-Path $ModulesPath "ShimGenerator.ps1")
```

**Step 5: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/InvokeShim.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

**Step 6: Commit**

```powershell
git add modules/Commands/shim.ps1 strap.ps1 tests/powershell/InvokeShim.Tests.ps1
git commit -m "feat(shim): rewrite Invoke-Shim with v3.1 signature

- Add new parameter set (Cmd/Exe/BaseArgs, ShimType, VenvPath, NodeExe, etc.)
- Implement collision policy (same repo = update, different = error unless --force)
- Integrate parser, resolver, and generator modules
- Add dual-file generation (.ps1 + .cmd)
- Add rollback on write or registry save failure
- Validate pwshExe at creation time

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Implement CLI Dispatch for Shim Command

**Files:**
- Modify: `modules/CLI.ps1:50-150`
- Test: `tests/powershell/CLI.Tests.ps1` (create)

**Step 1: Write failing tests for CLI parsing**

Create `tests/powershell/CLI.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../../modules/CLI.ps1"
    . "$PSScriptRoot/../../modules/Core.ps1"
}

Describe "Parse-ShimCommand" {
    It "parses simple shim command" {
        $result = Parse-ShimCommand @("mytool", "--cmd", "mytool --verbose", "--repo", "test")
        $result.ShimName | Should -Be "mytool"
        $result.Cmd | Should -Be "mytool --verbose"
        $result.RegistryEntryName | Should -Be "test"
    }

    It "parses venv shim with auto-detect" {
        $result = Parse-ShimCommand @("mytool", "--venv", "--cmd", "mytool", "--repo", "test")
        $result.ShimType | Should -Be "venv"
        $result.VenvPath | Should -BeNullOrEmpty
    }

    It "parses venv shim with explicit path" {
        $result = Parse-ShimCommand @("mytool", "--venv", "P:\path\.venv", "--cmd", "mytool", "--repo", "test")
        $result.ShimType | Should -Be "venv"
        $result.VenvPath | Should -Be "P:\path\.venv"
    }

    It "parses node shim" {
        $result = Parse-ShimCommand @("pm2", "--node", "--cmd", "P:\tools\pm2\bin\pm2", "--repo", "pm2-local")
        $result.ShimType | Should -Be "node"
    }

    It "parses explicit exe and args" {
        $result = Parse-ShimCommand @("mytool", "--exe", "python", "--args", "-m,mytool", "--repo", "test")
        $result.Exe | Should -Be "python"
        $result.BaseArgs | Should -HaveCount 2
        $result.BaseArgs[0] | Should -Be "-m"
    }

    It "parses working directory flag" {
        $result = Parse-ShimCommand @("mytool", "--cmd", "mytool", "--cwd", "P:\software\test", "--repo", "test")
        $result.WorkingDir | Should -Be "P:\software\test"
    }

    It "parses force flag" {
        $result = Parse-ShimCommand @("mytool", "--cmd", "mytool", "--repo", "test", "--force")
        $result.ForceOverwrite | Should -Be $true
    }

    It "parses dry-run flag" {
        $result = Parse-ShimCommand @("mytool", "--cmd", "mytool", "--repo", "test", "--dry-run")
        $result.DryRunMode | Should -Be $true
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/CLI.Tests.ps1 -Output Detailed"`
Expected: FAIL - Parse-ShimCommand not implemented

**Step 3: Implement CLI parsing in modules/CLI.ps1**

Add to `modules/CLI.ps1`:

```powershell
function Parse-ShimCommand {
  param([string[]] $Args)

  if ($Args.Count -eq 0) {
    Die "shim requires <name>. Usage: strap shim <name> --cmd `"command`" --repo <repo>"
  }

  $result = @{
    ShimName = $Args[0]
    Cmd = $null
    Exe = $null
    BaseArgs = @()
    ShimType = "simple"
    VenvPath = $null
    NodeExe = $null
    WorkingDir = $null
    RegistryEntryName = $null
    Regen = $false
    ForceOverwrite = $false
    DryRunMode = $false
    NonInteractive = $false
  }

  $i = 1
  while ($i -lt $Args.Count) {
    $arg = $Args[$i]

    switch -Regex ($arg) {
      '^--cmd$' {
        $i++
        $result.Cmd = $Args[$i]
      }
      '^--exe$' {
        $i++
        $result.Exe = $Args[$i]
      }
      '^--args$' {
        $i++
        $result.BaseArgs = $Args[$i] -split ','
      }
      '^--venv$' {
        $result.ShimType = "venv"
        # Check if next arg is a path or another flag
        if (($i + 1) -lt $Args.Count -and $Args[$i + 1] -notmatch '^--') {
          $i++
          $result.VenvPath = $Args[$i]
        }
      }
      '^--node$' {
        $result.ShimType = "node"
      }
      '^--node-exe$' {
        $i++
        $result.NodeExe = $Args[$i]
      }
      '^--cwd$' {
        $i++
        $result.WorkingDir = $Args[$i]
      }
      '^--repo$' {
        $i++
        $result.RegistryEntryName = $Args[$i]
      }
      '^--regen$' {
        $result.Regen = $true
      }
      '^--force$' {
        $result.ForceOverwrite = $true
      }
      '^--dry-run$' {
        $result.DryRunMode = $true
      }
      '^--yes$' {
        $result.NonInteractive = $true
      }
      default {
        Die "Unknown shim flag: $arg"
      }
    }

    $i++
  }

  return $result
}
```

Update the main CLI dispatch in `modules/CLI.ps1` to call `Parse-ShimCommand` when `shim` command is invoked.

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/CLI.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

**Step 5: Commit**

```powershell
git add modules/CLI.ps1 tests/powershell/CLI.Tests.ps1
git commit -m "feat(shim): add CLI parsing for shim command

- Implement Parse-ShimCommand for all v3.1 flags
- Handle --venv with optional path value
- Parse --args as comma-separated array
- Support --force, --dry-run, --yes flags

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Implement Doctor Checks (SHIM001-SHIM009)

**Files:**
- Create: `modules/Doctor.ps1`
- Test: `tests/powershell/Doctor.Tests.ps1` (create)

**Step 1: Write failing tests for doctor checks**

Create `tests/powershell/Doctor.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../../modules/Doctor.ps1"
    . "$PSScriptRoot/../../modules/Config.ps1"
    . "$PSScriptRoot/../../modules/Core.ps1"
}

Describe "Invoke-DoctorShimChecks" {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive "strap-test"
        $script:ShimsRoot = Join-Path $TestRoot "bin"
        New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $ShimsRoot -Force | Out-Null

        $script:Config = @{
            roots = @{
                shims = $ShimsRoot
            }
            defaults = @{
                pwshExe = "C:\Program Files\PowerShell\7\pwsh.exe"
                nodeExe = "C:\nvm4w\nodejs\node.exe"
            }
            registry = Join-Path $TestRoot "registry.json"
        }

        $script:Registry = @(
            @{
                name = "test-repo"
                repoPath = Join-Path $TestRoot "test-repo"
                shims = @()
            }
        )

        Mock Test-Path { $true } -ParameterFilter { $Path -like "*pwsh.exe" }
        Mock Test-Path { $true } -ParameterFilter { $Path -like "*node.exe" }
    }

    It "SHIM001: passes when shims dir exists and is on PATH" {
        Mock Test-Path { $true } -ParameterFilter { $Path -eq $ShimsRoot }
        $env:PATH = "$ShimsRoot;C:\other"

        $results = Invoke-DoctorShimChecks -Config $Config -Registry $Registry
        $shim001 = $results | Where-Object { $_.id -eq "SHIM001" }
        $shim001.passed | Should -Be $true
    }

    It "SHIM001: fails when shims dir not on PATH" {
        Mock Test-Path { $true }
        $env:PATH = "C:\other"

        $results = Invoke-DoctorShimChecks -Config $Config -Registry $Registry
        $shim001 = $results | Where-Object { $_.id -eq "SHIM001" }
        $shim001.passed | Should -Be $false
        $shim001.severity | Should -Be "critical"
    }

    It "SHIM002: fails when shim file missing" {
        $Registry[0].shims = @(
            @{
                name = "missing"
                ps1Path = Join-Path $ShimsRoot "missing.ps1"
            }
        )
        Mock Test-Path { $false } -ParameterFilter { $Path -like "*missing.ps1" }

        $results = Invoke-DoctorShimChecks -Config $Config -Registry $Registry
        $shim002 = $results | Where-Object { $_.id -eq "SHIM002" -and $_.passed -eq $false }
        $shim002 | Should -Not -BeNullOrEmpty
        $shim002.severity | Should -Be "error"
    }

    It "SHIM008: fails when .cmd launcher missing" {
        $ps1Path = Join-Path $ShimsRoot "mytool.ps1"
        New-Item -ItemType File -Path $ps1Path -Force | Out-Null

        $Registry[0].shims = @(
            @{
                name = "mytool"
                ps1Path = $ps1Path
            }
        )

        $results = Invoke-DoctorShimChecks -Config $Config -Registry $Registry
        $shim008 = $results | Where-Object { $_.id -eq "SHIM008" -and $_.passed -eq $false }
        $shim008 | Should -Not -BeNullOrEmpty
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/Doctor.Tests.ps1 -Output Detailed"`
Expected: FAIL - doctor functions not implemented

**Step 3: Implement Doctor.ps1**

Create `modules/Doctor.ps1`:

```powershell
# Doctor.ps1
# Health checks for strap shims

# Dot-source Core for utility functions
. "$PSScriptRoot\Core.ps1"

function Invoke-DoctorShimChecks {
  param(
    [Parameter(Mandatory)]
    [object] $Config,
    [Parameter(Mandatory)]
    [array] $Registry,
    [switch] $Deep
  )

  $results = @()

  # SHIM001: Shims directory on PATH
  $shimsRoot = $Config.roots.shims

  if (-not (Test-Path $shimsRoot)) {
    $results += @{
      id = "SHIM001"
      check = "Shims directory exists and is on PATH"
      severity = "critical"
      passed = $false
      message = "Shims directory does not exist: $shimsRoot"
      fix = "New-Item -ItemType Directory -Path '$shimsRoot'"
    }
  } else {
    $pathEntries = $env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') }
    $shimsNormalized = $shimsRoot.TrimEnd('\')

    if ($shimsNormalized -notin $pathEntries) {
      $fix = @"
`$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
`$entries = `$userPath -split ';' | Where-Object { `$_.TrimEnd('\') -ne '$shimsNormalized' }
`$newPath = '$shimsRoot;' + (`$entries -join ';')
[Environment]::SetEnvironmentVariable('PATH', `$newPath, 'User')
"@
      $results += @{
        id = "SHIM001"
        check = "Shims directory on PATH"
        severity = "critical"
        passed = $false
        message = "Shims directory not on PATH: $shimsRoot"
        fix = $fix
      }
    } else {
      $results += @{
        id = "SHIM001"
        check = "Shims directory on PATH"
        severity = "critical"
        passed = $true
      }
    }
  }

  # SHIM009: Config exe paths valid
  if ($Config.defaults.pwshExe) {
    if (-not (Test-Path $Config.defaults.pwshExe)) {
      $results += @{
        id = "SHIM009"
        check = "Config pwshExe valid"
        severity = "warning"
        passed = $false
        message = "defaults.pwshExe not found: $($Config.defaults.pwshExe)"
        fix = "Update strap config or install PowerShell 7"
      }
    }
  }

  if ($Config.defaults.nodeExe) {
    if (-not (Test-Path $Config.defaults.nodeExe)) {
      $results += @{
        id = "SHIM009"
        check = "Config nodeExe valid"
        severity = "warning"
        passed = $false
        message = "defaults.nodeExe not found: $($Config.defaults.nodeExe)"
        fix = "Update strap config with correct node path"
      }
    }
  }

  # Per-shim checks
  foreach ($entry in $Registry) {
    foreach ($shim in $entry.shims) {
      $shimName = $shim.name
      $ps1Path = $shim.ps1Path
      $cmdPath = $ps1Path -replace '\.ps1$', '.cmd'

      # SHIM002: Shim file exists
      if (-not (Test-Path $ps1Path)) {
        $results += @{
          id = "SHIM002"
          check = "Shim file exists: $shimName"
          severity = "error"
          passed = $false
          message = "Shim file not found: $ps1Path"
          fix = "Remove from registry or regenerate shim"
        }
        continue
      }

      # SHIM008: Launcher pair complete
      if (-not (Test-Path $cmdPath)) {
        $results += @{
          id = "SHIM008"
          check = "Launcher pair complete: $shimName"
          severity = "warning"
          passed = $false
          message = "Missing .cmd launcher for $shimName"
          fix = "strap shim $shimName --repo $($entry.name) --force"
        }
      }

      # SHIM003: Exe resolvable
      $exe = $shim.exe
      $type = $shim.type

      $exeCheckPassed = $true
      $exeMessage = $null
      $exeFix = $null

      switch ($type) {
        "venv" {
          if ([System.IO.Path]::IsPathRooted($exe)) {
            if (-not (Test-Path $exe)) {
              $exeCheckPassed = $false
              $exeMessage = "Venv exe not found: $exe"
              $exeFix = "Reinstall package in venv or regenerate shim"
            }
          }
        }
        "node" {
          if (-not [System.IO.Path]::IsPathRooted($exe)) {
            $exeCheckPassed = $false
            $exeMessage = "Node shim exe should be absolute path: $exe"
          } elseif (-not (Test-Path $exe)) {
            $exeCheckPassed = $false
            $exeMessage = "Node exe not found: $exe"
            $exeFix = "Update config.defaults.nodeExe or regenerate shim"
          }

          # Check JS entrypoint
          if ($exeCheckPassed -and $shim.baseArgs.Count -gt 0) {
            $jsEntry = $shim.baseArgs[0]
            if ([System.IO.Path]::IsPathRooted($jsEntry) -and -not (Test-Path $jsEntry)) {
              $exeCheckPassed = $false
              $exeMessage = "Node entrypoint not found: $jsEntry"
              $exeFix = "npm install in _node-tools directory"
            }
          }
        }
        "simple" {
          if ([System.IO.Path]::IsPathRooted($exe)) {
            if (-not (Test-Path $exe)) {
              $exeCheckPassed = $false
              $exeMessage = "Exe path not found: $exe"
            }
          } else {
            $found = Get-Command $exe -ErrorAction SilentlyContinue
            if (-not $found) {
              $exeCheckPassed = $false
              $exeMessage = "Exe not found on PATH: $exe"
              $exeFix = "Install $exe or use absolute path"
            }
          }
        }
      }

      if (-not $exeCheckPassed) {
        $results += @{
          id = "SHIM003"
          check = "Exe resolvable: $shimName"
          severity = "error"
          passed = $false
          message = $exeMessage
          fix = $exeFix
        }
      }

      # SHIM007: Venv is valid
      if ($type -eq "venv" -and $shim.venv) {
        $pythonExe = Join-Path $shim.venv "Scripts\python.exe"
        if (-not (Test-Path $pythonExe)) {
          $results += @{
            id = "SHIM007"
            check = "Venv valid: $shimName"
            severity = "error"
            passed = $false
            message = "Venv missing or invalid: $($shim.venv)"
            fix = "cd $($entry.repoPath); python -m venv .venv"
          }
        }
      }
    }
  }

  return $results
}

function Format-DoctorResults {
  param([array] $Results)

  $grouped = $Results | Group-Object severity

  $output = "=== SHIM HEALTH ===`n`n"

  foreach ($group in $grouped) {
    $severity = $group.Name.ToUpper()
    $output += "[$severity]`n"

    foreach ($result in $group.Group) {
      if (-not $result.passed) {
        $output += "  $($result.check)`n"
        $output += "    $($result.message)`n"
        if ($result.fix) {
          $output += "    Fix: $($result.fix)`n"
        }
        $output += "`n"
      }
    }
  }

  $passed = ($Results | Where-Object { $_.passed }).Count
  $failed = ($Results | Where-Object { -not $_.passed }).Count
  $output += "Passed: $passed | Failed: $failed"

  return $output
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/Doctor.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

**Step 5: Commit**

```powershell
git add modules/Doctor.ps1 tests/powershell/Doctor.Tests.ps1
git commit -m "feat(shim): add doctor checks SHIM001-SHIM009

- Implement SHIM001 (shims dir on PATH) with idempotent fix
- Implement SHIM002 (shim file exists)
- Implement SHIM003 (exe resolvable) for all types
- Implement SHIM007 (venv valid)
- Implement SHIM008 (launcher pair complete)
- Implement SHIM009 (config exe paths valid)
- Add Format-DoctorResults for output

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Implement Regen Command

**Files:**
- Create: `modules/Commands/regen.ps1` (or add to shim.ps1)
- Test: `tests/powershell/RegenShims.Tests.ps1` (create)

**Step 1: Write failing tests for regen**

Create `tests/powershell/RegenShims.Tests.ps1`:

```powershell
BeforeAll {
    $commandsPath = Join-Path "$PSScriptRoot\..\.." "modules\Commands"
    Get-ChildItem -Path $commandsPath -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
    . "$PSScriptRoot/../../modules/Config.ps1"
    . "$PSScriptRoot/../../modules/ShimGenerator.ps1"
    . "$PSScriptRoot/../../modules/Core.ps1"
}

Describe "Invoke-ShimRegen" {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive "strap-test"
        $script:ShimsRoot = Join-Path $TestRoot "bin"
        New-Item -ItemType Directory -Path $ShimsRoot -Force | Out-Null

        $configContent = @{
            roots = @{ shims = $ShimsRoot }
            defaults = @{ pwshExe = "C:\pwsh.exe"; nodeExe = "C:\node.exe" }
            registry = Join-Path $TestRoot "registry.json"
        } | ConvertTo-Json -Depth 10
        $configContent | Set-Content (Join-Path $TestRoot "config.json") -NoNewline

        $registryContent = @{
            version = 2
            repos = @(
                @{
                    name = "test-repo"
                    repoPath = Join-Path $TestRoot "test-repo"
                    shims = @(
                        @{
                            name = "shim1"
                            ps1Path = Join-Path $ShimsRoot "shim1.ps1"
                            type = "simple"
                            exe = "test.exe"
                            baseArgs = @()
                        }
                        @{
                            name = "shim2"
                            ps1Path = Join-Path $ShimsRoot "shim2.ps1"
                            type = "simple"
                            exe = "test2.exe"
                            baseArgs = @()
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10
        $registryContent | Set-Content (Join-Path $TestRoot "registry.json") -NoNewline

        Mock Test-Path { $true } -ParameterFilter { $Path -like "*pwsh.exe" }
    }

    It "regenerates all shims for a repo" {
        Invoke-ShimRegen -RepoName "test-repo" -StrapRootPath $TestRoot

        Test-Path (Join-Path $ShimsRoot "shim1.ps1") | Should -Be $true
        Test-Path (Join-Path $ShimsRoot "shim1.cmd") | Should -Be $true
        Test-Path (Join-Path $ShimsRoot "shim2.ps1") | Should -Be $true
        Test-Path (Join-Path $ShimsRoot "shim2.cmd") | Should -Be $true
    }

    It "errors on unknown repo" {
        { Invoke-ShimRegen -RepoName "nonexistent" -StrapRootPath $TestRoot } | Should -Throw "*not found*"
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester tests/powershell/RegenShims.Tests.ps1 -Output Detailed"`
Expected: FAIL - Invoke-ShimRegen not implemented

**Step 3: Implement Invoke-ShimRegen in modules/Commands/shim.ps1**

Add to `modules/Commands/shim.ps1` (or create separate regen.ps1 file):

```powershell
function Invoke-ShimRegen {
  param(
    [Parameter(Mandatory)]
    [string] $RepoName,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Find repo
  $repo = $registry | Where-Object { $_.name -eq $RepoName }
  if (-not $repo) {
    Die "Registry entry not found: '$RepoName'. Use 'strap list' to see all entries."
  }

  if ($repo.shims.Count -eq 0) {
    Info "No shims registered for repo '$RepoName'."
    return
  }

  Info "Regenerating $($repo.shims.Count) shim(s) for repo '$RepoName'..."

  $shimsRoot = $config.roots.shims
  $pwshExe = $config.defaults.pwshExe

  foreach ($shim in $repo.shims) {
    $shimName = $shim.name
    $ps1Path = Join-Path $shimsRoot "$shimName.ps1"
    $cmdPath = Join-Path $shimsRoot "$shimName.cmd"

    # Delete existing files
    if (Test-Path $ps1Path) { Remove-Item $ps1Path -Force }
    if (Test-Path $cmdPath) { Remove-Item $cmdPath -Force }

    # Generate new files
    $shimMeta = @{
      name = $shimName
      repo = $RepoName
      type = $shim.type
      exe = $shim.exe
      baseArgs = $shim.baseArgs
      cwd = $shim.cwd
      venv = $shim.venv
    }

    $ps1Content = Generate-ShimPs1 $shimMeta
    $cmdContent = Generate-ShimCmd -ShimName $shimName -PwshExe $pwshExe

    [System.IO.File]::WriteAllText($ps1Path, $ps1Content, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($cmdPath, $cmdContent, (New-Object System.Text.UTF8Encoding($false)))

    Ok "  Regenerated: $shimName"
  }

  Ok "`nRegeneration complete for repo '$RepoName'."
}
```

**Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester tests/powershell/RegenShims.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

**Step 5: Commit**

```powershell
git add modules/Commands/shim.ps1 tests/powershell/RegenShims.Tests.ps1
git commit -m "feat(shim): add regen command to rebuild all shims for a repo

- Implement Invoke-ShimRegen
- Delete and recreate .ps1 + .cmd files from registry metadata
- Error on unknown repo name

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Update Main CLI Dispatcher

**Files:**
- Modify: `strap.ps1:100-200`
- Modify: `modules/CLI.ps1:1-50`

**Step 1: Update CLI dispatcher to route shim command**

In `modules/CLI.ps1`, update the main dispatch logic to handle the `shim` command:

```powershell
function Invoke-StrapCommand {
  param(
    [string] $Command,
    [string[]] $Args,
    [string] $StrapRootPath
  )

  switch ($Command) {
    "shim" {
      if ($Args.Count -gt 0 -and $Args[0] -eq "--regen") {
        # Regen mode: strap shim --regen <repo>
        $repoName = if ($Args.Count -gt 1) { $Args[1] } else { Die "regen requires repo name" }
        Invoke-ShimRegen -RepoName $repoName -StrapRootPath $StrapRootPath
      } else {
        # Create mode: parse and invoke
        $parsed = Parse-ShimCommand $Args
        $parsed.StrapRootPath = $StrapRootPath
        Invoke-Shim @parsed
      }
    }
    "doctor" {
      $config = Load-Config $StrapRootPath
      $registry = Load-Registry $config
      $results = Invoke-DoctorShimChecks -Config $config -Registry $registry
      $output = Format-DoctorResults $results
      Write-Host $output
    }
    default {
      Die "Unknown command: $Command"
    }
  }
}
```

**Step 2: Update strap.ps1 to call CLI dispatcher**

Update the main script logic in `strap.ps1` to route the `shim` command:

```powershell
# Determine strap root
$StrapRoot = if ($StrapRootPath) { $StrapRootPath } else { $PSScriptRoot }

# Command dispatch
if ($RepoName -eq "shim") {
  # strap shim <args>
  Invoke-StrapCommand -Command "shim" -Args $ExtraArgs -StrapRootPath $StrapRoot
} elseif ($RepoName -eq "doctor") {
  # strap doctor
  Invoke-StrapCommand -Command "doctor" -Args $ExtraArgs -StrapRootPath $StrapRoot
} else {
  # ... existing command logic
}
```

**Step 3: Commit**

```powershell
git add strap.ps1 modules/CLI.ps1
git commit -m "feat(shim): wire up CLI dispatcher for shim and doctor commands

- Route 'strap shim' to shim creation or regen
- Route 'strap doctor' to health checks
- Handle --regen flag specially for shim regeneration

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 10: Integration Testing and Documentation

**Files:**
- Create: `tests/powershell/ShimIntegration.Tests.ps1`
- Create: `docs/shim-v3.1-usage.md`

**Step 1: Write integration tests**

Create `tests/powershell/ShimIntegration.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../../strap.ps1"
}

Describe "Shim v3.1 Integration" {
    BeforeEach {
        $script:TestRoot = Join-Path $TestDrive "integration-test"
        New-Item -ItemType Directory -Path $TestRoot -Force | Out-Null

        # Setup test environment
        # ... (create config, registry, test repos)
    }

    It "creates simple shim end-to-end" {
        # Test full workflow: create -> verify files -> verify registry
    }

    It "creates venv shim with auto-detect" {
        # Test venv auto-detection and direct invocation
    }

    It "creates node shim with pinned exe" {
        # Test node shim generation
    }

    It "regenerates all shims for a repo" {
        # Test regen workflow
    }

    It "doctor detects missing shim files" {
        # Test doctor checks
    }
}
```

**Step 2: Run integration tests**

Run: `pwsh -Command "Invoke-Pester tests/powershell/ShimIntegration.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

**Step 3: Write usage documentation**

Create `docs/shim-v3.1-usage.md` with examples from the spec:
- Basic usage examples
- Common workflows
- Doctor usage
- Troubleshooting

**Step 4: Commit**

```powershell
git add tests/powershell/ShimIntegration.Tests.ps1 docs/shim-v3.1-usage.md
git commit -m "test(shim): add integration tests and usage documentation

- Add end-to-end integration tests for shim v3.1
- Document usage examples and workflows
- Add troubleshooting guide for doctor checks

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 11: Migrate Existing Config and Test on Real Repos

**Files:**
- Modify: `config.json`
- Test: Manual testing on actual repos

**Step 1: Update production config.json**

Update `P:\software\_strap\config.json` with new v3.1 fields:

```json
{
  "roots": {
    "software": "P:\\software",
    "tools": "P:\\software\\_scripts",
    "shims": "P:\\software\\bin",
    "nodeTools": "P:\\software\\_node-tools",
    "archive": "P:\\software\\_archive"
  },
  "defaults": {
    "pwshExe": "C:\\Program Files\\PowerShell\\7\\pwsh.exe",
    "nodeExe": "C:\\nvm4w\\nodejs\\node.exe"
  },
  "registry": "P:\\software\\_strap\\build\\registry.json"
}
```

**Step 2: Create shims directory**

Run: `New-Item -ItemType Directory -Path "P:\software\bin" -Force`

**Step 3: Test shim creation on chinvex**

Run:
```powershell
cd P:\software\_strap
.\strap.ps1 shim chinvex --venv --cmd "chinvex" --repo chinvex
.\strap.ps1 shim chinvex-mcp --venv --cmd "chinvex-mcp" --repo chinvex
```

Expected: Shim files created in `P:\software\bin\`

**Step 4: Test shim invocation**

Run:
```powershell
chinvex --version
```

Expected: Command works from any directory

**Step 5: Run doctor**

Run:
```powershell
.\strap.ps1 doctor
```

Expected: SHIM001-SHIM009 checks pass

**Step 6: Commit**

```powershell
git add config.json
git commit -m "chore(shim): migrate production config to v3.1 schema

- Update config.json with shims, nodeTools, defaults
- Point registry to build/registry.json
- Ready for shim v3.1 usage on real repos

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Post-Implementation Verification

After completing all tasks:

1. Run full test suite: `pwsh -Command "Invoke-Pester tests/powershell -Output Detailed"`
2. Verify all doctor checks pass: `.\strap.ps1 doctor`
3. Create shims for all managed repos (chinvex, etc.)
4. Verify shims work from PowerShell, cmd.exe, and Task Scheduler contexts
5. Test regen command on one repo
6. Update project README with v3.1 features

---

## Notes for Implementation

- **TDD approach:** Write failing test → Run to verify failure → Implement → Run to verify pass → Commit
- **Frequent commits:** One commit per step (test + implementation)
- **DRY:** Reuse modules across functions
- **Error handling:** Use `Die` for fatal errors, `Warn` for warnings
- **File encoding:** Always UTF-8 without BOM
- **Rollback:** Delete created files if registry update fails
- **Validation:** Validate inputs early (shim name, pwshExe existence, etc.)

---

## Dependencies Between Tasks

- Task 2 (Parser) → Task 5 (Invoke-Shim)
- Task 3 (Resolver) → Task 5 (Invoke-Shim)
- Task 4 (Generator) → Task 5 (Invoke-Shim), Task 8 (Regen)
- Task 1 (Config/Registry) → All other tasks
- Task 5 (Invoke-Shim) → Task 6 (CLI Dispatch)
- Task 7 (Doctor) → Task 9 (CLI Dispatcher)
- Task 8 (Regen) → Task 9 (CLI Dispatcher)

Execute in order: 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11
