<!-- DO: Rewrite freely. Keep under 30 lines. Current truth only. -->
<!-- DON'T: Add history, rationale, or speculation. No "we used to..." -->

# State

## Current Objective
Stable operations - gauntlet Round 2 complete, all strap bugs resolved

## Active Work
None (maintenance mode)

## Blockers
None

## Next Actions
- Monitor async chinvex ingest completion in production
- Consider `strap doctor --symlinks` check for Windows Developer Mode
- Monitor validation false-negative rate with new output-based pass logic

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
Last memory update: 2026-02-17
Commits covered through: 04eed3a9089fcacca1c508618f5030f00d78c6d3

<!-- chinvex:last-commit:04eed3a9089fcacca1c508618f5030f00d78c6d3 -->
