# Dev Environment Consolidation Spec

**Status:** Approved (7 rounds of Codex debate)
**Context:** strap
**Created:** 2026-02-01
**Refined by:** Claude Code + Codex debate

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

## Registry as Source of Truth (with trust modes)

**Principle:** Registry is authoritative for strap-managed repo locations. Disk can drift due to external changes.

**Trust modes (command-specific):**
- **Registry-first commands** (default for most operations):
  - `strap move`, `strap rename`, `strap archive`, `strap consolidate`
  - Assumption: Registry paths are correct, disk is validated against registry
  - Drift detection: If disk doesn't match registry → fail with error, suggest `doctor --fix-paths`
- **Disk-discovery commands** (opt-in, explicit recovery mode):
  - `strap doctor --fix-paths`, `strap adopt --scan`
  - Assumption: Disk is source of truth, registry may be stale
  - Behavior: Scan disk, update registry to match (with confirmation)

**Rule:** Only one trust mode per command. No mixed mode. Clear separation of concerns.

**Conflict resolution (comprehensive):**

*Simple cases (strap doctor auto-detects):*
- Registry points to non-existent path + no repo found elsewhere → offer to remove entry
- Disk has repo at location not in registry → offer to adopt OR ignore

*Complex cases (require user decision):*
- Registry points to path A, disk has repo at path B with matching remote URL → offer: update registry to B, OR remove entry + re-adopt at B
  - **Remote URL matching rules:**
    - If repo has no remote → match by path only (don't remap)
    - If repo has multiple remotes → match by `origin` remote, fall back to first remote if no origin
    - If remotes rewritten (URL changed) → no match, treat as different repo
    - If identical fork remotes → manual selection required (can't auto-determine)
    - **URL normalization (REQUIRED for matching):**
      - Convert SSH to HTTPS: `git@github.com:user/repo.git` → `https://github.com/user/repo.git`
      - Strip trailing `.git`: `https://github.com/user/repo.git` → `https://github.com/user/repo`
      - Lowercase host: `GitHub.com` → `github.com`
      - Normalize path separators: `user\repo` → `user/repo` (Windows)
      - After normalization, exact string match for comparison
- Registry points to path A (doesn't exist), disk has multiple repos with matching remote URL → list all matches, require manual selection
- Registry points to path A, disk has DIFFERENT repo at path A (remote mismatch) → **fail**, require manual resolution (registry corruption or external change)

*During consolidate:*
- If both registry entry and disk target exist during move → **fail fast**, require manual resolution
- If scan finds repo with same name as registered repo but different path → treat as separate repo, warn about name collision, suggest rename

*Registry recovery modes (strap doctor --fix):*
- `--fix-paths`: Update registry paths to match disk locations (scan + match by remote URL)
- `--fix-orphans`: Remove registry entries with non-existent paths
- Default (no flag): Report issues, require manual confirmation per fix

**Validation:**
- `strap doctor` checks registry-disk consistency
- `strap snapshot` captures both registry and discovered repos for comparison

## New Commands

### `strap snapshot [--output <path>] [--scan <dir>...]`

Creates a JSON manifest of current state before migration.

```json
{
  "timestamp": "2026-02-01T00:45:00Z",
  "registry": {
    "version": 1,
    "entries": [...]
  },
  "discovered": [
    {"path": "C:\\Code\\chinvex", "in_registry": true, "name": "chinvex", "type": "git"},
    {"path": "C:\\Code\\random-thing", "in_registry": false, "type": "git", "last_commit": "2025-08-15"},
    {"path": "C:\\Code\\misc-scripts", "in_registry": false, "type": "directory", "last_modified": "2025-11-03"},
    {"path": "C:\\Code\\helper.ps1", "in_registry": false, "type": "file"}
  ],
  "external_refs": {
    "pm2": [{"name": "chinvex-gateway", "cwd": "C:\\Code\\chinvex"}],
    "scheduled_tasks": [{"name": "MorningBrief", "path": "C:\\Code\\chinvex\\scripts\\morning_brief.ps1"}],
    "shims": [{"name": "chinvex", "target": "C:\\Code\\chinvex"}],
    "path_entries": [{"entry": "C:\\Code\\chinvex\\bin", "matches_repo": "chinvex"}],
    "profile_refs": [
      {"file": "$PROFILE", "line": 12, "content": "Set-Alias cx C:\\Code\\chinvex\\scripts\\cli.ps1", "matches_repo": "chinvex"}
    ]
  },
  "disk_usage": {
    "C:": {"total_gb": 500, "free_gb": 50},
    "P:": {"total_gb": 2000, "free_gb": 1200}
  }
}
```

**Purpose:** Safety net. Not a file backup - just a map of what's where.

**Behavior:**
- `--scan` directories are searched for git repos (default: common locations if not specified)
- Snapshot is metadata-only, not a backup
- Include disk space check to verify target has capacity

**External ref detection:**
- PM2: parse `pm2 jlist`
- Scheduled tasks: `Get-ScheduledTask` + inspect Actions for file paths
- Shims: scan `build/shims/*.cmd` for target paths
- PATH: check `$env:PATH` entries for directories inside source repos
- Shell profiles: parse `$PROFILE` (PowerShell) and `~/.bashrc` / `~/.bash_profile` (WSL) for aliases, functions, and path additions referencing source repos

**Limitations (acknowledged):**
- Does NOT detect NSSM services, VS Code workspace settings, dynamic path construction, running Node/Python/PowerShell processes
- User must manually audit additional integrations
- User must close VS Code, terminals, and IDEs running from source repos before consolidation

### `strap adopt --scan <dir> [--recursive] [--dry-run] [--yes]`

Discovers all top-level directories (and standalone files) in a source directory and adds them to registry.

```
Scanning C:\Code...

Found 15 items:
  Git repos:
    chinvex        → already in registry
    streamside     → already in registry
    random-thing   → NEW (would adopt as software)
    old-experiment → NEW (would adopt as software, last commit 2024-03)

  Non-git directories:
    misc-scripts   → NEW (not git-tracked, would adopt as tool)
    old-notes      → NEW (not git-tracked, would adopt as archive)

  Standalone files:
    helper.ps1     → SKIP (standalone file, not a directory)
    notes.txt      → SKIP (standalone file, not a directory)

Run with --yes to adopt all NEW items (excluding standalone files).
```

**Classification of discovered items:**
- **Git repo** → full adoption with scope heuristics (see below)
- **Plain directory** → ask what to do: adopt as-is (tool/software/archive), skip, or ignore
- **Standalone file** → surface in report but skip by default (not a project)

**Scope detection heuristics (with confirmation):**

*For git repos:*
- Single script file + README → suggest tool
- Last commit > `archive_threshold_days` (default 180) → **tentatively** suggest archive
  - **Safety overrides (force to `software` instead):**
    - Repo has uncommitted changes → active
    - Repo is referenced by other repos in audit → actively used
    - Repo has open branches (>1 branch) → potentially active
    - Repo was recently checked out (check reflog for activity in last 90 days) → recently used
  - Rationale: stable ≠ archived; only suggest archive for truly inactive AND unreferenced repos
- Otherwise → suggest software

*For non-git directories:*
- Contains mostly scripts (`.ps1`, `.py`, `.js`, `.sh`) → suggest tool
- Last modified > `archive_threshold_days` → suggest archive
- Otherwise → prompt user (no strong heuristic)

**Confirmation behavior:**
- Without `--yes`: prompt per item with suggested scope + reasoning, allow override
- With `--yes`: apply suggested scopes but NEVER auto-archive without explicit `--allow-auto-archive` flag
  - Default `--yes`: treats archives as `software` (safe default)
  - With `--yes --allow-auto-archive`: applies archive suggestions (bulk cleanup use case)
- With `--scope <tool|software|archive>`: override heuristic, apply specified scope to all

**Behavior:**
- Skips repos already in registry (matches by path, case-insensitive on Windows)
- `--recursive` searches subdirectories (default: top-level only)
- `--dry-run` shows what would be adopted without writing
- `--yes` adopts all without prompting (excluding standalone files)

### `strap audit <name|--all> [--json] [--rebuild-index]`

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
  - PATH: C:\Code\chinvex\bin is in $env:PATH
  - $PROFILE:12 → Set-Alias cx C:\Code\chinvex\scripts\cli.ps1

Config files with paths:
  - .env:3 → P:\ai_memory (OK - data dir, not repo path)

Summary:
  2 repos reference chinvex - will need updates after move
  5 external refs - will need manual fix after move
```

**Scan targets:**
- `*.ps1`, `*.cmd`, `*.bat` - PowerShell/batch scripts
- `*.ts`, `*.js`, `*.mjs` - JavaScript/TypeScript
- `*.py` - Python
- `*.json`, `*.yaml`, `*.yml` - Config files
- `.env*` - Environment files

**Exclusions:**
- `node_modules/`, `venv/`, `.git/` - always skip
- Binary files, images, archives

**Path detection patterns:**
- Absolute Windows paths: `C:\`, `P:\`, `\\?\`, case-insensitive
- UNC paths: `\\server\share`
- Normalize all paths for comparison (case, slashes, trailing separators)
- Match paths that resolve to known registry repo locations

**Known limitations (IMPORTANT - audit is not a safety guarantee):**
- Does NOT detect dynamically constructed paths (string concatenation, template literals)
- Does NOT detect paths in compressed files or databases
- Does NOT detect embedded configs in binaries
- False positives possible for path-like strings (e.g., URLs, examples in docs)
- **User must manually review audit output** - audit is a discovery tool, not a complete safety check
- Consolidate shows audit warnings but does NOT block on potential issues (user confirmation required)

**Index optimization:**
- First run or `--rebuild-index`: scans all repos, builds index at `build/audit-index.json`
- Index format:
  ```json
  {
    "index_version": 1,
    "created_at": "timestamp",
    "repos": {
      "repo_path": {
        "last_scan": "timestamp",
        "last_commit_hash": "git_hash",
        "paths_found": {...}
      }
    }
  }
  ```
- Index invalidation (automatic rebuild if any true):
  - Registry entries added/removed/moved (compare registry paths with index keys)
  - Repo `last_commit_hash` changed (indicates repo content changed)
  - Repo path doesn't exist on disk (repo was moved/deleted externally)
  - `--rebuild-index` flag provided
- Subsequent runs: use index for repos where `last_commit_hash` matches current HEAD
- Re-scan only repos with changed commits
- `--all` uses index for efficiency, shows cache hit stats (e.g., "5/10 repos from cache")

**Behavior:**
- For single repo: scans that repo + checks index for references to it
- For `--all`: builds/uses full cross-reference matrix
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

Then updates scope to `archive` in registry.

**Chinvex behavior (via strap-chinvex integration):**
- Removes from individual context (if software)
- Removes from `tools` context (if tool)
- Adds to shared `archive` context
- Archive context gets minimal ingest: name, description (from README first line), last commit date

**Filtering behavior:**
- Archived repos are excluded from `strap update --all` (use `strap update <name>` explicitly)
- Archived repos appear in `strap list --all` but not `strap list` (default)
- `strap doctor` validates archived repos but with lower priority

### `strap consolidate --from <dir> [--to <root>] [--dry-run] [--yes]`

The single entrypoint for the entire migration. Walks the user through every step as a guided wizard - snapshot, discovery, audit, preflight, execution, and verification all happen in sequence.

```
strap consolidate --from "C:\Code"

╔══════════════════════════════════════════╗
║   Dev Environment Consolidation          ║
║   Source: C:\Code → P:\software          ║
╚══════════════════════════════════════════╝

Step 1/6: Snapshot
  Saving current state to build/consolidate-snapshot-20260201.json...
  Registry: 5 entries
  Discovered: 8 git repos, 3 directories, 2 standalone files
  External refs: 3 PM2, 1 scheduled task, 4 shims, 2 PATH entries, 1 $PROFILE ref
  Disk: C: 50 GB free, P: 1200 GB free (need ~15 GB)
  ✓ Snapshot saved

Step 2/6: Discovery & Adoption
  Scanning C:\Code...

  Git repos:
    chinvex        → already in registry
    streamside     → already in registry
    random-thing   → NEW → software? [Y/n/tool/archive/skip]: y
    old-experiment → NEW → archive (last commit 2024-03)? [Y/n/software/tool]: y

  Non-git directories:
    misc-scripts   → NEW → tool? [Y/n/software/archive/skip]: y

  Standalone files:
    helper.ps1     → SKIP (not a directory)

  ✓ 3 items adopted

Step 3/6: Audit
  Scanning for path dependencies...

  chinvex:
    Inbound: streamside (hooks/post-commit.ps1:8), godex (src/memory.ts:23)
    External: PM2 chinvex-gateway, Scheduled task MorningBrief, $PROFILE:12

  streamside:
    Inbound: (none)
    External: Shim streamside

  ✓ Audit complete: 2 cross-repo refs, 5 external refs

Step 4/6: Preflight
  ✓ Disk space: need 15 GB, have 1200 GB free
  ✓ No path collisions
  ✓ No git worktrees detected
  ✓ All working trees clean
  ⚠ PM2: chinvex-gateway uses C:\Code\chinvex → will stop with --stop-pm2
  ⚠ $PROFILE:12 references C:\Code\chinvex → manual fix needed after
  ⚠ Scheduled task MorningBrief → manual fix needed after

  Close IDEs and terminals for repos being moved.
  Press Enter to continue (or Ctrl+C to abort)...

Step 5/6: Execute
  Stopping PM2: chinvex-gateway... ✓
  Moving chinvex → P:\software\chinvex... ✓ (verified: git fsck OK, objects match)
  Moving streamside → P:\software\streamside... ✓ (verified)
  Moving random-thing → P:\software\random-thing... ✓ (verified)
  Moving old-experiment → P:\software\_archive\old-experiment... ✓ (verified)
  Moving misc-scripts → P:\software\_scripts\misc-scripts... ✓ (copied, file count verified)
  Updating registry... ✓
  Updating chinvex contexts... ✓
  Starting PM2: chinvex-gateway... ✓

Step 6/6: Verify
  Running strap doctor...
  ✓ All 8 registry paths valid
  ✓ All shims point to valid locations
  ✓ Chinvex contexts synced

  ⚠ Manual fixes needed:
    1. $PROFILE:12 → update: Set-Alias cx P:\software\chinvex\scripts\cli.ps1
    2. Scheduled task MorningBrief → update path to P:\software\chinvex\scripts\morning_brief.ps1
    3. PATH: remove C:\Code\chinvex\bin (now at P:\software\chinvex\bin via shim)

  Rollback log: build/consolidate-rollback-20260201.json
  Source directory C:\Code is now empty - safe to delete.

Done! Run 'strap consolidate --from "C:\Users\Jordan\Documents\Code"' next.
```

**Wizard behavior:**
- Each step runs automatically in sequence
- Interactive prompts pause at Step 2 (scope selection) and Step 4 (IDE closure)
- With `--yes`: skips scope confirmation (uses heuristic defaults) and IDE closure pause
- With `--dry-run`: runs Steps 1-4 only, shows full plan without executing
- Step 6 (verify) always runs `strap doctor` and shows actionable manual fix instructions
- PM2 services are stopped before moves and restarted after (with `--stop-pm2` or prompted)
- If any step fails, stops immediately with clear error and rollback instructions

**Flags:**
- `--from <dir>` — source directory to consolidate (required)
- `--to <root>` — override destination root (default: from config roots based on scope)
- `--dry-run` — run through Steps 1-4 (plan only), don't execute
- `--yes` — skip interactive prompts (still shows output)
- `--stop-pm2` — auto-stop affected PM2 services during migration
- `--ack-scheduled-tasks` — acknowledge scheduled task warnings
- `--allow-dirty` — allow repos with uncommitted changes
- `--allow-auto-archive` — with `--yes`, apply archive heuristic suggestions automatically

**Preflight checks (Step 4):**
- Target roots exist and are writable
- Sufficient free space on target drive (check each source repo size + 20% safety margin for cross-volume copies)
- No destination path collisions (case-insensitive on Windows)
  - Detect: `P:\software\repo` vs `P:\software\Repo` collision
  - Action: fail with error, require manual rename
- PM2 services using source repo paths (check `pm2 jlist`, compare cwd and script paths)
  - If PM2 services found **for repos being moved**: **warn** and require `--stop-pm2` flag to proceed
  - If PM2 services exist but none affect repos being moved: no action required
  - With `--stop-pm2`: automatically stop ONLY affected services, save list for restart after Step 5
  - If `pm2` command not found: skip PM2 check with warning
- Scheduled tasks check (best-effort, not required):
  - If running as admin: scan `Get-ScheduledTask` for source repo paths
  - If tasks found: **warn** (don't block), require `--ack-scheduled-tasks` to proceed
  - With flag: continue, user responsible for manual task config updates post-move
  - If not admin: **warn** "Run as admin for full scheduled task detection" but allow continuation
    - Preflight shows: `[PARTIAL] Scheduled tasks check skipped (not admin)`
    - User can still proceed (best-effort model)
- Git working trees: warn if dirty, require `--allow-dirty` flag to proceed
  - Default: block if uncommitted changes detected in ANY repo
  - With `--allow-dirty`: warn but continue (user responsibility)
- Windows file locking check:
  - For each repo being moved: attempt exclusive open on `.git/HEAD` (git repos) or a sentinel file (non-git dirs)
  - If lock fails: report which repo is locked, suggest `Handle.exe` or `Get-Process` to find offending process
  - Action: **fail** with "Close the application holding files in <repo> and retry"
  - Common culprarity: VS Code, terminals with CWD inside repo, file indexers, antivirus
- Git worktrees detection (comprehensive):
  - Method 1: Run `git worktree list` and check if output has >1 line (indicates linked worktrees)
  - Method 2 (fallback if git command fails): Check if `.git` is a file (gitdir pointer) OR `.git/worktrees/` exists
  - **Submodule disambiguation:** If `.git` is a file, read its content. If `gitdir:` points to `../.git/modules/` → submodule (NOT a worktree, safe to move). If `gitdir:` points to `../.git/worktrees/` → linked worktree (fail).
  - If worktrees detected: fail with error "Repo has linked worktrees, manual handling required (see git worktree list)"
  - Covers both: repos WITH linked worktrees AND repos that ARE linked worktrees

**Safety philosophy:** Preflight failures require explicit acknowledgment flags (no silent proceed)

**How the wizard maps to execution phases:**

The wizard's 6 steps are the user-facing view of a two-phase operation:

| Wizard Step | Phase | What happens |
|-------------|-------|--------------|
| Step 1: Snapshot | Plan | Save pre-migration state |
| Step 2: Discovery | Plan | Scan source, classify items, prompt for scope |
| Step 3: Audit | Plan | Detect dependencies + external refs |
| Step 4: Preflight | Plan | Validate safety, pause for IDE closure |
| Step 5: Execute | Execute | Moves + registry + chinvex (transactional) |
| Step 6: Verify | Post-execute | `strap doctor` + manual fix list |

- `--dry-run` stops after Step 4 (plan phase only)
- `--yes` skips interactive prompts in Steps 2 and 4 but still shows all output
- Plan is saved to `build/consolidate-plan-{timestamp}.json` after Step 4
- Step 5 validates plan freshness before executing (commit hashes + registry timestamp unchanged since Step 4)

**Plan file contents** (`build/consolidate-plan-{timestamp}.json`):
- Plan metadata: timestamp, plan hash, source directory
- Repos to move (list with current paths + destination paths + scopes)
- Adoptions planned (repos not yet in registry, with proposed scopes)
- Detected dependencies with **confidence markers:**
  - `[HIGH]`: File path found in tracked files
  - `[MEDIUM]`: Path-like string found (potential false positive)
  - `[AUDIT GAPS]`: Dynamic paths/binaries/submodules not scanned (user review required)
- Preflight status (PASS/WARN/FAIL per check)
- Estimated time/space requirements
- Plan hash (SHA256 of **deterministic** content: sorted repo paths + destinations + scopes + commit hashes, excluding timestamps)

**Transaction safety (Step 5):**
- Create rollback log at `build/consolidate-rollback-{timestamp}.json` before starting moves
- Log contains: source path, destination path, registry snapshot before changes, list of completed moves
- Registry changes are written only AFTER all moves succeed
- **Move semantics (IMPORTANT - not truly atomic):**
  - Same volume (e.g., P: → P:): `Move-Item` is atomic rename
  - Cross-volume (e.g., C: → P:): `Move-Item` = copy + verify + delete (NOT atomic, but safe)
  - **Cross-volume integrity verification (REQUIRED - git object database ONLY):**
    1. Capture source state:
       - Git hash: `git rev-parse HEAD` (if not bare repo and has commits)
       - For empty repos (no commits): check `.git/refs` and `.git/objects` exist
    2. Copy source to destination
    3. Verify destination integrity (**git object database only, NOT LFS/submodules/working tree**):
       - `git fsck --no-dangling` at destination (ensures repo integrity) - **PRIMARY CHECK**
       - Count objects: `git count-objects -v` at source and dest (compare loose + packed object counts)
       - Compare git hash: `git rev-parse HEAD` at destination matches source (if not bare and has commits)
       - For empty repos: verify `.git/refs` and `.git/objects` directories exist
       - For bare repos: skip HEAD check, rely on `git fsck` + object counts
       - **LIMITATIONS (explicitly acknowledged in verification output):**
         - Git LFS: LFS pointers verified, NOT actual LFS content - warn "LFS content not verified, run `git lfs fsck` manually"
         - Git submodules: parent repo verified, NOT submodule working trees - warn "Submodule content not verified"
         - Working tree: git filters/hooks may cause working tree differences - warn "Working tree may differ, .git integrity verified"
    4. Only if git fsck PASSES and object counts match and (HEAD matches OR empty repo): delete source
    5. If git fsck FAILS or object count mismatch or HEAD mismatch: delete incomplete destination copy, keep source, **fail consolidation with detailed error**
    6. **Verification scope:** Git object database integrity ONLY. User responsible for post-move validation of LFS/submodules if applicable.
  - **Non-git directories:** cross-volume verification uses file count + total size comparison (not git checks)
  - For cross-volume: if copy+verify succeeds but delete fails → destination has verified repo, source still exists (**safe** state, manual cleanup needed)
- **After all moves succeed (transactional block):**
  a. Write registry changes:
     - Update paths for moved repos
     - Add adopted repos to registry
     - Update scopes (e.g., archived repos)
     - Bump registry version if needed (V1→V2)
  b. Update chinvex contexts (via strap-chinvex integration):
     - Create individual contexts for new software repos
     - Add to `tools` context for new tool repos
     - Add to `archive` context for archived repos
     - **If chinvex update fails:** rollback registry changes, report error, consolidation **fails**
  c. Restart PM2 services that were stopped in preflight
     - **Non-fatal:** If restart fails (e.g., service config has hardcoded old path), log failure and surface in Step 6 verification output
     - Do NOT fail consolidation for PM2 restart failures — moves and registry are already committed
  d. Remove lock file
- If ANY move fails:
  - Stop immediately
  - Rollback completed moves in reverse order:
    - Same-volume moves: atomic rename back
    - Cross-volume moves: delete destination copy (already verified safe), keep source (safe - no data loss)
  - Registry NOT updated (still points to original paths)
  - Report failure with rollback log path showing what succeeded/failed

**Chinvex transaction safety:**
- Chinvex updates happen AFTER registry writes
- If chinvex fails: registry is rolled back (revert to backup made before transaction block)
- Result: all-or-nothing - either both registry + chinvex updated, or neither

**Concurrency control:**
- Lock file: `build/.consolidate.lock` (created at wizard start, deleted at completion)
- Lock contains: PID, timestamp, command, plan file path
- If lock exists: check if PID is running
  - If PID still running → **fail** "Another consolidation in progress (PID {pid})"
  - If PID not running → stale lock, remove and proceed
- Lock prevents: concurrent consolidate, concurrent doctor --fix-paths, concurrent adopt --scan

**Behavior:**
- Defaults `--to` based on scope (software root, tools root, archive root)
- Stops on first error, rolls back completed operations
- Chinvex contexts handled automatically via strap-chinvex integration
- Does NOT auto-fix cross-repo references (manual — surfaced in Step 6)

**Resume capability:**
- Rollback log tracks completion state per repo at `build/consolidate-rollback-{timestamp}.json`:
  ```json
  {
    "plan_hash": "sha256...",
    "started_at": "timestamp",
    "moves_completed": [
      {"repo": "chinvex", "from": "C:\\Code\\chinvex", "to": "P:\\software\\chinvex", "status": "success"}
    ],
    "moves_failed": [
      {"repo": "streamside", "from": "C:\\Code\\streamside", "to": "P:\\software\\streamside", "error": "..."}
    ],
    "registry_updated": false
  }
  ```
- "Already moved" determination: registry path matches destination AND disk has repo at destination
- After partial failure + successful rollback: re-running `strap consolidate` starts fresh (all repos back in source location)
- After partial failure + rollback failure OR user aborts: use rollback log to identify state
  - Completion status in log shows which moves succeeded
  - User must manually inspect disk, clean up partial state, then re-run consolidate with fresh plan
- After power loss mid-move: rollback log shows last completed move, user inspects disk for partial copies, manual cleanup required

## Archive Scope

**Why a separate scope instead of a flag?**

A distinct `archive` scope is cleaner than `{scope: "software", archived: true}` because:

**Chinvex integration requirement:** Chinvex contexts are assigned per-scope. A `software` repo with `archived: true` would still map to the `software` context, requiring separate logic to route archived software to the `archive` context. Using scope makes this mapping direct: `archive` scope → `archive` context, no conditional logic.

**Registry schema evolution:** Adding a third scope is a clean schema extension. A flag would require every command to implement filtering logic (`if scope=software && !archived`), while scope-based filtering is simpler (`if scope in [software, tool]`).

**Command routing:** Archive root selection (`strap archive` → `archive_root`) is direct with scope. With a flag, you'd need nested conditionals: `if scope=software && archived → archive_root else software_root`.

**Trade-off acknowledged:** Both approaches require filtering in commands like `list` and `update`. Scope adds one more enum value but removes conditional checks. Flag adds per-command filtering but keeps scope simple. We choose scope because chinvex integration is already scope-based.

New scope alongside `tool` and `software`:

```json
{
  "id": "old-experiment",
  "name": "old-experiment",
  "scope": "archive",
  "path": "P:\\software\\_archive\\old-experiment",
  "chinvex_context": "archive",
  "archived_at": "2026-02-01T01:00:00Z",
  "last_commit": "2024-03-15T10:23:00Z"
}
```

**Archive detection heuristic:**
- Last commit > `archive_threshold_days` (default 180) → suggest archive
- User can override with `--software` or `--archive` flag on adopt

**Chinvex integration:**
- All archived repos share single `archive` context
- Minimal ingest per repo:
  - Name
  - Description (first line of README, or folder name)
  - Last commit date
  - Path
- Enables "what was that old project where I did X?" searches

## Config

**Config location:** `P:\software\_strap\config.json` (user-editable, version-controlled)

**NOT** `build/config.json` (build artifacts should not contain user config)

Add new fields to existing config structure:

```json
{
  "roots": {
    "software": "P:\\software",
    "tools": "P:\\software\\_scripts",
    "shims": "P:\\software\\_scripts\\_bin",
    "archive": "P:\\software\\_archive"
  },
  "registry": "P:\\software\\_strap\\build\\registry.json",
  "archive_threshold_days": 180
}
```

## Migration Workflow

`strap consolidate` is the single entrypoint. It handles snapshot, discovery, audit, preflight, execution, and verification automatically.

```powershell
# Consolidate first source directory
strap consolidate --from "C:\Code"

# Consolidate second source directory
strap consolidate --from "C:\Users\Jordan\Documents\Code"

# Fix any remaining manual items (consolidate tells you exactly what)

# Delete empty source directories
```

**For cautious users:** Run with `--dry-run` first to see the full plan without executing:

```powershell
strap consolidate --from "C:\Code" --dry-run
```

**Individual commands are still available** for targeted operations:

```powershell
# Just snapshot without consolidating
strap snapshot --output pre-migration.json --scan "C:\Code"

# Just audit without moving anything
strap audit --all --rebuild-index

# Archive a single project
strap archive old-experiment --yes

# Adopt a single repo
strap adopt --path "C:\Code\random-thing" --software
```

## Acceptance Criteria

- [ ] `strap snapshot` captures registry + discovered items (git repos, dirs, files) + external refs + disk space
- [ ] `strap snapshot` detects PATH entries, $PROFILE refs, and .bashrc refs
- [ ] `strap adopt --scan` finds git repos AND non-git directories, classifies each
- [ ] `strap adopt --scan` surfaces standalone files but skips them by default
- [ ] `strap adopt` skips already-registered repos
- [ ] `strap audit` shows inbound + outbound path refs across all repos
- [ ] `strap audit` detects PM2, scheduled tasks, shim, PATH, and shell profile references
- [ ] `strap audit --all` builds and uses index for performance
- [ ] `strap audit` excludes node_modules/venv/.git
- [ ] `strap archive` moves to archive root and updates scope + chinvex context
- [ ] `strap consolidate` runs as guided wizard (Steps 1-6: Snapshot → Discovery → Audit → Preflight → Execute → Verify)
- [ ] `strap consolidate` wizard pauses for user input at Step 2 (scope selection) and Step 4 (IDE closure)
- [ ] `strap consolidate --yes` skips interactive prompts, uses heuristic defaults for scope
- [ ] `strap consolidate --dry-run` runs Steps 1-4 only, shows plan without executing
- [ ] `strap consolidate` Step 6 runs `strap doctor` and shows actionable manual fix list
- [ ] `strap consolidate` auto-restarts PM2 services after successful migration
- [ ] `strap consolidate` runs preflight checks (space, collisions, PM2, scheduled tasks, worktrees, dirty repos)
- [ ] `strap consolidate` supports `--allow-dirty` flag to bypass clean working tree requirement
- [ ] `strap consolidate` stops only affected PM2 services (not all)
- [ ] `strap consolidate` creates lock file at plan start, removes at completion
- [ ] `strap consolidate` detects and fails on stale/concurrent locks
- [ ] `strap consolidate` saves execution plan to `build/consolidate-plan-{timestamp}.json`
- [ ] `strap consolidate` validates plan freshness (commit hashes + registry timestamp)
- [ ] `strap consolidate` uses two-phase execution (plan → execute with confirmation)
- [ ] `strap consolidate` computes deterministic adoption IDs during planning
- [ ] `strap consolidate` adopts repos AFTER moves succeed (registry write in transaction block)
- [ ] `strap consolidate` creates rollback log before starting
- [ ] `strap consolidate` rolls back registry if chinvex update fails (transaction safety)
- [ ] `strap consolidate` verifies cross-volume copy integrity (git count-objects + git fsck + git hash)
- [ ] `strap consolidate` handles empty repos (no commits) by checking .git/refs and .git/objects
- [ ] `strap consolidate` deletes source only after successful verification
- [ ] `strap consolidate` verification scope: git object database ONLY (not LFS/submodules/working tree)
- [ ] `strap consolidate` warns about Git LFS content not verified
- [ ] `strap consolidate` warns about git filter/hook effects on working tree
- [ ] `strap consolidate` warns about submodule content not verified
- [ ] `strap consolidate` handles bare repos (skip HEAD check, use git fsck + object count)
- [ ] `strap consolidate` rolls back on first error (deletes destination copies for cross-volume)
- [ ] `strap consolidate` only updates registry AFTER all moves succeed
- [ ] `strap consolidate` rollback log includes completion status per repo
- [ ] `strap consolidate` detects git worktrees and fails with helpful message
- [ ] `strap consolidate` distinguishes submodules from worktrees (no false positives on submodule `.git` files)
- [ ] `strap consolidate` detects Windows file locks in preflight and reports offending repos
- [ ] `strap consolidate` handles adoption ID collisions (prompt in interactive, fail in `--yes` mode)
- [ ] `strap consolidate` treats PM2 restart failures as non-fatal, surfaces in Step 6 verification
- [ ] Archive scope exists alongside tool/software
- [ ] `archive` chinvex context receives minimal ingest (name, desc, date)
- [ ] Config location is `config.json` (user-editable), not `build/config.json`
- [ ] Config supports `roots.archive` and `archive_threshold_days`
- [ ] `strap list` excludes archived repos by default
- [ ] `strap update --all` excludes archived repos
- [ ] `strap doctor` validates registry-disk consistency
- [ ] `strap doctor --fix-paths` updates registry paths to match disk (by remote URL matching)
- [ ] `strap doctor --fix-orphans` removes registry entries for non-existent paths
- [ ] Remote URL normalization (SSH→HTTPS, strip .git, lowercase host)
- [ ] Archive heuristic includes safety overrides (uncommitted changes, audit refs, branches, reflog)
- [ ] Registry V1→V2 migration implemented with backup

## Edge Cases & Additional Considerations

**Adoption identity (deterministic):**
- During planning: compute adoption metadata WITHOUT writing to registry
  - ID: derived from folder name (sanitized: lowercase, alphanumeric + hyphens only)
  - Name: folder name (original case preserved for display)
  - Scope: determined by heuristics
  - Collision detection: check if ID conflicts with existing registry entries or other items in the same scan
  - Collision resolution: prompt user for alternative name during Step 2 (interactive) or fail with `--yes` (non-interactive)
- Plan stores: proposed ID, name, scope, source path, destination path
- During execution: use exact IDs/names/scopes from plan (no re-computation)
- Guarantee: ID derivation is pure function of folder name, cannot change between plan and execute
- Empty repos (no commits): supported, verified by checking `.git/refs` and `.git/objects` exist

**Cross-volume moves (C: → P:):**
- Not atomic - copy then delete
- If copy succeeds but delete fails: safe state (destination has repo, source cleanup needed manually)
- Rollback: delete destination copy, keep source
- Free space check must account for full repo size (no in-place rename)

**Git submodules and nested repos:**
- Treat parent repo as single unit (don't recurse into submodules)
- `.gitmodules` scanning out of scope for audit (manual review recommended)
- Nested repos (repo within repo): only scan top-level repo during `--scan`, skip nested
- Git worktrees: move operations only supported for main working tree, not linked worktrees
  - Preflight: detect worktrees via TWO checks:
    1. Check if `.git` is a file (gitdir pointer) - indicates this IS a worktree → fail
    2. Check if `.git/worktrees/` exists - indicates this HAS linked worktrees → fail
  - Error message: "Repo has linked worktrees, manual handling required (see git worktree list)"
- Bare repos: supported, moved as-is (no working tree checks needed)

**Windows path edge cases:**
- Long paths (>260 chars): assume long path support enabled on Windows 10+, error if move fails
- Reserved names (CON, NUL, etc.): validate destination names, fail preflight if invalid
- **Case sensitivity:**
  - Windows is case-insensitive, normalize all paths for comparison (lowercase)
  - Detect collisions **within source** before move (e.g., source has `repo` and `Repo` as separate dirs)
  - Detect collisions **at destination** (e.g., moving `Repo` when `repo` exists at dest)
  - Preflight fails on either collision type with list of conflicting paths

**Permissions and ACLs:**
- Moving C: → P: may change file ownership/ACLs if drives have different security policies
- Preflight check: warn if target drive has different owner than source
- Out of scope: preserving exact ACLs (user must verify permissions post-move)

**Non-git folders:**
- `adopt --scan` discovers ALL top-level items (git repos, plain directories, standalone files)
- Plain directories are surfaced and prompted for scope (tool/software/archive/skip)
- Standalone files are reported but skipped by default (not projects)
- Non-git directories have limited heuristics (no commit history) - scope suggestion based on file contents and last modified date
- Cross-volume integrity verification uses file count + size comparison instead of git-based checks for non-git directories

**Junctions and symlinks:**
- If found **inside** repo: treat as files, move as-is (don't follow)
- If found in **destination path** (e.g., `P:\software` is a junction): preflight **fails**, require real directory
- If junction/symlink points INTO a repo being moved: audit won't detect this (limitation)
- User should manually inspect junctions before consolidation

**Git repository types:**
- Standard `.git` directory: full support
- `.git` file (gitdir pointer for worktrees): preflight **fails** with "worktree detected" error
- Bare repo (no `.git` dir, has `HEAD` + `refs/`): supported, skip working tree checks
- Git LFS repos: supported but LFS content integrity not verified (user warning)

## Out of Scope

- **Auto-fixing cross-repo references** - too risky, manual is fine (audit provides roadmap)
- **Auto-shimming adopted tools** - strap can't reliably guess entry points; use `strap shim` after adoption
- **Symlinks/junctions deep handling** - if present, treat as files (move them as-is, don't follow)
- **Topological move ordering** - just move everything, fix what breaks (audit shows dependencies)
- **File-level backup** - snapshot is metadata only; use git for actual backup
- **Detection of all external integrations** - PM2, scheduled tasks, shims, PATH, $PROFILE, .bashrc covered; user audits NSSM, VS Code workspaces, etc.
- **Dynamic path construction** - static path scanning only
- **ACL preservation** - user must verify permissions after cross-volume moves
- **Concurrent strap operations** - no locking mechanism; user must not run multiple strap commands simultaneously
- **Byte-for-byte working tree verification** - only .git integrity verified, not working tree (line endings/filters may differ)

## Registry Schema Migration

**Current registry version:** V1 (existing)
**New registry version:** V2 (adds archive scope support)

**V2 schema changes:**
```json
{
  "registry_version": 2,
  "updated_at": "2026-02-01T01:00:00Z",
  "entries": [
    {
      "id": "...",
      "scope": "archive",  // NEW: archive is now valid scope value
      "archived_at": "...", // NEW: optional timestamp for archived repos
      "last_commit": "..."  // NEW: optional last commit date for audit/archive heuristics
    }
  ]
}
```

**Migration strategy:**
- V1 registries continue to work (no `archive` entries, no new fields)
- First use of `strap archive` command triggers V1→V2 upgrade
- Upgrade process:
  1. Backup current registry to `build/registry.v1.backup.json`
  2. Update `registry_version` to 2
  3. Add new fields to upgraded entry
  4. Save as V2
- **Backward compatibility (V1 reading V2):**
  - Older strap binaries check `registry_version`
  - If version > 1: **fail with message** "Registry requires strap version X.Y+, please upgrade"
  - No silent partial read (avoid corruption)
- **Downgrade path:** `strap registry downgrade` command:
  - Filters out `archive` scope entries (or converts to `software` with warning)
  - Strips new fields
  - Writes V1 format
  - Use case: rollback to older strap version

**Version detection:** Load-Registry function checks `registry_version`, applies appropriate parser or fails with upgrade message

## Dependencies

- Strap-chinvex integration spec (for context creation/archival)
- PowerShell 5.1+ (for `Move-Item`, `Get-ScheduledTask`)
- PM2 (for external ref detection, optional)
- Git (for `git fsck` integrity verification during cross-volume moves)

## Implementation Notes

**Why consolidation belongs in strap, not a separate tool:**

Consolidation is core to strap's mission of "making messy dev environments just work." This is not a one-time migration - users will continue to:
- Discover old repos in random locations
- Want to reorganize as projects evolve
- Need to audit dependencies when moving things

The safety rails (snapshot, audit, rollback) make this safe enough for permanent inclusion. A separate "migration tool" would duplicate strap's registry logic and become stale.

## Open Questions

**Resolved:**
1. ~~Should `consolidate` stop on first error or continue?~~ → **Stop on first error, rollback completed moves**
2. ~~Should `audit` scan node_modules/venv?~~ → **No, exclude them**
3. ~~Should archived repos be excluded from `strap update --all`?~~ → **Yes, exclude from --all, allow explicit update**

**Remaining:**
1. Should audit index rebuild automatically when registry changes, or only on `--rebuild-index`?
2. Should `consolidate` allow partial completion (e.g., move 5 of 10 repos, skip failures) with a `--continue-on-error` flag?
