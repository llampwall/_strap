<!-- DO: Append new entries to current month. Rewrite Recent rollup. -->
<!-- DON'T: Edit or delete old entries. Don't log trivial changes. -->

# Decisions

## Recent (last 30 days)
- Added configure command for post-ingestion metadata updates (1b551bc)
- Added setup status tracking with health visibility (09af3e0)
- Enabled full chinvex ingestion during adopt/clone (16cac94)
- Implemented instant system-wide availability via auto-setup (f6c2f14)
- Migrated from single scope field to orthogonal metadata (8bdedf2)
- Completed shim system v3.1 rewrite with dual-file architecture (23d34f1)
- Upgraded to Pester 5 for test modernization (f5b7914)
- Moved commands to modules/Commands/ hierarchy (305e0ea)
- Completed chinvex integration (TDD-driven, 14 tasks) (bd509da)

## 2026-02

### 2026-02-05 — Configure command for post-ingestion metadata updates

- **Why:** Need ability to modify chinvex metadata (depth, status, tags) after initial clone/adopt without manual registry editing
- **Impact:** Added `strap configure` command with intelligent chinvex sync optimization - metadata-only changes use lightweight sync-metadata-from-strap; depth changes trigger full reingest with --rebuild-index flag
- **Evidence:** 1b551bc

### 2026-02-05 — Setup status tracking to registry

- **Why:** Enable health monitoring for dependency installation across all repos
- **Impact:** Registry entries now track setup success/failure/skip with timestamps and error messages; `strap list` shows HEALTH column
- **Evidence:** 09af3e0

### 2026-02-04 — Enable full ingestion during adopt/clone

- **Why:** Repos were only registered but not ingested, limiting chinvex usefulness
- **Impact:** Removed --register-only flag; adopt/clone now fully ingest repos into chinvex; adopted 12 repos with appropriate presets
- **Evidence:** 16cac94

### 2026-02-04 — Instant system-wide availability

- **Why:** Core value prop is "Git URL → instant global availability" but required manual setup step
- **Impact:** clone/adopt now auto-run setup (venv creation + dep install) then auto-discover shims; tools available immediately after clone
- **Evidence:** f6c2f14

### 2026-02-04 — Fixed auto-shim creation during clone

- **Symptom:** Shims couldn't be created during clone workflow because venv didn't exist yet
- **Root cause:** Auto-discovery required venv to exist; setup hadn't run yet
- **Fix:** Added AllowMissingVenv parameter to tolerate missing venv during discovery
- **Prevention:** Shims now created immediately; work after `strap setup` completes
- **Evidence:** 976f20e

### 2026-02-04 — Registry V2→V3 metadata migration

- **Why:** Single "scope" field conflated multiple orthogonal concerns (ingestion depth, lifecycle state, grouping tags)
- **Impact:** Replaced scope with chinvex_depth/status/tags; flattened directory structure (all repos in P:\software); automatic migration on registry load
- **Evidence:** 8bdedf2

### 2026-02-04 — Fixed registry version mismatch

- **Symptom:** Registry version 3 triggers "requires newer strap (supports v1)" error
- **Root cause:** LATEST_REGISTRY_VERSION was hardcoded to 1 instead of 3; empty array check broken
- **Fix:** Updated constant to 3; fixed PSObject.Properties check for empty repos array
- **Prevention:** Version constant must match schema changes
- **Evidence:** 6c7d375

### 2026-02-04 — Reorganized project structure

- **Why:** Root directory cluttered with test files, utility scripts, and template files
- **Impact:** Moved context-hook to templates/, tests to tests/, utilities to scripts/, docs to docs/; root now contains only essential files
- **Evidence:** 84de919

### 2026-02-03 — Shim system v3.1 complete rewrite

- **Why:** Old shim system was fragile; dual-file pattern needed for cross-shell compatibility
- **Impact:** Full rewrite with .ps1 + .cmd wrapper, three shim types (simple/venv/node), JSON array + tokenizer parsing, registry v2 metadata, auto-discovery for Python/Node
- **Evidence:** 23d34f1, f7e2b36, 5409dc0, b25b650, 787594a, 7be5cbb, 3a98c15, 06631c0, 8ad3067, 2fdaec4, 257e430

### 2026-02-03 — Upgrade to Pester 5

- **Why:** Pester 3.x is legacy; Pester 5 is current standard with better syntax and features
- **Impact:** Updated 338 assertions across 22 test files; modernized 14 test runner scripts; updated assertion syntax (Should -Be), mocking (Should -Invoke), and runner (configuration objects)
- **Evidence:** f5b7914

### 2026-02-03 — Command hierarchy reorganization

- **Why:** Commands scattered in commands/ folder with abstraction layer (Commands.ps1 loader) that added no value
- **Impact:** Moved 12 command files to modules/Commands/; replaced loader with direct sourcing via Get-ChildItem; deleted Commands.ps1 and empty commands/ directory
- **Evidence:** 305e0eae

### 2026-02-03 — Completed chinvex integration (14 tasks)

- **Why:** Enable automatic code intelligence for all managed repos via single source of truth
- **Impact:** TDD implementation of 14 tasks: config schema extension, CLI wrappers, helper functions, command integration (clone/adopt/move/rename/uninstall/contexts/sync-chinvex), validation, documentation
- **Evidence:** bd509da, e80417d, 0a08cc5, 2773658, 3438c4d, 9a04584, 7061efa, 4ed8ba6, 0fec118, 82a26e9, cf54a74, 0611f44, 2893dae, 607c5d6, 474eaf6, 546748d, c1470b6

### 2026-02-02 — Kill switch for unsafe consolidate functions

- **Why:** Environment corruption incident highlighted safety risks in consolidate/audit/snapshot/migrate/archive commands
- **Impact:** Disabled 13 functions via $UNSAFE_COMMANDS array and Assert-CommandSafe guard; kept read-only discovery functions active; documented incident in docs/incidents/
- **Evidence:** 9a9ffd5

### 2026-02-02 — Fixed parsing errors and bugs

- **Symptom:** Unicode characters, problematic hashtable keys, duplicate function definitions, single-element array unwrapping
- **Root cause:** Copy-paste from Windows terminal mangled UTF-8; PowerShell unwraps single-element arrays
- **Fix:** Replaced Unicode with ASCII ([OK]/[X]/[!]); removed <REPO_NAME> tokens; deduplicated Config.ps1; used comma operator for array safety
- **Prevention:** Always use ASCII in output; protect arrays with comma operator
- **Evidence:** a3446aa
