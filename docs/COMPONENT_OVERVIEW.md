# Component Overview: _strap

**Component Type:** Development environment manager
**Language:** PowerShell
**Last Updated:** 2026-02-07
**Commits Analyzed:** Through 50fda24 (104 commits since 2026-02-01)

---

## 1. Purpose

_strap solves the Windows development environment chaos problem. Instead of scattered `git clone` operations, manual PATH edits, lost scripts, and "where did I install that tool?" confusion, _strap provides a single front door for managing development tools and projects.

**Core problems solved:**
- **Tool discovery hell:** Manual PATH management, forgotten install locations, duplicate tools
- **Environment brittleness:** PATH corruption, dependency installation failures, broken shims after moves
- **Project setup friction:** Repetitive boilerplate, inconsistent templates, manual venv/dependency setup
- **Intelligence isolation:** Code exists on disk but isn't indexed or searchable by AI tools

**Primary users:**
- Human developers (via CLI)
- chinvex (automated context sync)
- PM2 process manager (via shims)
- Windows Task Scheduler (via shims)

---

## 2. How It Works

### Core Flow: Git URL → Global Availability

The central value proposition is instant system-wide tool availability:

```powershell
strap clone https://github.com/user/tool  # or: cd existing-repo && strap adopt
# → Auto-detects stack (Python/Node/Go/Rust)
# → Runs dependency installation (venv + deps)
# → Discovers entry points from pyproject.toml/package.json
# → Creates dual-file shims (.ps1 + .cmd) in P:\software\bin
# → Syncs metadata to chinvex for code intelligence
# → Tool available globally in 30-60 seconds
```

### Architecture (Three Layers)

**1. Registry System (Single Source of Truth)**

`registry.json` (V3 schema) tracks all managed repos with metadata:
- Lifecycle fields: path, url, created_at, updated_at
- Stack detection: python, node, go, rust, docker
- Setup health: result (succeeded/failed/skipped), error message, timestamp
- Chinvex metadata: depth (light/full), status (active/stable/dormant), tags
- Shim registry: type (simple/venv/node), paths, executables, venv locations

Auto-migrates from V2 (scope field → orthogonal depth/status/tags).

**2. Shim System v3.1 (Dual-File Launchers)**

Every tool gets TWO files in `P:\software\bin`:
- `tool.ps1` → PowerShell launcher (activates venv, sets CWD, runs command)
- `tool.cmd` → Batch wrapper (calls .ps1 for cmd.exe compatibility)

Three shim types with different environment handling:
- **simple:** Direct execution, no environment setup
- **venv:** Auto-discovers Python venv (.venv, venv, .virtualenv), activates before running
- **node:** Sets NODE_PATH using configured nodeExe before running

Entry point discovery:
- Python: Parses `pyproject.toml` ([project.scripts], [tool.poetry.scripts]) or `setup.py` (console_scripts)
- Node: Parses `package.json` (bin field)

**3. Command Dispatch + Integration Layer**

`strap.ps1` loads modules from `modules/`:
- Core: Die, Info, Ok, Warn, registry load/save, kill-switch enforcement
- Commands/*: clone, adopt, setup, shim, update, move, rename, uninstall, list, open, doctor, configure, contexts, sync-chinvex, purge
- Chinvex: Test availability, invoke CLI, sync metadata
- Config: Load config.json, resolve roots
- Utils: Tokenization, validation, git helpers

Commands are atomic: registry saves only after successful operations.

### Key Data Stores

| File | Purpose | Location |
|------|---------|----------|
| `registry.json` | Central repo registry (V3) | `P:\software\_strap\registry.json` |
| `config.json` | System configuration (roots, defaults) | `P:\software\_strap\config.json` |
| Shim files | Dual-file launchers (.ps1 + .cmd) | `P:\software\bin\*.{ps1,cmd}` |
| Templates | Project scaffolds (4 types) | `P:\software\_strap\templates\*` |
| Memory files | Project context (STATE/CONSTRAINTS/DECISIONS) | `docs/memory/` |

### Deployment/Execution

- **Installation:** Add `P:\software\_strap` to PATH, run `strap doctor` to verify
- **Entry point:** `strap.cmd` (batch wrapper) → `strap.ps1` (PowerShell CLI)
- **One-time setup:** Add `P:\software\bin` to PATH (all future shims work automatically)
- **PM2:** Vendored at `P:\software\_node-tools\pm2`, system-wide shim at `P:\software\bin\pm2.{ps1,cmd}`
- **Tests:** Pester 5 test suite in `tests/powershell/`, run via `Invoke-Pester`

---

## 3. Interface Surface

### CLI Commands (Active)

| Command | Description |
|---------|-------------|
| `strap <name> -t <template>` | Bootstrap new project from template (mono, node-ts-service, node-ts-web, python) |
| `strap clone <url>` | Clone GitHub repo, auto-detect stack, run setup, create shims, sync chinvex |
| `strap adopt [--path <dir>]` | Register existing repo, auto-discover shims, sync chinvex |
| `strap setup [--repo <name>]` | Install dependencies (auto-detects python/node/go/rust) |
| `strap shim <name> --cmd "<cmd>"` | Create global launcher shim (auto-typed as simple/venv/node) |
| `strap update <name> --all` | Git pull (single or all repos), optional --rebase/--stash/--setup |
| `strap move <name> --dest <path>` | Relocate repo, update registry, optional --rehome-shims |
| `strap rename <name> --to <new>` | Change registry name, optional --move-folder |
| `strap configure <name> --depth <light\|full>` | Modify metadata post-adoption, intelligent chinvex sync |
| `strap list [--verbose]` | Show all repos with HEALTH column (setup status) |
| `strap open <name>` | Open repo in File Explorer |
| `strap contexts` | View chinvex sync status for all repos |
| `strap sync-chinvex [--reconcile]` | Preview/fix registry-chinvex drift |
| `strap uninstall <name>` | Remove folder + shims + registry entry + chinvex context |
| `strap purge [--cleanup-chinvex]` | Clear entire registry (keeps folders/shims) |
| `strap doctor [--json]` | Diagnose installation, registry integrity, shim health |

**Flags:** Most commands support `--yes`, `--dry-run`, `--json`

### CLI Commands (Disabled Since 2026-02-02)

Kill-switched pending safety review after environment corruption incident:
- `strap consolidate` - Guided migration wizard
- `strap audit` - Path dependency scanner
- `strap snapshot` - Environment state capture
- `strap migrate` - Registry schema upgrades
- `strap archive` - Move repos to archive location

### Configuration Files (Interface Points)

**`config.json` (system configuration):**
```json
{
  "roots": {
    "software": "P:\\software",
    "tools": "P:\\software\\_scripts",
    "shims": "P:\\software\\bin",
    "nodeTools": "P:\\software\\_node-tools",
    "archive": "P:\\software\\_archive"
  },
  "defaults": {
    "pwshExe": "C:\\Program Files\\WindowsApps\\...\\pwsh.exe",
    "nodeExe": "C:\\nvm4w\\nodejs\\node.exe"
  },
  "chinvex_integration": true
}
```

**`registry.json` (V3 schema):**
```json
{
  "version": 3,
  "repos": [
    {
      "id": "chinvex",
      "name": "chinvex",
      "path": "P:\\software\\chinvex",
      "url": "https://github.com/llampwall/chinvex",
      "chinvex_depth": "full",
      "status": "active",
      "tags": [],
      "stack": "python",
      "setup": {
        "result": "succeeded",
        "error": null,
        "last_attempt": "2026-02-05T10:42:35Z"
      },
      "shims": [
        {
          "name": "chinvex",
          "type": "venv",
          "ps1Path": "P:\\software\\bin\\chinvex.ps1",
          "exe": "P:\\software\\chinvex\\.venv\\Scripts\\chinvex.exe",
          "venv": "P:\\software\\chinvex\\.venv"
        }
      ]
    }
  ]
}
```

### No Public APIs or MCP Tools

_strap is CLI-only. Integration happens via:
- Direct invocation (humans, scripts, scheduled tasks)
- Chinvex CLI calls (two-way sync)

---

## 4. Integration Points

### Consumes From

**chinvex** (bidirectional sync)
- Uses: `chinvex context create/update/sync-metadata-from-strap/archive`, `chinvex ingest --rebuild-index`
- Receives: Context existence validation, sync confirmation
- Flow: _strap calls chinvex CLI → chinvex updates `P:\ai_memory\contexts\<name>\context.json`

**Git** (version control)
- Uses: `git clone`, `git pull`, `git status`, `git fsck`, commit hashes
- Provides: Repository source, update detection, integrity verification

**Package Managers** (dependency installation)
- Python: `uv` (preferred) or `python -m venv`, `pip install`
- Node: `pnpm` (via Corepack), `npm`, `yarn`
- Go: `go mod download`
- Rust: `cargo build`

**PM2** (process manager - vendored)
- Location: `P:\software\_node-tools\pm2`
- Shim: `P:\software\bin\pm2.{ps1,cmd}` registered to `_strap` repo
- Integration: PM2 ecosystem files reference shims in `P:\software\bin`

### Provides To

**chinvex** (code intelligence)
- Repo paths for ingestion
- Metadata (depth: light/full, status: active/stable/dormant, tags)
- Lifecycle events (clone, adopt, move, rename, uninstall)
- Single source of truth: "In strap registry = in chinvex"

**System** (global tool availability)
- Shims in `P:\software\bin` (one-time PATH setup)
- Dual-file compatibility (PowerShell + cmd.exe)
- Venv activation (Python tools work without manual activation)
- Node PATH setup (node tools find modules correctly)

**Developers** (project scaffolding)
- Templates: `mono` (pnpm workspace), `node-ts-service` (Fastify), `node-ts-web` (Vite), `python` (src-layout)
- Token replacement: {{REPO_NAME}} → actual name in files and filenames
- Logging: Pre-configured `logs/` directories with .gitignore
- Environment defaults: `.env.example` with SERVER_HOST/PORT, UI_HOST/PORT

**PM2/Scheduled Tasks** (stable entry points)
- Shims provide canonical paths regardless of tool install location
- No hardcoded paths in task definitions
- Example: `pwsh -File P:\software\bin\pm2-start.ps1` always works

---

## 5. Current State

### Shipped and In Daily Use

✅ **Template bootstrapping** (4 templates: mono, node-ts-service, node-ts-web, python)
✅ **Lifecycle management** (clone, adopt, setup, shim, update, move, rename, uninstall)
✅ **Shim system v3.1** (dual-file, three types, auto-discovery)
✅ **Chinvex integration** (automatic context sync, metadata propagation)
✅ **Setup status tracking** (HEALTH column in `strap list`)
✅ **Configure command** (post-adoption metadata updates with intelligent sync)
✅ **Registry V3** (orthogonal metadata fields: depth, status, tags)
✅ **PM2 vendoring** (system-wide availability via shim)
✅ **Pester 5 test suite** (22 test files, 338+ assertions)

Evidence from registry: 14 repos managed, 4 shims created (chinvex, chinvex-mcp, pm2, heretic, specify).

### Partially Built or Experimental

🚧 **Setup failures** for 3 repos:
- `codex_bot`: "No recognized stack detected" (no package.json/pyproject.toml)
- `mobile-comfy`, `sentinel-kit`, `heretic`: "Setup failed" (dependency issues)

These are tracked in registry.setup.result but don't block core functionality.

### Disabled Pending Review

⛔ **Consolidation workflow** (kill-switched since 2026-02-02 incident):
- consolidate, audit, snapshot, migrate, archive commands
- Reason: Subagent RAM spiral (45GB) → force-kill → User PATH deleted
- Impact: Lost global commands (git, npm, python, claude, codex) for hours
- Status: Code exists, tests exist, but guarded by Assert-CommandSafe
- Re-enablement: Requires safety review + controlled testing

See: `docs/incidents/2026-02-02-environment-corruption.md`

### Not Started

N/A - No specced-but-unbuilt features. System is feature-complete for current scope.

---

## 6. Known Gaps

### Broken or Unreliable

1. **Setup failures for 3/14 repos** (codex_bot, mobile-comfy, sentinel-kit)
   - Root cause: Stack detection miss (codex_bot), dependency issues (others)
   - Impact: Tools work if manually set up, but auto-setup fails
   - Workaround: `strap setup --stack python --repo <name>` or manual `pip install -e .`

2. **Consolidation commands disabled**
   - Impact: Can't migrate scattered repos in bulk
   - Workaround: Manual `strap adopt --scan <dir>` + individual `strap move` operations
   - Future: Needs controlled testing in isolated environment

3. **PowerShell parameter binding issues** (documented limitation)
   - Problem: `strap shim tool --- python -m module` may fail if PowerShell consumes `-m`
   - Workaround: Use `--cmd` flag instead: `strap shim tool --cmd "python -m module"`
   - Status: Design limitation, documented in README

### Missing Features That Would Add Value

1. **Chinvex depth presets unclear**
   - Gap: Users don't know when to use `--tool` (light) vs default (full)
   - Impact: May over-ingest third-party tools or under-ingest important code
   - Fix: Add guidance to `strap clone --help` or interactive prompt

2. **Setup health monitoring is passive**
   - Gap: Failed setups require manual `strap list` inspection
   - Impact: Silent failures until user notices tool doesn't work
   - Fix: Add `strap doctor` check that warns about failed setups

3. **PM2 vendoring not documented**
   - Gap: README doesn't explain PM2 shim or vendored install at `P:\software\_node-tools\pm2`
   - Impact: Users may install global PM2 redundantly
   - Fix: Document PM2 vendoring in README or doctor output

4. **No automated registry backups**
   - Gap: Registry corruption would lose all metadata (shims, setup status, chinvex mappings)
   - Impact: Would require manual re-adoption of all repos
   - Fix: Add periodic backup to `P:\software\_strap\backups\registry-<timestamp>.json`

5. **Shim regeneration not automatic after registry edits**
   - Gap: Manually editing registry (e.g., fixing paths) doesn't update shim content
   - Impact: Shims may point to old locations after manual fixes
   - Fix: Add `--rehome-shims` to more commands or auto-detect drift in `strap doctor`

### Documentation Drift

1. **chinvex-integration.md outdated** (docs:1-100 vs code reality)
   - Docs say: "Registers the repo path in the context (without running full ingestion)"
   - Code shows: Full ingestion happens during adopt/clone (16cac94)
   - Fix needed: Update docs to reflect --register-only flag removal

2. **README consolidate section commented out** (README:145-507)
   - Large commented block documents disabled commands
   - Confusing: Users may think features are available
   - Fix needed: Move to separate `docs/CONSOLIDATION_DISABLED.md` with incident reference

3. **Setup status tracking not in CLAUDE.md**
   - New feature (09af3e0) not reflected in project instructions
   - Impact: AI agents may not know to check HEALTH column
   - Fix needed: Add to Quick Reference section

4. **Configure command not in Quick Reference** (STATE.md:25)
   - Added in 1b551bc but STATE.md only shows basic usage
   - Impact: Users may not discover post-adoption metadata tuning
   - Fix needed: Add examples to STATE.md and README

---

## Summary for Synthesis Agent

_strap is the **Windows development environment manager** that provides instant system-wide tool availability. It's the single source of truth for repository lifecycle management, automatically syncing with chinvex for code intelligence. The core flow (Git URL → auto-setup → shim creation → chinvex sync) happens in 30-60 seconds per tool.

The system is **stable and in daily use** with 14 repos managed (evidence: registry.json). Major features are shipped (lifecycle management, shim system v3.1, chinvex integration, setup tracking, configure command). The consolidation workflow (bulk repo migration) is **disabled pending safety review** after a 2026-02-02 incident where subagent RAM consumption led to User PATH deletion.

**Integration surface:** Consumes from chinvex (bidirectional), git, package managers, PM2. Provides to chinvex (metadata + lifecycle events), system (global shims), developers (templates), PM2/Task Scheduler (stable entry points).

**Known gaps:** Setup failures for 3 repos (non-blocking), consolidation disabled, some docs drift, no automated registry backups.

**No public APIs or MCP tools** - CLI-only interface with PowerShell + batch entry points.
