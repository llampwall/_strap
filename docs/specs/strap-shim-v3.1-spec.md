# Strap Shim v3.1 Specification

> **Status:** Draft  
> **Purpose:** Define the unified shim system for strap-managed tools  
> **Solves:** "pm2 not found", "wrong python", "venv not activated", "PATH chaos"

---

## Problem Statement

Current state has multiple failure modes:

1. **PATH pollution** - Multiple directories on PATH, duplicates, exceeds 2047 char limit
2. **Wrong binary invoked** - System Python vs venv Python vs conda Python
3. **Venv not activated** - Commands fail because dependencies aren't visible
4. **Node globals drift** - `pm2` installed somewhere, maybe, depending on npm/nvm state
5. **Scheduled tasks can't find tools** - Task Scheduler doesn't have full PATH context
6. **cmd.exe vs PowerShell differences** - `.ps1` files don't run from cmd

## Solution

**One directory on PATH: `P:\software\bin`**

Everything else becomes an implementation detail behind shims. Shims handle:
- Direct venv binary invocation (no activation scripts)
- Working directory
- Correct binary resolution
- Argument forwarding

---

## Architecture

### Directory Structure

```
P:\software\bin\              ← Single PATH entry
├── chinvex.ps1              ← Logic (direct venv exe invocation)
├── chinvex.cmd              ← Launcher (calls .ps1 from any context)
├── chinvex-mcp.ps1
├── chinvex-mcp.cmd
├── pm2.ps1                  ← Node tool (vendored, pinned node)
├── pm2.cmd
├── strap.ps1                ← Points to _scripts location
├── strap.cmd
└── ...
```

### Dual-File Shims

Every shim generates **two files**:

| File | Purpose | Invoked From |
|------|---------|--------------|
| `<n>.ps1` | Contains actual logic | PowerShell |
| `<n>.cmd` | Thin launcher that calls .ps1 | cmd.exe, Task Scheduler, batch files, other tools |

This ensures `chinvex` works from PowerShell, cmd.exe, Task Scheduler, batch scripts, and any other context.

---

## Config

### strap.config.json

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
  }
}
```

**Note:** `defaults.pwshExe` and `defaults.nodeExe` are machine-pinned paths. Shims use these to avoid PATH drift in restricted contexts (Task Scheduler, etc.).

---

## Shim Types

| Type | Flag | Behavior |
|------|------|----------|
| `simple` | (default) | Direct command passthrough |
| `venv` | `--venv` | Direct venv binary invocation (no activation) |
| `node` | `--node` | Vendored node tool with pinned node exe |

---

## Registry Schema

### Registry Location & Structure

Registry file: `<strap-root>/build/registry.json`

```json
{
  "version": 1,
  "repos": [
    {
      "name": "chinvex",
      "repoPath": "P:\\software\\chinvex",
      "scope": "software",
      "shims": [...]
    }
  ]
}
```

**Repo identification:** By `name` field (unique, case-insensitive). The `--repo` flag matches against this.

### Shim Entry Structure

```json
{
  "name": "chinvex",
  "repoPath": "P:\\software\\chinvex",
  "shims": [
    {
      "name": "chinvex",
      "ps1Path": "P:\\software\\bin\\chinvex.ps1",
      "type": "venv",
      "exe": "chinvex",
      "baseArgs": [],
      "venv": "P:\\software\\chinvex\\.venv",
      "cwd": null
    },
    {
      "name": "chinvex-mcp",
      "ps1Path": "P:\\software\\bin\\chinvex-mcp.ps1",
      "type": "venv",
      "exe": "chinvex-mcp",
      "baseArgs": [],
      "venv": "P:\\software\\chinvex\\.venv",
      "cwd": null
    }
  ]
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Shim command name (creates `<n>.ps1` and `<n>.cmd`) |
| `ps1Path` | string | yes | Full path to `.ps1` file (`.cmd` is derived) |
| `type` | enum | yes | `simple`, `venv`, or `node` |
| `exe` | string | yes | Executable to run (resolved at generation time) |
| `baseArgs` | string[] | yes | Arguments prepended before user args |
| `venv` | string | no | Path to venv (required if type=venv) |
| `cwd` | string | no | Working directory override |

**Resolution at generation time:**
- `venv` type: `exe` becomes `<venv>\Scripts\<exe>.exe` or `<venv>\Scripts\python.exe`
- `node` type: `exe` becomes resolved node path, `baseArgs[0]` is JS entrypoint
- `simple` type: `exe` stored as-is

### Examples

**Python module in venv:**
```json
{
  "name": "mytool",
  "ps1Path": "P:\\software\\bin\\mytool.ps1",
  "type": "venv",
  "exe": "python",
  "baseArgs": ["-m", "mytool"],
  "venv": "P:\\software\\mytool\\.venv",
  "cwd": null
}
```

**Venv script entry point:**
```json
{
  "name": "chinvex",
  "ps1Path": "P:\\software\\bin\\chinvex.ps1",
  "type": "venv",
  "exe": "chinvex",
  "baseArgs": [],
  "venv": "P:\\software\\chinvex\\.venv",
  "cwd": null
}
```

**Vendored Node tool:**
```json
{
  "name": "pm2",
  "ps1Path": "P:\\software\\bin\\pm2.ps1",
  "type": "node",
  "exe": "C:\\nvm4w\\nodejs\\node.exe",
  "baseArgs": ["P:\\software\\_node-tools\\pm2\\node_modules\\pm2\\bin\\pm2"],
  "cwd": null
}
```

**Note:** For node shims, `exe` is always the resolved node executable path (from `config.defaults.nodeExe` or per-shim override), and `baseArgs[0]` is the JS entrypoint.

**Simple passthrough with cwd:**
```json
{
  "name": "pm2-services",
  "ps1Path": "P:\\software\\bin\\pm2-services.ps1",
  "type": "simple",
  "exe": "pm2",
  "baseArgs": ["start", "ecosystem.config.js"],
  "cwd": "P:\\software\\chinvex"
}
```

---

## Generated Shim Templates

### Launcher (.cmd) - Same for All Types

Uses full path to pwsh.exe to avoid PATH issues in Task Scheduler:

```bat
@echo off
"<pwshExe>" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0<n>.ps1" %*
exit /b %errorlevel%
```

Example with resolved path:
```bat
@echo off
"C:\Program Files\PowerShell\7\pwsh.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0chinvex.ps1" %*
exit /b %errorlevel%
```

### Simple Type (.ps1)

```powershell
# Generated by strap shim - do not edit
# Repo: <repo> | Type: simple
$ErrorActionPreference = "Stop"
$exe = "<exe>"
$baseArgs = @(<baseArgs>)
& $exe @baseArgs @args
$ec = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
exit $ec
```

### Venv Type (.ps1) - Direct Invocation (No Activation)

**Key principle:** Call the venv's python/script directly. No `Activate.ps1` needed.

```powershell
# Generated by strap shim - do not edit
# Repo: <repo> | Type: venv | Venv: <venv>
$ErrorActionPreference = "Stop"
$venv = "<venv>"
$exe = "<resolvedExe>"
$baseArgs = @(<baseArgs>)
& $exe @baseArgs @args
$ec = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
exit $ec
```

**Exe resolution rules for venv type:**

| `exe` value | Resolved to |
|-------------|-------------|
| `python` | `<venv>\Scripts\python.exe` |
| `<scriptname>` | `<venv>\Scripts\<scriptname>.exe` |

**Example: chinvex (script entry point)**
```powershell
# Generated by strap shim - do not edit
# Repo: chinvex | Type: venv | Venv: P:\software\chinvex\.venv
$ErrorActionPreference = "Stop"
$venv = "P:\software\chinvex\.venv"
$exe = "P:\software\chinvex\.venv\Scripts\chinvex.exe"
$baseArgs = @()
& $exe @baseArgs @args
$ec = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
exit $ec
```

**Example: python -m mytool**
```powershell
# Generated by strap shim - do not edit
# Repo: mytool | Type: venv | Venv: P:\software\mytool\.venv
$ErrorActionPreference = "Stop"
$venv = "P:\software\mytool\.venv"
$exe = "P:\software\mytool\.venv\Scripts\python.exe"
$baseArgs = @("-m", "mytool")
& $exe @baseArgs @args
$ec = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
exit $ec
```

### Node Type (.ps1) - Pinned Node Exe

```powershell
# Generated by strap shim - do not edit
# Repo: <repo> | Type: node
$ErrorActionPreference = "Stop"
$exe = "<nodeExe>"
$baseArgs = @("<path-to-js-bin>")
& $exe @baseArgs @args
$ec = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
exit $ec
```

**Example: pm2**
```powershell
# Generated by strap shim - do not edit
# Repo: pm2 | Type: node
$ErrorActionPreference = "Stop"
$exe = "C:\nvm4w\nodejs\node.exe"
$baseArgs = @("P:\software\_node-tools\pm2\node_modules\pm2\bin\pm2")
& $exe @baseArgs @args
$ec = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
exit $ec
```

### With Working Directory (.ps1)

```powershell
# Generated by strap shim - do not edit
# Repo: <repo> | Type: <type> | Cwd: <cwd>
$ErrorActionPreference = "Stop"
$ec = 0
Push-Location "<cwd>"
try {
    $exe = "<resolvedExe>"
    $baseArgs = @(<baseArgs>)
    & $exe @baseArgs @args
    $ec = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
} finally {
    Pop-Location
}
exit $ec
```

---

## CLI Interface

### Invoke-Shim Signature

```powershell
function Invoke-Shim {
  param(
    [Parameter(Mandatory)]
    [string] $ShimName,
    
    # Command specification (mutually exclusive approaches)
    [string] $Cmd,                    # Tokenized or JSON array form
    [string] $Exe,                    # Explicit: executable name/path
    [string[]] $BaseArgs,             # Explicit: base arguments array
    
    # Shim configuration
    [ValidateSet("simple", "venv", "node")]
    [string] $ShimType = "simple",
    [string] $VenvPath,               # Override venv location (default: auto-detect)
    [string] $NodeExe,                # Override node exe for generation (default: config.defaults.nodeExe)
    [string] $WorkingDir,             # Working directory override
    
    # Context
    [string] $RegistryEntryName,      # --repo flag
    
    # Regeneration
    [switch] $Regen,                  # Regenerate all shims for specified repo
    
    # Behavior
    [switch] $ForceOverwrite,
    [switch] $DryRunMode,
    [switch] $NonInteractive,
    [string] $StrapRootPath
  )
}
```

**Note:** `--node-exe` is a generation-time override. The resolved path is stored in the registry's `exe` field, not as a separate `nodeExe` field.

### Collision Policy

When a shim name already exists:

| Condition | Behavior |
|-----------|----------|
| Same repo owns existing shim | Update in place (no `--force` needed) |
| Different repo owns existing shim | **Error** - must use `--force` |
| `--force` flag provided | Overwrite and reassign to new repo |

**Note:** "Same repo owns existing shim" means the shim is already in that repo's `shims` array in the registry. This allows iterating on shim configuration without `--force` spam.

Error message example:
```
Error: Shim 'mytool' already exists (owned by repo 'other-tool').
Use --force to overwrite and reassign to 'new-tool'.
```

### Usage Examples

```powershell
# Simple shim
strap shim mytool --cmd "mytool" --repo mytool

# Venv shim with auto-detection
strap shim chinvex --venv --cmd "chinvex" --repo chinvex

# Venv shim with explicit venv path
strap shim chinvex --venv "P:\software\chinvex\.venv" --cmd "chinvex" --repo chinvex

# Python module in venv
strap shim mytool --venv --cmd "python -m mytool" --repo mytool

# JSON array form for complex args
strap shim mytool --venv --cmd '["python", "-m", "mytool", "--config", "path with spaces"]' --repo mytool

# Explicit exe/args (complex cases)
strap shim mytool --venv --exe python --args "-m","mytool" --repo mytool

# With working directory
strap shim pm2-services --cmd "pm2 start ecosystem.config.js" --cwd "P:\software\chinvex" --repo chinvex

# Node tool (vendored)
# For --node type, --cmd specifies the JS entrypoint; node exe comes from config
strap shim pm2 --node --cmd "P:\software\_node-tools\pm2\node_modules\pm2\bin\pm2" --repo pm2-local

# Node tool with explicit node exe override
strap shim pm2 --node --cmd "P:\software\_node-tools\pm2\node_modules\pm2\bin\pm2" --node-exe "C:\custom\node.exe" --repo pm2-local

# Force overwrite existing shim owned by different repo
strap shim chinvex --venv --cmd "chinvex" --repo chinvex --force

# Regenerate all shims for a repo (deletes and recreates from registry)
strap shim --regen chinvex

# Dry run
strap shim chinvex --venv --cmd "chinvex" --repo chinvex --dry-run
```

---

## Command Parsing

`--cmd` accepts two forms:

### 1. Simple String (Tokenized via PowerShell)

```powershell
strap shim mytool --cmd "python -m mytool" --venv --repo mytool
```

Parsing uses PowerShell's built-in tokenizer:

```powershell
function Parse-CommandLine {
  param([string] $CommandLine)
  
  # Use PowerShell's parser for proper tokenization
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
    throw "Shims only support direct exec + args. Use a wrapper script and shim that instead."
  }
  
  # Extract string tokens (skip '&' operator)
  # Prefer .Value (unquoted) over .Text (may include quotes)
  $parts = $tokens | 
    Where-Object { $_.Kind -eq 'StringLiteral' -or $_.Kind -eq 'Generic' } |
    ForEach-Object { 
      if ($_.Value) { $_.Value } else { $_.Text }
    }
  
  if ($parts.Count -eq 0) {
    throw "Could not parse command: $CommandLine"
  }
  
  return @{
    exe = $parts[0]
    baseArgs = @($parts | Select-Object -Skip 1)
  }
}
```

This handles:
- Quoted strings with spaces: `"python" "-m" "my tool"`
- Mixed quoting: `python -m "my tool"`
- Paths with spaces: `"C:\Program Files\tool.exe" --flag`

**Safety rule:** Shims are exec primitives, not shell scripts. If the tokenizer finds any of these, error immediately:

| Blocked Token | Reason |
|---------------|--------|
| `\|` (pipe) | No pipelines in shims |
| `;` (semicolon) | No command chaining |
| `>`, `>>`, `2>` | No redirects |
| `&` (background) | No background exec |

Error message: `"Shims only support direct exec + args. Use a wrapper script and shim that instead."`

### 2. JSON Array (Explicit)

```powershell
strap shim mytool --cmd '["python", "-m", "mytool", "--config", "path with spaces"]' --venv --repo mytool
```

Parsing:

```powershell
function Parse-CommandLine {
  param([string] $CommandLine)
  
  $trimmed = $CommandLine.Trim()
  
  # Detect JSON array form
  if ($trimmed.StartsWith('[')) {
    try {
      $parts = $trimmed | ConvertFrom-Json
      if ($parts.Count -eq 0) {
        throw "Empty command array"
      }
      return @{
        exe = $parts[0]
        baseArgs = @($parts | Select-Object -Skip 1)
      }
    } catch {
      throw "Invalid JSON array: $CommandLine"
    }
  }
  
  # Otherwise use PowerShell tokenizer
  # ... (tokenizer code above)
}
```

**Important:** Parsing happens once at shim creation. The shim file and registry store the parsed form. No runtime parsing.

**Type-specific `--cmd` interpretation:**

| Type | `--cmd` value | Result |
|------|---------------|--------|
| `simple` | Full command | Parsed into `exe` + `baseArgs` |
| `venv` | Full command | Parsed, then `exe` resolved to venv path |
| `node` | JS entrypoint path | Becomes `baseArgs[0]`, `exe` set to resolved node path |

---

## Venv Auto-Detection

When `--venv` is passed without explicit path:

```powershell
$repoPath = $attachedEntry.repoPath
$venvCandidates = @(".venv", "venv", ".virtualenv")

$detectedVenv = $null
foreach ($candidate in $venvCandidates) {
  $testPath = Join-Path $repoPath $candidate
  $pythonExe = Join-Path $testPath "Scripts\python.exe"
  if (Test-Path $pythonExe) {
    $detectedVenv = $testPath
    break
  }
}

if (-not $detectedVenv) {
  Die "No venv found in $repoPath. Use --venv <path> to specify explicitly."
}
```

---

## Venv Exe Resolution

At shim generation time, resolve the exe to a full path:

```powershell
function Resolve-VenvExe {
  param(
    [string] $Exe,
    [string] $VenvPath
  )
  
  $scriptsDir = Join-Path $VenvPath "Scripts"
  
  # Special case: python
  if ($Exe -eq "python") {
    return Join-Path $scriptsDir "python.exe"
  }
  
  # Try as script in venv
  $scriptExe = Join-Path $scriptsDir "$Exe.exe"
  if (Test-Path $scriptExe) {
    return $scriptExe
  }
  
  # Fallback: assume it's installed in venv
  # (will be validated by doctor)
  return $scriptExe
}
```

**Generation-time behavior:**

| Condition | Action |
|-----------|--------|
| Resolved exe exists | Write shim, success |
| Resolved exe missing | Write shim, **print warning**, rely on doctor for enforcement |

Warning message: `"Warning: $exe not found in venv. Shim created but may not work until package is installed."`

This prevents "strap shim succeeded but is dead on arrival" confusion while still allowing shim creation before package installation.

---

## Node Tools Strategy

### Problem

`pm2`, `eslint`, etc. are typically installed via `npm install -g`, which lands in unpredictable locations depending on nvm/volta/npm config.

### Solution: Vendor + Pin

1. **Vendor node CLIs** into strap-managed locations
2. **Pin node exe** at machine level (or per-shim override)

```
P:\software\_node-tools\
├── pm2\
│   ├── package.json
│   └── node_modules\
│       └── pm2\
│           └── bin\
│               └── pm2
└── ...
```

### Node Exe Resolution

At shim generation time, resolve the node path and store in `exe`:

```powershell
function Resolve-NodeExe {
  param(
    [string] $CliOverride,    # --node-exe flag
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

The resolved path is stored directly in the registry's `exe` field. No separate `nodeExe` field needed - everything is resolved at generation time.

### Helper Command

```powershell
strap install-node-tool pm2

# Equivalent to:
# 1. mkdir P:\software\_node-tools\pm2
# 2. cd P:\software\_node-tools\pm2
# 3. npm init -y
# 4. npm install pm2
# 5. strap shim pm2 --node --exe "P:\software\_node-tools\pm2\node_modules\pm2\bin\pm2"
```

---

## Doctor Checks

### Check Summary

| ID | Check | Severity | Auto-fix |
|----|-------|----------|----------|
| `SHIM001` | Shims directory exists and is on PATH | Critical | No |
| `SHIM002` | Shim file exists on disk | Error | Remove from registry |
| `SHIM003` | Exe is resolvable | Error | No |
| `SHIM004` | Shim registry entry matches disk | Warning | Rebuild shim |
| `SHIM005` | No orphan shims (on disk but not in registry) | Warning | Register or delete |
| `SHIM006` | No duplicate shim names across repos | Error | No |
| `SHIM007` | Venv is valid (python.exe exists) | Error | No |
| `SHIM008` | Launcher pair complete (.ps1 + .cmd) | Warning | Regenerate |
| `SHIM009` | pwshExe and nodeExe in config are valid | Warning | No |

### SHIM001: Shims Directory on PATH

```powershell
$shimsRoot = $Config.roots.shims

if (-not (Test-Path $shimsRoot)) {
  # FAIL: Directory doesn't exist
  $fix = "New-Item -ItemType Directory -Path '$shimsRoot'"
} else {
  $pathEntries = $env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') }
  $shimsNormalized = $shimsRoot.TrimEnd('\')
  
  if ($shimsNormalized -notin $pathEntries) {
    # FAIL: Not on PATH
    # Fix must be idempotent: remove existing entries first, then prepend once
    $fix = @"
`$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
`$entries = `$userPath -split ';' | Where-Object { `$_.TrimEnd('\') -ne '$shimsNormalized' }
`$newPath = '$shimsRoot;' + (`$entries -join ';')
[Environment]::SetEnvironmentVariable('PATH', `$newPath, 'User')
"@
  }
}
```

**Important:** The fix de-duplicates before prepending to prevent PATH pollution if run multiple times.

### SHIM003: Exe is Resolvable (Comprehensive)

```powershell
$exe = $shim.exe
$type = $shim.type

switch ($type) {
  "venv" {
    # Exe should be resolved to full path at generation time
    if ([System.IO.Path]::IsPathRooted($exe)) {
      $passed = Test-Path $exe
      if (-not $passed) {
        $message = "Venv exe not found: $exe"
        $fix = "Reinstall package in venv or regenerate shim"
      }
    } else {
      # Legacy: exe not resolved, try to resolve now
      $venvScripts = Join-Path $shim.venv "Scripts"
      
      if ($exe -eq "python") {
        $resolved = Join-Path $venvScripts "python.exe"
      } else {
        $resolved = Join-Path $venvScripts "$exe.exe"
      }
      
      $passed = Test-Path $resolved
      if (-not $passed) {
        # Check if it's a module invocation
        if ($shim.baseArgs.Count -ge 2 -and $shim.baseArgs[0] -eq "-m") {
          $module = $shim.baseArgs[1]
          $message = "Module '$module' - verify installed in venv (deep doctor can check)"
          $passed = $true  # Soft pass, deep doctor validates
        } else {
          $message = "Exe not found in venv: $resolved"
          $fix = "pip install <package> in venv"
        }
      }
    }
  }
  
  "node" {
    # exe should be absolute path to node
    if (-not [System.IO.Path]::IsPathRooted($exe)) {
      $message = "Node shim exe should be absolute path to node: $exe"
      $passed = $false
    } else {
      $passed = Test-Path $exe
      if (-not $passed) {
        $message = "Node exe not found: $exe"
        $fix = "Update config.defaults.nodeExe or regenerate shim with --node-exe"
      }
    }
    
    # Also check the JS entrypoint in baseArgs[0]
    if ($passed -and $shim.baseArgs.Count -gt 0) {
      $jsEntry = $shim.baseArgs[0]
      if ([System.IO.Path]::IsPathRooted($jsEntry) -and -not (Test-Path $jsEntry)) {
        $passed = $false
        $message = "Node entrypoint not found: $jsEntry"
        $fix = "npm install in _node-tools directory or check path"
      }
    }
  }
  
  "simple" {
    # Must be on PATH or absolute
    if ([System.IO.Path]::IsPathRooted($exe)) {
      $passed = Test-Path $exe
      if (-not $passed) {
        $message = "Exe path not found: $exe"
      }
    } else {
      $found = Get-Command $exe -ErrorAction SilentlyContinue
      $passed = $null -ne $found
      if (-not $passed) {
        $message = "Exe not found on PATH: $exe"
        $fix = "Install $exe or use absolute path"
      }
    }
  }
}
```

### SHIM007: Venv is Valid

```powershell
if ($shim.type -eq "venv") {
  $venvPath = $shim.venv
  $pythonExe = Join-Path $venvPath "Scripts\python.exe"
  
  $passed = Test-Path $pythonExe
  if (-not $passed) {
    $message = "Venv missing or invalid: $venvPath"
    $fix = "cd $($entry.repoPath); python -m venv .venv"
  }
}
```

### SHIM008: Launcher Pair Complete

```powershell
$ps1Path = $shim.ps1Path
$cmdPath = $ps1Path -replace '\.ps1$', '.cmd'

if ((Test-Path $ps1Path) -and -not (Test-Path $cmdPath)) {
  $message = "Missing .cmd launcher for $($shim.name)"
  $fix = "strap shim $($shim.name) --repo $($entry.name) --force"
}
```

### SHIM009: Config Exe Paths Valid

```powershell
# Check pwshExe
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

# Check nodeExe
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
```

### Deep Doctor Mode

For comprehensive validation, `strap doctor --deep` adds:

```powershell
# Verify venv module imports actually work
if ($shim.type -eq "venv" -and $shim.baseArgs[0] -eq "-m") {
  $module = $shim.baseArgs[1]
  $pythonExe = Join-Path $shim.venv "Scripts\python.exe"
  
  $result = & $pythonExe -c "import $module" 2>&1
  if ($LASTEXITCODE -ne 0) {
    # FAIL: Module not importable
    $message = "Module '$module' not importable in venv"
    $fix = "pip install $module in venv"
  }
}
```

### Example Output

```
=== SHIM HEALTH ===

[CRITICAL]
  Shims directory on PATH
    Shims directory not on PATH: P:\software\bin
    Fix: [Environment]::SetEnvironmentVariable('PATH', "P:\software\bin;" + ...)

[ERROR]
  Exe resolvable: chinvex
    Venv exe not found: P:\software\chinvex\.venv\Scripts\chinvex.exe
    Fix: Reinstall package in venv or regenerate shim

[WARNING]
  Launcher pair: mytool
    Missing .cmd launcher for mytool
    Fix: strap shim mytool --repo mytool --force

  Config nodeExe valid
    defaults.nodeExe not found: C:\nvm4w\nodejs\node.exe
    Fix: Update strap config with correct node path

Passed: 12 | Failed: 4
```

---

## Implementation Checklist

- [ ] Update `Load-Config` to include `shims`, `nodeTools`, and `defaults` sections
- [ ] Update registry schema: `path` → `repoPath`, shim `path` → `ps1Path`, bump version to 2
- [ ] Add registry version check in `Load-Registry` (error if version > supported)
- [ ] Modify `Invoke-Shim` with new signature
- [ ] Implement PowerShell tokenizer + JSON array parsing for `--cmd`
- [ ] Add tokenizer safety checks (block pipes, redirects, semicolons)
- [ ] Add mutual exclusivity check (`--cmd` vs `--exe`/`--args`)
- [ ] Add pwshExe validation before writing shims
- [ ] Implement venv exe resolution (direct path, no activation) with missing-exe warning
- [ ] Implement node exe resolution (pinned path)
- [ ] Reject relative paths for simple type exe
- [ ] Generate dual files (.ps1 + .cmd) with full pwsh.exe path in launcher
- [ ] Implement collision policy (error on different repo, `--force` to override, same repo = update)
- [ ] Implement orphan detection (disk-only shim not in any registry)
- [ ] Add `strap shim --regen --repo <name>` command (regenerate all shims for a repo)
- [ ] Update `Invoke-Doctor` with SHIM001-SHIM009 checks (SHIM001 fix must be idempotent)
- [ ] Add `--deep` flag for module import validation
- [ ] Update documentation

---

## Decision Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Shims location | `P:\software\bin` | Single PATH entry, clean separation |
| Dual-file approach | `.ps1` + `.cmd` | Works from all contexts (PS, cmd, scheduler) |
| Launcher pwsh path | Full absolute path | Task Scheduler doesn't have reliable PATH |
| pwshExe validation | Fail-fast at creation | Prevents broken shims |
| Command storage | `exe` + `baseArgs[]` | Avoids runtime parsing, quoting hell |
| Command parsing | PowerShell tokenizer + JSON array | Handles quotes/spaces correctly |
| Token extraction | Prefer `.Value` over `.Text` | Avoids quoting artifacts |
| Blocked tokens | Pipes, redirects, semicolons | Shims are exec primitives, not shell scripts |
| Venv invocation | Direct exe call | Faster, more deterministic than activation |
| Missing venv exe | Warn at creation, doctor enforces | Allows shim creation before package install |
| Node shim format | `exe` = node path, `baseArgs[0]` = JS entry | Consistent with template, simplifies SHIM003 |
| Node exe | Resolved at generation time from config | No runtime drift |
| Simple type exe | Absolute or bare command only | Relative paths cause caller-cwd confusion |
| Collision policy | Error unless `--force` (same repo = update) | Prevents accidental overwrites |
| Orphan handling | Warn, suggest `--force` to claim | User decides ownership |
| PATH fix | Idempotent with de-dupe | Running fix twice won't corrupt PATH |
| Registry field names | `repoPath`, `ps1Path` | Avoid overloaded `path` field |
| Shim ownership | Registry `shims` array per repo | No subfolders needed, registry is the index |
| Registry versioning | Top-level `version` field, bump on breaking changes | Prevents old strap from corrupting new format |
| Concurrent access | No locking (personal tool) | Acceptable to race at this scale |
| install-node-tool | Optional for v3.1 | Can add later without spec changes |

---

## Clarifications & Edge Cases

### Registry Structure

Registry location: `<strap-root>/build/registry.json`

Top-level structure (existing strap pattern):
```json
{
  "version": 2,
  "repos": [
    {
      "name": "chinvex",
      "repoPath": "P:\\software\\chinvex",
      "scope": "software",
      "shims": [ ... ]
    }
  ]
}
```

**Repo identification:** By `name` field. The `--repo` parameter matches against this.

**Unknown repo:** `strap shim tool --repo nonexistent` → Error: "Registry entry 'nonexistent' not found."

### Parameter Mutual Exclusivity

`--cmd` vs `--exe`/`--args`:

| Provided | Behavior |
|----------|----------|
| `--cmd` only | Parse into exe + baseArgs |
| `--exe` + `--args` only | Use directly |
| Both | **Error:** "Cannot use --cmd with --exe/--args. Pick one." |
| Neither | **Error:** "Must provide --cmd or --exe." |

### Venv Auto-Detect vs Explicit Path

The `--venv` flag is a **switch that optionally accepts a value**:

| Usage | Behavior |
|-------|----------|
| `--venv` (no value) | Auto-detect from repo (.venv, venv, .virtualenv) |
| `--venv "P:\path"` | Use explicit path |
| No `--venv` flag | Not a venv shim (simple or node type) |

Implementation: Check if `$VenvPath` is empty string vs has value.

### Venv Detection Priority

First match wins from: `.venv`, `venv`, `.virtualenv`

If multiple exist, first in list is used. No warning - this is deterministic.

### Orphan vs Collision

| Shim file state | Registry state | Classification | Behavior |
|-----------------|----------------|----------------|----------|
| Exists | In this repo's shims array | Owned | Update in place |
| Exists | In different repo's shims array | Collision | Error unless `--force` |
| Exists | Not in any repo's shims array | Orphan | Warn, suggest `--force` to claim or delete |
| Missing | In registry | Dead reference | Doctor SHIM002 error |

**Orphan handling at creation time:**
```
Warning: Shim 'mytool' exists on disk but isn't registered to any repo.
Use --force to claim ownership, or delete P:\software\bin\mytool.ps1 manually.
```

### Regen Command Signature

Takes repo name, not shim name:

```powershell
# Correct - regenerate all shims for chinvex repo
strap shim --regen --repo chinvex

# Also valid (positional)
strap shim --regen chinvex
```

When `--regen` is present:
1. `$ShimName` parameter is ignored
2. `$RegistryEntryName` (from `--repo` or positional) identifies the repo
3. All shims in that repo's `shims` array are regenerated

### Simple Type Exe Path Rules

For `simple` type shims, `--exe` must be:

| Form | Valid | Example |
|------|-------|---------|
| Absolute path | ✅ | `C:\tools\mytool.exe` |
| Bare command (PATH lookup) | ✅ | `git`, `curl.exe` |
| Relative path | ❌ | `./scripts/tool.sh` |

Relative paths are rejected: "Simple shim exe must be absolute path or bare command name. Use --cwd if you need working directory context."

**Rationale:** Relative paths would resolve from caller's cwd, not repo, causing inconsistent behavior.

### Cwd + Venv Interaction

Order of operations in generated shim:
1. `Push-Location $cwd`
2. Resolve and call venv exe (path is absolute, so cwd doesn't affect it)
3. `Pop-Location` in finally block

Venv path is **always stored as absolute** in registry, so cwd doesn't interfere.

### Exit Code Handling

Generated shims handle null `$LASTEXITCODE`:

```powershell
$exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
exit $exitCode
```

### pwshExe Validation at Creation Time

Before writing shims, validate `config.defaults.pwshExe`:

```powershell
if (-not (Test-Path $config.defaults.pwshExe)) {
  Die "pwshExe not found: $($config.defaults.pwshExe). Update strap config before creating shims."
}
```

This prevents creating broken shims that can't be invoked from cmd.exe or Task Scheduler.

### Registry Schema Version

Top-level `version` field indicates schema version. When v3.1 shim changes are implemented:

1. Bump registry version from `1` to `2`
2. Add migration logic in `Load-Registry` to handle v1 → v2 if needed
3. New shim fields (`ps1Path`, etc.) only exist in v2+ registries

Old strap versions encountering v2 registry: should error with "Registry version 2 requires strap v3.1 or later."

### Partial Failure & Rollback

Write order:
1. Write `.ps1` file
2. Write `.cmd` file
3. Update registry

Rollback on failure:
- If `.cmd` write fails: delete `.ps1`, error out
- If registry update fails: delete both files, error out

### Shim Name Restrictions

Valid shim names:
- Alphanumeric, hyphen, underscore: `my-tool`, `my_tool`, `tool123`
- No spaces, no path separators, no special chars

Validation regex: `^[a-zA-Z0-9_-]+$`

Invalid names error immediately with clear message.

### File Encoding

All generated files: **UTF-8 without BOM**

### Dry Run Output

`--dry-run` shows:
```
DRY RUN - no changes will be made

Would create:
  P:\software\bin\chinvex.ps1
  P:\software\bin\chinvex.cmd

Would update registry:
  Add shim 'chinvex' to repo 'chinvex'

Generated .ps1 content:
---
# Generated by strap shim - do not edit
...
---
```

### Success Message

On successful creation:
```
✅ Created shim: chinvex
   P:\software\bin\chinvex.ps1
   P:\software\bin\chinvex.cmd
   Registered to: chinvex (venv)

You can now run 'chinvex' from anywhere.
```

### install-node-tool Command

**Status:** Optional for v3.1, can be added later.

If implemented, behavior:
1. Create `P:\software\_node-tools\<name>\`
2. Run `npm init -y`
3. Run `npm install <name>`
4. Auto-detect bin path from `node_modules/<name>/package.json` `bin` field
5. Create shim pointing to detected bin

For packages with multiple binaries, create one shim per binary.

---

## Out of Scope for v3.1

These are explicitly deferred:

- **Migration from old shim formats:** User will delete old `_scripts/_bin` folder and regenerate. No automatic conversion.
- **Concurrent access locking:** Personal tool, acceptable to race. If corruption occurs, regenerate.
- **WSL/Git Bash/Cygwin compatibility:** cmd.exe + PowerShell is sufficient for the target use case.
- **Registry encryption or access control:** Not needed for single-user local tool.
- **Remote/networked shim storage:** Shims are local to machine.
- **`install-node-tool` command:** Can be added later without changing shim spec.

---

## References

- [2026-02-02 Environment Corruption Incident](./2026-02-02-environment-corruption.md)
- Original `Invoke-Shim` implementation (strap.ps1:3129-3329)
