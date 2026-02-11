---
name: using-strap
description: Use when working with strap dev environment manager - cloning repos, creating shims, managing lifecycle, configuring metadata, troubleshooting, or combining multiple strap operations
---

# Using Strap

## Overview

**Strap** is a Windows dev environment manager that provides instant system-wide tool availability. Core workflow: Git URL or local folder → `strap adopt/clone` → automatic shim creation → tool available globally.

**One PATH entry (`P:\software\bin`), unlimited tools.** All shims live there, cross-shell compatible (.ps1 + .cmd).

## When to Use This Skill

Use when:
- User wants to make a CLI tool system-wide available on Windows
- User asks about strap commands, flags, or workflows
- User needs to troubleshoot strap registry, shims, or chinvex sync
- User wants to batch-operate on repos (update all, configure multiple)
- User mentions pyenv-win, Python version management, or venv automation

## Quick Command Reference

### Core Workflow (New Tool)
```powershell
# Clone from GitHub → auto-setup → global availability
strap clone <github-url>

# Or adopt existing local repo
cd P:\software\existing-repo
strap adopt

# Install dependencies (auto-detects Python/Node/Go/Rust)
strap setup --repo <name>
```

**CRITICAL: Metadata changes use `strap configure`, NOT `strap update`**
```powershell
# Change metadata AFTER adoption
strap configure <name> --depth light --status stable --add-tags third-party
```

### Lifecycle Management
```powershell
strap list                    # Show all registered repos
strap list --verbose          # Full details (paths, shims, health)
strap open <name>             # Open in file explorer
strap update <name>           # Pull latest changes
strap update --all            # Update all repos
strap move <name> --dest <path>   # Relocate repo
strap rename <name> --to <new>    # Rename in registry
strap uninstall <name>        # Remove folder + shims + registry
strap purge                   # Clear entire registry
```

### Metadata Configuration
```powershell
# Change depth/status after adoption
strap configure <name> --depth light --status stable

# Tag management
strap configure <name> --add-tags third-party,archived
strap configure <name> --remove-tags deprecated
strap configure <name> --clear-tags
```

### Shim Creation
```powershell
# Auto-created during adopt/clone (Python/Node projects)
# Manual creation for custom commands:

# Use --cmd for commands with flags (ALWAYS for -m, -p, etc.)
strap shim flask --cmd "python -m flask run" --repo myapp

# Shim with working directory
strap shim mytool --cmd "node cli.js" --cwd P:\software\myapp --repo myapp

# Regenerate after moving repo
strap shim --regen <repo-name>
```

### Python Version Management
```powershell
# Install pyenv-win (one-time)
strap doctor --install-pyenv

# Auto-detected during clone/adopt/setup from:
# - .python-version (e.g., "3.12" or "3.12.10")
# - pyproject.toml (requires-python)
# - requirements.txt comments
```

### Chinvex Integration
```powershell
strap contexts                # View sync status
strap sync-chinvex            # Dry-run (preview drift)
strap sync-chinvex --reconcile # Fix drift (create/archive)
```

**CRITICAL: Use `strap sync-chinvex --reconcile`, NOT chinvex commands directly**

### Troubleshooting
```powershell
strap doctor                  # System health check
strap doctor --system         # Just PATH/tools check
strap doctor --shims          # Validate all shims
strap doctor --install-pyenv  # Install pyenv-win
```

## Common Workflows

### Workflow 1: Clone Third-Party Tool
```powershell
# Clone with tool preset (light depth, stable status, third-party tag)
strap clone https://github.com/user/cli-tool --tool

# Verify it's available
cli-tool --help
```

### Workflow 2: Python Project with Version Requirement
```powershell
# Clone automatically:
# 1. Detects .python-version or pyproject.toml
# 2. Installs Python via pyenv-win if needed
# 3. Creates venv with correct Python
# 4. Creates shims from [project.scripts]
strap clone https://github.com/user/python-app

# Everything is ready to use
python-app --help
```

### Workflow 3: Update All Own Projects (Skip Tools)
```powershell
# First time: tag third-party repos
strap configure third-party-tool --add-tags third-party --yes

# Then filter updates by tag
strap update --all --software --stash --yes
```

### Workflow 4: Move Repo and Fix Chinvex
```powershell
# Move repo to new location
strap move myproject --dest P:\software\projects\ --yes

# If chinvex shows orphaned, reconcile
strap sync-chinvex --reconcile
```

### Workflow 5: Change Tool Metadata Post-Adoption
```powershell
# Adopted with wrong preset, fix it with strap configure (NOT strap update)
strap configure mytool --depth light --status stable --add-tags third-party --yes

# Chinvex will auto-sync metadata
```

**Common confusion: `strap update` pulls git changes, `strap configure` modifies metadata**

## Critical Flags and Their Purposes

### Global Flags
- `--yes` — Skip confirmation prompts (use in scripts/automation)
- `--dry-run` — Preview without executing (safe exploration)
- `--json` — Machine-readable output (for scripts)

### Clone/Adopt Flags
- `--tool` — Use tool preset: depth=light, status=stable, tags=[third-party]
- `--software` — Use software preset: depth=full, status=active (default)
- `--no-chinvex` — Skip chinvex integration for this operation
- `--skip-setup` — Don't run automatic dependency installation

### Setup Flags
- `--stack <python|node|go|rust>` — Force stack detection (use when multiple)
- `--venv <path>` — Python: custom venv directory (default .venv)
- `--use-uv` — Python: use uv instead of pip (opt-in)
- `--python <exe>` — Python: specific Python executable
- `--pm <npm|pnpm|yarn>` — Node: force package manager
- `--corepack` — Node: enable corepack before install

### Update Flags
- `--all` — Update all repos (filter with --tool/--software)
- `--tool` — Only third-party tagged repos
- `--software` — Only non-third-party repos
- `--rebase` — Use git pull --rebase instead of merge
- `--stash` — Auto-stash dirty working tree before update
- `--setup` — Run setup after successful update (currently unimplemented)

### Shim Flags
- `--cmd "<command>"` — **ALWAYS use this for commands with single-letter flags** (e.g., `-m`, `-p`)
- `--repo <name>` — Attach shim to registry entry
- `--cwd <path>` — Set working directory for shim
- `--venv` — Create Python venv shim (auto-detected)
- `--node` — Create Node shim
- `--force` — Overwrite existing shim
- `--regen` — Regenerate all shims for a repo

### Move Flags
- `--dest <path>` — Destination (ends with `\` keeps name, otherwise full path)
- `--rehome-shims` — Update shim content to reference new path (rarely needed)

### Rename Flags
- `--to <newName>` — New registry name
- `--move-folder` — Also rename folder on disk to match

### Configure Flags
- `--depth <light|full>` — Chinvex indexing depth
- `--status <active|stable|archived|deprecated>` — Lifecycle status
- `--tags <tag1,tag2>` — Replace all tags
- `--add-tags <tag1,tag2>` — Add tags without removing existing
- `--remove-tags <tag1,tag2>` — Remove specific tags
- `--clear-tags` — Remove all tags

## Critical Rules

### Shim Command Syntax
**ALWAYS use `--cmd` for commands with single-letter flags:**
```powershell
# ✅ CORRECT
strap shim flask --cmd "python -m flask run" --repo myapp

# ❌ WRONG (PowerShell will consume -m)
strap shim flask --- python -m flask run
```

**Why:** PowerShell parameter binding will try to match single-letter flags like `-m`, `-p`, `-h` to strap's own parameters. `--cmd` treats the entire command as a single quoted string, avoiding this conflict.

### Metadata Presets
- **Third-party tools**: Use `--tool` flag or manually configure with `depth=light`, `status=stable`, `tags=[third-party]`
- **Your own projects**: Default preset is fine (depth=full, status=active)
- **Old/inactive projects**: Configure with `status=dormant` or `status=archived`

### Python Version Management
- Major.minor versions (e.g., "3.12") automatically resolve to latest patch (e.g., 3.12.10) via pyenv
- Strap uses **pip by default** (conservative), use `--use-uv` to opt into uv
- pyenv-win ignores `PYENV_ROOT` environment variable (hardcoded to `P:\software\_python-tools\pyenv-win\versions\`)

### Chinvex Integration
- Automatic by default (global opt-out only via config.json)
- `strap move`, `strap rename`, `strap configure` all auto-sync with chinvex
- If drift occurs: `strap sync-chinvex --reconcile` fixes it
- Reserved context names: "tools", "archive" (case-insensitive)

### Registry Backups
- Automatic before every write operation
- Stored in `P:\software\_strap\backups\registry-{timestamp}.json`
- Keeps 30 most recent backups
- Manual restore: `Copy-Item backups\registry-TIMESTAMP.json registry.json -Force`

## Troubleshooting Patterns

### Problem: Shim creation failed with "parameter binding" error
**Solution:** Use `--cmd` instead of `---`
```powershell
strap shim mytool --cmd "python -m mypackage.cli" --repo mytool
```

### Problem: Python version not found
**Solution:** Install pyenv-win first
```powershell
strap doctor --install-pyenv
pyenv install 3.12.10
```

### Problem: Chinvex shows orphaned after move
**Solution:** Reconcile sync with strap command (NOT chinvex command)
```powershell
# ✅ CORRECT: Use strap's chinvex integration
strap sync-chinvex --reconcile

# ❌ WRONG: Don't use chinvex commands directly
# chinvex context sync-metadata-from-strap  # This bypasses strap's registry
```

### Problem: Setup failed, unknown error
**Solution:** Check health status
```powershell
strap list --verbose    # Shows HEALTH column
strap doctor --shims    # Validates all shims
```

### Problem: Want to update only my projects, not third-party tools
**Solution:** Tag third-party repos once, then filter
```powershell
# One-time tagging
strap configure third-party-tool --add-tags third-party --yes

# Future updates
strap update --all --software --yes
```

### Problem: Registry corrupted or inconsistent
**Solution:** Restore from automatic backup
```powershell
# List recent backups
Get-ChildItem P:\software\_strap\backups | Sort-Object Name -Descending | Select-Object -First 10

# Restore specific backup
Copy-Item P:\software\_strap\backups\registry-20260209-143052.json P:\software\_strap\registry.json -Force
```

## Architecture Notes (For Understanding Behavior)

### Shim System v3.1
- **Dual-file**: Every shim is `.ps1` (does work) + `.cmd` (wrapper for cmd.exe)
- **Cross-shell**: Works from PowerShell, cmd.exe, bash, IDEs, scheduled tasks
- **Types**: `simple` (direct exec), `venv` (Python with venv activation), `node` (Node with PATH setup)
- **Auto-discovery**: Python ([project.scripts], [tool.poetry.scripts], console_scripts) and Node (package.json bin field)

### Registry V3 Schema
- **Metadata**: depth (light/full), status (active/stable/dormant/deprecated), tags (array)
- **Setup tracking**: result (succeeded/failed/skipped), error message, last_attempt timestamp
- **Python version**: Stored per-repo, detected from .python-version/pyproject.toml/requirements.txt
- **Shims**: Array of shim metadata (name, type, paths, venv, baseArgs, cwd)

### Chinvex Integration
- **Single source of truth**: Being in strap registry = being in chinvex
- **Auto-sync**: All lifecycle operations (clone, adopt, move, rename, uninstall) update chinvex
- **Metadata forwarding**: All three fields (depth, status, tags) passed to chinvex
- **Individual contexts**: Each repo gets its own chinvex context (context name = repo name)

### Infrastructure Directories
- **Underscore-prefixed directories are NOT repos**: `_node-tools`, `_strap`, `_python-tools`, etc.
- **Not in registry.json**: These are strap infrastructure, not user repos
- **Can have shims**: Tools vendored in these directories can have shims created (e.g., `pm2`, `pm2-startup`)
- **Examples**:
  - `P:\software\_node-tools\pm2` — Vendored PM2 with shim at `P:\software\bin\pm2.cmd`
  - `P:\software\_strap` — Strap itself
  - `P:\software\_python-tools\pyenv-win` — Python version manager

## Common Mistakes

### Mistake: Using --- instead of --cmd
```powershell
# ❌ Will fail
strap shim mytool --- python -m package.cli

# ✅ Correct
strap shim mytool --cmd "python -m package.cli" --repo mytool
```

### Mistake: Forgetting --repo when creating shim outside repo directory
```powershell
# ❌ Will fail if not in repo directory
strap shim mytool --cmd "python main.py"

# ✅ Correct
strap shim mytool --cmd "python main.py" --repo mytool
```

### Mistake: Running setup without adopting first
```powershell
# ❌ Setup won't know which repo
cd P:\software\myproject
strap setup

# ✅ Adopt first, then setup
strap adopt
strap setup
```

### Mistake: Using update instead of configure for metadata
```powershell
# ❌ Wrong command for metadata changes
strap update mytool --depth light --status stable

# ✅ Correct: Use configure for metadata
strap configure mytool --depth light --status stable
```

### Mistake: Expecting --setup flag to work with update
```powershell
# ❌ This flag is currently unimplemented
strap update --all --setup

# ✅ Run setup separately
strap update --all
# Then manually: strap setup --repo <name>
```

### Mistake: Moving repo without fixing chinvex
```powershell
# Move works, but chinvex may drift
strap move myproject --dest P:\software\projects\
# Later: chinvex shows orphaned

# ✅ Reconcile immediately after
strap move myproject --dest P:\software\projects\
strap sync-chinvex --reconcile
```

## Real-World Impact

**Before strap:**
- Manual `git clone` to scattered locations
- Edit PATH for each new tool (2000 char limit)
- Manual Python venv creation and activation
- "Where did I install that script?"
- Inconsistent tool versions across projects

**After strap:**
- One command: `strap clone <url>` → tool available everywhere
- One PATH entry: `P:\software\bin`
- Automatic Python version management via pyenv-win
- Central registry: `strap list` shows everything
- Metadata system: know which tools are third-party vs your own

**Example:** Installing chinvex (Python CLI tool)
```powershell
# Without strap: 8+ manual steps
git clone https://github.com/llampwall/chinvex P:\software\chinvex
cd P:\software\chinvex
pyenv install 3.12.10
pyenv local 3.12.10
python -m venv .venv
.venv\Scripts\activate
pip install -e .
# Edit PATH to add P:\software\chinvex\.venv\Scripts

# With strap: 1 command
strap clone https://github.com/llampwall/chinvex
# Done. chinvex is now available system-wide.
```
