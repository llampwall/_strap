# strap

Repo bootstrapper for common project templates. `strap` copies a shared `common/` baseline plus a template, replaces tokens, initializes git, optionally installs deps, runs `context-hook`, and makes the first commit.

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

From a PowerShell prompt:

```powershell
# bootstrap a monorepo in P:\software\myrepo
strap myrepo -t mono

# full install + start dev
strap myrepo -t mono --start

# run deterministic health checks
strap doctor
```

## Usage

```
strap <project-name> --template <template> [--path <parent-dir>] [--skip-install] [--install] [--start]
strap <project-name> -t <template> [-p <parent-dir>] [--skip-install] [--install] [--start]

strap doctor [--strap-root <path>] [--keep]
```

### Parameters

- `project-name` (positional) — target repo name
- `--template` / `-t` — one of: `node-ts-service`, `node-ts-web`, `python`, `mono`
- `--path` / `-p` — parent directory for the new repo (default: `P:\software`)
- `--skip-install` — do not install dependencies (lockfile-only install is skipped)
- `--install` — do full install after the initial commit
- `--start` — do full install after the initial commit, then start dev
- `strap doctor` — run deterministic smoke checks across all templates
- `--strap-root` — override the strap repo root (defaults to the current strap root)
- `--keep` — keep doctor artifacts (otherwise cleaned up)

### Examples

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
```

## What Strap Does

1. Creates the repo folder in the parent dir
2. Initializes git and creates the default branch
3. Copies `common/` and the selected template
4. Replaces tokens (`{{REPO_NAME}}`, `{{PY_PACKAGE}}`, `<REPO_NAME>`, `<PY_PACKAGE>`) in file contents and names
5. Ensures `.env.example` exists
6. Installs deps:
   - default: lockfile-only (node/mono)
   - `--install` / `--start`: full install (real dependencies)
7. Runs `build/context-hook.cmd install`
8. Creates initial commit: `chore: init repo from <template> template`
9. Prints next steps (and starts dev if `--start`)

## Doctor

`strap doctor` creates a temporary root inside `_strap/_doctor/<timestamp>`, boots each template with `--skip-install`, then installs and runs a deterministic smoke matrix sequentially:

- node service: `pnpm install && pnpm -s test`
- web: `pnpm install && pnpm -s build`
- python: `python -m pip install -e . pytest && python -m pytest`
- mono: `pnpm install && pnpm -s -w test`

It also performs a short-lived `/health` check for backend templates by starting the server with `SERVER_PORT` from `.env.example`, polling `http://127.0.0.1:<port>/health` for up to 10 seconds, and then shutting it down.

It fails if any unresolved tokens remain outside ignored paths, prints a concise PASS/FAIL summary, and cleans up unless `--keep` is provided.

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
common/           # shared baseline files
node-ts-service/  # service template
node-ts-web/      # web template
python/           # python template
mono/             # monorepo template
build/            # bootstrap scripts + context-hook
```