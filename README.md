# strap

Complete Windows dev environment manager with two halves:

**1. Template bootstrapping** — spin up new projects from templates (node-ts-service, mono, python, etc.) with deps installed and ready to code.

**2. Lifecycle management** — the real power:
- Clone GitHub repos and track them in a central registry
- Install deps safely with stack auto-detection (python/node/go/rust)
- Create global `.cmd` shims for any command (no manual PATH edits)
- Move and rename repos while keeping registry consistent
- Update all your tools at once (`--all` flag)
- Uninstall cleanly (removes folder + shims + registry entry)
- Schema versioning means it won't brick itself as it evolves

**What makes it special:** Single front door for your dev tools. Instead of scattered `git clone` + manual PATH edits + "where did I put that script?", everything goes through strap.

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
```

### Lifecycle Management

```powershell
# clone a tool and register it
strap clone https://github.com/user/cli-tool --tool

# install its dependencies (auto-detects python/node/go/rust)
strap setup --repo cli-tool --yes

# create a global launcher (no PATH editing needed)
strap shim mytool --cmd "python -m cli_tool" --repo cli-tool

# now "mytool" works from anywhere
mytool --help

# update all your tools at once
strap update --all --tool

# diagnose issues
strap doctor
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
strap move <name> --dest <path> [--yes] [--dry-run] [--force] [--rehome-shims]
strap rename <name> --to <newName> [--yes] [--dry-run] [--move-folder] [--force]
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
- `--strap-root` — override the strap repo root (defaults to the current strap root)

#### Lifecycle Management

**clone**
- `<github-url>` — GitHub repository URL (https or git)
- `--tool` — clone into `P:\software\_scripts` instead of `P:\software`
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
- Installs the context hook (`build/context-hook.cmd install`)
- Creates an initial commit
- Prints next steps (and starts dev if `--start`)

### Lifecycle management (existing repo/tool)

- `clone`: clone a GitHub repo into `P:\software\...` or `P:\software\_scripts\...` and register it
- `adopt`: register a repo you already cloned manually
- `setup`: detect stack and run an allowlisted install plan (python/node/go/rust; docker = detect only)
- `shim`: generate a `.cmd` launcher in your shims dir and attach it to the registry entry
- `update`: pull latest changes (single or `--all`, supports `--rebase`, `--stash`, optional `--setup`)
- `move`: relocate a managed repo to a new path while keeping registry consistent
- `rename`: change a registry entry name (optionally rename folder on disk)
- `uninstall`: remove shims + folder + registry entry
- `list`: show all registered repos
- `open`: open a registered repo's folder in File Explorer
- `doctor`: diagnose strap + registry health
- `migrate`: upgrade registry schema safely (backfills required fields, enforces invariants)

### Registry System

Lifecycle management uses a JSON registry at `build/registry.json` to track all cloned repos and their associated shims. Each entry includes:

- `id` — unique identifier
- `name` — repo name (used for commands)
- `scope` — "tool" or "software"
- `path` — absolute path to the cloned repository
- `url` — git remote URL (if available)
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