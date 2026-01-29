# strap

PowerShell-based repo bootstrapper and lifecycle manager.

**Template Bootstrapping**: Create new projects from templates with dependency installation and initial commit.

**Lifecycle Management**: Clone, track, and manage GitHub repos with shim generation for global command access.

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
- `build/context-hook.cmd` (bundled in this repo)

## Quick Start

### Template Bootstrapping

```powershell
# bootstrap a monorepo in P:\software\myrepo
strap myrepo -t mono

# full install + start dev
strap myrepo -t mono --start

# run deterministic health checks
strap doctor
```

### Lifecycle Management

```powershell
# clone and register a GitHub repo
strap clone https://github.com/user/repo --tool

# list all registered repos
strap list

# create a global command shim
cd P:\software\myrepo
strap shim my-command --cmd "python script.py"

# uninstall a registered repo (removes shims and directory)
strap uninstall myrepo --yes
```

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
strap adopt [--path <dir>] [--name <name>] [--tool|--software] [--yes] [--dry-run]
strap setup [--yes] [--dry-run] [--stack python|node|go|rust] [--repo <name>]
strap setup [--venv <path>] [--uv] [--python <exe>] [--pm npm|pnpm|yarn] [--corepack]
strap update <name> [--yes] [--dry-run] [--rebase] [--stash] [--setup]
strap update --all [--tool] [--software] [--yes] [--dry-run] [--rebase] [--stash] [--setup]
strap shim <name> --- <command...> [--cwd <path>] [--repo <name>] [--force] [--dry-run] [--yes]
strap shim <name> --cmd "<command>" [--cwd <path>] [--repo <name>] [--force] [--dry-run] [--yes]
strap uninstall <name> [--yes]
strap doctor [--json]
strap migrate [--yes] [--dry-run] [--backup] [--json] [--to <version>] [--plan]
```

### Parameters

#### Template Bootstrapping

- `project-name` (positional) — target repo name
- `--template` / `-t` — one of: `node-ts-service`, `node-ts-web`, `python`, `mono`
- `--path` / `-p` — parent directory for the new repo (default: `P:\software`)
- `--skip-install` — do not install dependencies (lockfile-only install is skipped)
- `--install` — do full install after the initial commit
- `--start` — do full install after the initial commit, then start dev
- `strap doctor` — run deterministic smoke checks across all templates
- `--strap-root` — override the strap repo root (defaults to the current strap root)
- `--keep` — keep doctor artifacts (otherwise cleaned up)

#### Lifecycle Management

**clone**
- `<github-url>` — GitHub repository URL (https or git)
- `--tool` — clone into `P:\software\_scripts` instead of `P:\software`
- `--name <custom-name>` — override the repo name (default: extracted from URL)
- `--yes` — skip confirmation prompts

**list**
- `--verbose` — show full details including paths, types, shims, and timestamps

**adopt**
- `--path <dir>` — path to existing repo (default: current directory)
- `--name <name>` — custom registry name (default: folder name)
- `--tool` — force scope=tool
- `--software` — force scope=software
- `--yes` — skip confirmation prompts
- `--dry-run` — preview only, no registry write

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
- `--setup` — run strap setup after successful update (when implemented)
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

**migrate**
- `--yes` — skip confirmation prompts
- `--dry-run` — preview migrations without writing to registry
- `--backup` — create timestamped backup before migrating
- `--json` — output structured JSON report instead of human-readable format
- `--to <version>` — migrate to specific version (default: latest)
- `--plan` — show migration plan without executing

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

# Migrate registry to latest version
strap migrate --yes

# Preview migration plan without executing
strap migrate --plan

# Migrate with backup
strap migrate --yes --backup

# Preview migration changes
strap migrate --dry-run

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
```

## What Strap Does

### Template Bootstrapping

1. Creates the repo folder in the parent dir
2. Initializes git and creates the default branch
3. Copies `templates/common/` and the selected template
4. Replaces tokens (`{{REPO_NAME}}`, `{{PY_PACKAGE}}`, `<REPO_NAME>`, `<PY_PACKAGE>`) in file contents and names
5. Ensures `.env.example` exists
6. Installs deps:
   - default: lockfile-only (node/mono)
   - `--install` / `--start`: full install (real dependencies)
7. Runs `build/context-hook.cmd install`
8. Creates initial commit: `init repo from <template> template`
9. Prints next steps (and starts dev if `--start`)

### Lifecycle Management

**clone**
1. Parses GitHub URL and determines repo name
2. Creates registry entry with metadata (type: tool/project, paths, timestamps)
3. Runs `git clone` into the appropriate directory (`P:\software` or `P:\software\_scripts`)
4. Updates registry with clone status and timestamps
5. Returns next steps (suggest creating shims if needed)

**list**
1. Loads registry from `build/registry.json`
2. Displays registered repos with name, type, and status
3. With `--verbose`: shows full paths, shim lists, and timestamps

**adopt**
1. Resolves target path (from `--path` flag or current directory)
2. Validates path is within managed roots (`P:\software` or `P:\software\_scripts`)
3. Validates it's a git repository (`.git` directory exists)
4. Determines scope (tool/software) from flags or infers from location
5. Extracts git metadata (best-effort):
   - `url`: from `git remote get-url origin`
   - `last_head`: from `git rev-parse HEAD`
   - `default_branch`: from symbolic ref (if available)
6. Detects stack (same logic as `strap setup`)
7. Creates registry entry with all metadata
8. Previews entry and confirms (unless `--yes`)
9. Writes to registry (unless `--dry-run`)
10. Suggests next steps (setup, shim, update)

**doctor**
1. Loads config and validates paths
2. Checks if `shims_root` is in PATH
3. Checks availability and versions of tools:
   - Critical: git, pwsh
   - Python: python, uv (standalone or python -m uv)
   - Node: node, npm, pnpm, yarn, corepack
   - Optional: go, cargo
4. Validates registry integrity:
   - JSON validity
   - Registry version (warns if outdated)
   - Required fields present
   - Path existence
   - Shim existence
   - Duplicate name detection
5. Outputs report (human-readable or JSON with `--json`)
6. Returns status: OK, WARN, or FAIL
7. Exit codes: 0 for OK/WARN, 1 for FAIL

**migrate**
1. Loads registry and detects current version
2. If version == target: exits with "nothing to do"
3. If version > latest supported: fails (tool too old)
4. Plans migrations needed (e.g., V0→V1)
5. Applies migrations sequentially in memory:
   - **V0→V1**: Wraps array in versioned object, backfills required fields (id, shims, created_at, updated_at)
6. Validates schema after migration (checks all required fields)
7. Detects and fails on duplicate entries (requires manual resolution)
8. Displays migration summary (entries scanned, fields backfilled, etc.)
9. Confirms with user (unless `--yes` or `--dry-run`)
10. Creates timestamped backup if `--backup` flag provided
11. Writes migrated registry atomically (temp file → rename)
12. Outputs result (human-readable or JSON with `--json`)
13. Exit codes: 0 for success/nothing to do, 1 for validation failure, 3 for write failure

**setup**
1. Determines repo path (from `--repo` flag or current directory)
2. Validates path is within managed roots
3. Detects stack in precedence order:
   - Python: `pyproject.toml` or `requirements.txt`
   - Node: `package.json`
   - Rust: `Cargo.toml`
   - Go: `go.mod`
   - Docker: detected but not auto-run
4. Generates allowlisted install plan based on stack:
   - **Python**: create venv, install pip/uv, run uv sync or pip install
   - **Node**: enable corepack (optional), run npm/pnpm/yarn install
   - **Rust**: run cargo build
   - **Go**: run go mod download
5. Prints plan preview with exact commands
6. Confirms with user (unless `--yes`)
7. Executes plan sequentially, stops on first failure
8. Updates registry metadata:
   - `updated_at` — current timestamp
   - `stack_detected` — detected stack type
   - `setup_last_run_at` — timestamp of last setup
   - `setup_status` — success or fail

**update**
1. Loads registry and finds repo(s) to update
2. Validates paths are within managed roots (`P:\software` or `P:\software\_scripts`)
3. Checks for `.git` directory presence
4. Detects dirty working tree (uncommitted changes):
   - Default: aborts (single) or skips (--all)
   - With `--stash`: auto-stash before pull, restore after
5. Runs `git fetch --all --prune`
6. Runs `git pull` or `git pull --rebase` (with `--rebase`)
7. Updates registry metadata:
   - `updated_at` — current timestamp
   - `last_pull_at` — timestamp of last pull
   - `last_head` — current HEAD commit hash
   - `last_remote` — remote tracking branch hash
8. Optionally runs `strap setup` after successful pull (with `--setup`)
9. For `--all`: prints summary of updated/skipped/failed repos

**shim**
1. Validates shim name (no path separators or reserved characters)
2. Determines registry attachment (current directory or `--repo` flag)
3. Generates `.cmd` file in `P:\software\_scripts\_bin`
4. Optionally wraps command with `pushd`/`popd` if `--cwd` specified
5. Updates registry entry's shim list
6. Makes shim globally accessible (assumes `_bin` is in PATH)

**uninstall**
1. Finds registry entry by name
2. Confirms deletion (unless `--yes`)
3. Removes all associated shims from `P:\software\_scripts\_bin`
4. Deletes the repository directory
5. Removes registry entry
6. Reports cleanup results

### Registry System

Lifecycle management uses a JSON registry at `build/registry.json` to track all cloned repos and their associated shims. Each entry includes:

- `id` — unique identifier
- `name` — repo name (used for commands)
- `type` — "tool" or "project"
- `repo_path` — absolute path to the cloned repository
- `shims` — array of shim file paths
- `created_at` — ISO 8601 timestamp
- `updated_at` — ISO 8601 timestamp
- `last_pull_at` — ISO 8601 timestamp of last update (added by `strap update`)
- `last_head` — git commit hash after last update (added by `strap update`)
- `last_remote` — remote tracking branch hash after last update (added by `strap update`)
- `stack_detected` — detected stack type (added by `strap setup`)
- `setup_last_run_at` — ISO 8601 timestamp of last setup (added by `strap setup`)
- `setup_status` — setup execution status: "success" or "fail" (added by `strap setup`)

The registry enables:
- Tracking which repos have been cloned
- Associating shims with their parent repos
- Safe cleanup during uninstall (removes repo + all shims)
- Quick listing of all managed repos

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

## Doctor

`strap doctor` diagnoses the strap installation and environment:

- Validates config paths (software_root, tools_root, shims_root, registry_path, strap_root)
- Checks if shims_root is in PATH
- Checks availability and versions of required tools (git, pwsh, python, uv, node toolchain, go, rust)
- Validates registry integrity (JSON validity, required fields, path/shim existence, duplicates)
- Reports status: OK (all good), WARN (non-critical issues), or FAIL (critical issues)
- Use `--json` for structured output instead of human-readable format

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

## Repo Layout

```
templates/common/           # shared baseline files
templates/node-ts-service/  # service template
templates/node-ts-web/      # web template
templates/python/           # python template
templates/mono/             # monorepo template
build/
  strap.ps1                 # main script (bootstrapping + lifecycle)
  strap.cmd                 # entry point
  context-hook.cmd          # context gathering hook
  registry.json             # lifecycle management registry
test-*.ps1                  # test suites for each command
```

## Skills

This repo ships a local Codex skill to drive strap via intent inference:

- `skills/strap-bootstrapper/SKILL.md` — intent-based template selection, templatize, and doctor rules

To install it locally, copy the folder into your Codex skills directory (e.g., `C:\Users\<you>\.codex\skills\strap-bootstrapper`).