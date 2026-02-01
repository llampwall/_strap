# Dev Environment Consolidation Spec (DRAFT)

**Status:** Ready for /spec-refine
**Context:** strap

## Problem Statement

Projects are scattered across multiple locations:
- `C:\Code\`
- `P:\software\`
- `C:\Users\Jordan\Documents\Code\`

This causes:
- Inconsistent management (some in strap registry, some not)
- C: drive filling up
- No clear distinction between active projects and old experiments
- Manual hunting when looking for old code

Moving repos risks breaking:
- Hardcoded paths in scripts/configs
- Cross-repo references (repo A calls script in repo B)
- PM2/service configs
- Scheduled tasks
- Shims with absolute paths

## Target State

```
P:\software\           # active software (individual chinvex contexts)
P:\software\_scripts\  # tools (shared 'tools' context)
P:\software\_archive\  # old stuff (shared 'archive' context, minimal ingest)
```

All repos tracked in strap registry. All active repos have chinvex contexts (via strap-chinvex integration).

## New Commands

### `strap snapshot [--output <path>]`

Creates a JSON manifest of current state before migration.

```json
{
  "timestamp": "2026-02-01T00:45:00Z",
  "registry": { },
  "discovered": [
    {"path": "C:\\Code\\chinvex", "in_registry": true, "name": "chinvex"},
    {"path": "C:\\Code\\random-thing", "in_registry": false, "git": true, "last_commit": "2025-08-15"}
  ],
  "external_refs": {
    "pm2": [{"name": "chinvex-gateway", "cwd": "C:\\Code\\chinvex"}],
    "scheduled_tasks": [{"name": "MorningBrief", "path": "C:\\Code\\chinvex\\scripts\\morning_brief.ps1"}],
    "shims": [{"name": "chinvex", "target": "C:\\Code\\chinvex"}]
  }
}
```

**Purpose:** Safety net. Not a file backup - just a map of what's where.

**External ref detection:**
- PM2: parse `pm2 jlist`
- Scheduled tasks: `Get-ScheduledTask` + inspect Actions
- Shims: scan `build/shims/*.cmd`

### `strap adopt --scan <dir> [--recursive] [--dry-run] [--yes]`

Discovers git repos in a directory and adds them to registry.

```
Scanning C:\Code...

Found 12 git repos:
  chinvex        → already in registry
  streamside     → already in registry  
  random-thing   → NEW (would adopt as software)
  old-experiment → NEW (would adopt as software, last commit 2024-03)
  tiny-script    → NEW (would adopt as tool - single file)
  
Run with --yes to adopt all NEW repos.
```

**Scope detection heuristics:**
- Single script file + README → tool
- Last commit > 6 months ago → prompt for archive
- Otherwise → software

**Behavior:**
- Skips repos already in registry
- `--recursive` searches subdirectories (default: top-level only)
- `--dry-run` shows what would be adopted without writing
- `--yes` adopts all without prompting

### `strap audit <name|--all> [--json]`

Scans for path dependencies that would break on move. Checks both directions:
- **Outbound:** What does this repo depend on?
- **Inbound:** What other repos reference this repo?

```
Auditing chinvex (C:\Code\chinvex)...

Outbound refs (chinvex depends on):
  (none found)

Inbound refs (other repos depend on chinvex):
  - streamside: hooks/post-commit.ps1:8 → C:\Code\chinvex\scripts\sync.ps1
  - godex: src/memory.ts:23 → C:\Code\chinvex

External refs:
  - PM2: chinvex-gateway (cwd: C:\Code\chinvex)
  - Scheduled task: MorningBrief → C:\Code\chinvex\scripts\morning_brief.ps1
  - Shim: chinvex → C:\Code\chinvex

Config files with paths:
  - .env:3 → P:\ai_memory (OK - data dir, not repo path)

Summary:
  2 repos reference chinvex - will need updates after move
  2 external refs - will need manual fix after move
```

**Scan targets:**
- `*.ps1`, `*.cmd`, `*.bat` - PowerShell/batch scripts
- `*.ts`, `*.js`, `*.mjs` - JavaScript/TypeScript
- `*.py` - Python
- `*.json`, `*.yaml`, `*.yml` - Config files
- `.env*` - Environment files

**Behavior:**
- For single repo: scans that repo + scans all other registered repos for references to it
- For `--all`: builds full cross-reference matrix
- `--json` outputs structured data for tooling

### `strap archive <name> [--yes] [--dry-run]`

Moves a repo to the archive location.

```powershell
strap archive old-experiment --yes
```

Equivalent to:
```powershell
strap move old-experiment --dest P:\software\_archive\ --yes
```

**Chinvex behavior (via strap-chinvex integration):**
- Removes from individual context (if software)
- Removes from `tools` context (if tool)
- Adds to shared `archive` context
- Archive context gets minimal ingest: name, description (from README first line), last commit date

### `strap consolidate --from <dir> [--to <root>] [--dry-run] [--yes]`

The big operation: adopt + move in one pass.

```
Planning consolidation from C:\Code → P:\software...

Step 1: Adopt untracked repos
  random-thing     → adopt as software
  old-experiment   → adopt as archive (last commit: 2024-03-15)
  tiny-script      → adopt as tool

Step 2: Move repos
  chinvex          → P:\software\chinvex
  streamside       → P:\software\streamside
  random-thing     → P:\software\random-thing
  old-experiment   → P:\software\_archive\old-experiment
  tiny-script      → P:\software\_scripts\tiny-script

Potential breakage (from audit):
  chinvex:
    - streamside references C:\Code\chinvex (hooks/post-commit.ps1:8)
    - PM2 config points to C:\Code\chinvex
    - Scheduled task MorningBrief references C:\Code\chinvex

Run without --dry-run to execute.
After migration, run 'strap doctor' and fix any issues.
```

**Behavior:**
- Defaults `--to` based on scope (software root, tools root, archive root)
- Runs audit as part of planning
- Shows all potential breakage upfront
- Moves everything, updates registry
- Chinvex contexts handled automatically via strap-chinvex integration
- Does NOT auto-fix cross-repo references (manual)

## Archive Scope

New scope alongside `tool` and `software`:

```json
{
  "id": "old-experiment",
  "name": "old-experiment",
  "scope": "archive",
  "path": "P:\\software\\_archive\\old-experiment",
  "chinvex_context": "archive",
  "archived_at": "2026-02-01T01:00:00Z"
}
```

**Archive detection heuristic:**
- Last commit > 6 months ago → suggest archive
- User can override with `--software` or `--archive` flag

**Chinvex integration:**
- All archived repos share single `archive` context
- Minimal ingest per repo:
  - Name
  - Description (first line of README, or folder name)
  - Last commit date
  - Path
- Enables "what was that old project where I did X?" searches

## Config

Add to `build/config.json`:

```json
{
  "software_root": "P:\\software",
  "tools_root": "P:\\software\\_scripts",
  "archive_root": "P:\\software\\_archive",
  "archive_threshold_days": 180
}
```

## Migration Workflow

```powershell
# 1. Snapshot current state
strap snapshot --output pre-migration.json

# 2. See what's out there
strap adopt --scan "C:\Code" --dry-run
strap adopt --scan "C:\Users\Jordan\Documents\Code" --dry-run

# 3. Audit everything for potential breakage
strap audit --all

# 4. Do it
strap consolidate --from "C:\Code" --yes
strap consolidate --from "C:\Users\Jordan\Documents\Code" --yes

# 5. Validate
strap doctor

# 6. Fix what broke (probably a few PM2/task configs)

# 7. Delete empty source directories
```

## Acceptance Criteria

- [ ] `strap snapshot` captures registry + discovered repos + external refs
- [ ] `strap adopt --scan` finds git repos and adds to registry
- [ ] `strap audit` shows inbound + outbound path refs across all repos
- [ ] `strap audit` detects PM2, scheduled tasks, and shim references
- [ ] `strap archive` moves to archive root and updates chinvex context
- [ ] `strap consolidate` adopts + moves in one pass
- [ ] Archive scope exists alongside tool/software
- [ ] `archive` chinvex context receives minimal ingest (name, desc, date)
- [ ] Config supports `archive_root` and `archive_threshold_days`

## Out of Scope

- **Auto-fixing cross-repo references** - too risky, manual is fine
- **Symlinks/junctions** - unnecessary complexity
- **Topological move ordering** - just move everything, fix what breaks
- **File-level backup** - snapshot is metadata only; use git for actual backup

## Dependencies

- Strap-chinvex integration spec (for context creation/archival)

## Open Questions

1. Should `consolidate` stop on first error or continue and report all failures at end?
2. Should `audit` scan node_modules/venv or skip them? (probably skip)
3. Should archived repos be excluded from `strap update --all`? (probably yes)
