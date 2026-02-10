<!-- DO: Add bullets. Edit existing bullets in place with (updated YYYY-MM-DD). -->
<!-- DON'T: Delete bullets. Don't write prose. Don't duplicate — search first. -->

# Constraints

## Infrastructure
- Shims directory: `P:\software\bin` (must be on PATH)
- Software root: `P:\software` (flat structure)
- Tools root: `P:\software\_scripts`
- Registry path: `P:\software\_strap\registry.json`
- Registry backups: `P:\software\_strap\backups\` (automatic, keeps 30 most recent) (added 2026-02-09)
- Registry version: 3 (auto-migrates from V2)
- Default PWsh: Windows Store pwsh.exe (`C:\Program Files\WindowsApps\...`)
- Chinvex contexts root: `P:\ai_memory\contexts`
- PM2 vendored location: `P:\software\_node-tools\pm2`
- pyenv-win vendored location: `P:\software\_python-tools\pyenv-win`
- Python versions directory: `P:\software\_python-tools\pyenv-win\pyenv-win\versions` (managed by pyenv-win)

## Rules
- Never run consolidate/audit/snapshot/migrate/archive commands (kill-switched since 2026-02-02)
- Chinvex integration is machine-level (global opt-out only via config.json)
- Reserved context names: "tools", "archive" (case-insensitive)
- Setup auto-runs during clone/adopt (use --skip-setup to opt out)
- Shims are dual-file (.ps1 + .cmd wrapper) for cross-shell compatibility
- Use `--cmd` for commands with single-letter flags (avoids PowerShell parameter binding)
- Registry must be atomic (save only after successful operations)
- Never modify venv shims manually (regenerate with `strap shim --regen`)
- Metadata-only changes use sync-metadata-from-strap; depth changes trigger full reingest with --rebuild-index (updated 2026-02-05)
- System tools (PM2, etc.) can be vendored and shimmed to _strap repo for system-wide availability (updated 2026-02-05)
- Python versions auto-detected from .python-version, pyproject.toml, or requirements.txt; stored in registry as python_version (updated 2026-02-08)
- pyenv-win ignores PYENV_ROOT environment variable; hardcoded to pyenv-win\versions\ in VBScript (updated 2026-02-08)
- Major.minor Python versions (e.g., "3.12") dynamically resolve to latest stable patch via pyenv install --list (updated 2026-02-08)
- Python installations validated after install by running python --version (updated 2026-02-08)
- Conservative default: pip (not uv) for dependency installation unless --use-uv specified (updated 2026-02-08)
- Registry automatically backed up before every write with timestamp; pruned to keep 30 most recent (added 2026-02-09)

## Key Facts
- Shim types: simple (direct exec), venv (Python), node (Node.js PATH setup)
- Venv auto-discovery order: .venv, venv, .virtualenv
- Python entry point sources: pyproject.toml [project.scripts], [tool.poetry.scripts], setup.py console_scripts
- Node entry point source: package.json bin field
- Setup status values: succeeded, failed, skipped, null
- Metadata presets: --tool (light/stable/third-party), --software (full/active/[])
- Configure command flags: --depth, --status, --tags, --add-tags, --remove-tags, --yes, --dry-run, --json
- Python version detection order: .python-version, pyproject.toml requires-python, requirements.txt comments
- pyenv-win shim location: `P:\software\bin\pyenv.{ps1,cmd}` (created by strap doctor --install-pyenv)

## Hazards
- PowerShell unwraps single-element arrays (use comma operator: `,$array`)
- Unicode chars in output cause parsing errors (use ASCII: [OK], [X], [!])
- Pester 5 syntax differs from Pester 3.x (Should -Be, not Should Be)
- Git worktrees detected by consolidate cause failure
- Cross-volume moves require git integrity verification (fsck + object count)
- PM2 services must be stopped before consolidation moves
- Chinvex context purge requires stdin confirmation ("y") - use `Invoke-Chinvex -StdIn "y"`

## Superseded
(None yet)
