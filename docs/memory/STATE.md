<!-- DO: Rewrite freely. Keep under 30 lines. Current truth only. -->
<!-- DON'T: Add history, rationale, or speculation. No "we used to..." -->

# State

## Current Objective
Stable operations - all major features implemented and working

## Active Work
None (maintenance mode)

## Recent Completions (Feb 12, 2026)
- fnm integration for Node version management (mirrors pyenv-win pattern)
- Auto-detection from .nvmrc/.node-version/package.json engines field
- Auto-installation of Node versions during setup
- Build step detection (automatic build/prepare execution)
- Migrated all 5 Node projects to fnm (node_version tracked in registry)
- Comprehensive test suite (19 tests), documentation, and migration tooling

## Blockers
None

## Next Actions
- Monitor setup health via HEALTH column in `strap list`
- Monitor pyenv-win integration across different Python projects and version formats
- Monitor major.minor → latest patch version resolution accuracy
- Use configure command to optimize chinvex syncing (metadata vs full reingest)
- Consider enabling chinvex integration by default in new installs

## Quick Reference
- Install: Add `P:\software\_strap` to PATH, then `strap doctor`
- Test: `Invoke-Pester tests/powershell/ -Output Detailed`
- Entry point: `strap.ps1` (invoked via `strap.cmd`)
- Configure: `strap configure <name> --depth <light|full>` (modify metadata post-adoption)

## Out of Scope (for now)
Consolidate/audit/archive commands (disabled since 2026-02-02 incident)

---
Last memory update: 2026-02-12
Commits covered through: dceddcb5b88f8cf69e35e96ae3e7dd5db12e08c4

<!-- chinvex:last-commit:dceddcb5b88f8cf69e35e96ae3e7dd5db12e08c4 -->
