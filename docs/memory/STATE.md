<!-- DO: Rewrite freely. Keep under 30 lines. Current truth only. -->
<!-- DON'T: Add history, rationale, or speculation. No "we used to..." -->

# State

## Current Objective
Stable operations - all major features implemented and working

## Active Work
None (maintenance mode)

## Recent Completions (Feb 12, 2026)
- Version upgrade commands (upgrade-node, upgrade-python) with --latest/--version/--list-only flags
- Batch upgrade with --all flag (upgrade all Node or Python projects at once)
- Doctor health checks with version outdated warnings (NODE004, PY004)
- fnm integration for Node version management (mirrors pyenv-win pattern)
- Comprehensive test suite (19 fnm tests), documentation (FNM_INTEGRATION.md, CLAUDE.md)
- Migrated all 5 Node projects to fnm (node_version tracked in registry)

## Blockers
None

## Next Actions
- Monitor upgrade commands in production use
- Monitor setup health via HEALTH column in `strap list`
- Monitor pyenv-win integration across different Python projects
- Use configure command to optimize chinvex syncing (metadata vs full reingest)

## Quick Reference
- Install: Add `P:\software\_strap` to PATH, then `strap doctor`
- Test: `Invoke-Pester tests/powershell/ -Output Detailed`
- Upgrade: `strap upgrade-node <name> --latest` or `strap upgrade-python <name> --latest`
- Batch upgrade: `strap upgrade-node --all --latest`
- Entry point: `strap.ps1` (invoked via `strap.cmd`)

## Out of Scope (for now)
Consolidate/audit/archive commands (disabled since 2026-02-02 incident)

---
Last memory update: 2026-02-14
Commits covered through: 6e76969e0c4ced01ff197d68d6484b5d30491107

<!-- chinvex:last-commit:6e76969e0c4ced01ff197d68d6484b5d30491107 -->
