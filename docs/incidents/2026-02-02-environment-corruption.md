# Incident Report: Environment Corruption During Strap Development

**Date:** 2026-02-02
**Duration:** ~5 hours
**Severity:** Critical - Multiple system components broken
**Root Cause:** Subagent processes consumed 45GB RAM, required force-kill, resulting in environment corruption

## Executive Summary

While developing strap's snapshot and audit functionality (Tasks 11-14 of the PowerShell port), Claude Code subagents spiraled out of control, consuming 45GB of RAM. Force-killing these processes corrupted multiple environment variables, PowerShell profiles, and system configurations. The irony: strap was being built to protect against exactly this kind of environment corruption.

---

## Timeline of Events

### Phase 1: Initial Corruption
- Working on strap PowerShell TDD tasks (batch3-tasks13-14)
- Subagents spawned for parallel work
- RAM usage spiked to 45GB
- User force-killed processes to recover system
- Corruption occurred during ungraceful termination

### Phase 2: Discovery
User noticed multiple issues:
1. PowerShell 5 terminals hanging (non-interactive)
2. PowerShell 7 (pwsh) terminals hanging
3. Wezterm not displaying (visible in task manager but no window)
4. Telegram not displaying (same symptom)
5. Claude Desktop showing blank window
6. Claude Code and Codex not recognized as commands, delaying immediate diagnosis
7. No global commands recognized

---

## Issues Identified and Resolutions

### Issue 1: PowerShell Environment Variables Corrupted

**Symptom:**
- full `PATH` environment variable completely DELETED
- `$env:PATH` displayed as `:PATH`
- `$env:TEMP` displayed as `:TEMP`
- Variable names being interpreted as `extglob.Name` instead of `$_.Name`

**Diagnosis:**
- opened windows environment variables -> PATH is empty
```powershell
# This command showed corruption:
$env:PATH  # Returned ":PATH" instead of actual path
```

**Resolution:**
- Extremeley lucky a PATH backup had been made earlier
- Restart PowerShell session to reload environment from registry
- Registry values were intact; only session-level environment was corrupted

**Strap Requirement:** Capture and restore process-level environment variables

---

### Issue 2: PATH Exceeded 2047 Character Limit

**Symptom:**
- PATH backup file contained duplicate entries
- Total length exceeded Windows PATH limit
- Had to manually remove paths to get under limit

**Diagnosis:**
```powershell
[Environment]::GetEnvironmentVariable('PATH', 'User').Length  # Was over 2047
```

**Resolution:**
- User manually deduplicated PATH entries
- Removed redundant paths until under 2047 characters

**Backup locations:**
- `C:\Users\Jordan\path-backup.txt` - Original PATH (with duplicates)
- `C:\Users\Jordan\env-backup-power.txt` - PS5 environment snapshot
- `C:\Users\Jordan\env-backup-pwsh.txt` - PS7 environment snapshot

**Strap Requirement:** PATH deduplication, length validation, atomic backup/restore

---

### Issue 3: Conda Completely Broken

**Symptom:**
- `conda --version` hung indefinitely
- `python -m conda` hung indefinitely
- Even `conda.exe` called directly hung

**Diagnosis Steps:**
1. Tested `conda --version` - hung
2. Tested Python import: `import conda.cli.main; print(conda.__version__)` - worked (returned 25.9.1)
3. Tested CLI: `python -m conda --version` - hung
4. Created debug script with print statements - hung after "Calling main"
5. Checked for conda plugins - found telemetry/TOS plugins
6. Disabled plugins by renaming - still hung
7. Removed `.conda` directory temporarily - still hung
8. Found `__editable__.chinvex-0.1.0.pth` pointing to non-existent `C:\Code\chinvex\src`

**Root Cause:**
The chinvex `.pth` file was trying to load from `C:\Code\chinvex\src` which no longer existed. This was causing Python site-packages initialization to fail/hang during conda startup.

**However:** Even after removing the `.pth` file, conda still hung. The corruption was deeper.

**Resolution:**
1. Kill all conda/Python processes
2. Delete entire `C:\ProgramData\miniconda3` directory
3. Download fresh Miniconda installer
4. Reinstall Miniconda silently:
   ```powershell
   Start-Process -FilePath 'Miniconda3-latest.exe' -ArgumentList '/S', '/AddToPath=0', '/RegisterPython=0', '/D=C:\ProgramData\miniconda3' -Wait
   ```
5. Verify: `conda --version` returned `conda 25.11.1`

**User's existing environments were preserved** at `C:\Users\Jordan\.conda\envs\` (dlc310, visomaster)

**Strap Requirement:**
- Conda installation state capture
- Environment list backup
- Conda config backup (`.condarc`, `.conda/`)
- Ability to reinstall and restore environments

---

### Issue 4: PowerShell Profiles Not Loading / Conda Init Hanging

**Symptom:**
- Opening PowerShell 5 caused terminal to hang
- Conda init block in profile.ps1 was the culprit

**Original profile.ps1 content:**
```powershell
#region conda initialize
If (Test-Path "C:\ProgramData\miniconda3\Scripts\conda.exe") {
    (& "C:\ProgramData\miniconda3\Scripts\conda.exe" "shell.powershell" "hook") | Out-String | ?{$_} | Invoke-Expression
}
#endregion
```

**Diagnosis:**
- Commented out conda init - terminal worked
- Uncommented - terminal hung
- Tried adding `[Environment]::UserInteractive` guard - still hung
- Issue was conda itself was broken (see Issue 3)

**Resolution:**
1. Comment out conda init temporarily
2. Fix conda (Issue 3)
3. Restore conda init after conda fixed
4. Run `conda init powershell` to regenerate hooks

**Profile locations:**
- PS5: `C:\Users\Jordan\Documents\WindowsPowerShell\profile.ps1`
- PS5: `C:\Users\Jordan\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`
- PS7: `C:\Users\Jordan\Documents\PowerShell\profile.ps1`
- PS7: `C:\Users\Jordan\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`

**Strap Requirement:** Profile backup with validation that profiles load correctly

---

### Issue 5: Chinvex Directory Deleted

**Symptom:**
- `C:\Code\chinvex` was completely empty
- User discovered this when trying to manually move repos

**Root Cause:** Unknown - possibly related to subagent corruption or cleanup gone wrong

**Resolution:**
1. Clone from GitHub to new location:
   ```powershell
   # User did this manually to P:\software\chinvex
   ```
2. Create venv:
   ```powershell
   py -3.12 -m venv .venv
   ```
3. Install editable:
   ```powershell
   .\.venv\Scripts\pip.exe install -e .
   ```
4. Run bootstrap:
   ```powershell
   chinvex bootstrap install --ntfy-topic dual-nature
   ```
5. Update ecosystem.config.js to use venv Python:
   ```javascript
   script: "P:\\software\\chinvex\\.venv\\Scripts\\pythonw.exe"
   ```
6. Start pm2:
   ```powershell
   pm2 start ecosystem.config.js
   pm2 save
   ```

**Strap Requirement:** Git remote tracking, ability to re-clone and restore project state

---

### Issue 6: Wezterm Not Displaying

**Symptom:**
- Wezterm visible in Task Manager
- No window appeared on screen
- Shift+right-click on taskbar caused explorer.exe to reload

**Diagnosis:**
- Checked for display-related env vars - none found
- Suspected window position saved to non-existent monitor

**Resolution:**
- Issue persisted through initial troubleshooting
- Eventually resolved after environment fixes
- Wezterm started working after conda/PATH fixes

**Strap Requirement:** Terminal emulator config backup (`.wezterm.lua`)

---

### Issue 7: Wezterm Launching pwsh with -NoProfile

**Symptom:**
- `dual` command not found in wezterm
- `dual` worked in regular PowerShell 5
- Profile existed and was correct

**Diagnosis:**
```powershell
# In wezterm:
$PROFILE  # Showed correct path
. $PROFILE  # Loaded profile, dual worked after
```

**Root Cause:**
`.wezterm.lua` line 10:
```lua
config.default_prog = { 'pwsh.exe', '-NoLogo', '-NoProfile' }
```

**Resolution:**
```lua
config.default_prog = { 'pwsh.exe', '-NoLogo' }  -- Removed -NoProfile
```

**Strap Requirement:** Terminal config validation and backup

---

### Issue 8: Telegram Not Displaying

**Symptom:** Same as wezterm - visible in Task Manager but no window

**Resolution:**
- Shift+right-click on taskbar icon
- Select "Maximize" or "Move"
- Use arrow keys to bring window back on screen

**Root Cause:** Window position saved for a monitor that no longer exists or display config changed

**Strap Requirement:** This is outside strap's scope (application window state)

---

### Issue 9: Claude Desktop Blank Window

**Symptom:**
- Claude Desktop opened to blank white window
- App visible in Task Manager
- No content loaded

**Diagnosis:**
Checked MCP server logs:
```
C:\Python313\python.exe: Error while finding module specification for 'chinvex_mcp.server' (ModuleNotFoundError: No module named 'chinvex_mcp')
```

**Root Cause:**
`claude_desktop_config.json` was configured to use system Python which didn't have chinvex_mcp:
```json
{
  "mcpServers": {
    "chinvex": {
      "command": "C:\\Python313\\python.exe",  // WRONG
      ...
    }
  }
}
```

**Resolution:**
```json
{
  "mcpServers": {
    "chinvex": {
      "command": "P:\\software\\chinvex\\.venv\\Scripts\\python.exe",  // CORRECT
      ...
    }
  }
}
```

**Strap Requirement:**
- Claude Desktop config backup
- MCP server configuration tracking
- Validation that MCP Python paths are valid

---

### Issue 10: pm2 Python Window Popping Up

**Symptom:**
- A `python.exe` command window kept appearing
- Closing it caused it to reappear

**Root Cause:**
`ecosystem.config.js` was using `python.exe` instead of `pythonw.exe`:
```javascript
script: "python.exe"  // Shows console window
```

**Resolution:**
```javascript
script: "P:\\software\\chinvex\\.venv\\Scripts\\pythonw.exe",  // No console window
windowsHide: true
```

**Strap Requirement:** pm2 ecosystem config backup and validation

---

### Issue 11: `dual` Function Not in PS5 Profile

**Symptom:**
- `dual` command worked in PS7 but not PS5

**Root Cause:**
- Bootstrap only updated PS7 profile
- PS5 profile didn't have the dual function

**Resolution:**
Added dual function to `Microsoft.PowerShell_profile.ps1` for both PS5 and PS7.

**Strap Requirement:** Track which profile files contain which functions

---

### Issue 12: Claude Code `.claude/config.json` Missing

**Symptom:**
- User mentioned `.claude/config.json` was missing

**Diagnosis:**
- Found `.claude.json` in home directory (wrong location)
- Found `.claude.json.backup` from Jan 26 (pre-corruption)
- Found timestamped backups from 6:22 AM (post-corruption)

**Resolution:**
```powershell
Copy-Item 'C:\Users\Jordan\.claude.json.backup' 'C:\Users\Jordan\.claude\config.json'
```

**Strap Requirement:** Claude Code config backup and restore

---

## Files Modified During Recovery

### PowerShell Profiles
- `C:\Users\Jordan\Documents\WindowsPowerShell\profile.ps1` - Conda init (commented/uncommented)
- `C:\Users\Jordan\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` - Added dual function
- `C:\Users\Jordan\Documents\PowerShell\profile.ps1` - Conda init + dual function
- `C:\Users\Jordan\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` - Already had dual function

### Configuration Files
- `C:\Users\Jordan\.wezterm.lua` - Removed `-NoProfile` flag
- `C:\Users\Jordan\AppData\Roaming\Claude\claude_desktop_config.json` - Fixed Python path
- `P:\software\chinvex\ecosystem.config.js` - Fixed Python path, added windowsHide

### Environment
- User PATH - Deduplicated, added `P:\software\chinvex\.venv\Scripts`
- System miniconda3 - Complete reinstall

---

## User Backups That Saved Us

1. `C:\Users\Jordan\path-backup.txt` - Original PATH (pre-corruption)
2. `C:\Users\Jordan\env-backup-power.txt` - PS5 environment snapshot
3. `C:\Users\Jordan\env-backup-pwsh.txt` - PS7 environment snapshot
4. `P:\documents\WindowsPowerShell\` - PS5 profile backups
5. `P:\documents\Powershell\` - PS7 profile backups
6. `C:\Users\Jordan\.claude.json.backup` - Claude config from Jan 26
7. GitHub - chinvex source code

---

## What Strap Needs to Capture for Full Environment Integrity

### Environment Variables
- [ ] User PATH (with deduplication)
- [ ] System PATH
- [ ] CONDA_* variables
- [ ] CHINVEX_* variables
- [ ] Custom env vars (CODEX_HOME, etc.)

### PowerShell Profiles
- [ ] All profile paths for PS5 and PS7
- [ ] Profile content with function extraction
- [ ] Validation that profiles load without error
- [ ] Conda init blocks

### Conda State
- [ ] Conda installation path and version
- [ ] Environment list (`conda env list`)
- [ ] Environment specifications (`conda env export`)
- [ ] `.condarc` configuration
- [ ] `.conda/` directory state

### Terminal Emulator Configs
- [ ] `.wezterm.lua`
- [ ] Windows Terminal settings.json
- [ ] Any shell launch flags

### Application Configs
- [ ] Claude Desktop config (`claude_desktop_config.json`)
- [ ] Claude Code config (`.claude/config.json`, `.claude.json`)
- [ ] MCP server configurations
- [ ] pm2 ecosystem configs

### Process State
- [ ] pm2 process list (`pm2 save`)
- [ ] Scheduled tasks referencing strap repos
- [ ] Running services

### Git State
- [ ] All repo locations
- [ ] Remote URLs
- [ ] Current branch and commit
- [ ] Dirty state warning

---

## Proposed Strap Commands

### `strap snapshot --full`
Capture complete environment state:
```powershell
strap snapshot --full --output environment-2026-02-02.json
```

Output includes:
- All registry entries
- PATH entries (User + System)
- Environment variables
- Profile contents
- Conda state
- pm2 state
- Application configs

### `strap restore`
Restore from snapshot:
```powershell
strap restore environment-2026-02-02.json --dry-run
strap restore environment-2026-02-02.json --yes
```

Capabilities:
- Restore PATH entries
- Restore environment variables
- Restore profile functions
- Re-clone missing repos
- Reinstall conda environments
- Restart pm2 processes

### `strap doctor --environment`
Validate environment integrity:
```powershell
strap doctor --environment
```

Checks:
- PATH length under limit
- No duplicate PATH entries
- All PATH entries exist
- Profiles load without error
- Conda functional
- pm2 processes running
- MCP servers accessible

---

## Lessons Learned

1. **Subagent resource limits are critical** - 45GB RAM consumption should have been caught earlier
2. **Force-killing processes corrupts environment** - Graceful shutdown is essential
3. **Multiple backup locations saved us** - User had PATH backup, profile backups, env backups
4. **Cascading failures are hard to debug** - Conda failure masked by profile failure masked by PATH corruption
5. **The tool being built was exactly what was needed** - Deep irony that strap's snapshot/restore would have prevented this

---

## Action Items

1. [ ] Complete strap snapshot command with full environment capture
2. [ ] Implement strap restore command
3. [ ] Add `strap doctor --environment` checks
4. [ ] Add resource monitoring/limits for subagents
5. [ ] Create automated backup schedule for critical configs
6. [ ] Document recovery procedures for common failures

---

## Appendix: Recovery Commands Reference

### Conda Reinstall
```powershell
# Download
curl.exe -L -o "$env:TEMP\Miniconda3-latest.exe" https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe

# Kill existing
Get-Process conda* | Stop-Process -Force

# Remove old installation
Remove-Item 'C:\ProgramData\miniconda3' -Recurse -Force

# Install fresh
Start-Process -FilePath "$env:TEMP\Miniconda3-latest.exe" -ArgumentList '/S', '/AddToPath=0', '/RegisterPython=0', '/D=C:\ProgramData\miniconda3' -Wait

# Initialize for PowerShell
conda init powershell
```

### Chinvex Reinstall
```powershell
# Clone
git clone <github-url> P:\software\chinvex

# Create venv
py -3.12 -m venv P:\software\chinvex\.venv

# Install
P:\software\chinvex\.venv\Scripts\pip.exe install -e P:\software\chinvex

# Bootstrap
P:\software\chinvex\.venv\Scripts\chinvex.exe bootstrap install --ntfy-topic dual-nature

# Start pm2
Set-Location P:\software\chinvex
pm2 start ecosystem.config.js
pm2 save
```

### Add to PATH
```powershell
$currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
$newPath = 'P:\software\chinvex\.venv\Scripts;' + $currentPath
[Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
```

### Profile Function (dual)
```powershell
function dual {
    param([string]$cmd, [string]$arg)
    switch ($cmd) {
        "brief"  { chinvex brief --all-contexts }
        "track"  {
            $repo = if ($arg) { Resolve-Path $arg } else { Get-Location }
            $name = (Split-Path $repo -Leaf).ToLower() -replace '[^a-z0-9-]', '-'
            chinvex ingest --context $name --repo $repo
            chinvex sync reconcile-sources 2>$null
            Write-Host "Tracking $repo in context '$name'"
        }
        "status" { chinvex status }
        default  { Write-Host "Usage: dual [brief|track|status]" }
    }
}
Set-Alias dn dual
```
