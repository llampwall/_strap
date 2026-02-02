# Strap-Chinvex Integration - Implementation Plan

**Generated:** 2026-02-01
**Source Spec:** `docs/specs/strap-chinvex-integration.md`
**Execution Model:** Batched (fresh subagent context per batch)

---

## Overview

This plan implements automatic synchronization between Strap's registry and Chinvex contexts. Strap becomes the source of truth for repository lifecycle, with Chinvex contexts created/updated/archived as side effects of strap operations.

**Key principles:**
- Registry-first design (chinvex follows strap state)
- Idempotent operations (safe to retry)
- Graceful degradation (chinvex failures don't break strap)
- Reconciliation support (fix drift via `sync-chinvex`)

---

## Batch 1: Foundation & Schema Migration

**Goal:** Establish registry schema, config system, and chinvex CLI wrapper

### Tasks

#### 1.1 Extend Registry Schema
- **File:** `src/registry/types.ts` (or equivalent)
- **Changes:**
  - Add `chinvex_context: string | null` field to registry entry interface
  - Document field semantics:
    - `null` = not synced or sync failed (needs reconciliation)
    - `string` = synced context name (`"myrepo"` for software, `"tools"` for tool scope)
  - Update registry validation to accept new field

#### 1.2 Create Config System
- **File:** `src/config/config.ts` (new)
- **Behavior:**
  - Load `config.json` from strap root (default: `P:\software\_strap\config.json`)
  - Schema:
    ```json
    {
      "chinvex_integration": true,
      "chinvex_whitelist": ["tools"],
      "software_root": "P:\\software",
      "tools_root": "P:\\software\\_scripts"
    }
    ```
  - Provide defaults if config file missing
  - Export `getConfig()` function for global access

#### 1.3 Chinvex CLI Wrapper
- **File:** `src/chinvex/cli.ts` (new)
- **Exports:**
  - `isChinvexAvailable(): boolean` - check if `chinvex` command exists
  - `contextCreate(name: string, idempotent: boolean): Promise<boolean>` - returns true on success
  - `contextExists(name: string): Promise<boolean>` - returns true if exists, false if not found
  - `contextRename(oldName: string, newName: string): Promise<boolean>`
  - `contextArchive(name: string): Promise<boolean>`
  - `ingestRegisterOnly(context: string, repoPath: string): Promise<boolean>`
  - `contextRemoveRepo(context: string, repoPath: string): Promise<boolean>`
  - `contextList(json: boolean): Promise<string>` - returns raw output for parsing
- **Error handling:**
  - All functions catch errors and return `false` on failure (don't throw)
  - Log warnings for failures (don't abort parent operation)
  - Distinguish between "not found" (exit code 1) and "error" (exit code 2+) for `contextExists`

#### 1.4 Integration Helper
- **File:** `src/chinvex/integration.ts` (new)
- **Exports:**
  - `shouldRunChinvex(flags: { noChinvex?: boolean }): boolean` - check precedence (flag > config > default)
  - `resolveContextName(entry: RegistryEntry): string` - returns context name based on scope (`entry.scope === 'tool' ? 'tools' : entry.name`)
  - `syncRegistryEntry(entry: RegistryEntry, action: 'create' | 'update-path' | 'remove-path' | 'archive'): Promise<void>` - high-level sync helper
    - Calls appropriate CLI functions based on action
    - Updates `entry.chinvex_context` field (sets to `null` on failure)
    - Handles scope-specific logic (software vs tool)

#### 1.5 Migration Script
- **File:** `src/registry/migrate.ts` (new or extend existing migration system)
- **Behavior:**
  - Detect registry version (if no versioning exists, add it)
  - Add `chinvex_context: null` to all existing entries (marks for reconciliation)
  - Bump registry schema version
  - Run automatically on first command execution if registry is old version

### Testing
- Unit tests for config loading (missing file, partial config, full config)
- Unit tests for CLI wrapper (mock `execa` or equivalent)
- Unit tests for integration helper (flag precedence, context name resolution)
- Migration test: old registry → new registry (validates field added)

### Acceptance Criteria
- [ ] Registry entries have `chinvex_context` field (nullable string)
- [ ] Config system loads from `config.json` with sensible defaults
- [ ] Chinvex CLI wrapper handles all 7 required commands
- [ ] Integration helper respects `--no-chinvex` flag and config precedence
- [ ] Migration script adds `chinvex_context: null` to existing entries

---

## Batch 2: Clone & Adopt Integration

**Goal:** Integrate chinvex context creation into `strap clone` and `strap adopt`

### Tasks

#### 2.1 Update `strap clone` Command
- **File:** `src/commands/clone.ts` (or equivalent)
- **Changes:**
  - Add `--no-chinvex` flag to CLI options
  - After adding entry to registry, call `syncRegistryEntry(entry, 'create')`
  - Behavior:
    - Software scope: create individual context, register repo path
    - Tool scope: create `tools` context (idempotent), register repo path
  - Update `entry.chinvex_context` based on result:
    - Success: set to context name (`entry.name` or `"tools"`)
    - Failure: set to `null`
  - Log chinvex actions (INFO level) for user visibility

#### 2.2 Update `strap adopt` Command
- **File:** `src/commands/adopt.ts` (or equivalent)
- **Changes:**
  - Add `--no-chinvex` flag to CLI options
  - After detecting repo and adding to registry, call `syncRegistryEntry(entry, 'create')`
  - Same scope-based behavior as `clone`
  - Update `entry.chinvex_context` based on result

#### 2.3 Reserved Name Validation
- **File:** `src/chinvex/validation.ts` (new)
- **Exports:**
  - `RESERVED_CONTEXT_NAMES: string[]` = `['tools', 'archive']`
  - `validateContextName(name: string, scope: string): { valid: boolean, error?: string }`
    - Returns `{ valid: false, error: 'Context name "tools" is reserved' }` if software repo named with reserved name
    - Returns `{ valid: true }` otherwise
- **Integration:**
  - Call in `clone` and `adopt` before registry insertion
  - Reject operation if validation fails (don't add to registry)

### Testing
- Integration test: `strap clone <url>` creates individual context
- Integration test: `strap clone <url> --tool` adds to `tools` context
- Integration test: `strap clone <url> --no-chinvex` skips chinvex integration
- Integration test: `strap adopt <path> --software` creates context
- Integration test: `strap adopt <path> --tool` adds to `tools` context
- Unit test: reserved name validation rejects `tools` and `archive` for software repos

### Acceptance Criteria
- [ ] `strap clone` creates corresponding chinvex context (or updates `tools`)
- [ ] `strap clone --tool` adds repo to shared `tools` context
- [ ] `strap adopt` creates chinvex context
- [ ] `--no-chinvex` flag skips integration on both commands
- [ ] Reserved names (`tools`, `archive`) rejected for software repos
- [ ] Registry entries have correct `chinvex_context` value after clone/adopt

---

## Batch 3: Move, Rename, Uninstall Integration

**Goal:** Integrate chinvex operations into lifecycle commands that modify repo state

### Tasks

#### 3.1 Update `strap move` Command
- **File:** `src/commands/move.ts` (or equivalent)
- **Pre-flight validation:**
  - Load `software_root` and `tools_root` from config
  - Validate destination is under one of these roots
  - Fail immediately if destination outside both roots (before filesystem move)
- **Scope detection:**
  - Implement most-specific path match:
    ```typescript
    function detectScope(path: string, config: Config): 'software' | 'tool' {
      if (path.startsWith(config.tools_root)) return 'tool';
      if (path.startsWith(config.software_root)) return 'software';
      throw new Error('Path outside managed roots');
    }
    ```
  - Compare old scope vs new scope
- **No scope change:**
  - Add new path to existing context: `ingestRegisterOnly(context, newPath)`
  - Remove old path: `contextRemoveRepo(context, oldPath)`
  - On failure: set `chinvex_context: null`, continue
- **Scope change (software → tool):**
  1. Create `tools` context (idempotent)
  2. Add to `tools`: `ingestRegisterOnly('tools', newPath)`
  3. If success: remove from old context: `contextArchive(oldContext)`
  4. Update registry `scope` and `chinvex_context`
  5. On failure: set `chinvex_context: null`, keep old `scope`
- **Scope change (tool → software):**
  1. Create individual context: `contextCreate(name, true)`
  2. Add to new context: `ingestRegisterOnly(name, newPath)`
  3. If success: remove from `tools`: `contextRemoveRepo('tools', oldPath)`
  4. Update registry `scope` and `chinvex_context`
  5. On failure: set `chinvex_context: null`, keep old `scope`

#### 3.2 Update `strap rename` Command
- **File:** `src/commands/rename.ts` (or equivalent)
- **Software scope:**
  - Call `contextRename(oldName, newName)`
  - Update `entry.name` in registry
  - If `--move-folder` was used:
    - Add new path: `ingestRegisterOnly(newName, newPath)`
    - Remove old path: `contextRemoveRepo(newName, oldPath)`
- **Tool scope:**
  - No chinvex action (stays in `tools` context)
  - If `--move-folder` was used:
    - Add new path: `ingestRegisterOnly('tools', newPath)`
    - Remove old path: `contextRemoveRepo('tools', oldPath)`

#### 3.3 Update `strap uninstall` Command
- **File:** `src/commands/uninstall.ts` (or equivalent)
- **Software scope:**
  - After removing shims/folder, call `contextArchive(context)`
- **Tool scope:**
  - After removing shims/folder, call `contextRemoveRepo('tools', path)`
  - Never archive `tools` (shared by all tool repos)
- **Remove from registry last** (after chinvex cleanup)

### Testing
- Integration test: `strap move` updates context path (same scope)
- Integration test: `strap move` (software → tool) adds to `tools`, archives old context
- Integration test: `strap move` (tool → software) creates new context, removes from `tools`
- Integration test: `strap move` outside roots is rejected (pre-flight validation)
- Integration test: `strap rename` (software) renames context
- Integration test: `strap rename` (tool) keeps `tools` context unchanged
- Integration test: `strap rename --move-folder` updates paths in chinvex
- Integration test: `strap uninstall` (software) archives context
- Integration test: `strap uninstall` (tool) removes from `tools` but doesn't archive `tools`

### Acceptance Criteria
- [ ] `strap move` updates chinvex context repo path
- [ ] `strap move` handles scope changes (tool ↔ software) correctly
- [ ] `strap move` outside managed roots is rejected before filesystem changes
- [ ] Scope detection uses most-specific path match (tools_root before software_root)
- [ ] `strap rename` renames chinvex context (software only)
- [ ] `strap rename --move-folder` updates repo path in chinvex
- [ ] `strap uninstall` archives context (software) or removes from `tools` (tool)
- [ ] All chinvex failures set `chinvex_context: null` in registry

---

## Batch 4: Discovery & Reconciliation Commands

**Goal:** Implement `strap contexts` and `strap sync-chinvex` for drift management

### Tasks

#### 4.1 Implement `strap contexts` Command
- **File:** `src/commands/contexts.ts` (new)
- **Behavior:**
  - Call `contextList(true)` to get JSON output
  - Parse context metadata (name, repo count, last ingest timestamp)
  - Load strap registry
  - For each context, determine sync status:
    - `✓ synced` - context has corresponding registry entry with matching `chinvex_context` field
    - `⚠ no strap entry` - context exists but no registry entry points to it (orphan)
  - Output formatted table:
    ```
    Context         Type       Repos  Last Ingest    Sync Status
    myrepo          software   1      2026-01-30     ✓ synced
    tools           tool       9      2026-01-29     ✓ synced
    orphan-context  software   0      never          ⚠ no strap entry
    ```

#### 4.2 Implement `strap sync-chinvex` Command
- **File:** `src/commands/sync-chinvex.ts` (new)
- **Flags:**
  - No flags: default to `--dry-run` (safe)
  - `--dry-run`: show drift without making changes
  - `--reconcile`: apply fixes
- **Reconciliation logic:**
  1. **Load state:**
     - Load registry entries
     - Call `contextList(true)` to get all contexts
  2. **Detect missing contexts (registry → chinvex):**
     - For each registry entry with `chinvex_context: null`:
       - Software: create individual context, register repo path
       - Tool: create `tools` context (if missing), register repo path
       - Update `entry.chinvex_context` on success
  3. **Detect orphaned contexts (chinvex → registry):**
     - For each context with no matching registry entry:
       - If in whitelist (config `chinvex_whitelist` or hardcoded `['tools']`): skip
       - If `tools` context and no tool repos in registry: skip (keep empty `tools`)
       - Otherwise: archive context
  4. **Detect orphaned repo paths:**
     - For each repo path in context includes:
       - If no registry entry has that path: remove from context
       - Tool scope: use `contextRemoveRepo('tools', path)`
       - Software scope: archive entire context (already handled by orphaned contexts)
  5. **Output:**
     - Dry-run: print actions that would be taken
     - Reconcile: execute actions, report success/failure for each

#### 4.3 Whitelist Management
- **File:** `src/config/config.ts` (extend)
- **Add field:**
  - `chinvex_whitelist: string[]` with default `['tools']`
- **Behavior:**
  - `sync-chinvex` never archives whitelisted contexts
  - User can extend via `config.json`

### Testing
- Integration test: `strap contexts` lists all contexts with sync status
- Integration test: `strap contexts` flags orphaned contexts
- Integration test: `strap sync-chinvex` (no flags) defaults to dry-run
- Integration test: `strap sync-chinvex --dry-run` shows drift without changes
- Integration test: `strap sync-chinvex --reconcile` creates missing contexts
- Integration test: `strap sync-chinvex --reconcile` archives orphaned contexts (not whitelisted)
- Integration test: `strap sync-chinvex --reconcile` preserves empty `tools` context
- Integration test: `strap sync-chinvex --reconcile` removes orphaned repo paths from `tools`

### Acceptance Criteria
- [ ] `strap contexts` lists all contexts and sync status
- [ ] `strap sync-chinvex` without flags defaults to dry-run
- [ ] `strap sync-chinvex --dry-run` shows drift without changes
- [ ] `strap sync-chinvex --reconcile` fixes drift automatically
- [ ] Whitelist prevents auto-archival of `tools` and user-defined contexts
- [ ] Orphaned repo paths removed from contexts during reconciliation

---

## Batch 5: Edge Cases & Polish

**Goal:** Handle edge cases, add comprehensive error messages, and finalize integration

### Tasks

#### 5.1 Chinvex Availability Handling
- **File:** All command files (`clone.ts`, `adopt.ts`, etc.)
- **Behavior:**
  - Before first chinvex invocation, call `isChinvexAvailable()`
  - If not available:
    - Log warning: `"Chinvex not found. Install and create a shim via: strap shim chinvex ..."`
    - Set `chinvex_context: null` in registry
    - Continue with strap operation (don't fail)
  - Cache availability check per command execution (don't repeat)

#### 5.2 Idempotency Validation
- **Test scenario:** Run `strap clone` twice for same repo
- **Expected:**
  - First run: creates context, registers path
  - Second run: `contextCreate` with `--idempotent` succeeds, `ingestRegisterOnly` deduplicates (no-op)
  - No errors, registry state unchanged
- **Test scenario:** Run `strap adopt` for already-adopted repo
- **Expected:**
  - Same idempotency guarantees as clone

#### 5.3 Error Message Improvements
- **File:** `src/chinvex/cli.ts`
- **Changes:**
  - Add detailed error messages for common failures:
    - Context already exists (without `--idempotent`)
    - Context not found (for rename/archive)
    - Target name collision (for rename)
    - Chinvex command timeout (if chinvex hangs)
  - Include full stderr output in warnings for debugging

#### 5.4 Documentation
- **Files:**
  - `README.md` (or `docs/usage.md`)
  - `docs/chinvex-integration.md` (new)
- **Content:**
  - Overview of integration (registry-first design)
  - Command-by-command behavior changes
  - How to opt-out (`--no-chinvex`, config)
  - How to reconcile drift (`sync-chinvex`)
  - Troubleshooting guide (chinvex not found, reconciliation failures)

#### 5.5 Final E2E Test
- **Scenario:** Full lifecycle test
  1. `strap clone https://github.com/user/repo` (software)
  2. Verify context created via `strap contexts`
  3. `strap move repo --dest P:\software\_scripts\repo` (scope change to tool)
  4. Verify `tools` context updated, old context archived
  5. `strap rename repo --to newtool`
  6. Verify `tools` context still has repo (name unchanged in shared context)
  7. `strap uninstall newtool`
  8. Verify repo removed from `tools` context, `tools` context still exists

### Testing
- E2E test: full lifecycle (clone → move → rename → uninstall)
- E2E test: chinvex not available (warning logged, operations succeed)
- Unit test: idempotency of `clone` and `adopt`
- Manual test: verify documentation accuracy

### Acceptance Criteria
- [ ] Chinvex not installed → commands warn but don't fail
- [ ] Integration is idempotent (running twice doesn't break state)
- [ ] Errors from chinvex CLI are caught and logged (don't break strap operations)
- [ ] Documentation covers integration behavior and troubleshooting
- [ ] Full E2E test passes (clone → move → rename → uninstall)

---

## Execution Strategy

**Per-batch execution:**
1. **Review batch tasks** - ensure all context from spec is understood
2. **Implement tasks** - focus on current batch only (ignore future batches)
3. **Run tests** - verify acceptance criteria
4. **Commit** - atomic commit per batch with descriptive message
5. **Notify** - webhook notification for user review before next batch

**Between batches:**
- User reviews commit, runs manual tests if desired
- User approves continuation or requests changes
- Next batch starts with fresh subagent context (no context contamination)

**Rollback strategy:**
- Each batch is atomic (single commit)
- If batch fails, revert commit and fix issues before retrying
- Previous batches are unaffected (independent of future work)

---

## Dependencies

**External tools:**
- `chinvex` CLI (must be installed and globally available via shim or PATH)
- PowerShell (for shell execution on Windows)

**Internal dependencies:**
- Strap registry system (must support schema versioning for migration)
- Config system (must support JSON loading with defaults)
- Existing command infrastructure (clone, adopt, move, rename, uninstall)

---

## Risk Assessment

**High risk:**
- Chinvex CLI contract changes (spec assumes specific command signatures)
  - Mitigation: Document contract in spec, version-check chinvex if possible
- Scope detection bugs (moving between roots)
  - Mitigation: Extensive testing of path matching logic, pre-flight validation

**Medium risk:**
- Registry corruption if chinvex fails mid-operation
  - Mitigation: Set `chinvex_context: null` on failure (marks for reconciliation)
- Idempotency bugs (duplicate contexts/paths)
  - Mitigation: Use `--idempotent` flag, rely on chinvex deduplication

**Low risk:**
- Performance impact (chinvex CLI invocations add latency)
  - Mitigation: Chinvex operations are async, failures don't block strap
- User confusion (automatic context management)
  - Mitigation: Clear logging, `strap contexts` for visibility

---

## Success Metrics

- [ ] All 11 acceptance criteria from spec are met
- [ ] No regression in existing strap commands
- [ ] Zero chinvex failures cause strap operations to abort
- [ ] `strap sync-chinvex --reconcile` successfully fixes all test drift scenarios
- [ ] Documentation enables users to understand and troubleshoot integration

---

## Notes

**Spec deviations:**
- None planned. This plan implements the spec as written.

**Future enhancements (out of scope):**
- Automatic full ingestion (currently only registers paths, user runs `chinvex ingest` separately)
- MCP server integration (spec is CLI-only)
- Bi-directional sync (chinvex changes don't trigger strap updates)

---

**End of Plan**
