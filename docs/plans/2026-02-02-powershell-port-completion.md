# PowerShell Port Completion Plan

**Date**: 2026-02-02
**Status**: Planning
**Goal**: Complete pure PowerShell port of TypeScript dev-environment-consolidation functionality

## Verification Summary

TypeScript tests: **75/75 passing** ✅
PowerShell implementation: **~40% complete** ⚠️

### What IS Implemented

- `strap consolidate` command with 6-step workflow
- Basic git repo discovery
- PM2 process checking
- Transaction with rollback capability
- Doctor verification integration

### What is MISSING

**Missing Commands** (not wired to CLI):
- `strap snapshot` - TypeScript exists, PowerShell missing
- `strap audit` - TypeScript exists, PowerShell missing
- `strap archive` - TypeScript exists, PowerShell missing

**Missing Enhanced Flags**:
- `strap adopt --scan` - bulk discovery mode not implemented
- `strap doctor --fix-paths` - only error messages exist, no functionality
- `strap doctor --fix-orphans` - not implemented

**Incomplete External Reference Detection**:
- Scheduled tasks: flag exists but no scanning
- Shims: not checked at all
- PATH entries: not checked
- Shell profiles: not checked

**Incomplete Audit**:
- Current: Only checks PM2 processes
- Missing: Path dependency scanning, audit index building, caching

**Incomplete Snapshot**:
- Current: Simple metadata JSON
- Missing: Comprehensive manifest with git metadata and external refs

## Port Strategy

**Critical**: Pure PowerShell implementation with ZERO TypeScript/Node.js dependencies

- TypeScript code serves as **reference specification**
- All algorithms must be **rewritten in PowerShell**
- No `node dist/commands/...` calls
- End result: strap.ps1 is fully self-contained

## Task Breakdown

### Phase 1: Missing Commands (3 tasks)

#### Task #17: Port snapshot logic to PowerShell
**Reference**: `src/commands/snapshot/*.ts`

Port to PowerShell:
- `parseSnapshotArgs()` - parse `--output`, `--scan` flags
- `scanDirectoriesTopLevel()` - scan dirs and classify as file/directory
- `discoverGitRepos()` - find .git folders, extract remotes/branches/commits
- `buildSnapshotManifest()` - combine all data into JSON structure

Create `Invoke-Snapshot` function in strap.ps1:
```powershell
function Invoke-Snapshot {
  param(
    [string] $OutputPath,
    [string[]] $ScanDirs,
    [string] $StrapRootPath
  )
  # Parse args, scan directories, discover repos, build manifest
  # Write JSON to $OutputPath
}
```

Add command dispatch:
```powershell
if ($RepoName -eq "snapshot") {
  # Parse --output and --scan from $ExtraArgs
  Invoke-Snapshot -OutputPath $output -ScanDirs $scans -StrapRootPath $TemplateRoot
  exit 0
}
```

#### Task #18: Port audit logic to PowerShell
**Reference**: `src/commands/audit/*.ts`

Port to PowerShell:
- `parseAuditArgs()` - parse target name, `--all`, `--json`, `--rebuild-index`
- `loadOrBuildAuditIndex()` - build/cache audit index at `build/audit-index.json`
- `scanRepo()` - search repo files for hardcoded path references

Index structure:
```json
{
  "built_at": "2026-02-02T10:00:00.000Z",
  "registry_updated_at": "2026-02-01T15:30:00.000Z",
  "repo_count": 12,
  "repos": {
    "C:\\Code\\chinvex": {
      "references": ["C:\\Code\\chinvex\\scripts\\build.ps1:42"]
    }
  }
}
```

Optimization: Use `last_commit` field from registry V2 to skip unchanged repos

Create `Invoke-Audit` function and add command dispatch.

#### Task #19: Port archive logic to PowerShell
**Reference**: `src/commands/archive/*.ts`

Port to PowerShell:
- `planArchiveMove()` - validate entry exists, path exists, destination free
- Trust mode validation (registry-first only)
- Archive move execution with registry update

Registry updates:
- Set `scope = "archive"`
- Set `archived_at = ISO8601 timestamp`
- Move folder to archive root

Create `Invoke-Archive` function and add command dispatch.

### Phase 2: Enhanced Flags (3 tasks)

#### Task #20: Port adopt --scan bulk mode to PowerShell
**Reference**: `src/commands/adopt/*.ts`

Port to PowerShell:
- `parseAdoptArgs()` - parse `--scan`, `--recursive`, `--scope`, `--allow-auto-archive`
- `scanAdoptTopLevel()` - scan directory for git repos, dirs, files
- Classification logic - determine if git/directory/file
- Check against registry to mark `alreadyRegistered` items

Modify existing `Invoke-Adopt` to support both modes:
- Single path mode (current)
- Scan mode (new) - batch adoption with scope suggestions

Support `--yes` for non-interactive batch adoption.

#### Task #21: Port doctor --fix-paths to PowerShell
**Reference**: `src/commands/doctor/fixPaths.ts`

Port to PowerShell:
- Disk discovery scan for git repos
- Git remote URL extraction and normalization
- Match registry entries (with invalid paths) to discovered repos by remote
- Single match: auto-update in `--yes`, prompt otherwise
- Multiple matches: require user selection, never auto-update

Add to existing `Invoke-Doctor`:
```powershell
function Invoke-Doctor {
  param(
    [string] $StrapRootPath,
    [switch] $OutputJson,
    [switch] $FixPaths  # NEW
  )

  if ($FixPaths) {
    # Run fix-paths logic
    # Discover repos, match by remote, update registry
  }

  # ... existing doctor logic
}
```

#### Task #22: Port doctor --fix-orphans to PowerShell
**Reference**: `src/commands/doctor/fixOrphans.ts`

Port to PowerShell:
- Scan registry for entries where path doesn't exist
- Present list of orphaned entries
- Prompt for confirmation (skip in `--yes`)
- Remove from registry, save

Add to existing `Invoke-Doctor` with `--fix-orphans` flag.

### Phase 3: External Reference Detection (3 tasks)

#### Task #23: Port scheduled task detection to PowerShell
**Reference**: `src/commands/snapshot/detectExternalRefs.ts:33-44`

Port to PowerShell:
```powershell
function Get-ScheduledTaskReferences {
  param([string[]] $RepoPaths)

  $csv = schtasks /query /fo csv
  $tasks = $csv | ConvertFrom-Csv | ForEach-Object {
    $pathMatch = "$($_.Execute) $($_.Arguments)" -match '[A-Za-z]:\\[^\s]+'
    if ($pathMatch) {
      @{ name = $_.TaskName; path = $Matches[0] }
    }
  } | Where-Object {
    $task = $_
    $RepoPaths | Where-Object { $task.path.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }
  }

  return $tasks
}
```

Integrate into `Invoke-ConsolidateMigrationWorkflow` preflight step (line 3455).

#### Task #24: Port shim detection to PowerShell
**Reference**: `src/commands/snapshot/detectExternalRefs.ts:46-60`

Port to PowerShell:
```powershell
function Get-ShimReferences {
  param(
    [string] $ShimDir,
    [string[]] $RepoPaths
  )

  $shims = Get-ChildItem -Path $ShimDir -Filter "*.cmd" | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    if ($content -match '[A-Za-z]:\\[^\r\n"]+') {
      $target = $Matches[0]
      $matchesRepo = $RepoPaths | Where-Object { $target.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }
      if ($matchesRepo) {
        @{ name = $_.BaseName; target = $target }
      }
    }
  }

  return $shims
}
```

Integrate into `Invoke-ConsolidateMigrationWorkflow` preflight step.

#### Task #25: Port PATH/profile scanning to PowerShell

Implement PATH scanning:
```powershell
function Get-PathReferences {
  param([string[]] $RepoPaths)

  $userPath = [Environment]::GetEnvironmentVariable("PATH", "User") -split ';'
  $systemPath = [Environment]::GetEnvironmentVariable("PATH", "Machine") -split ';'

  $allPaths = ($userPath + $systemPath) | ForEach-Object { $_.ToLower().TrimEnd('\') }

  $matches = $allPaths | Where-Object {
    $pathEntry = $_
    $RepoPaths | Where-Object { $pathEntry.StartsWith($_.ToLower()) }
  }

  return $matches | ForEach-Object { @{ type = "PATH"; path = $_ } }
}
```

Implement profile scanning:
```powershell
function Get-ProfileReferences {
  param([string[]] $RepoPaths)

  if (-not (Test-Path $PROFILE)) { return @() }

  $content = Get-Content $PROFILE -Raw
  $matches = [regex]::Matches($content, '[A-Za-z]:\\[^\s\r\n"'']+')

  return $matches | ForEach-Object {
    $path = $_.Value
    $matchesRepo = $RepoPaths | Where-Object { $path.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }
    if ($matchesRepo) {
      @{ type = "profile"; path = $path }
    }
  } | Where-Object { $_ }
}
```

Integrate both into consolidate preflight.

### Phase 4: Complete Audit (1 task)

#### Task #26: Port comprehensive audit index to PowerShell
**Reference**: `src/commands/audit/index.ts`

Replace basic PM2 check in consolidate with full audit index:

```powershell
function Build-AuditIndex {
  param(
    [string] $IndexPath,
    [bool] $RebuildIndex,
    [string] $RegistryUpdatedAt,
    [array] $Registry
  )

  # Check if existing index is fresh
  if ((Test-Path $IndexPath) -and -not $RebuildIndex) {
    $existing = Get-Content $IndexPath | ConvertFrom-Json
    if ($existing.registry_updated_at -eq $RegistryUpdatedAt -and
        $existing.repo_count -eq $Registry.Count) {
      return $existing
    }
  }

  # Build new index
  $repos = @{}
  foreach ($entry in $Registry) {
    # Skip if last_commit unchanged (optimization)
    # Scan repo files for path references
    $references = Find-PathReferences -RepoPath $entry.path
    $repos[$entry.path] = @{ references = $references }
  }

  $index = @{
    built_at = (Get-Date).ToUniversalTime().ToString("o")
    registry_updated_at = $RegistryUpdatedAt
    repo_count = $Registry.Count
    repos = $repos
  }

  $index | ConvertTo-Json -Depth 10 | Set-Content $IndexPath
  return $index
}

function Find-PathReferences {
  param([string] $RepoPath)

  $references = @()
  $files = Get-ChildItem -Path $RepoPath -Recurse -File -Include *.ps1,*.js,*.ts,*.json,*.yml,*.yaml,*.md,*.txt

  foreach ($file in $files) {
    $lineNum = 0
    Get-Content $file.FullName | ForEach-Object {
      $lineNum++
      if ($_ -match '[A-Za-z]:\\[^\s\r\n"'']+') {
        $references += "$($file.FullName):$lineNum"
      }
    }
  }

  return $references
}
```

Integrate into consolidate step 4.

### Phase 5: Polish (2 tasks)

#### Task #27: Enhance snapshot in consolidate workflow

Replace simple metadata JSON (lines 3356-3362) with comprehensive manifest:

```powershell
function Build-ConsolidateSnapshot {
  param(
    [string] $FromPath,
    [string] $ToPath,
    [array] $DiscoveredRepos,
    [object] $ExternalRefs,
    [array] $Registry,
    [hashtable] $Flags
  )

  $manifest = @{
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
    fromPath = $FromPath
    toPath = $ToPath
    flags = $Flags
    discovered = $DiscoveredRepos | ForEach-Object {
      @{
        name = $_.name
        path = $_.path
        remote = $_.remote
        branch = $_.branch
        commit = $_.commit
      }
    }
    external_refs = @{
      pm2 = $ExternalRefs.pm2
      scheduled_tasks = $ExternalRefs.scheduled_tasks
      shims = $ExternalRefs.shims
      path_entries = $ExternalRefs.path_entries
      profile_refs = $ExternalRefs.profile_refs
    }
    registry_snapshot = $Registry
  }

  return $manifest
}
```

Use in consolidate step 1.

#### Task #28: Update help text and README

Update `Show-Help` function (lines 137-186):
- Add `strap snapshot` usage line
- Add `strap audit` usage line
- Add `strap archive` usage line
- Update `strap adopt` to show `--scan`, `--recursive`, `--scope`, `--allow-auto-archive`
- Update `strap doctor` to show `--fix-paths`, `--fix-orphans`
- Update `strap consolidate` to show all flags

Verify README.md:
- Ensure no TypeScript/Node.js references
- Document pure PowerShell implementation
- Verify all command examples work

### Phase 6: Testing (1 task)

#### Task #29: Add PowerShell test coverage

Create `tests/powershell/` directory with Pester tests:

```powershell
# tests/powershell/Commands.Tests.ps1
Describe "strap commands" {
  It "snapshot command exists" {
    { strap snapshot --help } | Should -Not -Throw
  }

  It "audit command exists" {
    { strap audit --help } | Should -Not -Throw
  }

  It "archive command exists" {
    { strap archive --help } | Should -Not -Throw
  }

  It "adopt supports --scan flag" {
    # Test adopt --scan C:\Code --dry-run
  }

  It "doctor supports --fix-paths flag" {
    # Test doctor --fix-paths --dry-run
  }

  It "doctor supports --fix-orphans flag" {
    # Test doctor --fix-orphans --dry-run
  }
}

Describe "external reference detection" {
  It "detects scheduled tasks" {
    # Create test scheduled task
    # Run consolidate --dry-run
    # Verify warning appears
  }

  It "detects shims" {
    # Create test shim
    # Run consolidate --dry-run
    # Verify warning appears
  }
}

Describe "audit index" {
  It "builds and caches audit index" {
    # Run audit --all
    # Verify build/audit-index.json exists
    # Run again without --rebuild-index
    # Verify cached version used
  }
}
```

Add to CI pipeline alongside TypeScript tests.

## Implementation Order

1. **Phase 3** (Tasks #23-25) - Low-hanging fruit, integrates into existing consolidate
2. **Phase 4** (Task #26) - Complete audit functionality in consolidate
3. **Phase 5** (Task #27) - Enhance consolidate snapshot
4. **Phase 1** (Tasks #17-19) - New standalone commands
5. **Phase 2** (Tasks #20-22) - Enhanced flags for existing commands
6. **Phase 5** (Task #28) - Documentation updates
7. **Phase 6** (Task #29) - Test coverage

## Success Criteria

- [ ] All 13 tasks completed
- [ ] Zero TypeScript/Node.js dependencies
- [ ] All README commands are callable
- [ ] PowerShell tests pass
- [ ] TypeScript tests still pass (75/75)
- [ ] Help text matches implementation

## Dependencies

**None** - Pure PowerShell implementation requires only:
- PowerShell 7+ (`pwsh`)
- Git (for repository operations)
- Standard Windows tools (`schtasks`, environment variables)

## Rollout Strategy

1. Complete tasks in phases
2. Test each phase independently
3. Keep TypeScript code as reference (don't delete)
4. Update README progressively as features complete
5. Final validation: Clean Windows machine, run all documented commands

## Notes

- TypeScript tests (75 passing) validate business logic correctness
- Use TypeScript as **specification**, not **dependency**
- All algorithms must be rewritten in PowerShell idiomatically
- PowerShell has different patterns (pipelines, cmdlets) - don't port line-by-line
- Focus on maintainability - PowerShell should be clear and idiomatic
