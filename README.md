# strap

Complete Windows dev environment manager with three capabilities:

**1. Template bootstrapping** — spin up new projects from templates (node-ts-service, mono, python, etc.) with deps installed and ready to code.

**2. Lifecycle management** — the real power:
- **Instant system-wide availability**: `clone` or `adopt` a repo → automatic stack detection (python/node/go/rust) → auto-creates venv shims → tool available globally in seconds
- Clone GitHub repos and track them in a central registry
- Auto-discovers entry points from `pyproject.toml`, `setup.py`, `package.json`
- Creates global `.cmd`/`.ps1` shims for any command (no manual PATH edits)
- Move and rename repos while keeping registry consistent
- Update all your tools at once (`--all` flag)
- Uninstall cleanly (removes folder + shims + registry entry)
- Schema versioning means it won't brick itself as it evolves

<!--
**3. Environment consolidation** — migrate scattered repos:
- Guided wizard (`strap consolidate`) moves entire directories of repos
- Automatic discovery and adoption with scope classification
- Path dependency scanning (audit) catches breaking references
- External reference detection (PM2, scheduled tasks, shims, PATH, profiles)
- Safe cross-volume moves with git integrity verification
- Rollback on failure, actionable fix list on success
-->

**What makes it special:** Single front door for your dev tools. Instead of scattered `git clone` + manual PATH edits + "where did I put that script?", everything goes through strap.

## Core Workflow: Instant System-Wide Availability

The central value proposition of strap:

```
Git URL or local folder → strap adopt/clone → instant global availability
```

**How it works:**

1. **`strap clone <url>`** or **`cd folder && strap adopt`**
   - Detects stack (Python/Node/Go/Rust) from project files
   - Adds repo to central registry with metadata

2. **Automatic shim discovery** (happens during adopt/clone):
   - **Python**: parses `pyproject.toml` ([project.scripts], [tool.poetry.scripts]) or `setup.py` (console_scripts)
   - **Node**: parses `package.json` (bin field)
   - Creates venv shims (Python) or node shims (Node) in `P:\software\bin`

3. **Done!** Tools are now available system-wide
   - One-time PATH setup: add `P:\software\bin` to your PATH
   - Every new tool auto-creates shims, no PATH editing needed ever again

**Example:**
```powershell
strap clone https://github.com/llampwall/chinvex
# ✓ Auto-detected Python stack
# ✓ Found 2 entry points in pyproject.toml
# ✓ Created shims: chinvex.{ps1,cmd}, chinvex-mcp.{ps1,cmd}

chinvex --help  # works immediately!
```

Manual shim creation is still available for custom launchers or aliases.

## Templates

- `node-ts-service` — Fastify service (TypeScript, tsx, vitest)
- `node-ts-web` — Vite + TypeScript web app
- `python` — src-layout package (pytest + ruff)
- `mono` — pnpm workspace with `apps/server` (Fastify), `apps/ui` (Vite), `packages/shared`

## Requirements

- Windows PowerShell (pwsh recommended)
- Git
- Node 20+ (for node templates) + pnpm (via Corepack or global install)
- Python 3.11+ (for python template)
- `templates/context-hook.cmd` (bundled in this repo)

## Quick Start

### Template Bootstrapping

```powershell
# bootstrap a monorepo in P:\software\myrepo
strap myrepo -t mono

# full install + start dev
strap myrepo -t mono --start
```

### Lifecycle Management

**The magic workflow — Git URL to system-wide availability:**

```powershell
# Option 1: Clone from GitHub
strap clone https://github.com/llampwall/chinvex
# → Auto-detects Python stack from pyproject.toml
# → Finds [project.scripts]: chinvex, chinvex-mcp
# → Creates venv shims in P:\software\bin
# → chinvex and chinvex-mcp now available globally!

# Option 2: Adopt existing repo
cd P:\my-projects\awesome-tool
strap adopt
# → Auto-detects Node stack from package.json
# → Finds "bin" field with CLI entry point
# → Creates node shims in P:\software\bin
# → awesome-tool now available globally!

# Install dependencies (auto-detects python/node/go/rust)
strap setup --repo chinvex --yes

# Update all your tools at once
strap update --all

# Manually create additional shims if needed
strap shim custom-alias --cmd "python -m chinvex.special" --repo chinvex

# Diagnose issues
strap doctor
```

**What just happened?**
- Stack detection: reads `pyproject.toml`, `setup.py`, `package.json` to identify Python/Node
- Entry point discovery: parses `[project.scripts]`, `[tool.poetry.scripts]`, `console_scripts`, or `package.json.bin`
- Shim creation: generates `.ps1` + `.cmd` launchers in `P:\software\bin` (one-time PATH setup)
- Venv integration: Python shims point to `.venv\Scripts\tool.exe`, Node shims use `node.exe + entrypoint`

<!--
### Consolidation (Migrate Existing Repos)

```powershell
# consolidate an entire directory of repos into P:\software (guided wizard)
strap consolidate --from "C:\Code"

# preview what would happen without executing
strap consolidate --from "C:\Code" --dry-run

# automatic mode (no prompts, auto-stop PM2 if needed)
strap consolidate --from "C:\Code" --yes --stop-pm2
```
-->

## ⚠️ Disabled Commands

The following commands are currently **disabled** due to safety concerns from the 2026-02-02 environment corruption incident:

- `strap snapshot` - Create snapshots of managed repos
- `strap audit` - Scan for path dependencies
- `strap migrate` - Execute consolidation moves
- `strap consolidate` - Guided migration wizard
- `strap archive` - Archive old repos

These commands will return a warning message referencing `docs/incidents/2026-02-02-environment-corruption.md`. They are pending review and safety improvements before being re-enabled.

## Usage

### Template Bootstrapping

```
strap <project-name> --template <template> [--path <parent-dir>] [--skip-install] [--install] [--start]
strap <project-name> -t <template> [-p <parent-dir>] [--skip-install] [--install] [--start]

strap doctor [--strap-root <path>] [--keep]
strap templatize <templateName> [--source <path>] [--message "<msg>"] [--push] [--force] [--allow-dirty]
```

### Lifecycle Management

```
strap clone <github-url> [--tool] [--name <custom-name>] [--yes]
strap list [--verbose]
strap open <name>
strap move <name> --dest <path> [--yes] [--dry-run] [--force] [--rehome-shims]
strap rename <name> --to <newName> [--yes] [--dry-run] [--move-folder] [--force]
strap adopt [--path <dir>] [--name <name>] [--tool|--software] [--yes] [--dry-run]
strap adopt --scan <dir> [--recursive] [--dry-run] [--yes] [--allow-auto-archive] [--scope <tool|software|archive>]
strap setup [--yes] [--dry-run] [--stack python|node|go|rust] [--repo <name>]
strap setup [--venv <path>] [--uv] [--python <exe>] [--pm npm|pnpm|yarn] [--corepack]
strap update <name> [--yes] [--dry-run] [--rebase] [--stash] [--setup]
strap update --all [--tool] [--software] [--yes] [--dry-run] [--rebase] [--stash] [--setup]
strap shim <name> --- <command...> [--cwd <path>] [--repo <name>] [--force] [--dry-run] [--yes]
strap shim <name> --cmd "<command>" [--cwd <path>] [--repo <name>] [--force] [--dry-run] [--yes]
strap uninstall <name> [--yes]
strap doctor [--json]
# strap migrate [--yes] [--dry-run] [--backup] [--json] [--to <version>] [--plan]
# strap snapshot [--output <path>] [--scan <dir>...]
# strap audit <name|--all> [--json] [--rebuild-index]
# strap archive <name> [--yes] [--dry-run]
# strap consolidate --from <dir> [--to <root>] [--dry-run] [--yes] [--stop-pm2] [--ack-scheduled-tasks] [--allow-dirty] [--allow-auto-archive]
```

### Parameters

#### Template Bootstrapping

- `project-name` (positional) — target repo name
- `--template` / `-t` — one of: `node-ts-service`, `node-ts-web`, `python`, `mono`
- `--path` / `-p` — parent directory for the new repo (default: `P:\software`)
- `--skip-install` — do not install dependencies (lockfile-only install is skipped)
- `--install` — do full install after the initial commit
- `--start` — do full install after the initial commit, then start dev
- `--strap-root` — override the strap repo root (defaults to the current strap root)

#### Lifecycle Management

**clone**
- Automatically discovers and creates shims for Python and Node projects after cloning
- `<github-url>` — GitHub repository URL (https or git)
- `--tool` — use tool preset (depth=light, status=stable, tags=[third-party]); all repos clone to `P:\software`
- `--name <custom-name>` — override the repo name (default: extracted from URL)
- `--yes` — skip confirmation prompts

**list**
- `--verbose` — show full details including paths, types, shims, and timestamps

**move**
- `<name>` — registry entry name to move
- `--dest <path>` — destination path (if ends with `\` or is existing dir, keeps folder name; otherwise full new path)
- `--yes` — skip confirmation prompts
- `--dry-run` — preview only, no filesystem changes
- `--force` — allow overwriting existing destination (only if empty)
- `--rehome-shims` — update shim content to reference new repo path

**rename**
- `<name>` — registry entry name to rename
- `--to <newName>` — new registry name
- `--yes` — skip confirmation prompts
- `--dry-run` — preview only, no changes
- `--move-folder` — also rename folder on disk to match new name
- `--force` — reserved for future use

**adopt**
- Automatically discovers and creates shims for Python and Node projects
- `--path <dir>` — path to existing repo (default: current directory)
- `--name <name>` — custom registry name (default: folder name)
- `--tool` — use tool preset (depth=light, status=stable, tags=[third-party])
- `--software` — use software preset (depth=full, status=active, default)
- `--yes` — skip confirmation prompts
- `--dry-run` — preview only, no registry write
- `--scan <dir>` — discover and adopt all items in directory (top-level by default)
- `--recursive` — search subdirectories when scanning
- `--allow-auto-archive` — with `--yes`, apply archive suggestions automatically

**setup**
- `--repo <name>` — run setup for a registered repo (changes to its directory)
- `--stack <stack>` — force stack selection (python|node|go|rust)
- `--venv <path>` — Python: venv directory (default `.venv`)
- `--uv` — Python: use uv for installs (default on)
- `--python <exe>` — Python: executable for venv creation (default `python`)
- `--pm <manager>` — Node: force package manager (npm|pnpm|yarn)
- `--corepack` — Node: enable corepack before install (default on)
- `--dry-run` — preview plan without executing
- `--yes` — skip confirmation prompts

**update**
- `<name>` — registered repo name to update
- `--all` — update all registered repos (filtered by --tool/--software if specified)
- `--rebase` — use git pull --rebase instead of git pull
- `--stash` — auto-stash dirty working tree before update, restore after
- `--setup` — run strap setup after successful update
- `--dry-run` — preview operations without executing
- `--yes` — skip confirmation prompts

**shim**
- `<name>` — shim command name (creates `<name>.cmd`)
- `--- <command...>` — command to execute (use three dashes as separator)
- `--cmd "<command>"` — alternative to `---` for commands with flags (avoids PowerShell parameter binding)
- `--cwd <path>` — working directory for the shim
- `--repo <name>` — attach shim to this registry entry (otherwise uses current directory)
- `--force` — overwrite existing shim
- `--dry-run` — preview without writing files
- `--yes` — skip confirmation prompts

**uninstall**
- `<name>` — registered repo name to uninstall
- `--yes` — skip confirmation prompts

**doctor**
- `--json` — output structured JSON instead of human-readable format

<!--
**migrate**
- `--yes` — skip confirmation prompts
- `--dry-run` — preview migrations without writing to registry
- `--backup` — create timestamped backup before migrating
- `--json` — output structured JSON report instead of human-readable format
- `--to <version>` — migrate to specific version (default: latest)
- `--plan` — show migration plan without executing

**snapshot**
- `--output <path>` — output path for snapshot JSON (default: `build/snapshot.json`)
- `--scan <dir>` — directory to scan for repos (can be repeated, defaults to common locations)

**audit**
- `<name>` — registry entry name to audit
- `--all` — audit all registered repos
- `--json` — output structured JSON instead of human-readable format
- `--rebuild-index` — force rebuild of audit index (otherwise uses cached data when valid)

**archive**
- `<name>` — registered repo name to archive
- `--yes` — skip confirmation prompts
- `--dry-run` — preview without executing

**consolidate**
- `--from <dir>` — source directory to consolidate (required)
- `--to <root>` — override destination root (default: from config based on scope)
- `--dry-run` — run Steps 1-4 (plan only), don't execute moves
- `--yes` — skip interactive prompts (uses heuristic defaults)
- `--stop-pm2` — automatically stop affected PM2 services during migration
- `--ack-scheduled-tasks` — acknowledge scheduled task warnings
- `--allow-dirty` — allow repos with uncommitted changes
- `--allow-auto-archive` — with `--yes`, apply archive suggestions automatically
-->

### Examples

#### Template Bootstrapping

```powershell
# Node service
strap api -t node-ts-service

# Web app
strap ui -t node-ts-web -p D:\work

# Python
strap tools -t python

# Monorepo with full install + dev
strap godex -t mono --start

# Doctor run (creates temp repos, runs smoke matrix, cleans up)
strap doctor

# Snapshot an existing repo into a new template (no push)
strap templatize my-template --source C:\Code\SomeRepo
```

#### Lifecycle Management

```powershell
# Clone a tool/utility into _scripts
strap clone https://github.com/user/youtube-md --tool

# Clone a project into software (custom name)
strap clone https://github.com/user/repo --name my-project

# List registered repos
strap list

# List with full details
strap list --verbose

# Open repo folder in File Explorer
strap open my-project

# Move a repo to a new location
strap move my-project --dest P:\software\projects\ --yes

# Move and rename in one step
strap move cli-tool --dest P:\software\_scripts\cli-tool-renamed --yes

# Move with shim path updates (dry run first)
strap move my-tool --dest P:\software\_tools\ --rehome-shims --dry-run

# Rename a registry entry only
strap rename old-name --to new-name --yes

# Rename entry and folder on disk
strap rename youtube-md --to youtube-markdown --move-folder --yes

# Adopt an existing repo (current directory)
cd P:\software\existing-repo
strap adopt

# Adopt with custom name and scope
strap adopt --path P:\software\my-repo --name custom-name --tool --yes

# Dry run adoption
strap adopt --dry-run

# Diagnose strap installation
strap doctor

# Get doctor report as JSON
strap doctor --json

# Setup current repo (auto-detect stack)
strap setup

# Setup registered repo
strap setup --repo youtube-md --yes

# Force stack selection
strap setup --stack python --yes

# Force package manager for Node
strap setup --stack node --pm pnpm --yes

# Dry run to see what would be executed
strap setup --dry-run

# Update a single repo
strap update youtube-md

# Update with auto-stash (handles dirty working tree)
strap update youtube-md --stash --yes

# Update using rebase
strap update youtube-md --rebase --yes

# Update all tools
strap update --all --tool --yes

# Update all repos and run setup after
strap update --all --yes --setup

# Preview update without executing
strap update youtube-md --dry-run

# Check registry version and system health
strap doctor

<!--
# Migrate registry to latest version
strap migrate --yes

# Preview migration plan without executing
strap migrate --plan

# Migrate with backup
strap migrate --yes --backup

# Preview migration changes
strap migrate --dry-run
-->

# Create a shim from inside a registered repo
cd P:\software\_scripts\youtube-md
strap shim youtube-md --- python youtube-md.py

# Create a shim with working directory
strap shim godex --cwd P:\software\godex --- node scripts\cli.js

# Create a shim from outside the repo
strap shim my-tool --repo youtube-md --- python main.py

# Force overwrite an existing shim
strap shim youtube-md --force --- python updated-script.py

# Preview shim without creating it
strap shim test --- python test.py --dry-run

# Use --cmd for commands with single-letter flags (avoids PowerShell parameter binding)
strap shim flask --cmd "python -m flask run" --cwd P:\software\myapp

# Complex command with multiple flags
strap shim serve --cmd "python -m http.server 8080 --bind 127.0.0.1"

# Uninstall a registered repo (removes directory and shims)
strap uninstall youtube-md --yes

# Discover and adopt all repos in a directory
strap adopt --scan C:\Code --recursive

<!--
# Create a snapshot before major changes
strap snapshot --output pre-migration.json --scan C:\Code --scan P:\software

# Audit a single repo for path dependencies
strap audit chinvex

# Audit all repos and rebuild index
strap audit --all --rebuild-index

# Archive an old project
strap archive old-experiment --yes

# Consolidate an entire directory (guided wizard)
strap consolidate --from "C:\Code"

# Consolidate with automatic mode (no prompts)
strap consolidate --from "C:\Code" --yes --stop-pm2

# Preview consolidation without executing
strap consolidate --from "C:\Code" --dry-run
-->
```

## What Strap Does

Strap has two modes:

1. **Template bootstrapping**: make a new repo from a template (optionally install + start).
2. **Lifecycle management**: track existing repos/tools, install deps safely, create global shims, update, uninstall.

### Template bootstrapping (new repo)

- Creates a repo folder under the chosen parent directory
- Initializes git and writes the template contents
- Replaces tokens in filenames + file contents (repo/package name)
- Ensures `.env.example` exists
- Optionally installs deps:
  - default: minimal/lockfile-only (node/mono)
  - `--install` / `--start`: full install
- Installs the context hook (`templates/context-hook.cmd install`)
- Creates an initial commit
- Prints next steps (and starts dev if `--start`)

### Lifecycle management (existing repo/tool)

- `clone`: clone a GitHub repo into `P:\software\...` or `P:\software\_scripts\...` and register it
- `adopt`: register a repo you already cloned manually (or bulk-discover with `--scan`)
- `setup`: detect stack and run an allowlisted install plan (python/node/go/rust; docker = detect only)
- `shim`: generate a `.cmd` launcher in your shims dir and attach it to the registry entry
- `update`: pull latest changes (single or `--all`, supports `--rebase`, `--stash`, optional `--setup`)
- `move`: relocate a managed repo to a new path while keeping registry consistent
- `rename`: change a registry entry name (optionally rename folder on disk)
- `uninstall`: remove shims + folder + registry entry
- `list`: show all registered repos
- `open`: open a registered repo's folder in File Explorer
- `doctor`: diagnose strap + registry health
<!-- - `migrate`: upgrade registry schema safely (backfills required fields, enforces invariants) -->

<!--
### Consolidation workflow (migrate scattered repos)

- `snapshot`: create a JSON manifest of current dev environment (registry, discovered repos, external refs, disk space)
- `audit`: scan for path dependencies (inbound/outbound) and external references (PM2, scheduled tasks, shims, PATH, profiles)
- `archive`: move old/inactive repos to archive location and update scope
- `consolidate`: guided wizard for full migration (snapshot → discovery → audit → preflight → execute → verify)
-->

### Registry System

Lifecycle management uses a JSON registry at `registry.json` (in the strap directory) to track all cloned repos and their associated shims.

**Registry metadata (V3):**
- `version` — schema version (current: 3, auto-migrates from V2)
- `updated_at` — ISO 8601 timestamp of last registry update
- `metadata.trust_mode` — "registry-first" (default) or "disk-discovery" (recovery mode)

**Trust modes:**
- **registry-first** (default): Registry paths are assumed correct, disk is validated against registry. Commands like `move`, `rename`, `archive`, `consolidate` require registry to be accurate. If drift detected → fail with error; manual registry fix or re-adopt required.
- **disk-discovery** (recovery mode): Used by `strap snapshot` and `strap adopt --scan` to discover repos on disk regardless of registry state.

**Each entry includes:**
- `id` — unique identifier
- `name` — repo name (used for commands)
- `chinvex_depth` — ingestion depth: "full" (deep analysis), "light" (minimal), or "index" (metadata only)
- `status` — lifecycle state: "active" (in development), "stable" (mature/unchanging), or "dormant" (archived/inactive)
- `tags` — array of free-form tags for grouping (e.g., `["third-party"]`, `["ml", "web"]`)
- `path` — absolute path to the cloned repository
- `url` — git remote URL (if available)
- `chinvex_context` — chinvex context name (usually matches repo name)
- `shims` — array of shim metadata objects (see Shim System section)
- `created_at` — ISO 8601 timestamp
- `updated_at` — ISO 8601 timestamp
- `last_pull_at` — ISO 8601 timestamp of last update (added by `strap update`)
- `last_head` — git commit hash after last update (added by `strap update`)
- `last_remote` — remote tracking branch hash after last update (added by `strap update`)
- `stack_detected` — detected stack type (added by `strap setup`)
- `setup_last_run_at` — ISO 8601 timestamp of last setup (added by `strap setup`)
- `setup_status` — setup execution status: "success" or "fail" (added by `strap setup`)
- `archived_at` — ISO 8601 timestamp when moved to archive (null if not archived)
- `last_commit` — git commit hash for audit index optimization (null if not a git repo)

**V2→V3 Migration:**
The V2 `scope` field has been replaced with three orthogonal metadata fields for better flexibility:
- Old V2 `scope: "tool"` → V3 `chinvex_depth: "light"`, `status: "stable"`, `tags: ["third-party"]`
- Old V2 `scope: "software"` → V3 `chinvex_depth: "full"`, `status: "active"`, `tags: []`
- Old V2 `scope: "archive"` → V3 `chinvex_depth: "index"`, `status: "dormant"`, `tags: []`

Migration happens automatically on first registry load. All repos now live in `P:\software` (flat structure).

The registry enables:
- Tracking which repos have been cloned
- Associating shims with their parent repos
- Safe cleanup during uninstall (removes repo + all shims)
- Quick listing of all managed repos
- Path dependency tracking via audit index
- Consolidation workflow state management

### Known Limitations

**PowerShell Parameter Binding**: When using `strap shim` with the `---` separator, single-letter flags in the command (like `python -m module`) may conflict with PowerShell's parameter matching.

**Solution**: Use `--cmd "<command>"` instead of `--- <command...>` for commands with flags:

```powershell
# ✅ Recommended: use --cmd for commands with flags
strap shim flask --cmd "python -m flask run"

# ⚠️  May cause issues: PowerShell may consume -m
strap shim flask --- python -m flask run
```

The `--cmd` mode passes the entire command as a quoted string, preventing PowerShell from parsing individual flags.

## Shim System

The shim system is strap's solution to a class of recurring environment management problems. **One shims folder (`P:\software\bin`) on PATH. That's strap's PATH.** All tool launchers live there.

### Why Shims?

The shim pattern solves multiple error classes at once:

1. **"Which Python/process is running?"** — Shim explicitly activates the correct venv and calls the right binary
2. **"Scheduled task can't find X"** — Scheduled task calls the shim, shim handles the environment
3. **"Installed to wrong location"** — Doesn't matter, shim points to the canonical location
4. **PATH is 2000 chars and full of duplicates"** — One entry: `P:\software\bin`

For example, with chinvex:
```powershell
P:\software\bin\chinvex.ps1      # activates .venv, calls chinvex
P:\software\bin\chinvex-mcp.ps1  # activates .venv, calls chinvex-mcp
P:\software\bin\pm2-start.ps1    # sets up node PATH, calls pm2 start ecosystem
```

A scheduled task becomes:
```powershell
$action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File P:\software\bin\pm2-start.ps1"
```

No hardcoded paths in the task itself. The shim owns that knowledge.

**This is strap's job.** When strap registers a tool, it creates the shim. `strap adopt/shim/clone` creates shims pointing to venvs or executables. Strap's doctor command verifies all shims point to valid targets.

### Dual-File System

Shims are generated as **two files**:
- `<name>.ps1` — PowerShell launcher script (does the actual work)
- `<name>.cmd` — Batch wrapper that calls the `.ps1` file

This dual-file system ensures shims work from any Windows shell (cmd.exe, PowerShell, pwsh, IDEs, scheduled tasks).

### Shim Types

Strap supports three shim types with different environment handling:

#### `simple`
Direct command execution with no special environment setup.

```powershell
strap shim godex --cmd "node scripts/cli.js" --repo godex
```

Generated shim runs `node scripts/cli.js` directly in the repo directory.

#### `venv` (Python)
Automatically discovers and activates Python virtual environments before running the command.

```powershell
strap shim chinvex --cmd "chinvex" --repo chinvex
```

Auto-discovery searches for:
- `.venv/Scripts/chinvex.exe`
- `venv/Scripts/chinvex.exe`
- `.virtualenv/Scripts/chinvex.exe`

The shim activates the venv and resolves the executable automatically. No need to specify venv path manually.

#### `node`
Sets up Node.js PATH using `nodeExe` from config before running the command.

```powershell
strap shim pm2-start --cmd "pm2 start ecosystem" --repo pm2-tools
```

The shim uses the configured Node.js installation path and ensures proper `NODE_PATH` resolution.

### Command Parsing

Shims support two command input formats:

**JSON Array** (explicit):
```powershell
strap shim mytool --cmd '["python", "-m", "myapp", "--arg"]' --repo mytool
```

**PowerShell Command String** (tokenized):
```powershell
strap shim mytool --cmd "python -m myapp --arg" --repo mytool
# Alternative with --- separator
strap shim mytool --- python -m myapp --arg
```

The tokenizer automatically parses the command string into executable + arguments using PowerShell's AST parser. It blocks dangerous operators:
- Pipes (`|`)
- Redirects (`>`, `<`, `>>`)
- Command chaining (`&&`, `||`, `;`)

### Shim Regeneration

After moving a repo or changing configuration, regenerate its shims:

```powershell
strap shim --regen <repo-name>
```

This updates the shim to point to the new repo location without re-specifying commands.

### Registry V2 Shim Metadata

Each shim is tracked in the registry with full metadata:

```json
{
  "name": "chinvex",
  "type": "venv",
  "ps1Path": "P:\\software\\bin\\chinvex.ps1",
  "exe": "P:\\software\\chinvex\\.venv\\Scripts\\chinvex.exe",
  "venv": "P:\\software\\chinvex\\.venv",
  "baseArgs": [],
  "cwd": "P:\\software\\chinvex"
}
```

Fields:
- `name` — shim command name
- `type` — `simple`, `venv`, or `node`
- `ps1Path` — path to the .ps1 launcher script
- `exe` — resolved executable path
- `venv` — virtual environment path (venv type only)
- `baseArgs` — arguments array from command parsing
- `cwd` — working directory override (optional)

This metadata enables `strap doctor` health checks (SHIM001-SHIM009) to validate shim integrity.

## Move

`strap move` relocates a managed repository folder to a new location while keeping the registry consistent. This is useful for reorganizing your workspace or moving repos between the software and tools directories.

**How it works:**
1. Validates the source path exists and is inside a managed root (`software_root` or `tools_root`)
2. Computes the destination path:
   - If `--dest` ends with `\` or points to an existing directory, treats it as the parent directory and keeps the original folder name
   - Otherwise, treats `--dest` as the full new path (allowing rename during move)
3. Validates the destination is also inside a managed root
4. Shows a preview of the planned move
5. Moves the folder using PowerShell `Move-Item`
6. Updates the registry entry's `path` field
7. Optionally updates `scope` if moving between software/tools roots
8. Optionally updates shim content to reference the new path (with `--rehome-shims`)

**Safety features:**
- Refuses to move repos outside managed roots
- Refuses to move to root directories themselves
- Requires `--force` to overwrite existing destinations (and only if they're empty)
- Validates all paths before making changes
- Supports `--dry-run` to preview without executing
- Atomic registry updates (only saves if move succeeds)

**Common use cases:**

```powershell
# Move to a new parent directory (keeps folder name)
strap move my-project --dest P:\software\projects\ --yes

# Move and rename in one step
strap move cli-tool --dest P:\software\_scripts\renamed-tool --yes

# Move between roots (software -> tools)
strap move utility --dest P:\software\_scripts\ --yes

# Update shim content if it contains absolute paths
strap move my-tool --dest P:\software\_tools\ --rehome-shims --yes

# Preview before executing
strap move my-project --dest P:\software\archived\ --dry-run
```

**Flags:**
- `--dest <path>` — destination directory or full path (required)
- `--yes` — skip confirmation prompt
- `--dry-run` — show preview without making changes
- `--force` — allow overwriting existing destination (only if empty)
- `--rehome-shims` — update shim file content to reference new repo path

**Notes:**
- The `--rehome-shims` flag performs simple string replacement of the old path with the new path in shim files
- It only updates shims that contain the old path in their content
- Most shims execute commands relative to the repo or use absolute paths from environment variables, so this flag is rarely needed
- The registry is saved atomically only after the move succeeds

## Rename

`strap rename` changes the registry name of a managed repo. Optionally, it can also rename the folder on disk to match.

**How it works:**
1. Validates the new name doesn't contain invalid filesystem characters (`\/:*?"<>|`)
2. Checks the new name isn't already used by another registry entry
3. Shows a preview of the planned rename
4. Updates the registry entry's `name` field
5. If the `id` field matches the old name, updates it to the new name (follows id=name convention)
6. Optionally renames the folder on disk (with `--move-folder`)
7. Updates the `updated_at` timestamp

**Safety features:**
- Validates new name against filesystem reserved characters
- Prevents duplicate names in registry
- Refuses to rename folder if destination already exists
- Validates paths remain inside managed roots
- Supports `--dry-run` to preview without executing
- Atomic registry updates

**Common use cases:**

```powershell
# Rename registry entry only (folder stays the same)
strap rename old-name --to new-name --yes

# Rename both registry entry and folder
strap rename youtube-md --to youtube-markdown --move-folder --yes

# Preview before executing
strap rename myproject --to my-project --move-folder --dry-run
```

**Flags:**
- `--to <newName>` — new registry name (required)
- `--yes` — skip confirmation prompt
- `--dry-run` — show preview without making changes
- `--move-folder` — also rename the folder on disk to match new name
- `--force` — reserved for future use

**Use cases:**

**Registry-only rename** (default):
- Fix typos in the registry name
- Use a better command-friendly name for shims
- Standardize naming conventions across your tools
- The folder path remains unchanged

**Rename with folder** (`--move-folder`):
- Keep registry name and folder name in sync
- Standardize folder naming across your workspace
- Fix naming inconsistencies after adopting an existing repo

**Notes:**
- Renaming only affects the registry entry name used in `strap` commands
- Existing shims continue to work (they reference the repo path, not the name)
- Git remote URLs and commit history are unaffected
- The `id` field is updated automatically if it follows the id=name convention
- Combining rename + move operations: use `strap rename --move-folder` to change both name and folder, or use `strap move` with a destination that includes a new folder name

## Doctor

`strap doctor` diagnoses the strap installation and environment:

- Validates config paths (software_root, tools_root, shims_root, registry_path, strap_root)
- Checks if shims_root is in PATH
- Checks availability and versions of required tools (git, pwsh, python, uv, node toolchain, go, rust)
- Validates registry integrity (JSON validity, required fields, path/shim existence, duplicates)
- Checks for registry-disk drift (repos in registry but not on disk, or vice versa)
- Reports status: OK (all good), WARN (non-critical issues), or FAIL (critical issues)
- Use `--json` for structured output instead of human-readable format

<!--
## Snapshot

`strap snapshot` creates a JSON manifest of your current dev environment state before migration or major changes. It's a metadata-only safety net - not a file backup, just a map of what's where.

**What it captures:**
- Current registry entries
- Discovered git repos (including those not in registry)
- Non-git directories and standalone files
- External references:
  - PM2 services (via `pm2 jlist`)
  - Windows scheduled tasks
  - Shims in your shims directory
  - PATH entries pointing to repos
  - Shell profile references (`$PROFILE`, `.bashrc`, `.bash_profile`)
- Disk space on all relevant drives

**Usage:**

```powershell
# Create snapshot with default locations
strap snapshot

# Custom output path and scan directories
strap snapshot --output pre-migration.json --scan C:\Code --scan P:\software
```

**Limitations:**
- Does NOT detect: NSSM services, VS Code workspace settings, dynamic path construction, running processes
- User must manually audit additional integrations
- User must close IDEs and terminals before consolidation
-->

## Adopt (Enhanced)

`strap adopt` registers existing repos with the strap registry. It now supports bulk discovery mode to scan entire directories.

**Single repo adoption** (original behavior):
```powershell
# Adopt current directory
cd P:\software\existing-repo
strap adopt

# Adopt with custom name and scope
strap adopt --path P:\software\my-repo --name custom-name --tool --yes
```

**Bulk discovery mode** (new):
```powershell
# Discover and adopt all items in directory (top-level only)
strap adopt --scan C:\Code

# Recursive scan
strap adopt --scan C:\Code --recursive

# Automatic mode with heuristic defaults
strap adopt --scan C:\Code --recursive --yes

# Override scope for all discovered items
strap adopt --scan C:\Code --scope software --yes
```

**Classification heuristics:**
- **Git repos:**
  - Single script + README → suggests `--tool` preset (light depth, stable status)
  - Inactive (last commit >180 days) + no references + no uncommitted changes → suggests archive metadata (index depth, dormant status)
  - Otherwise → suggests default preset (full depth, active status)
- **Non-git directories:**
  - Mostly scripts (`.ps1`, `.py`, `.js`, `.sh`) → suggests `--tool` preset
  - Inactive (last modified >180 days) → suggests archive metadata
  - Otherwise → prompts for classification
- **Standalone files:** Surfaced in report but skipped by default

**Safety features:**
- Skips repos already in registry
- With `--yes`: never auto-archives unless `--allow-auto-archive` is also provided
- Validates paths before writing to registry

<!--
## Audit

`strap audit` scans for path dependencies that would break when repos are moved. It checks both outbound (what this repo depends on) and inbound (what depends on this repo) references.

**Scan coverage:**
- File types: `*.ps1`, `*.cmd`, `*.bat`, `*.ts`, `*.js`, `*.mjs`, `*.py`, `*.json`, `*.yaml`, `*.yml`, `.env*`
- Exclusions: `node_modules/`, `venv/`, `.git/`, binaries, images, archives
- External references: PM2 services, scheduled tasks, shims, PATH entries, shell profiles

**Usage:**

```powershell
# Audit a single repo
strap audit chinvex

# Audit all registered repos (uses cached index for performance)
strap audit --all

# Force rebuild of audit index
strap audit --all --rebuild-index

# Get structured JSON output
strap audit --all --json
```

**Index optimization:**
- First run: scans all repos and builds index at `build/audit-index.json`
- Subsequent runs: uses cached data for repos where commit hash hasn't changed
- Automatic invalidation when registry changes or repo content changes

**Known limitations (IMPORTANT):**
- Does NOT detect dynamically constructed paths (string concatenation, template literals)
- Does NOT detect paths in compressed files or databases
- Does NOT detect embedded configs in binaries
- False positives possible for path-like strings in docs
- **Audit is a discovery tool, not a complete safety guarantee** - always manually review output
-->

<!--
## Archive

`strap archive` moves a repo to the archive location (`P:\software\_archive\` by default) and updates its scope to `archive`.

**How it works:**
1. Moves the repo to archive root (equivalent to `strap move <name> --dest P:\software\_archive\`)
2. Updates scope to `archive` in registry
3. Updates chinvex contexts (removes from individual/tools, adds to shared archive)

**Filtering behavior:**
- Archived repos are excluded from `strap update --all`
- Archived repos appear in `strap list --all` but not `strap list`
- `strap doctor` validates archived repos with lower priority

**Usage:**

```powershell
# Archive a project
strap archive old-experiment --yes

# Preview before archiving
strap archive old-experiment --dry-run
```
-->

<!--
## Consolidate

`strap consolidate` is the single entrypoint for migrating entire directories of repos. It runs as a guided wizard that walks through every step: snapshot, discovery, audit, preflight, execution, and verification.

**Wizard Steps:**

1. **Snapshot** - Save current state to `build/consolidate-snapshot-{timestamp}.json`
2. **Discovery & Adoption** - Scan source directory and register all discovered repos
3. **Audit** - Check for path dependencies and external references
4. **Preflight** - Verify disk space, check for collisions, detect PM2/scheduled tasks
5. **Execute** - Move repos, update registry, update chinvex contexts, restart PM2
6. **Verify** - Run `strap doctor`, show manual fix list

**Usage:**

```powershell
# Interactive wizard (recommended first time)
strap consolidate --from "C:\Code"

# Automatic mode (uses heuristic defaults, no prompts)
strap consolidate --from "C:\Code" --yes --stop-pm2

# Preview without executing (runs Steps 1-4 only)
strap consolidate --from "C:\Code" --dry-run

# Allow repos with uncommitted changes
strap consolidate --from "C:\Code" --allow-dirty

# Auto-archive old repos during discovery
strap consolidate --from "C:\Code" --yes --allow-auto-archive
```

**Preflight checks:**
- Target roots exist and are writable
- Sufficient free space (source size + 20% safety margin)
- No destination path collisions (case-insensitive)
- PM2 services check (requires `--stop-pm2` if affected services found)
- Scheduled tasks check (requires `--ack-scheduled-tasks` if detected)
- Git worktrees check (fails if detected)
- Working tree cleanliness (can override with `--allow-dirty`)

**Safety features:**
- Creates rollback log at `build/consolidate-rollback-{timestamp}.json`
- Verifies git integrity after cross-volume copies (`git fsck`, object count, hash)
- Rolls back on first error (deletes destination copies, restores registry)
- Only updates registry after all moves succeed
- PM2 services: stops only affected services, restarts after success
- Transaction safety: rolls back registry if chinvex update fails

**Verification scope:**
- Git object database only (commit history, branches, tags)
- Does NOT verify: LFS content, submodules, working tree files affected by git filters/hooks

**After consolidation:**
- Manually update shell profiles, PATH entries, scheduled tasks (consolidate shows exact instructions)
- Source directory will be empty - safe to delete
- Run `strap doctor` anytime to verify registry consistency
-->

## Templatize

`strap templatize` snapshots an existing repo into a new template folder under `_strap/templates/` (next to `templates/mono/`, `templates/python/`, etc.). It does a filtered copy only (no tokenization), stages just the destination folder, and creates a commit in the strap repo.

Defaults:
- Uses the current working directory's git root as the source (or `--source`).
- Fails if the template folder exists (use `--force` to overwrite).
- Fails if the strap repo is dirty (use `--allow-dirty`).
- Does not push unless `--push` is provided.

Excluded paths include: `.git`, `node_modules`, `dist`, `build`, `.turbo`, `.vite`, `.next`, `coverage`, `.pytest_cache`, `__pycache__`, `.venv`, `venv`, `.pnpm-store`, and `*.log`/`*.tmp`.

## Logging

All templates now include a `logs/` folder at repo root (ignored in git except `logs/.keep`).

- **node-ts-service** and **mono server** write Fastify/Pino logs to `logs/server.log`.
- **python** writes to `logs/app.log` via the stdlib `logging` module.
- **node-ts-web** and **mono UI** log to the browser console (frontends can’t write files). To persist UI logs, send them to a backend endpoint that writes into `logs/`.

## Environment Defaults

The templates assume a repo-root `.env` and `.env.example`:

- Backend (node/mono):
  - `SERVER_HOST=0.0.0.0`
  - `SERVER_PORT=6969`

- Frontend (vite):
  - `UI_HOST=0.0.0.0`
  - `UI_PORT=5174`

Notes:
- `node-ts-service` also honors `HOST/PORT` if present.
- `node-ts-web` and `mono/apps/ui` load `.env` via dotenv in `vite.config.ts` and set `strictPort: true`.
- `mono/apps/server` loads the repo-root `.env` from `apps/server/src/index.ts` so it works even when the working directory is `apps/server`.
- Vite is configured with `allowedHosts: true` to allow access via Tailscale hostnames (e.g., `central-command`).

## Token Replacement

`strap` replaces tokens in both file contents and filenames. The token scan ignores:
`.git`, `node_modules`, `dist`, `build`, `coverage`, `.venv`, `__pycache__`, `.turbo`, `.vite`, `.pnpm-store`.

## Troubleshooting

### `pnpm not found`
Install pnpm via Corepack or global install:

```powershell
corepack enable
# or
npm i -g pnpm
```

Then rerun with `--install` or `--start`.

### CRLF / LF Warnings
`strap` normalizes template files to LF and writes UTF-8 without BOM. Ensure `node_modules/` is ignored to avoid git warning spam.

### Vite host access
Vite configs are set to `allowedHosts: true` to allow access from other hosts.

## Chinvex Integration

**Strap and chinvex are synchronized automatically. Being in the strap registry means being in chinvex.** This gives you a single source of truth for what's available in your system.

### Automatic Context Management

When you manage repos with strap, chinvex contexts are created/updated automatically:

- `strap clone <url>` → Creates repo entry in registry **and** registers path in chinvex with metadata
- `strap adopt <path>` → Registers repo in registry **and** adds to chinvex with metadata
- `strap move <name>` → Updates registry path **and** updates chinvex path
- `strap rename <name>` → Updates registry name **and** updates chinvex context name
- `strap uninstall <name>` → Removes from registry **and** deletes chinvex context

**No manual chinvex commands needed.** The integration is automatic and keeps both systems in perfect sync.

### Metadata-Driven Contexts (V3)

Strap passes all metadata to chinvex for each repo:
- **Individual contexts**: Each repo gets its own chinvex context (context name = repo name)
- **Metadata forwarding**: All three fields (`chinvex_depth`, `status`, `tags`) are passed to chinvex
- **Chinvex decides**: Chinvex receives the metadata and uses what it needs for ingestion and indexing

**Presets** (CLI convenience):
- `--tool` flag → Sets `depth=light`, `status=stable`, `tags=["third-party"]`
- Default → Sets `depth=full`, `status=active`, `tags=[]`

This decouples strap's organizational model from chinvex's ingestion strategy, allowing each tool to evolve independently.

### Global Opt-Out

Chinvex integration is a machine-level decision. To disable it entirely, set in `config.json`:
```json
{
  "chinvex_integration": false
}
```

Once disabled, strap will operate independently without touching chinvex contexts.

### Verification Commands

- `strap contexts` — View all chinvex contexts and their sync status
- `strap sync-chinvex` — Preview registry/chinvex drift (dry run)
- `strap sync-chinvex --reconcile` — Fix any drift between registry and chinvex

See [docs/chinvex-integration.md](docs/chinvex-integration.md) for full technical details.

## Repo Layout

```
templates/common/           # shared baseline files
templates/node-ts-service/  # service template
templates/node-ts-web/      # web template
templates/python/           # python template
templates/mono/             # monorepo template
  context-hook.cmd          # context gathering hook (copied to new projects)
  context-hook.ps1          # context hook PowerShell script
strap.ps1                   # main script (bootstrapping + lifecycle)
strap.cmd                   # entry point
config.json                 # system configuration
registry.json               # lifecycle management registry
modules/                    # core functionality modules
tests/                      # test suites
```

## Testing

This project uses Pester 5 for automated testing. See [TESTING.md](docs/TESTING.md) for detailed documentation.

Quick start:
```powershell
# Install Pester 5
Install-Module Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck

# Run all tests
pwsh -File scripts\run_tests.ps1

# Run specific test
Import-Module Pester -MinimumVersion 5.0.0
Invoke-Pester tests\powershell\YourTest.Tests.ps1 -Output Detailed
```

## Skills

This repo ships a local Codex skill to drive strap via intent inference:

- `skills/strap-bootstrapper/SKILL.md` — intent-based template selection, templatize, and doctor rules

To install it locally, copy the folder into your Codex skills directory (e.g., `C:\Users\<you>\.codex\skills\strap-bootstrapper`).