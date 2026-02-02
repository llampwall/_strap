# Strap-Chinvex Integration

**Status:** Approved
**Created:** 2026-01-31
**Updated:** 2026-02-02 (archive redesign)
**Context:** _strap (system-level integration)
**Refined by:** Claude Code + Codex debate (4 rounds)

## Problem Statement

Two independent systems track repositories without coordination:

- **Strap** maintains a registry (`registry.json`) of all cloned repos, providing lifecycle management (clone, setup, update, move, rename, uninstall)
- **Chinvex** maintains context configs (`P:\ai_memory\contexts\{name}\context.json`) for semantic search, requiring repo paths for ingestion

**Current pain:** Users must manually register repos in both systems. Changes in one (moving a repo via strap, adding a path to chinvex) don't propagate to the other. This creates:
- Double-work on every repo clone/uninstall
- Inevitable drift when registry and contexts fall out of sync
- No single source of truth for "what repos exist"

## Proposed Solution

**Strap becomes the source of truth for repo lifecycle.** Chinvex contexts are automatically created/updated/archived as a side effect of strap operations.

**Scope mapping:**
- Software repos (`strap clone --software` or default) → 1 chinvex context per repo (context name = repo name)
- Tool repos (`strap clone --tool`) → ALL tools share 1 chinvex context named `"tools"`

**Integration points:**
1. `strap clone` → creates chinvex context (or updates `tools` context includes)
2. `strap adopt` → creates chinvex context (or updates `tools` context includes)
3. `strap move` → updates chinvex context repo path (handles scope changes)
4. `strap rename` → renames chinvex context (software only; tools stay in `tools` context)
5. `strap uninstall` → archives chinvex context (software) OR removes repo from `tools` context (tool)

## Technical Approach

### 1. Strap Registry Extension

Add optional `chinvex_context` field to registry entries:

```json
{
  "id": "myrepo",
  "name": "myrepo",
  "scope": "software",
  "path": "P:\\software\\myrepo",
  "chinvex_context": "myrepo",  // NEW: null if not synced
  "shims": [],
  ...
}
```

For tools, `chinvex_context: "tools"` (shared).

### 2. Chinvex CLI Invocation

Strap will shell out to `chinvex` CLI (assumes chinvex is globally available via shim or PATH).

**Required Chinvex CLI contract:**

1. **`chinvex context create {name} [--idempotent]`**
   - Creates new context at `P:\ai_memory\contexts\{name}\context.json`
   - With `--idempotent`: succeeds silently if context already exists (default behavior: error if exists)
   - Returns exit code 0 on success, non-zero on failure

2. **`chinvex context exists {name}`**
   - Checks if context exists
   - Exit codes: `0` = exists, `1` = not found, `2+` = error (chinvex broken)
   - No output (silent check)
   - Strap should treat exit code 1 as expected (context doesn't exist), exit code 2+ as chinvex failure

3. **`chinvex context rename {old} --to {new}`**
   - Renames context directory and updates context.json name field
   - Fails if target name already exists
   - Returns exit code 0 on success, non-zero on failure

4. **`chinvex context archive {name}`**
   - Archives an existing managed context to the shared `archive` context
   - Extracts lightweight metadata (name + description) and adds entry to `archive` context
   - Description sourced from: context config, STATE.md Current Objective, or README.md first paragraph
   - Removes the original full context (frees the name, drops embeddings/chunks)
   - Succeeds silently if context doesn't exist (idempotent)
   - Returns exit code 0 on success, non-zero on failure
   - **Note:** The `archive` context is a table of contents — agents can see what existed without paying full storage cost

5. **`chinvex archive --name {name} --dir {path} [--desc {description}]`**
   - Archives an unmanaged directory directly to the `archive` context (no existing context required)
   - If `--desc` omitted, auto-generates from: STATE.md Current Objective → README.md first paragraph → "No description available"
   - Creates `archive` context if it doesn't exist
   - Idempotent: adding same name twice updates the entry
   - Returns exit code 0 on success, non-zero on failure
   - **Use case:** Archiving repos that were never ingested into chinvex

6. **`chinvex ingest --context {name} --repo {path} [--register-only]`**
   - With `--register-only`: adds repo path to context includes without running full ingestion
   - Without `--register-only`: adds path AND runs embedding/indexing (existing behavior)
   - **Assumes context exists** (fails if context missing; use `context create` first)
   - Idempotent: adding same path twice is a no-op (deduplicates)
   - Returns exit code 0 on success, non-zero on failure

7. **`chinvex context remove-repo {context} --repo {path}`**
   - Removes repo path from context includes
   - Succeeds silently if path not in includes (idempotent)
   - Returns exit code 0 on success, non-zero on failure

8. **`chinvex context list [--json]`**
   - Lists all contexts with metadata: name, repo count, last ingest timestamp
   - With `--json`: machine-readable output for `strap contexts` to consume
   - Returns exit code 0 on success, non-zero on failure

**Example invocations:**

```powershell
# Create context (idempotent)
chinvex context create myrepo --idempotent

# Register repo path only (no ingestion)
chinvex ingest --context myrepo --repo "P:\software\myrepo" --register-only

# Check if context exists (for conditional logic)
if (chinvex context exists tools) { ... }

# Rename context
chinvex context rename oldname --to newname

# Archive managed context (extracts metadata, removes full context)
chinvex context archive myrepo

# Archive unmanaged directory directly
chinvex archive --name old-experiment --dir "P:\software\old-experiment" --desc "Failed prototype from Q3"

# Remove repo from context includes
chinvex context remove-repo tools --repo "P:\software\_scripts\oldtool"
```

### 3. Command Behavior Changes

**`strap clone [--tool|--software]`:**
1. Clone repo as normal
2. Add to registry
3. **NEW:** If --software:
   - Invoke `chinvex context create {name} --idempotent`
   - Invoke `chinvex ingest --context {name} --repo {path} --register-only`
   - Set `chinvex_context: {name}` in registry
4. **NEW:** If --tool:
   - Invoke `chinvex context create tools --idempotent` (bootstrap on first tool)
   - Invoke `chinvex ingest --context tools --repo {path} --register-only`
   - Set `chinvex_context: "tools"` in registry

**`strap adopt [--tool|--software]`:**
1. Detect existing repo path
2. Add to registry
3. **NEW:** If --software:
   - Invoke `chinvex context create {name} --idempotent`
   - Invoke `chinvex ingest --context {name} --repo {path} --register-only`
   - Set `chinvex_context: {name}` in registry
4. **NEW:** If --tool:
   - Invoke `chinvex context create tools --idempotent`
   - Invoke `chinvex ingest --context tools --repo {path} --register-only`
   - Set `chinvex_context: "tools"` in registry

**`strap move {name} --dest {path}`:**

**Pre-flight validation (before filesystem move):**
- `software_root` = `P:\software` (from `config.json` or default)
- `tools_root` = `P:\software\_scripts` (from `config.json` or default)
- Validate destination is under `software_root` or `tools_root`
- If destination is outside both roots: **fail immediately** (no filesystem changes)

**Execution:**
1. Move repo folder to destination
2. Update registry `path` field to new location
3. **NEW:** Detect scope change based on destination path:
   - **Most specific path match wins** (e.g., `P:\software\_scripts` matches before `P:\software` for paths under `_scripts`)
   - If destination is under `tools_root` and current scope is `software`: scope becomes `tool`
   - If destination is under `software_root` (but NOT under `tools_root`) and current scope is `tool`: scope becomes `software`
4. **NEW:** If scope changed:
   - **Order: create → add → remove (rollback-safe)**
   - If new scope is `software`, create individual context: `chinvex context create {name} --idempotent`
   - If new scope is `tool`, create `tools` context: `chinvex context create tools --idempotent`
   - Add to new context: `chinvex ingest --context {new_context} --repo {new_path} --register-only`
   - If `ingest` succeeds:
     - Remove from old context: `chinvex context remove-repo {old_context} --repo {old_path}`
     - Update registry `scope` and `chinvex_context` fields
   - If `ingest` fails:
     - Log error
     - Set `chinvex_context: null` in registry (marks for reconciliation)
     - Keep `scope` unchanged (reconciliation needs to know target scope)
     - Continue (repo moved on disk, but chinvex sync broken; user runs `strap sync-chinvex --reconcile` to fix)
5. **NEW:** If scope unchanged:
   - **Order: add new path → remove old path**
   - Add new path: `chinvex ingest --context {context} --repo {new_path} --register-only`
   - If `ingest` succeeds:
     - Remove old path: `chinvex context remove-repo {context} --repo {old_path}`
   - If `ingest` fails:
     - Log error
     - Set `chinvex_context: null` in registry (marks for reconciliation)
     - Keep `scope` unchanged
     - Continue

**Note:**
- Scope changes are automatic when moving between `software_root` and `tools_root`. There is no dedicated scope-change command; use `strap move` to relocate the repo to the appropriate root.
- All Chinvex steps are skipped when `--no-chinvex` flag is passed or global config disables integration. **Exception:** `strap sync-chinvex` always runs regardless of flags/config (it's explicitly for chinvex management).
- Pre-flight validation intentionally blocks moves outside managed roots (hard guardrail to prevent registry drift). Use `strap uninstall` + manual move + `strap adopt` for non-standard relocations.

**`strap rename {name} --to {newName} [--move-folder]`:**
1. Rename registry entry (+ optionally folder)
2. **NEW:** If `scope=software`, invoke `chinvex context rename {oldName} --to {newName}`
3. **NEW:** If `scope=tool`, no chinvex action (stays in `tools` context)
4. **NEW:** If `--move-folder` was used (folder path changed), update repo path in chinvex context:
   - Add new path: `chinvex ingest --context {newName} --repo {new_path} --register-only`
   - Remove old path: `chinvex context remove-repo {newName} --repo {old_path}`

**`strap uninstall {name}`:**
1. Remove shims
2. Remove folder
3. **NEW:** If `scope=software`:
   - Invoke `chinvex context archive {context}`
4. **NEW:** If `scope=tool`:
   - Invoke `chinvex context remove-repo tools --repo {path}` (remove from shared context)
   - Never archive `tools` (shared by all tool repos)
5. Remove from registry

### 4. Opt-out Mechanism

**Flag-based opt-out:** Add `--no-chinvex` flag to all commands to skip integration:

```powershell
strap clone https://github.com/user/repo --no-chinvex
```

**Global config:** Add `config.json` with integration toggle:

```json
{
  "chinvex_integration": true  // default: true
}
```

**Precedence (highest to lowest):**
1. Explicit `--no-chinvex` flag (overrides config)
2. Explicit `--chinvex` flag (**deferred** — not implemented in this spec)
3. `config.json` value
4. Default (enabled)

**Note:** `strap sync-chinvex` ALWAYS runs regardless of config/flags (it's explicitly for chinvex management).

### 5. Discovery Commands

**`strap contexts`** - new command to list chinvex contexts and show sync status:

```powershell
strap contexts

# Output:
# Context         Type       Repos  Last Ingest    Sync Status
# myrepo          software   1      2026-01-30     ✓ synced
# tools           tool       9      2026-01-29     ✓ synced
# archive         system     15     2026-01-28     ✓ synced
# orphan-context  software   0      never          ⚠ no strap entry
```

**`strap sync-chinvex [--dry-run] [--reconcile]`** - reconcile strap registry with chinvex contexts:

- No flags (default): equivalent to `--dry-run` (safe — shows drift without making changes)
- `--dry-run`: Show what would change without making changes
- `--reconcile`: Apply reconciliation actions:
  - **Missing contexts:** Create contexts for strap entries that have `chinvex_context: null`
  - **Orphaned contexts:** Archive contexts that have no corresponding strap entry
  - **Whitelist:** Never archive system contexts: `tools`, `archive`
  - **Empty tools context:** If `tools` context exists but no tool repos in registry, keep it (don't archive)

**Reconciliation rules:**

| Scenario | Action |
|----------|--------|
| Registry entry (software) has `chinvex_context: null` | Create individual context + register repo path |
| Registry entry (tool) has `chinvex_context: null` | Create `tools` context (if missing) + register repo path |
| Context exists but no registry entry | Archive (unless whitelisted: `tools`, `archive`) |
| Registry entry points to missing context | Create context + register repo path (respects scope) |
| `tools` context empty (0 tool repos) | Keep (don't archive) |
| User-managed context (not in registry) | Archive UNLESS in whitelist |
| Tool repo removed from registry (orphan) | Remove repo path from `tools` context via `context remove-repo` |

**Whitelist (never auto-archive):**
- `tools` (system context for tool repos)
- `archive` (system context for archived repos)
- User can extend via `config.json`: `"chinvex_whitelist": ["custom-context"]`

**Orphan handling:**
When reconciling, if a repo path appears in a context but has no corresponding registry entry:
- For individual contexts (software): archive the entire context
- For `tools` context: remove just the orphaned repo path via `context remove-repo tools --repo {path}`

## Acceptance Criteria

- [ ] `strap clone` creates corresponding chinvex context (or updates `tools` context)
- [ ] `strap clone --tool` adds repo to shared `tools` context instead of individual context
- [ ] `strap adopt` creates chinvex context
- [ ] `strap move` updates chinvex context repo path
- [ ] `strap rename` renames chinvex context (software only)
- [ ] `strap uninstall` archives chinvex context (software) or removes from `tools` (tool)
- [ ] `--no-chinvex` flag skips integration on all commands
- [ ] `strap contexts` lists all contexts and sync status
- [ ] `strap sync-chinvex --dry-run` shows drift without changes
- [ ] `strap sync-chinvex --reconcile` fixes drift automatically
- [ ] Registry entries have `chinvex_context` field
- [ ] Integration is idempotent (running twice doesn't break state)
- [ ] Errors from chinvex CLI are caught and logged (don't break strap operations)
- [ ] All chinvex failures set `chinvex_context: null` in registry (canonical error handling)
- [ ] Scope detection uses most-specific path match (tools_root before software_root)
- [ ] `strap rename --move-folder` updates repo path in chinvex context
- [ ] `strap clone`/`strap adopt` rejects reserved context names (`tools`, `archive`) for software repos
- [ ] `strap sync-chinvex` without flags defaults to dry-run

## Edge Cases

1. **Chinvex not installed:** Commands should warn but not fail. Set `chinvex_context: null` in registry.
2. **Chinvex context already exists:** On clone/adopt, use `chinvex context create --idempotent` which succeeds silently if context exists. Then `ingest --register-only` adds path (deduplicates automatically).
3. **Registry has entry but chinvex context missing:** `strap sync-chinvex --reconcile` creates missing context.
4. **Chinvex has context but no strap entry:** `strap contexts` flags as orphan. `--reconcile` archives it.
5. **Moving repo between scopes (tool ↔ software):**
   - **Order: create context → add to new context → remove from old context**
   - Create new context if needed (idempotent)
   - Add repo path to new context via `chinvex ingest --register-only`
   - Remove repo path from old context via `chinvex context remove-repo`
   - Update registry `scope` and `chinvex_context` fields
   - Example: software→tool creates `tools` (if missing), adds to `tools`, removes from individual context
6. **Renaming folder but not registry entry:** Chinvex path stays stale until `strap move` is used.
7. **Manual chinvex path edits:** Not detected by strap. User must use strap commands for consistency.
8. **Running strap clone twice for same repo:** Idempotency guaranteed by `--idempotent` flag on `chinvex context create` and `--register-only` deduplication in chinvex (path already in includes = no-op).
9. **Repo name collides with reserved context name:** If a software repo is named `tools` or `archive` (reserved system context names), `strap clone`/`strap adopt` must reject or namespace it (e.g., `software-tools`). Reserved names: `tools`, `archive`.

## Out of Scope

- **Automatic ingestion:** Strap won't run full `chinvex ingest` (embeddings). Users run `chinvex ingest --context {name}` separately.
- **Chinvex MCP integration:** This spec only covers CLI integration, not MCP server changes.
- **Bi-directional sync:** Chinvex changes won't trigger strap registry updates. Strap is the source of truth.
- **Legacy config migration:** Existing chinvex contexts not created by strap won't be auto-imported.

## Implementation Notes

**Dependency check:** Before first chinvex invocation, check if `chinvex` command exists:

```powershell
$chinvexAvailable = Get-Command chinvex -ErrorAction SilentlyContinue
if (-not $chinvexAvailable) {
  Write-Warning "Chinvex not found. Install and create a shim via: strap shim chinvex ..."
  return
}
```

**Error handling:** Wrap all chinvex calls in try-catch. Log errors but don't abort strap operation. **Canonical rule:** any chinvex failure sets `chinvex_context: null` in registry and continues. `strap sync-chinvex --reconcile` cleans up later.

```powershell
try {
  & chinvex context create $contextName
} catch {
  Write-Warning "Failed to create chinvex context: $_"
  $entry.chinvex_context = $null  # Mark for reconciliation
  # Continue with strap operation
}
```

**Testing strategy:**
1. Unit tests for registry schema changes (validate `chinvex_context` field)
2. Integration tests for each command (mock chinvex CLI calls)
3. E2E smoke test: clone repo, move it, rename it, uninstall it, verify chinvex contexts at each step
