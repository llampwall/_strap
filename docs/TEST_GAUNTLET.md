# Strap Setup & Shim Reliability Test Gauntlet

**Goal:** Test 10 diverse repos to identify and fix all failure modes in setup and shim generation.

**Date Started:** 2026-02-16

---

## Test Matrix

| # | Repo URL | Stack | Test Focus | Expected Outcome | Actual Result | Status | Notes |
|---|----------|-------|------------|------------------|---------------|--------|-------|
| 1 | `https://github.com/sharkdp/bat` | Rust | Graceful failure handling | Detect Rust, handle missing cargo | Stack detected, setup failed gracefully, chinvex ingested | ✅ | Cargo not installed - expected behavior |
| 2 | `https://github.com/junegunn/fzf` | Go | Graceful failure, Docker detection | Detect Go, handle missing go toolchain | Stack detected, Docker noted, setup failed gracefully, chinvex ingested | ✅ | Go not installed - expected |
| 3 | `https://github.com/httpie/cli` | Python | setup.py only (no pyproject.toml) | Detect Python, install from setup.py | Stack NOT detected, manual setup worked | ❌ | BUG: setup.py not checked in stack detection |
| 4 | `https://github.com/pallets/click` | Python | pyproject.toml, library (no CLI) | Detect Python 3.10, install deps, no shims | Full success - version detected, venv created, deps installed, 0 shims (correct) | ✅ | First full success! |
| 5 | `https://github.com/antfu-collective/ni` | Node | Multiple bins, pnpm, version range | Detect Node, create 8 shims, install deps | 8 shims created ✓, setup failed (corepack/nvm), validation failed (no node_modules), uninstall broken | ⚠️ | 3 bugs found |
| 6 | `https://github.com/sindresorhus/trash-cli` | Node | Single bin, npm, no version spec | Detect Node, install deps, create shim | Full success - npm install worked, 1 shim created & validated, shim works | ✅ | Cosmetic: incorrect shim count in logs |
| 7 | `https://github.com/astral-sh/ruff` | Python+Rust | Multi-stack repo, old Python (3.7) | Detect stack, handle multi-stack | Clone detected Python only, setup detected both → error, hung installing Python 3.7 | ❌ | Multi-stack inconsistency + old Python install hang |
| 8 | `https://github.com/charmbracelet/glow` | Go | Markdown renderer CLI, graceful failure | Detect Go, handle missing go toolchain | Stack detected, Docker noted, setup failed gracefully, chinvex ingested | ✅ | Go not installed - expected behavior |
| 9 | `https://github.com/changesets/changesets` | Node | Monorepo with yarn packageManager | Detect Node, enable corepack, install deps | Setup failed - corepack permission error with nvm Node | ❌ | REGRESSION: Bug #4 still occurring despite fix 424de1f |
| 10 | `https://github.com/casey/just` | Rust | Command runner, graceful failure | Detect Rust, handle missing cargo | Stack detected, setup failed gracefully, chinvex ingested | ✅ | Cargo not installed - expected behavior |
| 11 | `https://github.com/ytdl-org/youtube-dl` | Python | setup.py only (legacy project) | Detect Python, install from setup.py | Stack NOT detected, clone hung after git clone, no setup ran | ❌ | Same bug as Test 3 - setup.py not checked. Clone also hung. |
| 12 | `https://github.com/vercel/serve` | Node | Static server, has packageManager field | Detect Node, install deps, create shims | 3 shims created ✓, setup failed (corepack/nvm), validation failed (no node_modules), uninstall broken | ⚠️ | Same 3 bugs as Test 5: corepack, validation, uninstall |
| 13 | `https://github.com/commitizen-tools/commitizen` | Python | CLI tool with pyproject.toml | Detect Python, create venv, install deps, create shims | Full success - venv created, deps installed, 2 shims created & validated | ✅ | Uninstall bug hit but setup/shims worked perfectly |
| 14 | `https://github.com/eslint/eslint` | Node | JavaScript linter | Detect Node, install deps, create shims | Stack detected (node), version detected (20.19.0), then hung before setup | ❌ | Clone hung after version detection - no setup, no shims |
| 15 | `https://github.com/psf/requests` | Python | HTTP library (no CLI) | Detect Python 3.10, install deps, no shims | Full success - pyenv Python used, venv created, deps installed, 0 shims (correct), uninstall clean | ✅ | Perfect! Similar to Test 4 (click) |
| 16 | `https://github.com/biomejs/biome` | Rust+Node | Multi-stack formatter/linter | Detect stack, handle multi-stack | Detected as Node (has both Cargo.toml + package.json), no Node version, hung before setup | ❌ | Multi-stack bug (#7) + clone hang (#9) |
| 17 | `https://github.com/encode/httpx` | Python | HTTP client library + CLI | Detect Python 3.9, install deps, create shims | Setup succeeded, Python 3.9 installed via pyenv, 1 shim created, validation failed, uninstall broken | ⚠️ | Setup worked but validation/shim count/uninstall bugs |

**Status Key:**
- ⏸️ Not Started
- 🔄 In Progress
- ✅ Passed
- ❌ Failed
- ⚠️ Partial (some issues)

---

## Detailed Test Results

### Test 1: bat (Rust CLI - Graceful Failure Test)

**Command:**
```powershell
strap clone https://github.com/sharkdp/bat -v
```

**Expected:**
- Auto-detect Rust stack (Cargo.toml)
- Attempt cargo build
- Gracefully handle missing cargo
- Register repo even if setup fails
- Chinvex ingestion succeeds

**Actual:**
```
✓ Cloning https://github.com/sharkdp/bat -> P:\software\bat
✓ Cloned to P:\software\bat
  [VERBOSE] Detecting stack type...
  [VERBOSE] Found Cargo.toml - Rust stack
  [VERBOSE] Stack detection complete: rust
✓ Synced to chinvex context: bat (depth=full, status=active)

✓ Running automatic setup for rust stack...
  [VERBOSE] Detected stack: rust

=== SETUP PLAN ===
Commands to execute:
  1. Build Rust project
     cargo build

ERROR: Command failed with exit code 1
Command: cargo build
Output: cargo: The term 'cargo' is not recognized...

WARNING: Setup failed: Setup failed
  [VERBOSE] Setup error: Setup failed
  [VERBOSE] Running auto-discovery for shims...
  [VERBOSE] Auto-discovery found 0 shim(s)
✓ Added to registry
```

**Issues Found:**
- None - this is expected behavior (cargo not installed)

**Root Cause:**
- N/A - test validates graceful failure handling

**Fix Applied:**
- N/A - working as designed

**Observations:**
- ✅ Rust stack detection works
- ✅ Chinvex ingestion successful (depth=full, status=active)
- ✅ Setup failure handled gracefully
- ✅ Repo still registered despite setup failure
- ✅ Clear error messages
- ✅ Verbose logging shows all steps
- ✅ Uninstall worked cleanly (tested separately)

---

### Test 2: fzf (Go CLI - Docker Detection)

**Command:**
```powershell
strap clone https://github.com/junegunn/fzf -v
```

**Expected:**
- Auto-detect Go stack (go.mod)
- Detect Docker files
- Attempt go mod download
- Gracefully handle missing go toolchain
- Chinvex ingestion succeeds

**Actual:**
```
✓ Cloned to P:\software\fzf
  [VERBOSE] Found go.mod - Go stack
✓ Synced to chinvex context: fzf (depth=full, status=active)

✓ Detected stack: go
  (Docker also detected; not auto-running)

=== SETUP PLAN ===
Commands to execute:
  1. Download Go modules
     go mod download

ERROR: Command failed with exit code 1
Command: go mod download
Output: go: The term 'go' is not recognized...

WARNING: Setup failed: Setup failed
✓ Added to registry
```

**Issues Found:**
- None - expected behavior (go not installed)

**Observations:**
- ✅ Go stack detection works
- ✅ Docker detection works (noted but not auto-run)
- ✅ Chinvex ingestion successful (depth=full, status=active)
- ✅ Setup failure handled gracefully
- ✅ Repo still registered
- ✅ Clear error messages
- ✅ Uninstall worked cleanly

---

## Summary of Fixes

| Issue | Affected Component | Fix | Commit |
|-------|-------------------|-----|--------|
| Stack detection doesn't check for setup.py | clone.ps1, Setup.ps1 | Add setup.py to Python stack markers | Pending |
| Setup plan doesn't install from setup.py | Setup.ps1 | Add setup.py check in dependency installation | Pending |
| Node version range (>=20) not resolved to specific version | FnmIntegration.ps1 | Resolve ranges to latest compatible fnm version | Pending |
| Corepack still uses nvm Node instead of fnm | Setup.ps1 | Ensure fnm Node used even when no specific version detected | REGRESSION: Still failing in Test 9 despite fix 424de1f |
| Uninstall fails with IsPathRooted error | Validation.ps1 | Add null check before IsPathRooted call | Pending |
| Shim auto-discovery reports incorrect count | clone.ps1 or Shim.ps1 | Fix shim counting logic in logs | Pending (cosmetic) |
| Multi-stack repos handled inconsistently | clone.ps1, Setup.ps1 | Clone uses if/elseif (first match), setup detects all then errors | Pending |
| Python 3.7 installation hangs/times out | PyenvIntegration.ps1 | Add timeout or better error handling for old Python versions | Pending |
| Clone command hangs after version detection | clone.ps1 | Investigate why clone hangs after git clone + chinvex sync + version detection | Pending - seen in Tests 11, 14 |

---

## Lessons Learned

-

---

## Next Steps

- [ ] Complete all 10 tests
- [ ] Document all failure patterns
- [ ] Implement fixes
- [ ] Re-run failed tests
- [ ] Update memory files with new constraints/decisions
