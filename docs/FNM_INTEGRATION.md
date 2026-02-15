# fnm Integration Guide

## Overview

_strap integrates **fnm (Fast Node Manager)** for automatic Node.js version management, mirroring the pyenv-win integration for Python. This provides:

- **Automatic version detection** from `.nvmrc`, `.node-version`, or `package.json` engines field
- **Auto-installation** of missing Node versions during `strap setup`
- **Version-specific Node executables** for shims (no global version conflicts)
- **Build step detection** - automatically runs `build` or `prepare` scripts
- **Registry tracking** of `node_version` for each repo

## Quick Start

### 1. Install fnm

```powershell
strap doctor --install-fnm
```

This installs fnm to `P:\software\_node-tools\fnm` and creates system-wide shims.

### 2. Verify Installation

```powershell
fnm --version
strap doctor --system
```

Expected output:
```
[OK] fnm installed
[OK] fnm shim exists
```

### 3. Use in Projects

When you clone or set up a Node project, fnm integration activates automatically:

```powershell
strap clone https://github.com/example/node-project.git
# → Detects Node version from .nvmrc
# → Auto-installs Node via fnm if missing
# → Runs build step automatically
# → Creates shims using fnm-managed Node
```

## Version Detection

fnm integration detects Node versions from project files in this priority order:

### 1. `.nvmrc` (highest priority)

```
18.17.0
```

Supports:
- Exact versions: `18.17.0`
- With `v` prefix: `v20.19.0`
- Major.minor: `18.17` → resolves to latest patch (e.g., `18.17.1`)
- LTS aliases: `lts/hydrogen`

### 2. `.node-version`

```
22.15.1
```

Same format as `.nvmrc`.

### 3. `package.json` engines field

```json
{
  "engines": {
    "node": ">=20.19.0"
  }
}
```

Supports:
- Exact versions: `"18.17.0"`
- Comparison operators: `">=20.19.0"`
- Caret ranges: `"^18.17.0"`
- Tilde ranges: `"~18.17.0"`

## Architecture

### Directory Structure

```
P:\software\_node-tools\fnm\
├── fnm.exe                          # fnm binary (downloaded from GitHub)
└── node-versions\                   # Node installations
    ├── v18.17.0\
    │   └── installation\
    │       └── node.exe             # Version-specific Node executable
    ├── v20.19.0\
    └── v22.15.1\

P:\software\bin\
├── fnm.ps1                          # System-wide fnm shim
└── fnm.cmd                          # CMD wrapper
```

### Integration Points

#### 1. **FnmIntegration.ps1 Module**

11 functions mirroring PyenvIntegration.ps1:

| Function | Purpose |
|----------|---------|
| `Get-VendoredFnmPath` | Returns `P:\software\_node-tools\fnm` |
| `Get-NodeVersionsPath` | Returns fnm's node-versions directory |
| `Install-FnmBinary` | Downloads fnm-windows.zip from GitHub releases |
| `Test-FnmInstalled` | Checks vendored location then PATH |
| `Get-FnmCommand` | Returns path to fnm.exe |
| `Get-NodeVersionFromFile` | Detects version from project files |
| `Get-FnmVersions` | Lists installed Node versions |
| `Get-LatestFnmVersion` | Resolves major.minor to latest patch |
| `Install-FnmVersion` | Installs and validates Node versions |
| `Get-FnmNodePath` | Returns path to version-specific node.exe |
| `New-FnmShim` | Creates system-wide fnm.ps1/fnm.cmd shims |

#### 2. **Setup Command Integration**

When `strap setup` runs on a Node project:

1. **Detects version** from `.nvmrc`, `.node-version`, or `package.json`
2. **Checks if installed** via `Get-FnmVersions`
3. **Auto-installs** if missing via `Install-FnmVersion`
4. **Validates** installation by running `node --version`
5. **Enables corepack** (if `package.json` has `packageManager` field or `--enable-corepack` flag)
6. **Sets up environment** to use fnm-managed Node (prepends to PATH)
7. **Stores** `node_version` in registry
8. **Runs build step** if `package.json` has `build` or `prepare` script

Example output:
```
Setting up: my-node-project
Detected stack: node
Detected Node version requirement: 20.19.0
  Installing Node 20.19.0 via fnm...
  [OK] Node 20.19.0 installed and validated
Using Node: P:\software\_node-tools\fnm\node-versions\v20.19.0\installation\node.exe

=== SETUP PLAN ===
Commands to execute:
  1. Enable corepack
     & 'P:\software\_node-tools\fnm\node-versions\v20.19.0\installation\corepack.cmd' enable
  2. Install Node dependencies via yarn
  3. Build project

Setup completed successfully
registry updated
```

#### 3. **Shim System Integration**

Shims for Node CLIs use fnm-managed Node executables:

**Resolution priority:**
1. CLI override (`--node-exe`)
2. **fnm-managed Node** (if version detected and fnm available)
3. config.json `nodeExe`
4. PATH fallback

**Regeneration:**
- `strap shim --regen <repo>` re-resolves Node exe path
- Automatically picks up fnm-managed Node if version file exists
- Updates registry with new exe path

#### 4. **Doctor Command Integration**

New checks:
- **SYS003**: fnm installed
- **SYS004**: fnm shim exists

## Usage Examples

### Installing Specific Node Versions

```powershell
fnm install 18.17.0
fnm install 20.19.0
fnm install lts/hydrogen

fnm list  # Show installed versions
```

### Setting Up a Project with Version Requirements

Create `.nvmrc` in your project:

```
22.15.1
```

Then run setup:

```powershell
strap setup my-project
```

strap will:
1. Detect the version requirement
2. Install Node 22.15.1 via fnm (if not already installed)
3. Use that specific version for the project
4. Run `npm/yarn/pnpm install` and build steps

### Migrating Existing Projects to fnm

If you have a Node project already registered:

```powershell
# Add version file
echo "20.19.0" > P:\software\my-project\.nvmrc

# Re-run setup
strap setup my-project

# Regenerate shims to use fnm-managed Node
strap shim --regen my-project
```

## Comparison with pyenv-win Integration

fnm integration follows the exact architectural pattern established by pyenv-win:

| Aspect | pyenv-win | fnm |
|--------|-----------|-----|
| **Installation** | Git clone | Binary download (faster) |
| **Location** | `P:\software\_python-tools\pyenv-win` | `P:\software\_node-tools\fnm` |
| **Version detection** | `.python-version`, `pyproject.toml` | `.nvmrc`, `.node-version`, `package.json` |
| **Auto-install** | ✅ During setup | ✅ During setup |
| **Registry field** | `python_version` | `node_version` |
| **Shim resolution** | Detects version, uses pyenv Python | Detects version, uses fnm Node |
| **System-wide shim** | `pyenv.ps1` / `pyenv.cmd` | `fnm.ps1` / `fnm.cmd` |

**Key improvements in fnm integration:**
- Binary installation (no git clone needed)
- Build step detection (automatic `yarn build`)
- Shim regeneration fix (re-resolves exe instead of using stale registry value)

## Corepack Integration

Starting with Node 16.9.0, corepack is bundled with Node and provides package manager version management.

### Automatic Corepack Detection

`strap setup` automatically enables corepack if:
1. `package.json` has a `packageManager` field, OR
2. User passes `--enable-corepack` flag

### Example: Using pnpm via Corepack

```json
{
  "name": "my-project",
  "packageManager": "pnpm@8.6.0"
}
```

When you run `strap setup`:
```
=== SETUP PLAN ===
Commands to execute:
  1. Enable corepack
     & 'P:\software\_node-tools\fnm\node-versions\v20.19.0\installation\corepack.cmd' enable
  2. Install Node dependencies via pnpm
```

**Important:** Corepack uses the **fnm-managed Node**, not the global Node. This prevents permission errors when you have nvm installed globally.

### Skipping Corepack

To skip corepack even if `packageManager` is defined:

```powershell
strap setup --enable-corepack:$false
```

## Environment Isolation

All Node commands (`npm install`, `pnpm install`, `yarn build`, etc.) run with the fnm Node directory prepended to PATH. This ensures:

✅ Correct Node version is used (no conflicts with nvm/global Node)
✅ Corepack writes to fnm directory (no permission errors)
✅ Package managers use the right Node version

## Troubleshooting

### fnm not found after installation

```powershell
# Verify fnm.exe exists
Test-Path P:\software\_node-tools\fnm\fnm.exe

# Verify shim exists
Test-Path P:\software\bin\fnm.ps1

# Check PATH includes P:\software\bin
$env:PATH -split ';' | Select-String 'P:\\software\\bin'

# Reinstall
strap doctor --install-fnm
```

### Node version not detected

```powershell
# Check if version file exists
Get-ChildItem P:\software\my-project\.nvmrc
Get-ChildItem P:\software\my-project\.node-version
Get-Content P:\software\my-project\package.json | ConvertFrom-Json | Select-Object -ExpandProperty engines

# Test detection manually
. P:\software\_strap\modules\FnmIntegration.ps1
Get-NodeVersionFromFile -RepoPath P:\software\my-project
```

### Shims still using old Node path

```powershell
# Regenerate shims
strap shim --regen my-project

# Verify registry updated
(Get-Content P:\software\_strap\registry.json | ConvertFrom-Json) |
  Where-Object { $_.name -eq 'my-project' } |
  Select-Object -ExpandProperty shims |
  Select-Object name, exe
```

### Node version installation fails

```powershell
# Check fnm can list versions
fnm list-remote | Select-String '20.19'

# Try manual installation
fnm install 20.19.0

# Check error logs
fnm install 20.19.0 2>&1
```

## Best Practices

### 1. Always Use Version Files

Add `.nvmrc` to all Node projects for reproducible builds:

```
20.19.0
```

### 2. Commit Version Files

Add to `.gitignore` exceptions:
```gitignore
# Don't ignore version files
!.nvmrc
!.node-version
```

### 3. Use Exact Versions

Prefer exact versions (`18.17.0`) over ranges for reproducibility.

### 4. Regenerate Shims After Adding Version Files

```powershell
# Add .nvmrc to existing project
echo "20.19.0" > .nvmrc

# Re-run setup and regenerate shims
strap setup
strap shim --regen my-project
```

### 5. Check Doctor Regularly

```powershell
strap doctor --system
```

Ensure fnm and all other system dependencies are healthy.

## Migration Guide

### Migrating from Manual Node Management

**Before:**
- Node installed globally
- All projects use same Node version
- Shims hardcoded to global Node path

**After:**
1. Install fnm: `strap doctor --install-fnm`
2. Add `.nvmrc` to each project
3. Run `strap setup <project>` to install Node versions
4. Run `strap shim --regen <project>` to update shims
5. Verify: `strap list` shows `node_version` for each project

### Batch Migration Script

```powershell
# Get all Node projects
$nodeProjects = (Get-Content P:\software\_strap\registry.json | ConvertFrom-Json) |
  Where-Object { $_.stack -eq 'node' }

foreach ($project in $nodeProjects) {
  Write-Host "Migrating: $($project.name)"

  # Add .nvmrc with default version
  $nvmrcPath = Join-Path $project.path '.nvmrc'
  if (-not (Test-Path $nvmrcPath)) {
    "20.19.0" | Set-Content $nvmrcPath -NoNewline
  }

  # Re-run setup
  strap setup $project.name --yes

  # Regenerate shims
  strap shim --regen $project.name
}
```

## Advanced Usage

### Using Multiple Node Versions

```powershell
# Install multiple versions
fnm install 18.17.0
fnm install 20.19.0
fnm install 22.15.1

# Each project uses its own version via .nvmrc
cd P:\software\project-a  # .nvmrc: 18.17.0
node --version  # → v18.17.0 (via fnm)

cd P:\software\project-b  # .nvmrc: 22.15.1
node --version  # → v22.15.1 (via fnm)
```

### Custom fnm Configuration

fnm uses environment variables for configuration. The system-wide shim sets:

```powershell
$env:FNM_DIR = "P:\software\_node-tools\fnm"
```

This ensures all projects use the vendored fnm installation.

### Uninstalling Node Versions

```powershell
# List installed versions
fnm list

# Uninstall specific version
fnm uninstall 18.17.0
```

**Warning:** Only uninstall versions not used by any registered project. Check:

```powershell
(Get-Content P:\software\_strap\registry.json | ConvertFrom-Json) |
  Select-Object name, node_version
```

## Testing

Run the test suite:

```powershell
Invoke-Pester tests/powershell/FnmIntegration.Tests.ps1 -Output Detailed
```

**Coverage:**
- ✅ Vendored path resolution
- ✅ Version detection from .nvmrc, .node-version, package.json
- ✅ Priority order (prefers .nvmrc over package.json)
- ✅ Version format handling (exact, major.minor, LTS aliases)
- ✅ fnm installation detection
- ✅ Node executable path resolution

## Related Documentation

- [Python/pyenv-win Integration](./PYENV_INTEGRATION.md) (similar pattern)
- [Shim System](./SHIM_SYSTEM.md)
- [Setup Command](./SETUP_COMMAND.md)
- [fnm Official Documentation](https://github.com/Schniz/fnm)

## FAQ

**Q: Does fnm replace nvm-windows?**
A: Yes. fnm is faster and cross-platform. strap uses fnm for all Node version management.

**Q: Can I still use Node installed via other means?**
A: Yes. If no version file exists, shims fall back to config.json `nodeExe` or PATH.

**Q: What happens if I don't have a version file?**
A: Setup works normally but doesn't install a specific Node version. Shims use config.json `nodeExe` or PATH fallback.

**Q: How do I update Node versions?**
A: Update the version in `.nvmrc`, run `strap setup`, then `strap shim --regen`.

**Q: Can I use fnm directly?**
A: Yes! The system-wide `fnm` command is available. strap uses it internally but you can also use it manually.

**Q: Does this work with Yarn/pnpm/npm?**
A: Yes. Setup auto-detects package manager from lock files and uses it for installation.
