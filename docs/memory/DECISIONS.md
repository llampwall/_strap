<!-- DO: Append new entries to current month. Rewrite Recent rollup. -->
<!-- DON'T: Edit or delete old entries. Don't log trivial changes. -->

# Decisions

## Recent (last 30 days)
- Documented fnm integration, corepack fixes, and upgrade commands in README (f05650b)
- Fixed corepack permission errors with smart detection and fnm environment isolation (424de1f)
- Added upgrade-node and upgrade-python commands for easy version management (55ab13e, 11a0a10)
- Implemented --all flag for batch upgrades of all projects of a type (c1858a6)
- Added doctor health checks (NODE004, PY004) with version outdated warnings (11189fe)
- Fixed critical PowerShell parameter binding bug in upgrade-node (4892ef0)
- Implemented fnm integration for Node version management (bdf4442)
- Implemented automatic Python version detection, download, and installation (a910b75)
- Vendored PM2 and created system-wide shim to ensure availability (50fda24)
- Added configure command for post-ingestion metadata updates (1b551bc)

## 2026-02

### 2026-02-14 — Comprehensive README documentation update

- **Why:** Recent features (fnm integration, upgrade commands, corepack fixes) lacked documentation; users needed clear guidance on version management workflows
- **Impact:** Added Node Version Management section (mirroring Python docs); documented upgrade-node/upgrade-python commands with all flags (--latest/--version/--list-only/--all); documented doctor targeted checks (--system/--shims/--node/--python) and installer flags (--install-fnm/--install-pyenv); clarified corepack smart detection (auto-enabled when packageManager field present); documented registry schema node_version field; updated setup flags (--enable-corepack/--no-corepack); 187 lines added to README
- **Evidence:** f05650b
- **Key Design:** Documentation follows same structure as Python section for consistency; examples show complete workflows

### 2026-02-14 — Fixed corepack permission errors with fnm/nvm conflicts

- **Symptom:** `corepack enable` failing with permission denied when writing to nvm directory (C:\Users\...\nvm\v22.15.1\)
- **Root cause:** strap uses fnm per-project; users may have nvm globally; corepack running in global environment tried writing to nvm directory
- **Fix:** (1) Smart detection - only enable corepack when package.json has packageManager field OR --enable-corepack explicitly passed; (2) Resolve corepack.cmd from fnm Node directory; (3) Environment isolation - prepend fnm Node directory to PATH for all setup commands (npm/pnpm/yarn/corepack)
- **Prevention:** Always use fnm-managed Node for version-specific operations; avoid global environment when version management tools present; validate corepack need before enabling
- **Evidence:** 424de1f; tested with fnm/nvm conflict scenario; added Setup.NodeCorepack.Tests.ps1 with packageManager detection and environment isolation tests; documented in FNM_INTEGRATION.md Corepack Integration section

### 2026-02-12 — Doctor version outdated warnings (NODE004, PY004)

- **Why:** Need visibility into which projects are running outdated versions to encourage timely upgrades
- **Impact:** Added NODE004 check in Invoke-DoctorNodeChecks; created Invoke-DoctorPythonChecks with PY001-004 checks (version file, consistency, installation, currency); added --python flag to doctor; severity "info" (informational, not error); suggests specific upgrade command per project
- **Evidence:** 11189fe; tested on 5 Node projects (20.19.0 < 25.6.1) and 8 Python projects (3.10.0-3.12.10 < 3.14.2)
- **Key Design:** Detects major and minor version differences (not just patch); Format functions updated to handle "info" severity; checks run only if pyenv/fnm installed

### 2026-02-12 — Batch upgrade with --all flag

- **Why:** Need efficient way to upgrade all projects of a type at once instead of individual upgrades
- **Impact:** Added --all parameter to Invoke-UpgradeNode and Invoke-UpgradePython; batch processes all projects in registry filtered by stack type; forces non-interactive mode; shows individual upgrade info and summary with success/failure counts; graceful error handling for missing version files
- **Evidence:** c1858a6; tested upgrade-node --all (5 projects, all succeeded) and upgrade-python --all (10 projects, 8 succeeded, 2 failed with clear errors)
- **Key Design:** Recursive function calls for each project; results tracked in array; summary displays succeeded/failed counts with error details

### 2026-02-12 — upgrade-python command for Python version management

- **Why:** Need parity with upgrade-node for Python projects; manual Python version upgrades tedious
- **Impact:** Created modules/Commands/upgrade-python.ps1 (267 lines) mirroring upgrade-node; auto-detects current version from .python-version; fetches available versions from pyenv; interactive or flag-based selection (--latest, --version, --list-only); updates .python-version, installs via pyenv, runs setup, regenerates shims
- **Evidence:** 11a0a10; tested with yt-dlp (3.10.0 → 3.14.2 available)
- **Key Design:** Uses PyenvIntegration module functions; script block isolation for parameter binding safety; follows same UX as upgrade-node

### 2026-02-12 — Fixed PowerShell parameter binding error in upgrade-node

- **Symptom:** "Cannot convert '21.0.0' to SwitchParameter" error when displaying available upgrades
- **Root cause:** PowerShell's parameter binder trying to bind version strings to function's switch parameters ($Latest, $ListOnly, $NonInteractive) when accessing $group.Group property in foreach loop
- **Fix:** Wrapped foreach loop in script block (`& { }`) to isolate from parameter binding; replaced `exit 0` with `return` for proper function exit (3 occurrences); added pipeline output suppression (`$null =`) in strap.ps1 handler; improved Group-Object/Sort-Object with defensive checks; used negative array indexing ($items[-1]) instead of Select-Object
- **Prevention:** Wrap loops that access pipeline properties in script blocks to create new binding scope; use `return` not `exit` within functions; suppress pipeline output at call site
- **Evidence:** 4892ef0

### 2026-02-12 — upgrade-node command for Node version management

- **Why:** Need easy way to upgrade Node versions across projects without manual .nvmrc edits and fnm commands
- **Impact:** Created modules/Commands/upgrade-node.ps1 (267 lines); auto-detects current version from .nvmrc/.node-version/package.json engines; fetches available versions from fnm; displays grouped by major.minor with latest patch; interactive or automated upgrade (--latest, --version, --list-only flags); updates version file, installs via fnm, runs setup, regenerates shims; added doctor --node checks (NODE001-003) for version file existence, consistency, installation
- **Evidence:** 55ab13e; tested on allmind (20.19.0 → 25.6.1 available); 15 doctor checks across 5 Node projects (all passing)
- **Key Design:** Mirrors Python/pyenv-win pattern; non-interactive mode via --latest; dry-run mode with --list-only; comprehensive validation and error handling

### 2026-02-12 — fnm integration for Node version management

- **Why:** Node projects lacked automatic version management, requiring manual Node installation and creating version conflicts; needed parity with Python/pyenv-win integration
- **Impact:** Created FnmIntegration.ps1 module (11 functions mirroring PyenvIntegration.ps1); auto-detects Node versions from .nvmrc/.node-version/package.json engines field; auto-installs via fnm during setup; stores node_version in registry; shims use version-specific Node executables; includes build step detection (automatic build/prepare); vendored fnm to P:\software\_node-tools\fnm; system-wide shim at P:\software\bin\fnm.{ps1,cmd}; comprehensive test suite (19 Pester 5 tests); documentation (docs/FNM_INTEGRATION.md); migration script (scripts/migrate-node-to-fnm.ps1); migrated all 5 Node projects
- **Evidence:** bdf4442; binary installation (faster than git clone); shim regeneration bugfix (re-resolves exe instead of stale registry value); corepack command fix (removed Python-style -m flag); doctor checks SYS003/004; happy-cli case study validated end-to-end workflow
- **Key Design:** Follows pyenv-win pattern exactly (vendored binary, version detection priority, auto-install, registry tracking, shim resolution); improvements include faster installation, build step automation, regeneration fix

### 2026-02-08 — pyenv-win integration for Python version management

- **Why:** Zero manual Python management needed - eliminate manual version installation and conda dependency
- **Impact:** Vendored pyenv-win to P:\software\_python-tools\pyenv-win; created PyenvIntegration.ps1 module with 11 functions; Python versions auto-detected from .python-version/pyproject.toml/requirements.txt with major.minor → latest patch resolution; validation after install; integrated with doctor/adopt/clone/setup; stores python_version in registry; conservative pip default
- **Evidence:** a910b75; complete rewrite after initial implementation failed; pyenv-win ignores PYENV_ROOT (hardcoded in VBScript); system-wide shim at P:\software\bin\pyenv.{ps1,cmd}
- **Key Fixes:** Dynamic version lookup via pyenv install --list; post-install validation; robust command execution via pwsh -NoProfile -Command; shim path duplication fix; exit code -1073741515 (DLL not found) resolved by using correct pyenv-win directory structure

### 2026-02-05 — Vendor PM2 and create system-wide shim

- **Why:** Need PM2 available system-wide without depending on global package manager installations
- **Impact:** Vendored PM2 6.0.14 to P:\software\_node-tools\pm2; created shim at P:\software\bin\pm2.cmd registered to _strap repo; removed dependency on pnpm global PM2
- **Evidence:** 50fda24

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
