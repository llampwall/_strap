# TDD Tasks Status Report

**Date:** 2026-02-02
**Context:** Following environment corruption incident, assessment of PowerShell port progress

---

## Overview

The PowerShell TDD plan (`docs/plans/2026-02-02-powershell-port-tdd.md`) defined 14 tasks across 3 batches to port dev-environment-consolidation functionality from TypeScript to pure PowerShell.

Development was interrupted when subagent processes consumed 45GB RAM, requiring force-kill, which caused the environment corruption documented in `docs/incidents/2026-02-02-environment-corruption.md`.

---

## Task Status Summary

| Task | Description | Status | Notes |
|------|-------------|--------|-------|
| 1 | Scheduled Task Detection | **COMMITTED** | `Get-ScheduledTaskReferences` function exists |
| 2 | Shim Detection | **COMMITTED** | `Get-ShimReferences` function exists |
| 3 | PATH/Profile Scanning | **COMMITTED** | `Get-PathReferences`, `Get-ProfileReferences` exist |
| 4 | Audit Index Foundation | **COMMITTED** | `Find-PathReferences`, `Build-AuditIndex` exist |
| 5 | Audit Index Integration | **COMMITTED** | Integrated into consolidate workflow |
| 6 | Snapshot Command | **COMMITTED** | `Invoke-Snapshot` exists with CLI wiring |
| 7 | Audit Command | **PARTIAL** | `Invoke-Audit` exists but tests may be incomplete |
| 8 | Archive Command | **NOT STARTED** | `Invoke-Archive` does not exist |
| 9 | Adopt --scan Bulk Mode | **NOT STARTED** | `Invoke-Adopt` lacks `--scan` parameter |
| 10 | Doctor --fix-paths | **NOT STARTED** | `Invoke-Doctor` lacks `FixPaths` parameter |
| 11 | Doctor --fix-orphans | **NOT STARTED** | `Invoke-Doctor` lacks `FixOrphans` parameter |
| 12 | Consolidate Snapshot Enhancement | **NOT STARTED** | `Build-ConsolidateSnapshot` does not exist |
| 13 | Help Text and README | **NOT STARTED** | Help text not updated for new commands |
| 14 | Test Infrastructure | **NOT STARTED** | No PesterConfig.ps1, Run-Tests.ps1, etc. |

---

## Detailed Findings

### Batch 1: External Reference Detection Foundation (Tasks 1-5) - COMPLETE

All 5 tasks were committed. Git log shows:
```
34e1578 Task 1: Scheduled task detection with Pester tests
d756668 Task 2: Shim detection with Pester tests
0ade7d4 Task 3: PATH and profile scanning with Pester tests
acf67f6 Task 4: Add audit index foundation with Pester tests
284ddcc Task 5: Integrate comprehensive audit into consolidate workflow
```

**Functions implemented:**
- `Get-ScheduledTaskReferences` (line 729)
- `Get-ShimReferences` (line 795)
- `Get-PathReferences` (line 865)
- `Get-ProfileReferences` (line 918)
- `Find-PathReferences` (line 984)
- `Build-AuditIndex` (line 1040)

**Test files exist:**
- `tests/powershell/Get-ScheduledTaskReferences.Tests.ps1`
- `tests/powershell/Get-ShimReferences.Tests.ps1`
- `tests/powershell/Get-PathProfileReferences.Tests.ps1`
- `tests/powershell/Build-AuditIndex.Tests.ps1`
- `tests/powershell/Invoke-ConsolidateAuditStep.Tests.ps1`

### Batch 2: Standalone Commands (Tasks 6-10) - PARTIAL

Only Task 6 was committed:
```
621d5d7 Task 6: Add snapshot command with CLI wiring
```

**Task 6 (Snapshot) - COMPLETE:**
- `Invoke-Snapshot` exists (line 1175)
- Test file: `tests/powershell/Invoke-Snapshot.Tests.ps1`

**Task 7 (Audit) - PARTIAL:**
- `Invoke-Audit` exists (line 1400)
- Test file exists: `tests/powershell/Invoke-Audit.Tests.ps1`
- **UNKNOWN:** Tests may not pass, implementation may be incomplete

**Task 8 (Archive) - NOT STARTED:**
- `Invoke-Archive` function does not exist
- No test file
- No CLI wiring

**Task 9 (Adopt --scan) - NOT STARTED:**
- `Invoke-Adopt` exists but lacks `--scan` parameter
- Help text shows: `strap adopt [--path <dir>] [--name <name>]` (no `--scan`)
- No recursive scanning or bulk adoption capability

**Task 10 (Doctor --fix-paths) - NOT STARTED:**
- `Invoke-Doctor` signature: `param([string] $StrapRootPath, [switch] $OutputJson)`
- No `FixPaths` parameter
- Error messages reference `--fix-paths` but the flag doesn't work

### Batch 3: Final Enhancements (Tasks 11-14) - NOT STARTED

None of these tasks were implemented.

**Task 11 (Doctor --fix-orphans):**
- No `FixOrphans` parameter on `Invoke-Doctor`

**Task 12 (Consolidate Snapshot Enhancement):**
- `Build-ConsolidateSnapshot` function does not exist
- Consolidate workflow uses simple snapshot (lines 4184-4191):
  ```powershell
  $snapshot = @{
      timestamp = $timestamp
      fromPath = $FromPath
      registryCount = $registry.Count
      dryRun = $DryRun.IsPresent
  }
  ```
- Missing: git metadata, external references, full registry snapshot

**Task 13 (Help Text and README):**
- Help text doesn't include: `snapshot`, `audit`, `archive`, `consolidate`
- Help text shows old adopt syntax without `--scan`
- Doctor help shows only `[--json]`

**Task 14 (Test Infrastructure):**
- No `tests/powershell/PesterConfig.ps1`
- No `tests/powershell/Run-Tests.ps1`
- No `tests/powershell/Test-Helpers.ps1`
- No `tests/powershell/fixtures/` directory
- No `.github/workflows/test-powershell.yml`

---

## Current State of Key Components

### Help Text (Show-Help)
Does NOT document:
- `strap snapshot`
- `strap audit`
- `strap archive`
- `strap consolidate`
- `strap adopt --scan`
- `strap doctor --fix-paths`
- `strap doctor --fix-orphans`

### Consolidate Workflow (Invoke-ConsolidateMigrationWorkflow)
**EXISTS** with 6-step workflow:
1. Snapshot (basic - missing comprehensive manifest)
2. Discovery (scans FromPath for git repos)
3. Plan moves (interactive scope selection)
4. Audit (calls external reference functions)
5. Preflight checks
6. Execute moves

**Known issues:**
- References `--fix-paths` in error messages but flag doesn't exist
- Snapshot lacks git metadata and external references structure

---

## Recommendations

### Option A: Quarantine All New Functions
Disable Tasks 1-7 functions by commenting them out or gating behind a flag. Keep only stable, pre-TDD functionality.

**Impact:** Lose external reference detection during consolidate, lose snapshot and audit commands.

### Option B: Stabilize Batch 1-2, Disable Rest
Keep Tasks 1-6 (external reference detection + snapshot), disable/remove Tasks 7-14 references.

**Required cleanup:**
1. Remove `Invoke-Audit` or mark experimental
2. Remove references to non-existent `--fix-paths`, `--fix-orphans`
3. Remove references to non-existent `--scan`
4. Don't call `Invoke-Snapshot` or `Invoke-Audit` from CLI dispatch

### Option C: Document Current State, Ship As-Is
Accept that commands are incomplete, document limitations, ship what works.

**Required:**
1. Update help text to reflect actual capabilities
2. Document experimental status of snapshot/audit
3. Remove broken CLI dispatch for unimplemented commands

---

## Files to Review

### Test Files (may require scheduled tasks/shim setup to run)
- `tests/powershell/Get-ScheduledTaskReferences.Tests.ps1`
- `tests/powershell/Get-ShimReferences.Tests.ps1`
- `tests/powershell/Get-PathProfileReferences.Tests.ps1`
- `tests/powershell/Build-AuditIndex.Tests.ps1`
- `tests/powershell/Invoke-ConsolidateAuditStep.Tests.ps1`
- `tests/powershell/Invoke-Snapshot.Tests.ps1`
- `tests/powershell/Invoke-Audit.Tests.ps1`

### Implementation (strap.ps1)
- Lines 729-982: External reference detection functions
- Lines 984-1173: Audit index functions
- Lines 1175-1398: `Invoke-Snapshot`
- Lines 1400-1555: `Invoke-Audit`
- Lines 3153-3409: `Invoke-Doctor` (basic, no enhancements)
- Lines 4155-end: `Invoke-ConsolidateMigrationWorkflow`

---

## Git Commits (Relevant)

```
621d5d7 Task 6: Add snapshot command with CLI wiring
284ddcc Task 5: Integrate comprehensive audit into consolidate workflow
acf67f6 Task 4: Add audit index foundation with Pester tests
0ade7d4 Task 3: PATH and profile scanning with Pester tests
d756668 Task 2: Shim detection with Pester tests
34e1578 Task 1: Scheduled task detection with Pester tests
```

After Tasks 1-6, development was interrupted by the environment corruption incident.

---

## Kill Switch Implementation (2026-02-02)

Following the incident, a kill switch was implemented to disable dangerous functions while preserving read-only discovery functionality.

### Kill Switch Location
- **File:** `strap.ps1` lines 73-103
- **Array:** `$UNSAFE_COMMANDS`
- **Guard function:** `Assert-CommandSafe`

### Disabled Commands
```powershell
$UNSAFE_COMMANDS = @(
    'Invoke-Snapshot',
    'Invoke-Audit',
    'Invoke-Migrate',
    'Invoke-Migration-0-to-1',
    'Should-ExcludePath',
    'Copy-RepoSnapshot',
    'Invoke-ConsolidateExecuteMove',
    'Invoke-ConsolidateRollbackMove',
    'Invoke-ConsolidateTransaction',
    'Invoke-ConsolidateMigrationWorkflow',
    'Test-ConsolidateArgs',
    'Test-ConsolidateRegistryDisk',
    'Test-ConsolidateEdgeCaseGuards'
)
```

### Still Active (Read-Only Discovery)
The following functions from Tasks 1-6 remain active because they are read-only:
- `Get-ScheduledTaskReferences` - detects scheduled tasks
- `Get-ShimReferences` - detects shims
- `Get-PathReferences` - detects PATH entries
- `Get-ProfileReferences` - detects profile references
- `Find-PathReferences` - scans repos for hardcoded paths
- `Build-AuditIndex` - assembles audit data (no disk writes except cache)

### Re-enabling Commands
To re-enable a command, remove it from the `$UNSAFE_COMMANDS` array. Test thoroughly before re-enabling.

### Why This Approach?
- **Low risk:** Read-only functions kept active for strap-chinvex integration work
- **High risk disabled:** All file move/write operations blocked
- **Easy to audit:** Single array lists all disabled commands
- **Easy to restore:** Remove from array to re-enable
