# CLAUDE.md

## Project

_strap - Complete Windows dev environment manager with template bootstrapping, lifecycle management, and automatic shim discovery

## Language

PowerShell

## Structure

- strap.ps1 - Main entry point with CLI dispatch
- strap.cmd - Batch wrapper for cross-shell compatibility
- modules/ - Core functionality modules (Commands/, Config, Chinvex, Audit, etc.)
- templates/ - Project templates (mono, node-ts-service, node-ts-web, python)
- tests/powershell/ - Pester 5 test suite
- docs/ - Documentation (chinvex integration, memory system, incidents)
- registry.json - Lifecycle management registry (V3 schema)
- config.json - System configuration

## Commands (PowerShell)

strap doctor                      # Diagnose installation and registry health
strap doctor --install-fnm        # Install fnm (Fast Node Manager) for Node version management
strap doctor --install-pyenv      # Install pyenv-win for Python version management
strap clone <url>                 # Clone repo and auto-create shims
strap adopt                       # Register existing repo with auto-shim discovery
strap setup --repo <name>         # Install dependencies (auto-detects Python/Node/Go/Rust)
strap list --verbose              # Show all managed repos with full details
strap shim <name> --cmd "<cmd>"   # Create global launcher shim
strap shim --regen <name>         # Regenerate shims (re-resolves executables)
strap update --all --yes          # Update all repos at once
strap move <name> --dest <path>   # Relocate repo and update registry
strap contexts                    # View chinvex sync status
Invoke-Pester tests/powershell/ -Output Detailed  # Run test suite

## Current Sprint

Stable operations - all major features implemented. Recent work: fnm integration for Node version management, setup status tracking (09af3e0), instant system-wide availability (f6c2f14), chinvex integration (bd509da).

## Architecture

- **Lifecycle Management**: Central registry tracks repos, shims, setup status, and metadata
- **Shim System v3.1**: Dual-file (.ps1 + .cmd) launchers in P:\software\bin for cross-shell compatibility
- **Auto-Discovery**: Parses pyproject.toml/setup.py/package.json to auto-create shims on clone/adopt
- **Version Management**: fnm for Node (auto-detects from .nvmrc/.node-version/package.json), pyenv-win for Python
- **Chinvex Integration**: Automatic sync with code intelligence (single source of truth)
- **Template Bootstrapping**: Four templates (mono, node-ts-service, node-ts-web, python) with token replacement
- **Metadata System**: Orthogonal fields (chinvex_depth, status, tags) replace single scope field

## Memory System

Chinvex repos use structured memory files in `docs/memory/`:

- **STATE.md**: Current objective, active work, blockers, next actions
- **CONSTRAINTS.md**: Infrastructure facts, rules, hazards (merge-only)
- **DECISIONS.md**: Append-only decision log with dated entries

**SessionStart Integration**: When you open a chinvex-managed repo, a hook runs `chinvex brief --context <name>` to load project context.

**If memory files are uninitialized** (empty or bootstrap templates), the brief will show "ACTION REQUIRED" instructing you to run `/update-memory`.

**The /update-memory skill** analyzes git history and populates memory files with:
- Current state from recent commits
- Constraints learned from bugs/infrastructure
- Decisions with evidence (commit hashes)

See `\docs\MEMORY_SYSTEM_HOW_IT_WORKS.md` and `docs/PROJECT_MEMORY_SPEC` for details.

## Rules

- Never run consolidate/audit/snapshot/migrate/archive commands (kill-switched since 2026-02-02)
- Use PowerShell (pwsh), not bash, for all shell operations on Windows
- Use `--cmd` for commands with single-letter flags (avoids PowerShell parameter binding)
- Registry updates must be atomic (save only after successful operations)
- Shims are dual-file (.ps1 + .cmd) and must remain in sync
- PowerShell unwraps single-element arrays (use comma operator: `,$array`)
- Unicode chars in output cause parsing errors (use ASCII: [OK], [X], [!])
- When opening a repo, check if brief shows "ACTION REQUIRED" - if so, offer to run `/update-memory`
- Chinvex integration is machine-level (global opt-out only via config.json)
- Reserved context names: "tools", "archive" (case-insensitive)
- Test with Pester 5 syntax (Should -Be, not Should Be; Should -Invoke, not Assert-MockCalled)
