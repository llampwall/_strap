# Strap Setup & Shim Reliability Test Gauntlet

**Goal:** Test 10 diverse repos to identify and fix all failure modes in setup and shim generation.

**Date Started:** 2026-02-16

---

## Test Matrix

| # | Repo URL | Stack | Test Focus | Expected Outcome | Actual Result | Status | Notes |
|---|----------|-------|------------|------------------|---------------|--------|-------|
| 1 | `https://github.com/astral-sh/ruff` | Python | pyproject.toml, modern packaging | Shim created for `ruff` | | ⏸️ | |
| 2 | TBD | Python | setup.py (legacy) | Shim auto-discovered from console_scripts | | ⏸️ | |
| 3 | `https://github.com/python-poetry/poetry` | Python | Poetry tool.poetry.scripts | Shim created for `poetry` | | ⏸️ | |
| 4 | TBD | Node | Single bin entry | Shim created for single CLI | | ⏸️ | |
| 5 | TBD | Node | Multiple bins | Multiple shims created | | ⏸️ | |
| 6 | TBD | Node | pnpm project | Correct PM detection, corepack if needed | | ⏸️ | |
| 7 | TBD | Python | Specific version requirement | Auto-detect & install correct Python version | | ⏸️ | |
| 8 | TBD | Node | Specific version requirement | Auto-detect & install correct Node version | | ⏸️ | |
| 9 | TBD | Python | Library only (no scripts) | Graceful handling, no shims | | ⏸️ | |
| 10 | TBD | Mixed | Complex monorepo | Multiple stacks handled correctly | | ⏸️ | |

**Status Key:**
- ⏸️ Not Started
- 🔄 In Progress
- ✅ Passed
- ❌ Failed
- ⚠️ Partial (some issues)

---

## Detailed Test Results

### Test 1: Ruff (Modern Python CLI)

**Command:**
```powershell
strap clone https://github.com/astral-sh/ruff
```

**Expected:**
- Auto-detect Python stack
- Detect Python version from pyproject.toml
- Create venv
- Install dependencies
- Auto-discover `ruff` shim from `[project.scripts]`
- Shim works: `ruff --version`

**Actual:**
```
[Paste output here]
```

**Issues Found:**
-

**Root Cause:**
-

**Fix Applied:**
-

---

### Test 2: [Repo Name]

**Command:**
```powershell

```

**Expected:**
-

**Actual:**
```

```

**Issues Found:**
-

---

## Summary of Fixes

| Issue | Affected Component | Fix | Commit |
|-------|-------------------|-----|--------|
| | | | |

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
