<!-- DO: Rewrite freely. Keep under 30 lines. Current truth only. -->
<!-- DON'T: Add history, rationale, or speculation. No "we used to..." -->

# State

## Current Objective
Stable operations - all major features implemented and working

## Active Work
None (maintenance mode)

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
Last memory update: 2026-02-16
Commits covered through: d73e462ffc1c93c5ea0ff2d8004da9e3089e8b6a

<!-- chinvex:last-commit:d73e462ffc1c93c5ea0ff2d8004da9e3089e8b6a -->
