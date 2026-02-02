# Strap-Chinvex Integration — PowerShell Implementation Plan

**TARGET: PowerShell. All code goes in `strap.ps1`. No TypeScript. No Node.js.**

**Generated:** 2026-02-02
**Replaces:** `strap-chinvex-integration-plan.md` (TypeScript, obsolete)
**Source Spec:** `docs/specs/strap-chinvex-integration.md` (approved, 4-round debate)
**Execution Model:** Batched (3 tasks per batch, verify between each)

---

## Context

Strap is a single-file PowerShell tool (`strap.ps1`). All new functions go in this file.
The spec defines WHAT to build. This plan defines WHERE each piece goes in strap.ps1.

### What Already Exists in strap.ps1

**Output helpers:** `Die`, `Info`, `Ok`, `Warn`
**Config/Registry:** `Load-Config`, `Load-Registry`, `Save-Registry`, `Get-RegistryVersion`
**Command availability:** `Has-Command`, `Ensure-Command`
**Lifecycle commands:** `Invoke-Clone`, `Invoke-Adopt`, `Invoke-Move`, `Invoke-Rename`, `Invoke-Uninstall`
**Other commands:** `Invoke-Shim`, `Invoke-Setup`, `Invoke-Update`, `Invoke-List`, `Invoke-Open`, `Invoke-Doctor`
**CLI dispatch:** `Show-Help` + main switch at bottom of file
**Arg parsing:** `Apply-ExtraArgs`

### What Does NOT Exist Yet

- `scope` field on registry entries (needs to be added)
- `chinvex_context` field on registry entries (needs to be added)
- `--tool` / `--software` flags on clone/adopt (needs to be added)
- `--no-chinvex` flag (needs to be added)
- Any chinvex-related functions
- `strap contexts` or `strap sync-chinvex` commands

### Registry State

Registry is currently **empty** (0 entries). No migration script needed — just ensure new entries get the right fields from the start.

---

## Incident Lessons (Non-Negotiable)

From the 2026-02-02 environment corruption:

1. **No environment writes.** Chinvex integration ONLY calls the `chinvex` CLI and updates `registry.json`. No PATH modifications, no profile edits, no env var changes, no conda commands.
2. **Kill switch works independently.** Both `--no-chinvex` flag AND `config.json` toggle must independently disable integration. Test both.
3. **No parallel subagents.** Each batch = one Claude Code session. Do not spawn subagents.
4. **Memory guard.** If a batch is getting complex, stop and split it. Do not let a single session grow unbounded.
5. **Test before commit.** Every task has a verification step. Don't commit blind.
6. **Read-only by default.** New functions must not modify the filesystem outside of registry.json and chinvex CLI calls.

---

## New Functions to Add (all in strap.ps1)

### Foundation Functions

| Function | Purpose | Returns |
|----------|---------|---------|
| `Test-ChinvexAvailable` | Cached check: is `chinvex` command on PATH? | `[bool]` |
| `Test-ChinvexEnabled` | Should chinvex run? (flag > config > default) | `[bool]` |
| `Invoke-Chinvex` | CLI wrapper: runs chinvex with args, handles errors | `[bool]` ($true = exit 0) |
| `Invoke-ChinvexQuery` | CLI wrapper for commands that return output (e.g. `context list --json`) | `[string]` or `$null` |
| `Detect-RepoScope` | Path → 'software' or 'tool' (most-specific match) | `[string]` or `$null` |
| `Get-ContextName` | Scope + entry name → context name | `[string]` ('tools' or entry name) |
| `Test-ReservedContextName` | Rejects 'tools', 'archive' for software scope | `[bool]` ($true = reserved) |
| `Sync-ChinvexForEntry` | High-level: create context + register path | `[string]` (context name) or `$null` |

### New Commands

| Function | CLI Command | Purpose |
|----------|-------------|---------|
| `Invoke-Contexts` | `strap contexts` | List all chinvex contexts with sync status |
| `Invoke-SyncChinvex` | `strap sync-chinvex` | Reconcile registry ↔ chinvex contexts |

### Modified Functions

| Function | Changes |
|----------|---------|
| `Invoke-Clone` | Add `--tool`/`--software`/`--no-chinvex` flags, set `scope` + `chinvex_context` on entry, call `Sync-ChinvexForEntry` |
| `Invoke-Adopt` | Add `--tool`/`--software`/`--no-chinvex` flags, auto-detect scope from path, call `Sync-ChinvexForEntry` |
| `Invoke-Move` | Add `--no-chinvex`, detect scope change, update chinvex path or handle scope transition |
| `Invoke-Rename` | Add `--no-chinvex`, rename chinvex context (software), update paths if `--move-folder` |
| `Invoke-Uninstall` | Add `--no-chinvex`, archive context (software) or remove-repo (tool) |
| `Load-Config` | Add defaults for `chinvex_integration`, `chinvex_whitelist`, `software_root`, `tools_root` |
| `Show-Help` | Add `contexts`, `sync-chinvex` commands, document `--no-chinvex`/`--tool`/`--software` flags |

---

## Batched Execution Plan

### Batch 1: Foundation (Tasks 1–3)

**Goal:** Config defaults, chinvex CLI wrapper, integration helpers. Nothing touches existing commands yet.

#### Task 1: Config Schema Extension

**Where:** Modify `Load-Config` function in strap.ps1

**Changes:**
- After loading `config.json`, apply defaults for missing keys:
  ```powershell
  if ($null -eq $config.chinvex_integration) { $config | Add-Member -NotePropertyName chinvex_integration -NotePropertyValue $true }
  if ($null -eq $config.chinvex_whitelist) { $config | Add-Member -NotePropertyName chinvex_whitelist -NotePropertyValue @("tools") }
  if ($null -eq $config.software_root) { $config | Add-Member -NotePropertyName software_root -NotePropertyValue "P:\software" }
  if ($null -eq $config.tools_root) { $config | Add-Member -NotePropertyName tools_root -NotePropertyValue "P:\software\_scripts" }
  ```
- If `config.json` doesn't exist, create it with these defaults on first access (or just use in-memory defaults)

**Config schema (config.json):**
```json
{
  "chinvex_integration": true,
  "chinvex_whitelist": ["tools"],
  "software_root": "P:\\software",
  "tools_root": "P:\\software\\_scripts"
}
```

**Verify:** `Load-Config` returns object with all 4 chinvex fields populated even when config.json is empty or missing.

---

#### Task 2: Chinvex CLI Wrapper

**Where:** Add new functions in strap.ps1 (insert after utility functions, before command functions)

**Functions:**

```powershell
# Script-level cache for chinvex availability
$script:chinvexChecked = $false
$script:chinvexAvailable = $false

function Test-ChinvexAvailable {
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
    param(
        [switch] $NoChinvex  # from --no-chinvex flag
    )
    # Flag overrides everything
    if ($NoChinvex) { return $false }
    # Config check
    $config = Load-Config
    if ($config.chinvex_integration -eq $false) { return $false }
    # Default: enabled, but only if chinvex is actually installed
    return (Test-ChinvexAvailable)
}

function Invoke-Chinvex {
    # Runs chinvex CLI command. Returns $true on exit 0, $false otherwise.
    # Does NOT throw — caller checks return value.
    param(
        [Parameter(Mandatory)][string[]] $Arguments
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
    # Runs chinvex CLI command and returns stdout. Returns $null on failure.
    param(
        [Parameter(Mandatory)][string[]] $Arguments
    )
    if (-not (Test-ChinvexAvailable)) { return $null }
    try {
        $output = & chinvex @Arguments 2>$null
        if ($LASTEXITCODE -eq 0) { return ($output -join "`n") }
        return $null
    } catch {
        Warn "Chinvex query error: $_"
        return $null
    }
}
```

**Verify:**
- `Test-ChinvexAvailable` returns `$false` when chinvex not on PATH (rename chinvex shim temporarily to test)
- `Test-ChinvexAvailable` caches result (call twice, only one warning)
- `Invoke-Chinvex "context" "list"` returns `$true` when chinvex is running
- `Invoke-Chinvex "nonsense"` returns `$false`, no exception thrown

---

#### Task 3: Integration Helpers

**Where:** Add after CLI wrapper functions

**Functions:**

```powershell
function Detect-RepoScope {
    # Returns 'tool', 'software', or $null (outside managed roots).
    # Most-specific match wins: tools_root checked before software_root.
    param(
        [Parameter(Mandatory)][string] $Path
    )
    $config = Load-Config
    $normalPath = (Normalize-Path $Path)  # existing strap function
    $toolsRoot = (Normalize-Path $config.tools_root)
    $softwareRoot = (Normalize-Path $config.software_root)

    if ($normalPath.StartsWith($toolsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'tool'
    }
    if ($normalPath.StartsWith($softwareRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return 'software'
    }
    return $null
}

function Get-ContextName {
    # Scope + name → chinvex context name.
    # Tools share one context. Software gets individual contexts.
    param(
        [Parameter(Mandatory)][string] $Scope,
        [Parameter(Mandatory)][string] $Name
    )
    if ($Scope -eq 'tool') { return 'tools' }
    return $Name
}

function Test-ReservedContextName {
    # Returns $true if name is reserved and scope is 'software'.
    # Reserved names: 'tools', 'archive'
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $Scope
    )
    if ($Scope -ne 'software') { return $false }
    $reserved = @('tools', 'archive')
    return ($reserved -contains $Name.ToLower())
}

function Sync-ChinvexForEntry {
    # High-level: create context + register repo path.
    # Returns context name on success, $null on failure.
    # Canonical rule: any failure returns $null (caller sets chinvex_context = $null).
    param(
        [Parameter(Mandatory)][string] $Scope,
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $RepoPath
    )
    $contextName = Get-ContextName -Scope $Scope -Name $Name

    # Step 1: Create context (idempotent)
    $created = Invoke-Chinvex "context", "create", $contextName, "--idempotent"
    if (-not $created) {
        Warn "Failed to create chinvex context '$contextName'"
        return $null
    }

    # Step 2: Register repo path (no full ingestion)
    $registered = Invoke-Chinvex "ingest", "--context", $contextName, "--repo", $RepoPath, "--register-only"
    if (-not $registered) {
        Warn "Failed to register repo in chinvex context '$contextName'"
        return $null
    }

    Info "Synced to chinvex context: $contextName"
    return $contextName
}
```

**Verify:**
- `Detect-RepoScope "P:\software\_scripts\foo"` → `'tool'`
- `Detect-RepoScope "P:\software\myrepo"` → `'software'`
- `Detect-RepoScope "C:\random\path"` → `$null`
- `Get-ContextName -Scope 'tool' -Name 'sometool'` → `'tools'`
- `Get-ContextName -Scope 'software' -Name 'myrepo'` → `'myrepo'`
- `Test-ReservedContextName -Name 'tools' -Scope 'software'` → `$true`
- `Test-ReservedContextName -Name 'tools' -Scope 'tool'` → `$false`
- `Test-ReservedContextName -Name 'myrepo' -Scope 'software'` → `$false`

---

### Batch 2: Clone & Adopt (Tasks 4–6)

**Goal:** First two lifecycle commands get chinvex integration. Registry entries start including `scope` and `chinvex_context`.

#### Task 4: Invoke-Clone — Chinvex Integration

**Where:** Modify existing `Invoke-Clone` function

**Changes:**

1. **Add parameters:** `[switch] $Tool`, `[switch] $Software`, `[switch] $NoChinvex`
   - Wire into `Apply-ExtraArgs` / CLI dispatch so `--tool`, `--software`, `--no-chinvex` flags work
   - Default: `--software` (if neither flag given, scope = 'software')
   - Error if both `--tool` and `--software` given

2. **Determine scope:**
   ```powershell
   $scope = if ($Tool) { 'tool' } else { 'software' }
   ```

3. **Reserved name check (before registry write):**
   ```powershell
   if (Test-ReservedContextName -Name $repoName -Scope $scope) {
       Die "Cannot use reserved name '$repoName' for software repos. Reserved names: tools, archive"
   }
   ```

4. **Set fields on registry entry (during entry creation):**
   ```powershell
   $entry.scope = $scope
   $entry.chinvex_context = $null  # default, updated below
   ```

5. **Chinvex sync (after registry write, before final save):**
   ```powershell
   if (Test-ChinvexEnabled -NoChinvex:$NoChinvex) {
       $contextName = Sync-ChinvexForEntry -Scope $scope -Name $repoName -RepoPath $repoPath
       $entry.chinvex_context = $contextName  # $null on failure
       Save-Registry $registry  # persist chinvex_context update
   }
   ```

**Verify:**
- `strap clone https://github.com/user/repo` → registry entry has `scope: "software"`, `chinvex_context: "repo"` (or `$null` if chinvex unavailable)
- `strap clone https://github.com/user/tool --tool` → registry entry has `scope: "tool"`, `chinvex_context: "tools"`
- `strap clone https://github.com/user/repo --no-chinvex` → registry entry has `chinvex_context: null`
- `strap clone https://github.com/user/tools` → rejected ("reserved name")
- Chinvex not installed → warning logged, `chinvex_context: null`, clone completes

---

#### Task 5: Invoke-Adopt — Chinvex Integration

**Where:** Modify existing `Invoke-Adopt` function

**Changes:**

1. **Add parameters:** `[switch] $Tool`, `[switch] $Software`, `[switch] $NoChinvex`
   - Wire into CLI dispatch

2. **Auto-detect scope from path (if no flag given):**
   ```powershell
   if ($Tool) {
       $scope = 'tool'
   } elseif ($Software) {
       $scope = 'software'
   } else {
       $scope = Detect-RepoScope -Path $repoPath
       if ($null -eq $scope) {
           Warn "Path is outside managed roots. Defaulting to 'software'. Use --tool or --software to override."
           $scope = 'software'
       }
       Info "Auto-detected scope: $scope (from path)"
   }
   ```

3. **Reserved name check, scope field, chinvex sync:** Same pattern as Invoke-Clone (Task 4).

**Verify:**
- `strap adopt --path P:\software\myrepo` → auto-detects `scope: "software"`, creates context
- `strap adopt --path P:\software\_scripts\tool` → auto-detects `scope: "tool"`, adds to tools context
- `strap adopt --path P:\software\myrepo --tool` → explicit override, `scope: "tool"`
- `strap adopt --path C:\random\repo` → warns "outside managed roots", defaults to software

---

#### Task 6: CLI Dispatch Wiring

**Where:** Modify CLI dispatch (main switch block at bottom of strap.ps1) + `Apply-ExtraArgs` + `Show-Help`

**Changes:**

1. **Add global `--no-chinvex` flag** recognition in `Apply-ExtraArgs` (or wherever extra flags are parsed)
   - Extract `--no-chinvex` from args, pass as `$NoChinvex` switch to command functions
   - Extract `--tool` / `--software` from args, pass as switches

2. **Update `Show-Help`** to document:
   - `--tool` / `--software` flags on clone and adopt
   - `--no-chinvex` flag (global, works on all commands)

3. **Ensure `scope` and `chinvex_context` fields survive registry round-trip:**
   - `Save-Registry` / `Load-Registry` should preserve unknown fields (they likely already do since it's JSON)
   - Verify: save entry with `scope` + `chinvex_context`, reload, fields present

**Verify:**
- `strap clone https://github.com/user/repo --no-chinvex` → NoChinvex flag reaches Invoke-Clone
- `strap adopt --path P:\software\repo --tool` → Tool flag reaches Invoke-Adopt
- Registry round-trip preserves `scope` and `chinvex_context` fields
- `strap help` shows new flags

---

### Batch 3: Move, Rename, Uninstall (Tasks 7–9)

**Goal:** Remaining lifecycle commands handle chinvex context updates including scope transitions.

#### Task 7: Invoke-Move — Chinvex Integration

**Where:** Modify existing `Invoke-Move` function

**Changes:**

1. **Add parameters:** `[switch] $NoChinvex`

2. **Pre-flight: validate destination under managed roots:**
   ```powershell
   $destScope = Detect-RepoScope -Path $destPath
   if ($null -eq $destScope) {
       Die "Destination '$destPath' is outside managed roots. Use strap uninstall + manual move + strap adopt instead."
   }
   ```

3. **After filesystem move + registry path update, if chinvex enabled:**

   **Case A — No scope change (same scope before and after):**
   ```powershell
   $oldScope = $entry.scope
   $newScope = $destScope

   if ($oldScope -eq $newScope) {
       $contextName = Get-ContextName -Scope $newScope -Name $entry.name
       # Add new path first, then remove old
       $added = Invoke-Chinvex "ingest", "--context", $contextName, "--repo", $destPath, "--register-only"
       if ($added) {
           Invoke-Chinvex "context", "remove-repo", $contextName, "--repo", $oldPath | Out-Null
       } else {
           $entry.chinvex_context = $null
       }
   }
   ```

   **Case B — Scope change (e.g. software → tool):**
   ```powershell
   if ($oldScope -ne $newScope) {
       $newContextName = Get-ContextName -Scope $newScope -Name $entry.name
       $oldContextName = Get-ContextName -Scope $oldScope -Name $entry.name

       # Order: create → add → remove (rollback-safe)
       $created = Invoke-Chinvex "context", "create", $newContextName, "--idempotent"
       if ($created) {
           $added = Invoke-Chinvex "ingest", "--context", $newContextName, "--repo", $destPath, "--register-only"
           if ($added) {
               # Remove from old context
               if ($oldScope -eq 'software') {
                   Invoke-Chinvex "context", "archive", $oldContextName | Out-Null
               } else {
                   Invoke-Chinvex "context", "remove-repo", $oldContextName, "--repo", $oldPath | Out-Null
               }
               $entry.scope = $newScope
               $entry.chinvex_context = $newContextName
           } else {
               $entry.chinvex_context = $null  # mark for reconciliation
           }
       } else {
           $entry.chinvex_context = $null
       }
       Save-Registry $registry
   }
   ```

**Verify:**
- Move within software root → chinvex path updated, scope unchanged
- Move from software root to tools root → old context archived, added to tools
- Move from tools root to software root → removed from tools, new context created
- Move to path outside roots → rejected before filesystem move
- Chinvex failure → `chinvex_context: null`, move still succeeds

---

#### Task 8: Invoke-Rename — Chinvex Integration

**Where:** Modify existing `Invoke-Rename` function

**Changes:**

1. **Add parameters:** `[switch] $NoChinvex`

2. **After registry rename, if chinvex enabled:**
   ```powershell
   if ($entry.scope -eq 'software' -and $entry.chinvex_context) {
       # Rename the chinvex context
       $renamed = Invoke-Chinvex "context", "rename", $oldName, "--to", $newName
       if ($renamed) {
           $entry.chinvex_context = $newName
       } else {
           $entry.chinvex_context = $null
       }
   }
   # Tool scope: no chinvex action (stays in 'tools' context)
   ```

3. **If `--move-folder` was used and path changed:**
   ```powershell
   if ($folderMoved -and $entry.chinvex_context) {
       $contextName = $entry.chinvex_context
       $added = Invoke-Chinvex "ingest", "--context", $contextName, "--repo", $newPath, "--register-only"
       if ($added) {
           Invoke-Chinvex "context", "remove-repo", $contextName, "--repo", $oldPath | Out-Null
       } else {
           $entry.chinvex_context = $null
       }
   }
   ```

**Verify:**
- Rename software repo → chinvex context renamed
- Rename tool repo → no chinvex action (still in 'tools')
- Rename with `--move-folder` → path updated in context
- Chinvex rename fails (target exists) → `chinvex_context: null`, strap rename still succeeds

---

#### Task 9: Invoke-Uninstall — Chinvex Integration

**Where:** Modify existing `Invoke-Uninstall` function

**Changes:**

1. **Add parameters:** `[switch] $NoChinvex`

2. **Before removing from registry (chinvex cleanup first):**
   ```powershell
   if (Test-ChinvexEnabled -NoChinvex:$NoChinvex) {
       if ($entry.scope -eq 'software' -and $entry.chinvex_context) {
           Invoke-Chinvex "context", "archive", $entry.chinvex_context | Out-Null
       }
       elseif ($entry.scope -eq 'tool' -and $entry.chinvex_context) {
           Invoke-Chinvex "context", "remove-repo", "tools", "--repo", $entry.path | Out-Null
           # Never archive 'tools' context
       }
   }
   ```

3. **Then remove from registry as normal.**

**Verify:**
- Uninstall software repo → chinvex context archived
- Uninstall tool repo → removed from tools context, tools context still exists
- Uninstall with `--no-chinvex` → no chinvex actions
- Chinvex archive fails → warning, uninstall still completes

---

### Batch 4: Discovery & Reconciliation (Tasks 10–12)

**Goal:** New commands for visibility and drift repair.

#### Task 10: Invoke-Contexts

**Where:** New function in strap.ps1 + CLI dispatch entry

**Behavior:**
1. Load registry via `Load-Registry`
2. Query chinvex: `Invoke-ChinvexQuery "context", "list", "--json"`
3. Parse JSON output to get list of contexts with metadata
4. Cross-reference:
   - For each registry entry with `chinvex_context`: mark as synced
   - For each chinvex context with no registry entry: mark as orphan
   - For each registry entry with `chinvex_context: null`: mark as unsynced
5. Output formatted table:
   ```
   Context         Type       Repos  Last Ingest    Sync Status
   myrepo          software   1      2026-01-30     ✓ synced
   tools           tool       9      2026-01-29     ✓ synced
   orphan-ctx      unknown    0      never          ⚠ no strap entry
   myrepo2         software   -      -              ✗ not synced
   ```

**Verify:**
- Shows synced entries from registry
- Shows orphaned contexts from chinvex
- Shows unsynced entries (chinvex_context: null)
- Works when chinvex is unavailable (shows registry-only view with warning)

---

#### Task 11: Invoke-SyncChinvex

**Where:** New function in strap.ps1 + CLI dispatch entry

**Parameters:** `[switch] $DryRun`, `[switch] $Reconcile`
**Default (no flags):** equivalent to `--dry-run`

**Reconciliation logic:**
```
1. Load registry + chinvex context list
2. For each registry entry with chinvex_context = $null:
   → Create context + register path (respects scope)
3. For each registry entry pointing to missing context:
   → Create context + register path
4. For each chinvex context with no registry entry:
   → Archive (unless whitelisted)
5. For orphaned repo paths in 'tools' context:
   → Remove via context remove-repo
```

**Whitelist:** `['tools'] + config.chinvex_whitelist`

**Dry-run output:**
```
Would create context 'myrepo' for registry entry 'myrepo'
Would archive orphaned context 'old-project'
Would remove orphaned path 'P:\software\_scripts\deleted-tool' from 'tools' context
```

**Reconcile output:**
```
✓ Created context 'myrepo'
✓ Archived orphaned context 'old-project'
✗ Failed to remove orphaned path (chinvex error)
```

**Important:** This command ALWAYS runs regardless of `--no-chinvex` flag or config. It IS the chinvex management command.

**Verify:**
- `strap sync-chinvex` (no flags) → shows drift, makes no changes
- `strap sync-chinvex --dry-run` → same
- `strap sync-chinvex --reconcile` → creates missing contexts, archives orphans
- Whitelisted contexts ('tools') never archived
- Empty tools context preserved (not archived)

---

#### Task 12: CLI Dispatch + Help Text

**Where:** Main switch block + `Show-Help`

**Changes:**

1. **Add dispatch entries:**
   ```powershell
   "contexts"      { Invoke-Contexts @extraArgs }
   "sync-chinvex"  { Invoke-SyncChinvex @extraArgs }
   ```

2. **Update Show-Help** to include:
   ```
   COMMANDS:
     clone <url> [--tool|--software] [--no-chinvex]  Clone and register a repo
     adopt [--path <dir>] [--tool|--software] [--no-chinvex]  Adopt existing repo
     move <name> --dest <path> [--no-chinvex]  Move repo to new location
     rename <name> --to <new> [--move-folder] [--no-chinvex]  Rename repo
     uninstall <name> [--no-chinvex]  Remove repo
     list  List registered repos
     contexts  List chinvex contexts and sync status
     sync-chinvex [--dry-run|--reconcile]  Reconcile registry with chinvex

   FLAGS:
     --tool        Register as tool (shared 'tools' context)
     --software    Register as software (individual context, default)
     --no-chinvex  Skip chinvex integration for this command
   ```

**Verify:**
- `strap contexts` dispatches to Invoke-Contexts
- `strap sync-chinvex` dispatches to Invoke-SyncChinvex
- `strap help` shows all new commands and flags

---

### Batch 5: Edge Cases & Polish (Tasks 13–14)

**Goal:** Validate idempotency, error paths, and document everything.

#### Task 13: Idempotency & Error Path Validation

**Manual test script** (not committed, run interactively):

```powershell
# 1. Clone same repo twice — no errors, state unchanged
strap clone https://github.com/user/testrepo
strap clone https://github.com/user/testrepo  # should be idempotent or error cleanly

# 2. Adopt already-adopted repo — no errors
strap adopt --path P:\software\testrepo

# 3. Chinvex unavailable — operations succeed with warnings
# (temporarily rename chinvex shim)
Rename-Item P:\software\_scripts\chinvex.ps1 chinvex.ps1.bak
strap clone https://github.com/user/testrepo2  # should warn, set chinvex_context: null
Rename-Item P:\software\_scripts\chinvex.ps1.bak chinvex.ps1

# 4. Reconcile fixes the above
strap sync-chinvex --reconcile  # should create context for testrepo2

# 5. Reserved name rejection
strap clone https://github.com/user/tools  # should error

# 6. Full lifecycle
strap clone https://github.com/user/lifecycle-test
strap move lifecycle-test --dest P:\software\_scripts\lifecycle-test  # software → tool
strap rename lifecycle-test --to renamed-tool
strap uninstall renamed-tool
strap contexts  # should show clean state
```

#### Task 14: Documentation

**Where:** `docs/chinvex-integration.md` (new) + README.md updates

**Content:**
- Overview: strap is source of truth, chinvex follows
- Scope mapping (software = individual, tool = shared 'tools')
- Command-by-command behavior
- Opt-out: `--no-chinvex` flag, `config.json` toggle
- Reconciliation: when to run `strap sync-chinvex`
- Troubleshooting: chinvex not found, drift recovery

---

## Chinvex CLI Contract (What Must Exist on Chinvex Side)

These chinvex CLI commands are REQUIRED by this integration. If any don't exist yet, they need to be implemented in chinvex before the corresponding strap batch.

| Command | Required By | Exists? |
|---------|-------------|---------|
| `chinvex context create {name} [--idempotent]` | Batch 2 | **CHECK** |
| `chinvex context exists {name}` | Batch 4 | **CHECK** |
| `chinvex context rename {old} --to {new}` | Batch 3 | **CHECK** |
| `chinvex context archive {name}` | Batch 3 | **CHECK** |
| `chinvex ingest --context {name} --repo {path} [--register-only]` | Batch 2 | **CHECK** |
| `chinvex context remove-repo {context} --repo {path}` | Batch 3 | **CHECK** |
| `chinvex context list [--json]` | Batch 4 | **CHECK** |

**Before starting Batch 2:** Verify which commands exist. Missing commands need stubs or full implementation on the chinvex side first.

---

## Execution Strategy

1. **Before each batch:** Review task descriptions. Ask questions if anything is unclear.
2. **During batch:** Implement 3 tasks. Test each. Commit atomically.
3. **After each batch:** Run verification steps. Report results. Wait for approval.
4. **Between batches:** User reviews, may request changes before next batch proceeds.
5. **Rollback:** Each batch is one commit. `git revert` if needed.

**Commit message format:**
```
feat(chinvex): Batch N — [summary]

Tasks:
- Task X: [one-liner]
- Task Y: [one-liner]
- Task Z: [one-liner]
```

---

## Dependencies

- `chinvex` CLI must be installed and on PATH (or shimmed via `strap shim`)
- PowerShell 5.1+ (Windows)
- Existing strap.ps1 functions (Load-Config, Load-Registry, Save-Registry, etc.)

## Out of Scope

- Automatic full ingestion (strap only registers paths, user runs `chinvex ingest` for embeddings)
- Chinvex MCP server changes
- Bi-directional sync (chinvex → strap)
- Legacy context migration (existing chinvex contexts not auto-imported)
- Consolidation (shelved independently)

---

**End of Plan**
