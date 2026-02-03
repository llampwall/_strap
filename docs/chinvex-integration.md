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

Adopting an existing repository works similarly to clone, automatically creating the appropriate chinvex context:

```powershell
# Auto-detect scope from path
strap adopt --path P:\software\existing-repo

# Force tool scope
strap adopt --path P:\software\script --tool

# Skip chinvex integration
strap adopt --path P:\software\existing-repo --no-chinvex
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
