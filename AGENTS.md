# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Overview

**strap** is a Windows dev environment manager written in PowerShell with three core capabilities:

1. **Template bootstrapping** - Spin up new projects from templates (node-ts-service, node-ts-web, python, mono)
2. **Lifecycle management** - Clone, track, setup, update, move, rename, and uninstall repos with central registry
3. **Environment consolidation** - Migrate scattered repos with dependency tracking and integrity verification

The entire system is in a single PowerShell script (`strap.ps1`) with a registry (`registry.json`) and optional chinvex integration for semantic search.

## Core Architecture

### Single-File Design
All functionality lives in `strap.ps1` (~5000+ lines). The script is both:
- A command dispatcher (handles all `strap <command>` invocations)
- A library of functions (called internally by commands)

Entry point: `strap.cmd` → calls `pwsh -File strap.ps1` with args

### Registry System (V1)
`registry.json` tracks all managed repos:
```json
{
  "registry_version": 1,
  "updated_at": "2026-01-29T03:09:54Z",
  "entries": [
    {
      "id": "unique-id",
      "name": "repo-name",
      "scope": "tool|software|archive",
      "path": "P:\\software\\repo-name",
      "url": "git-remote-url",
      "shims": ["P:\\software\\_scripts\\_bin\\cmd.cmd"],
      "created_at": "timestamp",
      "updated_at": "timestamp",
      "chinvex_context": "context-name|null"
    }
  ]
}
```

**Trust modes:**
- `registry-first` (default) - Registry is source of truth, disk must match
- `disk-discovery` (recovery) - Used by `snapshot` and `adopt --scan` to discover repos regardless of registry state

### Config System
`config.json` defines root paths:
```json
{
  "roots": {
    "software": "P:\\software",
    "tools": "P:\\software\\_scripts",
    "shims": "P:\\software\\_scripts\\_bin"
  },
  "registry": "P:\\software\\_strap\\registry.json"
}
```

### Chinvex Integration
Strap optionally syncs to chinvex (semantic search system):
- Software repos → individual chinvex contexts (`context-name = repo-name`)
- Tool repos → shared `tools` context
- Archive repos → metadata-only entries in shared `archive` context

Integration points: clone, adopt, move, rename, uninstall. When chinvex operations fail, registry marks `chinvex_context: null` for reconciliation.

## Command Categories

### Template Bootstrapping
- `strap <name> -t <template>` - Create new project from template
- `strap templatize <name>` - Snapshot existing repo into new template
- `strap doctor` - Diagnose strap installation

Templates: `node-ts-service`, `node-ts-web`, `python`, `mono` (monorepo with Vite UI + Fastify server)

### Lifecycle Management
- `strap clone <url>` - Clone GitHub repo and register it
- `strap adopt` - Register existing repo
- `strap list` - Show all registered repos
- `strap open <name>` - Open repo folder
- `strap setup` - Install dependencies (auto-detects python/node/go/rust)
- `strap update <name>` - Pull latest changes
- `strap move <name> --dest <path>` - Relocate repo folder
- `strap rename <name> --to <new>` - Rename registry entry
- `strap shim <name> --- <command>` - Create global launcher
- `strap uninstall <name>` - Remove repo + shims + registry entry

### Consolidation Workflow
- `strap snapshot` - Capture environment state (repos, PATH, profiles, pm2, conda)
- `strap audit <name>` - Scan for path dependencies
- `strap archive <name>` - Move to archive location
- `strap consolidate --from <dir>` - Guided migration wizard

**DISABLED PENDING REVIEW:** `snapshot`, `audit`, `migrate`, and `consolidate` commands are currently disabled due to environment corruption incident (see `docs/incidents/2026-02-02-environment-corruption.md`). Do NOT attempt to enable or use these without thorough review.

## Development Commands

### Running Tests
```powershell
# Run all Pester tests in tests/powershell/
Invoke-Pester tests/powershell/

# Run specific test file
Invoke-Pester tests/powershell/KillSwitch.Tests.ps1

# Run single test with the provided wrapper
.\test_single.ps1  # Creates temp test, runs via Pester

# Run the configured test suite
.\run_tests.ps1  # Currently runs Invoke-Audit.Tests.ps1
```

### Manual Testing Scripts
- `test_manual.ps1` - Manual testing wrapper
- `test_one.ps1` - Single command testing
- `test_simple.ps1` - Simple smoke test
- `manual_verify_audit.ps1` - Manual audit verification

### Function Extraction Pattern
Tests extract functions from `strap.ps1` using brace-counting:
```powershell
function Extract-Function {
    param($Content, $FunctionName)
    # Finds "function FunctionName {" or "function FunctionName("
    # Counts braces to find matching close brace
    # Returns function source code
}
```

## Key Technical Patterns

### Atomic Registry Updates
Registry writes use temp file + atomic move:
```powershell
$tmpPath = "$registryPath.tmp"
$json | Set-Content $tmpPath
Move-Item -LiteralPath $tmpPath -Destination $registryPath -Force
```

### Path Normalization
All path comparisons use normalized lowercase:
```powershell
function Normalize-Path {
  [System.IO.Path]::GetFullPath($Path).ToLowerInvariant().Replace('/', '\').TrimEnd('\')
}
```

### Error Handling
- `Die($msg)` - Errors with ❌ prefix and exits
- `Warn($msg)` - Warnings via Write-Warning
- `Info($msg)` - Info with ➡️ prefix
- `Ok($msg)` - Success with ✅ prefix

### Chinvex Wrapper
```powershell
function Invoke-Chinvex {
    param([string[]]$Arguments)
    # Shells out to chinvex.cmd
    # Returns $true on success, $false on failure
    # Handles exit codes and output
}
```

## Context Hook System

`context-hook.cmd` / `context-hook.ps1` provide git commit hooks that:
1. Auto-generate project context files (AGENTS.md, CLAUDE.md, docs/project_notes/)
2. Skip on merge commits, lockfile-only changes, or commits with `[skip maintainer]`
3. Use Codex to maintain documentation based on commit diffs
4. Install via `context-hook.cmd install` in repo root

**Skip patterns:** commits with subject "...", notes/docs commits, chore/ci/style/refactor/test, releases, bot commits

## Templates Structure

```
templates/
  common/          # Shared baseline files
  node-ts-service/ # Fastify service (TypeScript, tsx, vitest)
  node-ts-web/     # Vite + TypeScript web app
  python/          # src-layout package (pytest + ruff)
  mono/            # pnpm workspace (apps/server, apps/ui, packages/shared)
```

Token replacement: `__REPO_NAME__`, `__PACKAGE_NAME__` in filenames and contents. Exclusions: `.git`, `node_modules`, `dist`, `build`, `coverage`, `.venv`, `__pycache__`.

## Environment Defaults

Templates use repo-root `.env`:
- Backend: `SERVER_HOST=0.0.0.0`, `SERVER_PORT=6969`
- Frontend: `UI_HOST=0.0.0.0`, `UI_PORT=5174`

Vite configured with `strictPort: true` and `allowedHosts: true` for Tailscale hostnames.

## Known Constraints

### Kill Switch
Functions in `$UNSAFE_COMMANDS` array are disabled pending review. Check `Assert-CommandSafe` before implementing features that touch: snapshot, audit, migration, consolidation.

### PowerShell Parameter Binding
`strap shim` with `---` separator can conflict with single-letter flags. Use `--cmd "command"` instead:
```powershell
# ✅ Recommended
strap shim flask --cmd "python -m flask run"

# ⚠️ May fail (PowerShell consumes -m)
strap shim flask --- python -m flask run
```

### PATH Length Limit
Windows User PATH limited to 2047 characters. Strap deduplicates and validates length.

### Scope Inference
- `P:\software\_scripts\` → `scope: tool`
- `P:\software\` (excluding `_scripts`) → `scope: software`
- `P:\software\_archive\` → `scope: archive`

Most specific path match wins (e.g., `_scripts` matches before `software`).

## Common Pitfalls

1. **Registry format changes**: Load/Save-Registry handle both legacy (array) and V1 (object) formats
2. **Case-insensitive paths**: Always use `Normalize-Path` for comparisons
3. **Atomic operations**: Registry must be transaction-safe (write to temp, then move)
4. **Chinvex failures**: Non-critical; mark `chinvex_context: null` and continue
5. **Git operations across volumes**: Use copy + verify + delete pattern (not move)

## Testing Philosophy

Tests use Pester framework. Extract functions from `strap.ps1` into test context, mock external dependencies (git, chinvex), verify behavior without side effects.

**Test structure:**
- `BeforeAll` - Extract functions, set up mocks
- `It` blocks - Individual test cases
- `AfterAll` - Cleanup

## Recovery Procedures

If registry becomes corrupted:
1. Check `registry.json.tmp` for partial writes
2. Use `strap doctor` to validate integrity
3. Use `strap adopt --scan <dir>` to rediscover repos
4. Reconcile chinvex with `strap sync-chinvex --reconcile` (when implemented)

## Integration with External Tools

- **Git**: All repos must be git repositories (`.git` directory required)
- **Chinvex**: Optional semantic search integration (fails gracefully if unavailable)
- **pm2**: Tracked by consolidation workflow (external reference detection)
- **Conda**: Environment state captured by snapshot (disabled)
- **Codex**: Used by context-hook for documentation generation

## Skills

`skills/strap-bootstrapper/SKILL.md` provides intent-based template selection for Codex/Claude:
- UI + backend → `mono`
- Backend-only → `node-ts-service`
- Frontend-only → `node-ts-web`
- Python tooling → `python`
