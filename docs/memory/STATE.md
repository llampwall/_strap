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
Last memory update: 2026-02-08
Commits covered through: a910b754153b35f1ac974a0da69d1d20c5341227

<!-- chinvex:last-commit:a910b754153b35f1ac974a0da69d1d20c5341227 -->
