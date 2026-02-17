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
- fnm vendored location: `P:\software\_node-tools\fnm` (added 2026-02-12)
- Node versions directory: managed by fnm (added 2026-02-12)
- Test gauntlet framework: `docs/TEST_GAUNTLET.md` (systematic testing guide) (added 2026-02-16)

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
- Node versions auto-detected from .nvmrc, .node-version, or package.json engines.node field; stored in registry as node_version (added 2026-02-12)
- Node installations handled by fnm during setup if version missing (added 2026-02-12)
- Corepack only enabled when package.json has packageManager field or --enable-corepack explicitly passed (updated 2026-02-14)
- Corepack commands use fnm-managed Node to prevent permission errors with nvm installations (updated 2026-02-14)
- Validation runs automatically after clone (Tier 1+2) unless --skip-validation passed (added 2026-02-16)
- PowerShell -Verbose common parameter requires custom parameters use different names (e.g., VerboseOutput) (added 2026-02-16)

## Key Facts
- Shim types: simple (direct exec), venv (Python), node (Node.js PATH setup)
- Venv auto-discovery order: .venv, venv, .virtualenv
- Python entry point sources: pyproject.toml [project.scripts], [tool.poetry.scripts], setup.cfg [options.entry_points] console_scripts, setup.py console_scripts (updated 2026-02-17)
- Node entry point source: package.json bin field
- Setup status values: succeeded, failed, skipped, null
- Metadata presets: --tool (light/stable/third-party), --software (full/active/[])
- Configure command flags: --depth, --status, --tags, --add-tags, --remove-tags, --yes, --dry-run, --json
- Python version detection order: .python-version, pyproject.toml requires-python, requirements.txt comments
- pyenv-win shim location: `P:\software\bin\pyenv.{ps1,cmd}` (created by strap doctor --install-pyenv)
- Node version detection order: .nvmrc, .node-version, package.json engines.node (added 2026-02-12)
- fnm shim location: `P:\software\bin\fnm.{ps1,cmd}` (created by strap doctor --install-fnm) (added 2026-02-12)
- Doctor check IDs: SHIM001-009, SYS001-004, NODE001-004, PY001-004 (updated 2026-02-12)
- Setup command environment: fnm Node directory prepended to PATH for all operations (npm/pnpm/yarn/corepack) (added 2026-02-14)
- Validation tiers: Tier 1 (filesystem, <100ms), Tier 2 (invocation, 10s timeout), Tier 3 (deep diagnostics, manual only) (updated 2026-02-17)
- Validation Tier 2 pass condition: exit 0 OR produced any output (non-zero exit still passes if binary launched); PowerShell "not recognized" errors fail (added 2026-02-17)
- Multi-stack detection priority: python > node > rust > go; first match wins, warning shown, --stack overrides (added 2026-02-17)
- Chinvex ingest runs as detached background process (Start-Process); context name stored in registry immediately so uninstall can purge it (added 2026-02-17)
- Verbose logging flags: --verbose / -v (available on clone, setup, verify commands) (added 2026-02-16)

## Hazards
- PowerShell unwraps single-element arrays (use comma operator: `,$array`)
- Unicode chars in output cause parsing errors (use ASCII: [OK], [X], [!])
- Pester 5 syntax differs from Pester 3.x (Should -Be, not Should Be)
- Git worktrees detected by consolidate cause failure
- Cross-volume moves require git integrity verification (fsck + object count)
- PM2 services must be stopped before consolidation moves
- Chinvex context purge requires stdin confirmation ("y") - use `Invoke-Chinvex -StdIn "y"`
- PowerShell parameter binding can misinterpret pipeline values as parameters; wrap loops in script blocks (`& { }`) when accessing properties (added 2026-02-12)
- Global nvm installation can cause permission errors if corepack runs in wrong environment; always use fnm-managed Node for corepack (added 2026-02-14)
- PowerShell -Verbose is a common parameter that conflicts with custom function parameters named Verbose (added 2026-02-16)
- Regex character class brackets (e.g., `[[]`) require escaping in PowerShell regex patterns (added 2026-02-16)
- Windows symlink creation requires Developer Mode or admin rights; preconstruct/pnpm workspaces will EPERM without it (added 2026-02-17)
- Single-element array returned from function is unwrapped by PowerShell; always wrap call sites with `@()` when indexing result (added 2026-02-17)

## Superseded
(None yet)
