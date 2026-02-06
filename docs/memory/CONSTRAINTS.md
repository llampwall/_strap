<!-- DO: Add bullets. Edit existing bullets in place with (updated YYYY-MM-DD). -->
<!-- DON'T: Delete bullets. Don't write prose. Don't duplicate — search first. -->

# Constraints

## Infrastructure
- Shims directory: `P:\software\bin` (must be on PATH)
- Software root: `P:\software` (flat structure)
- Tools root: `P:\software\_scripts`
- Registry path: `P:\software\_strap\registry.json`
- Registry version: 3 (auto-migrates from V2)
- Default PWsh: Windows Store pwsh.exe (`C:\Program Files\WindowsApps\...`)
- Chinvex contexts root: `P:\ai_memory\contexts`

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

## Key Facts
- Shim types: simple (direct exec), venv (Python), node (Node.js PATH setup)
- Venv auto-discovery order: .venv, venv, .virtualenv
- Python entry point sources: pyproject.toml [project.scripts], [tool.poetry.scripts], setup.py console_scripts
- Node entry point source: package.json bin field
- Setup status values: succeeded, failed, skipped, null
- Metadata presets: --tool (light/stable/third-party), --software (full/active/[])
- Configure command flags: --depth, --status, --tags, --add-tags, --remove-tags, --yes, --dry-run, --json

## Hazards
- PowerShell unwraps single-element arrays (use comma operator: `,$array`)
- Unicode chars in output cause parsing errors (use ASCII: [OK], [X], [!])
- Pester 5 syntax differs from Pester 3.x (Should -Be, not Should Be)
- Git worktrees detected by consolidate cause failure
- Cross-volume moves require git integrity verification (fsck + object count)
- PM2 services must be stopped before consolidation moves

## Superseded
(None yet)
