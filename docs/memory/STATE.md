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
- Monitor validation system performance in production
- Monitor verbose logging usage patterns
- Monitor upgrade commands in production use
- Use configure command to optimize chinvex syncing (metadata vs full reingest)

## Quick Reference
- Install: Add `P:\software\_strap` to PATH, then `strap doctor`
- Test: `Invoke-Pester tests/powershell/ -Output Detailed`
- Validate: `strap verify <name>` (Tier 1+2) or `strap verify <name> --deep` (all tiers)
- Verbose: `strap clone <url> --verbose` or `strap setup --repo <name> --verbose`
- Upgrade: `strap upgrade-node <name> --latest` or `strap upgrade-python <name> --latest`
- Entry point: `strap.ps1` (invoked via `strap.cmd`)

## Out of Scope (for now)
Consolidate/audit/archive commands (disabled since 2026-02-02 incident)

---
Last memory update: 2026-02-16
Commits covered through: 4f55bb6ec48a66e5fa942278798b64b9c030edd7

<!-- chinvex:last-commit:4f55bb6ec48a66e5fa942278798b64b9c030edd7 -->
