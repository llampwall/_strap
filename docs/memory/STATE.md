<!-- DO: Rewrite freely. Keep under 30 lines. Current truth only. -->
<!-- DON'T: Add history, rationale, or speculation. No "we used to..." -->

# State

## Current Objective
Stable operations - all major features implemented and working

## Active Work
Configure command added for post-ingestion metadata management

## Blockers
None

## Next Actions
- Monitor setup health via HEALTH column in `strap list`
- Use configure command to optimize chinvex syncing (metadata vs full reingest)
- Consider enabling chinvex integration by default in new installs
- Evaluate consolidate/audit/archive commands for re-enablement

## Quick Reference
- Install: Add `P:\software\_strap` to PATH, then `strap doctor`
- Test: `Invoke-Pester tests/powershell/ -Output Detailed`
- Entry point: `strap.ps1` (invoked via `strap.cmd`)
- Configure: `strap configure <name> --depth <light|full>` (modify metadata post-adoption)

## Out of Scope (for now)
Consolidate/audit/archive commands (disabled since 2026-02-02 incident)

---
Last memory update: 2026-02-05
Commits covered through: 1b551bcdcc04e2f13eab0f3674efe23813c569ab

<!-- chinvex:last-commit:1b551bcdcc04e2f13eab0f3674efe23813c569ab -->
