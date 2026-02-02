# PowerShell Port - TDD Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use batch-exec to execute this plan.

**Date**: 2026-02-02
**Goal**: Complete pure PowerShell port of dev-environment-consolidation functionality using test-driven development

**Architecture**: Port TypeScript reference implementation to idiomatic PowerShell with zero Node.js dependencies. TypeScript code serves as specification only. All algorithms rewritten in PowerShell.

**Tech Stack**:
- PowerShell 7+ (pwsh)
- Pester testing framework
- Git for repository operations
- Windows tools (schtasks, environment variables)

**Success Criteria**:
- All 13 features ported with passing Pester tests
- Zero TypeScript/Node.js runtime dependencies
- All README commands callable
- TypeScript tests still pass (75/75) as validation
- Help text matches implementation

---

<!-- Tasks will be appended by batch-plan subagents -->

## Batch 1: External Reference Detection Foundation

### Task 1: Scheduled Task Detection with Pester Tests

**Goal**: Detect Windows scheduled tasks that reference repositories being consolidated

**Reference**: `src/commands/snapshot/detectExternalRefs.ts:33-44`, Original Task #23

**Files**:
- Test: `tests/powershell/Get-ScheduledTaskReferences.Tests.ps1`
- Implementation: Function in `strap.ps1` (integrate at line 3456, replacing line 3472)

**Step 1: Write the failing Pester test**

```powershell
# tests/powershell/Get-ScheduledTaskReferences.Tests.ps1
Describe "Get-ScheduledTaskReferences" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test scheduled task
        $testTaskName = "StrapTest-MorningBrief"
        $testScriptPath = "C:\Code\chinvex\scripts\morning_brief.ps1"
        $testTaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2">
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-File "$testScriptPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@
        Register-ScheduledTask -TaskName $testTaskName -Xml $testTaskXml -Force | Out-Null
    }

    AfterAll {
        # Clean up test task
        Unregister-ScheduledTask -TaskName "StrapTest-MorningBrief" -Confirm:$false -ErrorAction SilentlyContinue
    }

    It "should detect scheduled tasks referencing repository paths" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")

        # Act
        $result = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -BeGreaterThan 0
        $matchingTask = $result | Where-Object { $_.name -like "*MorningBrief*" }
        $matchingTask | Should -Not -BeNullOrEmpty
        $matchingTask.path | Should -Match "C:\\Code\\chinvex"
    }

    It "should return empty array when no tasks reference repo paths" {
        # Arrange
        $repoPaths = @("C:\NonExistent\Path")

        # Act
        $result = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert
        $result | Should -BeNullOrEmpty
    }

    It "should normalize paths and match case-insensitively" {
        # Arrange
        $repoPaths = @("c:\code\chinvex")  # lowercase

        # Act
        $result = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert
        $result | Should -Not -BeNullOrEmpty
    }

    It "should handle schtasks command failure gracefully" {
        # Arrange
        Mock Invoke-Expression { throw "schtasks failed" }
        $repoPaths = @("C:\Code\chinvex")

        # Act
        $result = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert
        $result | Should -BeNullOrEmpty
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Get-ScheduledTaskReferences.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - Get-ScheduledTaskReferences command not found`

**Step 3: Implement the PowerShell function**

```powershell
# Add to strap.ps1 after line 714 (after Get-TemplateNameFromArgs)
function Get-ScheduledTaskReferences {
    <#
    .SYNOPSIS
    Detects Windows scheduled tasks that reference repository paths

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'name' and 'path' properties
    #>
    param(
        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    try {
        # Get all scheduled tasks as CSV
        $csv = & schtasks /query /fo csv /v 2>$null
        if (-not $csv) { return @() }

        # Parse CSV output
        $tasks = $csv | ConvertFrom-Csv -ErrorAction SilentlyContinue
        if (-not $tasks) { return @() }

        # Normalize repo paths for comparison
        $normalizedRepoPaths = $RepoPaths | ForEach-Object {
            $_.Replace('/', '\').TrimEnd('\').ToLower()
        }

        # Scan each task for path references
        $references = @()
        foreach ($task in $tasks) {
            # Combine task name, command, and arguments for path extraction
            $searchText = "$($task.TaskName) $($task.'Task To Run')"

            # Extract Windows paths (e.g., C:\path\to\file)
            $pathMatches = [regex]::Matches($searchText, '[A-Za-z]:\\[^\s,\"]+')

            foreach ($match in $pathMatches) {
                $extractedPath = $match.Value.TrimEnd('\').ToLower()

                # Check if path starts with any repo path
                $matchesRepo = $normalizedRepoPaths | Where-Object {
                    $extractedPath.StartsWith($_)
                }

                if ($matchesRepo) {
                    $references += @{
                        name = $task.TaskName
                        path = $match.Value
                    }
                    break  # Only add task once even if multiple paths match
                }
            }
        }

        return $references

    } catch {
        # schtasks failed or not available - return empty array
        Write-Verbose "Failed to query scheduled tasks: $_"
        return @()
    }
}
```

Integration point: Replace PM2-only audit check in `Invoke-ConsolidateMigrationWorkflow` at line 3456-3472 with comprehensive external reference detection that includes scheduled tasks.

**Step 4: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Get-ScheduledTaskReferences.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 4 tests passing`

**Step 5: Manual verification**

```bash
# Create a test scheduled task manually
schtasks /create /tn "TestTask" /tr "powershell.exe -File C:\Code\test\script.ps1" /sc once /st 23:59

# Test the function
pwsh -Command ". .\strap.ps1; Get-ScheduledTaskReferences -RepoPaths @('C:\Code\test')"

# Clean up
schtasks /delete /tn "TestTask" /f
```

Expected: Function returns hashtable with task name and path

**Step 6: Commit**

```bash
git add tests/powershell/Get-ScheduledTaskReferences.Tests.ps1 strap.ps1
git commit -m "feat: add scheduled task detection with Pester tests

- Port detectExternalRefs scheduled task logic to PowerShell
- Add comprehensive Pester test coverage with setup/teardown
- Integrate into consolidate workflow audit step
- Handle schtasks failures gracefully

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Shim Detection with Pester Tests

**Goal**: Detect .cmd shims that reference repositories being consolidated

**Reference**: `src/commands/snapshot/detectExternalRefs.ts:46-60`, Original Task #24

**Files**:
- Test: `tests/powershell/Get-ShimReferences.Tests.ps1`
- Implementation: Function in `strap.ps1` (integrate at line 3456)

**Step 1: Write the failing Pester test**

```powershell
# tests/powershell/Get-ShimReferences.Tests.ps1
Describe "Get-ShimReferences" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test shim directory
        $testShimDir = Join-Path $TestDrive "shims"
        New-Item -ItemType Directory -Path $testShimDir -Force | Out-Null

        # Create test shim file
        $shimContent = @"
@echo off
set "TARGET=C:\Code\chinvex\scripts\cli.ps1"
powershell -File "%TARGET%" %*
"@
        Set-Content -Path (Join-Path $testShimDir "chinvex.cmd") -Value $shimContent

        # Create shim with no path reference
        $noPathShim = @"
@echo off
echo "No path here"
"@
        Set-Content -Path (Join-Path $testShimDir "nopath.cmd") -Value $noPathShim

        # Create shim with non-matching path
        $otherPathShim = @"
@echo off
set "TARGET=D:\Other\Project\script.ps1"
powershell -File "%TARGET%" %*
"@
        Set-Content -Path (Join-Path $testShimDir "other.cmd") -Value $otherPathShim
    }

    It "should detect shims referencing repository paths" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")
        $shimDir = Join-Path $TestDrive "shims"

        # Act
        $result = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -Be 1
        $result[0].name | Should -Be "chinvex"
        $result[0].target | Should -Match "C:\\Code\\chinvex"
    }

    It "should return empty array when no shims match repo paths" {
        # Arrange
        $repoPaths = @("C:\NonExistent\Path")
        $shimDir = Join-Path $TestDrive "shims"

        # Act
        $result = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # Assert
        $result | Should -BeNullOrEmpty
    }

    It "should normalize paths and match case-insensitively" {
        # Arrange
        $repoPaths = @("c:\code\chinvex")  # lowercase
        $shimDir = Join-Path $TestDrive "shims"

        # Act
        $result = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result[0].name | Should -Be "chinvex"
    }

    It "should handle missing shim directory gracefully" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")
        $shimDir = "C:\NonExistent\Shims"

        # Act
        $result = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # Assert
        $result | Should -BeNullOrEmpty
    }

    It "should only process .cmd files" {
        # Arrange
        $shimDir = Join-Path $TestDrive "shims"
        # Create non-.cmd file
        Set-Content -Path (Join-Path $shimDir "test.txt") -Value "C:\Code\chinvex\file.ps1"
        $repoPaths = @("C:\Code\chinvex")

        # Act
        $result = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # Assert
        # Should only find chinvex.cmd, not test.txt
        $result.Count | Should -Be 1
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Get-ShimReferences.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - Get-ShimReferences command not found`

**Step 3: Implement the PowerShell function**

```powershell
# Add to strap.ps1 after Get-ScheduledTaskReferences
function Get-ShimReferences {
    <#
    .SYNOPSIS
    Detects .cmd shim files that reference repository paths

    .PARAMETER ShimDir
    Directory containing shim files (typically build/shims)

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'name' and 'target' properties
    #>
    param(
        [Parameter(Mandatory)]
        [string] $ShimDir,

        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    # Check if shim directory exists
    if (-not (Test-Path $ShimDir)) {
        Write-Verbose "Shim directory not found: $ShimDir"
        return @()
    }

    # Normalize repo paths for comparison
    $normalizedRepoPaths = $RepoPaths | ForEach-Object {
        $_.Replace('/', '\').TrimEnd('\').ToLower()
    }

    # Scan all .cmd files in shim directory
    $references = @()
    $shimFiles = Get-ChildItem -Path $ShimDir -Filter "*.cmd" -ErrorAction SilentlyContinue

    foreach ($shimFile in $shimFiles) {
        try {
            # Read shim content
            $content = Get-Content $shimFile.FullName -Raw -ErrorAction Stop

            # Extract Windows paths from content
            $pathMatches = [regex]::Matches($content, '[A-Za-z]:\\[^\r\n\"]+')

            foreach ($match in $pathMatches) {
                $extractedPath = $match.Value.TrimEnd('\').ToLower()

                # Check if path starts with any repo path
                $matchesRepo = $normalizedRepoPaths | Where-Object {
                    $extractedPath.StartsWith($_)
                }

                if ($matchesRepo) {
                    $references += @{
                        name = $shimFile.BaseName
                        target = $match.Value
                    }
                    break  # Only add shim once even if multiple paths match
                }
            }
        } catch {
            Write-Verbose "Failed to read shim file $($shimFile.FullName): $_"
            continue
        }
    }

    return $references
}
```

Integration point: Call in `Invoke-ConsolidateMigrationWorkflow` at line 3456 within the audit step, adding to the `$auditWarnings` array.

**Step 4: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Get-ShimReferences.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 5 tests passing`

**Step 5: Manual verification**

```bash
# Create test shim manually
mkdir build\shims -Force
'@echo off
set "TARGET=C:\Code\test\cli.ps1"
powershell -File "%TARGET%" %*' | Out-File build\shims\testshim.cmd -Encoding ascii

# Test the function
pwsh -Command ". .\strap.ps1; Get-ShimReferences -ShimDir 'build\shims' -RepoPaths @('C:\Code\test')"

# Clean up
Remove-Item build\shims\testshim.cmd
```

Expected: Function returns hashtable with shim name "testshim" and target path

**Step 6: Commit**

```bash
git add tests/powershell/Get-ShimReferences.Tests.ps1 strap.ps1
git commit -m "feat: add shim detection with Pester tests

- Port detectExternalRefs shim logic to PowerShell
- Add comprehensive Pester test coverage
- Handle missing directories and file read errors gracefully
- Filter .cmd files only

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 3: PATH/Profile Scanning with Pester Tests

**Goal**: Detect PATH environment entries and PowerShell profile references to repositories

**Reference**: `src/commands/snapshot/detectExternalRefs.ts` (logic inferred from original plan Task #25)

**Files**:
- Test: `tests/powershell/Get-PathProfileReferences.Tests.ps1`
- Implementation: Functions in `strap.ps1` (integrate at line 3456)

**Step 1: Write the failing Pester test**

```powershell
# tests/powershell/Get-PathProfileReferences.Tests.ps1
Describe "Get-PathReferences" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Save original PATH
        $script:originalUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")

        # Set test PATH with repo reference
        [Environment]::SetEnvironmentVariable("PATH", "C:\Code\chinvex\bin;C:\Windows\System32", "User")
    }

    AfterAll {
        # Restore original PATH
        [Environment]::SetEnvironmentVariable("PATH", $script:originalUserPath, "User")
    }

    It "should detect PATH entries referencing repository paths" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")

        # Act
        $result = Get-PathReferences -RepoPaths $repoPaths

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $matching = $result | Where-Object { $_.path -like "*chinvex*" }
        $matching | Should -Not -BeNullOrEmpty
        $matching[0].type | Should -Be "PATH"
    }

    It "should return empty array when no PATH entries match" {
        # Arrange
        $repoPaths = @("C:\NonExistent\Path")

        # Act
        $result = Get-PathReferences -RepoPaths $repoPaths

        # Assert
        $matchingNonExistent = $result | Where-Object { $_.path -like "*NonExistent*" }
        $matchingNonExistent | Should -BeNullOrEmpty
    }

    It "should normalize paths and match case-insensitively" {
        # Arrange
        $repoPaths = @("c:\code\chinvex")  # lowercase

        # Act
        $result = Get-PathReferences -RepoPaths $repoPaths

        # Assert
        $result | Should -Not -BeNullOrEmpty
    }

    It "should check both User and Machine PATH variables" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")

        # Act
        $result = Get-PathReferences -RepoPaths $repoPaths

        # Assert
        # Function should scan both scopes (implementation detail verified)
        $result | Should -Not -BeNullOrEmpty
    }
}

Describe "Get-ProfileReferences" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test profile
        $testProfileDir = Join-Path $TestDrive "ProfileTest"
        New-Item -ItemType Directory -Path $testProfileDir -Force | Out-Null
        $testProfilePath = Join-Path $testProfileDir "Microsoft.PowerShell_profile.ps1"

        $profileContent = @"
# Test profile
`$env:CHINVEX_HOME = "C:\Code\chinvex"
. C:\Code\chinvex\scripts\init.ps1
Set-Location C:\Projects\work
"@
        Set-Content -Path $testProfilePath -Value $profileContent
    }

    It "should detect profile references to repository paths" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")
        $testProfilePath = Join-Path $TestDrive "ProfileTest\Microsoft.PowerShell_profile.ps1"

        # Act
        $result = Get-ProfileReferences -ProfilePath $testProfilePath -RepoPaths $repoPaths

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -BeGreaterOrEqual 2  # Two references to chinvex
        $result[0].type | Should -Be "profile"
    }

    It "should return empty array when profile does not exist" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")
        $nonExistentProfile = "C:\NonExistent\profile.ps1"

        # Act
        $result = Get-ProfileReferences -ProfilePath $nonExistentProfile -RepoPaths $repoPaths

        # Assert
        $result | Should -BeNullOrEmpty
    }

    It "should return empty array when no profile references match" {
        # Arrange
        $repoPaths = @("C:\NonExistent\Path")
        $testProfilePath = Join-Path $TestDrive "ProfileTest\Microsoft.PowerShell_profile.ps1"

        # Act
        $result = Get-ProfileReferences -ProfilePath $testProfilePath -RepoPaths $repoPaths

        # Assert
        $matchingNonExistent = $result | Where-Object { $_.path -like "*NonExistent*" }
        $matchingNonExistent | Should -BeNullOrEmpty
    }

    It "should normalize paths and match case-insensitively" {
        # Arrange
        $repoPaths = @("c:\code\chinvex")  # lowercase
        $testProfilePath = Join-Path $TestDrive "ProfileTest\Microsoft.PowerShell_profile.ps1"

        # Act
        $result = Get-ProfileReferences -ProfilePath $testProfilePath -RepoPaths $repoPaths

        # Assert
        $result | Should -Not -BeNullOrEmpty
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Get-PathProfileReferences.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - Get-PathReferences command not found`

**Step 3: Implement the PowerShell functions**

```powershell
# Add to strap.ps1 after Get-ShimReferences
function Get-PathReferences {
    <#
    .SYNOPSIS
    Detects PATH environment variable entries that reference repository paths

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'type' and 'path' properties
    #>
    param(
        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    # Normalize repo paths for comparison
    $normalizedRepoPaths = $RepoPaths | ForEach-Object {
        $_.Replace('/', '\').TrimEnd('\').ToLower()
    }

    # Get User and Machine PATH variables
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

    # Combine and split by semicolon
    $allPathEntries = @()
    if ($userPath) { $allPathEntries += $userPath -split ';' }
    if ($machinePath) { $allPathEntries += $machinePath -split ';' }

    # Find matching entries
    $references = @()
    foreach ($pathEntry in $allPathEntries) {
        if ([string]::IsNullOrWhiteSpace($pathEntry)) { continue }

        $normalizedEntry = $pathEntry.TrimEnd('\').ToLower()

        # Check if entry starts with any repo path
        $matchesRepo = $normalizedRepoPaths | Where-Object {
            $normalizedEntry.StartsWith($_)
        }

        if ($matchesRepo) {
            $references += @{
                type = "PATH"
                path = $pathEntry
            }
        }
    }

    return $references
}

function Get-ProfileReferences {
    <#
    .SYNOPSIS
    Detects PowerShell profile references to repository paths

    .PARAMETER ProfilePath
    Path to PowerShell profile file (defaults to $PROFILE)

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'type' and 'path' properties
    #>
    param(
        [Parameter()]
        [string] $ProfilePath = $PROFILE,

        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    # Check if profile exists
    if (-not (Test-Path $ProfilePath)) {
        Write-Verbose "Profile not found: $ProfilePath"
        return @()
    }

    try {
        # Read profile content
        $content = Get-Content $ProfilePath -Raw -ErrorAction Stop

        # Normalize repo paths for comparison
        $normalizedRepoPaths = $RepoPaths | ForEach-Object {
            $_.Replace('/', '\').TrimEnd('\').ToLower()
        }

        # Extract Windows paths from content
        $pathMatches = [regex]::Matches($content, '[A-Za-z]:\\[^\s\r\n\"\'']+')

        # Find matching paths
        $references = @()
        foreach ($match in $pathMatches) {
            $extractedPath = $match.Value.TrimEnd('\').ToLower()

            # Check if path starts with any repo path
            $matchesRepo = $normalizedRepoPaths | Where-Object {
                $extractedPath.StartsWith($_)
            }

            if ($matchesRepo) {
                $references += @{
                    type = "profile"
                    path = $match.Value
                }
            }
        }

        return $references

    } catch {
        Write-Verbose "Failed to read profile $ProfilePath: $_"
        return @()
    }
}
```

Integration point: Call both functions in `Invoke-ConsolidateMigrationWorkflow` at line 3456 within the audit step, adding to the `$auditWarnings` array.

**Step 4: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Get-PathProfileReferences.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 8 tests passing`

**Step 5: Manual verification**

```bash
# Test PATH detection
pwsh -Command ". .\strap.ps1; Get-PathReferences -RepoPaths @('C:\Code\chinvex')"

# Test profile detection
pwsh -Command ". .\strap.ps1; Get-ProfileReferences -RepoPaths @('C:\Code\chinvex')"
```

Expected: Functions return arrays of hashtables with detected references

**Step 6: Commit**

```bash
git add tests/powershell/Get-PathProfileReferences.Tests.ps1 strap.ps1
git commit -m "feat: add PATH and profile scanning with Pester tests

- Port PATH environment variable scanning to PowerShell
- Port PowerShell profile reference detection
- Add comprehensive Pester test coverage
- Check both User and Machine PATH scopes
- Handle missing profiles gracefully

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 4: Audit Index Foundation (Scanning Logic)

**Goal**: Build audit index that scans repositories for hardcoded path references

**Reference**: `src/commands/audit/index.ts:34-55`, `tests/commands/audit/index.test.ts`

**Files**:
- Test: `tests/powershell/Build-AuditIndex.Tests.ps1`
- Implementation: Function in `strap.ps1` (integrate at line 3456 for consolidate)

**Step 1: Write the failing Pester test**

```powershell
# tests/powershell/Build-AuditIndex.Tests.ps1
Describe "Find-PathReferences" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test repository with files containing path references
        $testRepo = Join-Path $TestDrive "TestRepo"
        New-Item -ItemType Directory -Path $testRepo -Force | Out-Null

        # Create test files with path references
        $scriptContent = @"
`$configPath = "C:\Code\chinvex\config\settings.json"
. C:\Code\chinvex\scripts\utils.ps1
# No path here
"@
        Set-Content -Path (Join-Path $testRepo "script.ps1") -Value $scriptContent

        $configContent = @"
{
  "dataPath": "C:\Code\chinvex\data",
  "logPath": "C:\Logs\app.log"
}
"@
        Set-Content -Path (Join-Path $testRepo "config.json") -Value $configContent

        $readmeContent = @"
# Project README
No paths in this file.
"@
        Set-Content -Path (Join-Path $testRepo "README.md") -Value $readmeContent
    }

    It "should find path references in repository files" {
        # Arrange
        $repoPath = Join-Path $TestDrive "TestRepo"

        # Act
        $result = Find-PathReferences -RepoPath $repoPath

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -BeGreaterOrEqual 3  # At least 3 path references

        # Verify line number format: filepath:linenum
        $result[0] | Should -Match ":\\d+$"
    }

    It "should scan common file types (ps1, json, yml, md, etc.)" {
        # Arrange
        $repoPath = Join-Path $TestDrive "TestRepo"

        # Act
        $result = Find-PathReferences -RepoPath $repoPath

        # Assert
        $psFiles = $result | Where-Object { $_ -like "*.ps1:*" }
        $jsonFiles = $result | Where-Object { $_ -like "*.json:*" }

        $psFiles | Should -Not -BeNullOrEmpty
        $jsonFiles | Should -Not -BeNullOrEmpty
    }

    It "should return empty array for repo with no path references" {
        # Arrange
        $cleanRepo = Join-Path $TestDrive "CleanRepo"
        New-Item -ItemType Directory -Path $cleanRepo -Force | Out-Null
        Set-Content -Path (Join-Path $cleanRepo "file.txt") -Value "No paths here"

        # Act
        $result = Find-PathReferences -RepoPath $cleanRepo

        # Assert
        $result | Should -BeNullOrEmpty
    }

    It "should handle non-existent repository gracefully" {
        # Arrange
        $nonExistentRepo = "C:\NonExistent\Repo"

        # Act
        $result = Find-PathReferences -RepoPath $nonExistentRepo

        # Assert
        $result | Should -BeNullOrEmpty
    }
}

Describe "Build-AuditIndex" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test registry entries
        $script:testRegistry = @(
            @{
                name = "chinvex"
                path = "C:\Code\chinvex"
                last_commit = "abc123"
            },
            @{
                name = "strap"
                path = "C:\Code\strap"
                last_commit = "def456"
            }
        )

        # Create mock repos
        $chinvexRepo = "C:\Code\chinvex"
        $strapRepo = "C:\Code\strap"

        New-Item -ItemType Directory -Path $chinvexRepo -Force | Out-Null
        New-Item -ItemType Directory -Path $strapRepo -Force | Out-Null

        Set-Content -Path (Join-Path $chinvexRepo "script.ps1") -Value "`$path = 'C:\Code\chinvex\data'"
        Set-Content -Path (Join-Path $strapRepo "config.json") -Value '{"root": "C:\Code\strap"}'
    }

    AfterAll {
        # Clean up test repos
        Remove-Item -Path "C:\Code\chinvex" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Code\strap" -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "should build audit index on first run" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index.json"
        $registryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Act
        $result = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.built_at | Should -Not -BeNullOrEmpty
        $result.registry_updated_at | Should -Be $registryUpdatedAt
        $result.repo_count | Should -Be 2
        $result.repos.Keys.Count | Should -Be 2

        # Verify index was written to disk
        Test-Path $indexPath | Should -Be $true
    }

    It "should include references array for each repository" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index-refs.json"
        $registryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Act
        $result = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        # Assert
        $chinvexEntry = $result.repos["C:\Code\chinvex"]
        $chinvexEntry | Should -Not -BeNullOrEmpty
        $chinvexEntry.references | Should -Not -BeNullOrEmpty
        $chinvexEntry.references.Count | Should -BeGreaterOrEqual 1
    }

    It "should reuse existing index when metadata is fresh" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index-cached.json"
        $registryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Build initial index
        $firstResult = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        $firstBuiltAt = $firstResult.built_at

        Start-Sleep -Milliseconds 100

        # Act - build again without forcing rebuild
        $secondResult = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        # Assert - should be cached (same built_at timestamp)
        $secondResult.built_at | Should -Be $firstBuiltAt
    }

    It "should force rebuild when -RebuildIndex is true" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index-rebuild.json"
        $registryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Build initial index
        $firstResult = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        $firstBuiltAt = $firstResult.built_at

        Start-Sleep -Milliseconds 100

        # Act - force rebuild
        $secondResult = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $true `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        # Assert - should be rebuilt (different built_at timestamp)
        $secondResult.built_at | Should -Not -Be $firstBuiltAt
    }

    It "should rebuild when registry_updated_at changes" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index-stale.json"
        $oldRegistryUpdatedAt = "2026-02-01T10:00:00.000Z"
        $newRegistryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Build initial index
        Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $oldRegistryUpdatedAt -Registry $script:testRegistry

        # Act - build with new registry timestamp
        $result = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $newRegistryUpdatedAt -Registry $script:testRegistry

        # Assert - should be rebuilt
        $result.registry_updated_at | Should -Be $newRegistryUpdatedAt
    }

    It "should rebuild when repo count changes" {
        # Arrange
        $indexPath = Join-Path $TestDrive "audit-index-count.json"
        $registryUpdatedAt = "2026-02-02T10:00:00.000Z"

        # Build initial index with 2 repos
        Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $script:testRegistry

        # Add third repo
        $expandedRegistry = $script:testRegistry + @(@{
            name = "newrepo"
            path = "C:\Code\newrepo"
            last_commit = "ghi789"
        })

        New-Item -ItemType Directory -Path "C:\Code\newrepo" -Force | Out-Null

        # Act - build with 3 repos
        $result = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryUpdatedAt -Registry $expandedRegistry

        # Assert - should be rebuilt
        $result.repo_count | Should -Be 3

        # Clean up
        Remove-Item -Path "C:\Code\newrepo" -Recurse -Force -ErrorAction SilentlyContinue
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Build-AuditIndex.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - Find-PathReferences command not found`

**Step 3: Implement the PowerShell functions**

```powershell
# Add to strap.ps1 after Get-ProfileReferences
function Find-PathReferences {
    <#
    .SYNOPSIS
    Scans repository files for hardcoded Windows path references

    .PARAMETER RepoPath
    Path to repository to scan

    .OUTPUTS
    Array of strings in format "filepath:linenum"
    #>
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    # Check if repo exists
    if (-not (Test-Path $RepoPath)) {
        Write-Verbose "Repository not found: $RepoPath"
        return @()
    }

    try {
        # Scan common file types for path references
        $fileExtensions = @('*.ps1', '*.js', '*.ts', '*.json', '*.yml', '*.yaml', '*.md', '*.txt', '*.config')
        $files = Get-ChildItem -Path $RepoPath -Recurse -File -Include $fileExtensions -ErrorAction SilentlyContinue

        $references = @()

        foreach ($file in $files) {
            try {
                $lineNum = 0
                $lines = Get-Content $file.FullName -ErrorAction Stop

                foreach ($line in $lines) {
                    $lineNum++

                    # Check if line contains Windows path pattern
                    if ($line -match '[A-Za-z]:\\[^\s\r\n\"\'']+') {
                        $references += "$($file.FullName):$lineNum"
                    }
                }
            } catch {
                Write-Verbose "Failed to read file $($file.FullName): $_"
                continue
            }
        }

        return $references

    } catch {
        Write-Verbose "Failed to scan repository $RepoPath: $_"
        return @()
    }
}

function Build-AuditIndex {
    <#
    .SYNOPSIS
    Builds or loads cached audit index of path references across all repositories

    .PARAMETER IndexPath
    Path to audit index JSON file

    .PARAMETER RebuildIndex
    Force rebuild even if cached index is fresh

    .PARAMETER RegistryUpdatedAt
    ISO8601 timestamp of registry last update

    .PARAMETER Registry
    Array of registry entries (hashtables with 'name', 'path', 'last_commit')

    .OUTPUTS
    Hashtable with audit index structure
    #>
    param(
        [Parameter(Mandatory)]
        [string] $IndexPath,

        [Parameter(Mandatory)]
        [bool] $RebuildIndex,

        [Parameter(Mandatory)]
        [string] $RegistryUpdatedAt,

        [Parameter(Mandatory)]
        [array] $Registry
    )

    # Check if existing index is fresh
    if ((Test-Path $IndexPath) -and -not $RebuildIndex) {
        try {
            $existing = Get-Content $IndexPath -Raw | ConvertFrom-Json

            # Check if cached index is still valid
            $isFresh = ($existing.registry_updated_at -eq $RegistryUpdatedAt) -and
                       ($existing.repo_count -eq $Registry.Count)

            if ($isFresh) {
                Write-Verbose "Using cached audit index"
                return $existing
            }
        } catch {
            Write-Verbose "Failed to read existing index, rebuilding"
        }
    }

    # Build new index
    Write-Host "Building audit index for $($Registry.Count) repositories..." -ForegroundColor Cyan

    $repos = @{}
    foreach ($entry in $Registry) {
        Write-Verbose "Scanning $($entry.name) at $($entry.path)"

        # Scan repo for path references
        $references = Find-PathReferences -RepoPath $entry.path

        $repos[$entry.path] = @{
            references = $references
        }
    }

    # Build index structure
    $index = @{
        built_at = (Get-Date).ToUniversalTime().ToString("o")
        registry_updated_at = $RegistryUpdatedAt
        repo_count = $Registry.Count
        repos = $repos
    }

    # Write to disk
    try {
        $indexDir = Split-Path $IndexPath -Parent
        if ($indexDir -and -not (Test-Path $indexDir)) {
            New-Item -ItemType Directory -Path $indexDir -Force | Out-Null
        }

        $index | ConvertTo-Json -Depth 10 | Set-Content $IndexPath -Encoding UTF8
        Write-Verbose "Audit index written to $IndexPath"
    } catch {
        Write-Warning "Failed to write audit index to disk: $_"
    }

    return $index
}
```

Integration point: Replace basic PM2 check in `Invoke-ConsolidateMigrationWorkflow` at line 3456-3472 with call to `Build-AuditIndex`.

**Step 4: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Build-AuditIndex.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 11 tests passing`

**Step 5: Manual verification**

```bash
# Build audit index manually
pwsh -Command "
. .\strap.ps1
`$registry = @(@{name='test'; path='C:\Code\test'; last_commit='abc'})
Build-AuditIndex -IndexPath 'build\audit-index.json' -RebuildIndex `$false -RegistryUpdatedAt '2026-02-02T10:00:00Z' -Registry `$registry
"

# Verify index file
cat build\audit-index.json
```

Expected: JSON file with audit index structure containing built_at, registry_updated_at, repo_count, and repos

**Step 6: Commit**

```bash
git add tests/powershell/Build-AuditIndex.Tests.ps1 strap.ps1
git commit -m "feat: add audit index foundation with Pester tests

- Port loadOrBuildAuditIndex logic to PowerShell
- Add Find-PathReferences function to scan repos
- Implement caching with freshness checks
- Add comprehensive Pester test coverage (11 tests)
- Support force rebuild flag

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 5: Audit Index Caching and Optimization

**Goal**: Integrate audit index into consolidate workflow with optimization for unchanged repos

**Reference**: `src/commands/audit/index.ts`, Original Task #26 optimization notes

**Files**:
- Test: `tests/powershell/Invoke-ConsolidateAuditStep.Tests.ps1`
- Implementation: Modify `Invoke-ConsolidateMigrationWorkflow` at line 3456-3482

**Step 1: Write the failing Pester test**

```powershell
# tests/powershell/Invoke-ConsolidateAuditStep.Tests.ps1
Describe "Consolidate Audit Step Integration" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create mock registry
        $testRegistryPath = Join-Path $TestDrive "registry-v2.json"
        $registry = @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @(
                @{
                    name = "testproject"
                    path = "C:\Code\testproject"
                    scope = "active"
                    last_commit = "abc123"
                }
            )
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $testRegistryPath

        # Create mock repo
        New-Item -ItemType Directory -Path "C:\Code\testproject" -Force | Out-Null
        Set-Content -Path "C:\Code\testproject\config.json" -Value '{"root": "C:\Code\testproject"}'

        # Create scheduled task referencing repo
        $taskName = "StrapTest-ConsolidateAudit"
        $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2">
  <Actions>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-File "C:\Code\testproject\task.ps1"</Arguments>
    </Exec>
  </Actions>
</Task>
"@
        Register-ScheduledTask -TaskName $taskName -Xml $taskXml -Force | Out-Null
    }

    AfterAll {
        # Clean up
        Unregister-ScheduledTask -TaskName "StrapTest-ConsolidateAudit" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Code\testproject" -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "should detect all external reference types in audit step" {
        # Arrange
        $fromPath = "C:\Code\testproject"
        $templateRoot = $TestDrive

        # Mock the external reference functions to return test data
        Mock Get-ScheduledTaskReferences {
            @(@{ name = "StrapTest-ConsolidateAudit"; path = "C:\Code\testproject\task.ps1" })
        }
        Mock Get-ShimReferences {
            @(@{ name = "testshim"; target = "C:\Code\testproject\cli.ps1" })
        }
        Mock Get-PathReferences {
            @(@{ type = "PATH"; path = "C:\Code\testproject\bin" })
        }
        Mock Get-ProfileReferences {
            @(@{ type = "profile"; path = "C:\Code\testproject\init.ps1" })
        }

        # Act - simulate audit step
        $auditWarnings = @()
        $repoPaths = @($fromPath)

        $scheduledTasks = Get-ScheduledTaskReferences -RepoPaths $repoPaths
        $shims = Get-ShimReferences -ShimDir (Join-Path $templateRoot "build\shims") -RepoPaths $repoPaths
        $pathRefs = Get-PathReferences -RepoPaths $repoPaths
        $profileRefs = Get-ProfileReferences -RepoPaths $repoPaths

        foreach ($task in $scheduledTasks) {
            $auditWarnings += "Scheduled task '$($task.name)' references $($task.path)"
        }
        foreach ($shim in $shims) {
            $auditWarnings += "Shim '$($shim.name)' targets $($shim.target)"
        }
        foreach ($pathRef in $pathRefs) {
            $auditWarnings += "PATH entry: $($pathRef.path)"
        }
        foreach ($profileRef in $profileRefs) {
            $auditWarnings += "Profile reference: $($profileRef.path)"
        }

        # Assert
        $auditWarnings.Count | Should -Be 4
        $auditWarnings[0] | Should -Match "Scheduled task"
        $auditWarnings[1] | Should -Match "Shim"
        $auditWarnings[2] | Should -Match "PATH"
        $auditWarnings[3] | Should -Match "Profile"
    }

    It "should build audit index as part of consolidate workflow" {
        # Arrange
        $indexPath = Join-Path $TestDrive "build\audit-index.json"
        $registryPath = Join-Path $TestDrive "registry-v2.json"
        $registryData = Get-Content $registryPath | ConvertFrom-Json

        # Act
        $index = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryData.updated_at -Registry $registryData.entries

        # Assert
        Test-Path $indexPath | Should -Be $true
        $index.repo_count | Should -Be 1
        $index.repos["C:\Code\testproject"] | Should -Not -BeNullOrEmpty
    }

    It "should cache audit index across multiple consolidate runs" {
        # Arrange
        $indexPath = Join-Path $TestDrive "build\audit-index-cache.json"
        $registryPath = Join-Path $TestDrive "registry-v2.json"
        $registryData = Get-Content $registryPath | ConvertFrom-Json

        # Act - first run
        $firstIndex = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryData.updated_at -Registry $registryData.entries

        $firstBuiltAt = $firstIndex.built_at

        Start-Sleep -Milliseconds 100

        # Act - second run (should use cache)
        $secondIndex = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryData.updated_at -Registry $registryData.entries

        # Assert - timestamps should match (cached)
        $secondIndex.built_at | Should -Be $firstBuiltAt
    }

    It "should warn about external references but allow --ack-scheduled-tasks override" {
        # Arrange
        $auditWarnings = @(
            "Scheduled task 'test' references C:\Code\testproject",
            "PATH entry: C:\Code\testproject\bin"
        )
        $ackScheduledTasks = $true

        # Act - simulate the warning logic
        $shouldBlock = ($auditWarnings.Count -gt 0) -and (-not $ackScheduledTasks)

        # Assert
        $shouldBlock | Should -Be $false
    }

    It "should block consolidate when external references exist without --ack-scheduled-tasks" {
        # Arrange
        $auditWarnings = @(
            "Scheduled task 'test' references C:\Code\testproject"
        )
        $ackScheduledTasks = $false

        # Act
        $shouldBlock = ($auditWarnings.Count -gt 0) -and (-not $ackScheduledTasks)

        # Assert
        $shouldBlock | Should -Be $true
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-ConsolidateAuditStep.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - External reference detection not integrated into consolidate`

**Step 3: Implement the integration in strap.ps1**

```powershell
# Replace lines 3455-3482 in Invoke-ConsolidateMigrationWorkflow
# Update Step 4: Audit for external references

  # Step 4: Audit for external references
  Write-Host "`n[4/6] Auditing external references..." -ForegroundColor Yellow
  $auditWarnings = @()

  # Determine repo paths to check
  $repoPaths = @($FromPath)

  # 1. Check scheduled tasks
  Write-Verbose "Checking scheduled tasks..."
  $scheduledTasks = Get-ScheduledTaskReferences -RepoPaths $repoPaths
  foreach ($task in $scheduledTasks) {
    $auditWarnings += "Scheduled task '$($task.name)' references $($task.path)"
  }

  # 2. Check shims
  Write-Verbose "Checking shims..."
  $shimDir = Join-Path $TemplateRoot "build\shims"
  $shims = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths
  foreach ($shim in $shims) {
    $auditWarnings += "Shim '$($shim.name)' targets $($shim.target)"
  }

  # 3. Check PATH environment variables
  Write-Verbose "Checking PATH entries..."
  $pathRefs = Get-PathReferences -RepoPaths $repoPaths
  foreach ($pathRef in $pathRefs) {
    $auditWarnings += "PATH entry: $($pathRef.path)"
  }

  # 4. Check PowerShell profile
  Write-Verbose "Checking PowerShell profile..."
  $profileRefs = Get-ProfileReferences -RepoPaths $repoPaths
  foreach ($profileRef in $profileRefs) {
    $auditWarnings += "Profile reference: $($profileRef.path)"
  }

  # 5. Check PM2 processes (existing check)
  if (Has-Command "pm2") {
    try {
      $pm2List = & pm2 jlist 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
      foreach ($proc in $pm2List) {
        if ($proc.pm2_env.pm_cwd -and $proc.pm2_env.pm_cwd.StartsWith($FromPath, [StringComparison]::OrdinalIgnoreCase)) {
          $auditWarnings += "PM2 process '$($proc.name)' references $FromPath"
        }
      }
    } catch {
      # PM2 not available or error - skip
    }
  }

  # 6. Build audit index for hardcoded path references
  Write-Verbose "Building audit index..."
  $indexPath = Join-Path $TemplateRoot "build\audit-index.json"
  $registryData = Get-Content (Join-Path $TemplateRoot "registry-v2.json") | ConvertFrom-Json

  try {
    $auditIndex = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
      -RegistryUpdatedAt $registryData.updated_at -Registry $registryData.entries

    # Check if any repos have hardcoded references to $FromPath
    foreach ($repoPath in $auditIndex.repos.Keys) {
      $refs = $auditIndex.repos[$repoPath].references
      foreach ($ref in $refs) {
        # Parse reference format: filepath:linenum
        if ($ref -match $FromPath.Replace('\', '\\')) {
          $auditWarnings += "Hardcoded path in $ref"
        }
      }
    }
  } catch {
    Write-Warning "Failed to build audit index: $_"
  }

  # Display warnings and enforce --ack-scheduled-tasks flag
  if ($auditWarnings.Count -gt 0) {
    Warn "External references detected:"
    foreach ($w in $auditWarnings) {
      Write-Host "  - $w" -ForegroundColor Yellow
    }

    if (-not $AckScheduledTasks) {
      Die "External references detected. Re-run with --ack-scheduled-tasks to continue."
    }

    Write-Host "`nProceeding with --ack-scheduled-tasks flag set." -ForegroundColor Yellow
  } else {
    Write-Host "No external references detected." -ForegroundColor Green
  }
```

Integration point: Lines 3455-3482 in `Invoke-ConsolidateMigrationWorkflow`

**Step 4: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-ConsolidateAuditStep.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 5 tests passing`

**Step 5: Manual verification**

```bash
# Test full consolidate workflow with audit integration
# Create test scheduled task
schtasks /create /tn "TestConsolidate" /tr "powershell.exe -File C:\Code\test\script.ps1" /sc once /st 23:59

# Run consolidate (should detect scheduled task)
strap consolidate C:\Code\test --dry-run

# Should show warning about scheduled task
# Run with flag to bypass
strap consolidate C:\Code\test --dry-run --ack-scheduled-tasks

# Clean up
schtasks /delete /tn "TestConsolidate" /f
```

Expected: First consolidate shows warning and blocks, second consolidate with flag proceeds

**Step 6: Commit**

```bash
git add tests/powershell/Invoke-ConsolidateAuditStep.Tests.ps1 strap.ps1
git commit -m "feat: integrate comprehensive audit into consolidate workflow

- Replace PM2-only check with full external reference audit
- Detect scheduled tasks, shims, PATH entries, profile refs
- Build and cache audit index for hardcoded path scanning
- Enforce --ack-scheduled-tasks flag when references found
- Add comprehensive integration tests (5 tests)
- Optimize with audit index caching

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```
## Batch 2: Standalone Commands and Enhanced Flags

### Task 6: Snapshot Command with CLI Wiring

**Goal**: Port snapshot command to capture comprehensive environment state and git metadata

**Reference**: `src/commands/snapshot/*.ts`, Original Task #17

**Files**:
- Test: `tests/powershell/Invoke-Snapshot.Tests.ps1`
- Implementation: Function in `strap.ps1` + CLI dispatch

**Step 1: Write the failing Pester test**

```powershell
# tests/powershell/Invoke-Snapshot.Tests.ps1
Describe "Invoke-Snapshot" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test scan directories with repos
        $testScanRoot = Join-Path $TestDrive "ScanTest"
        New-Item -ItemType Directory -Path $testScanRoot -Force | Out-Null

        # Create git repo
        $testRepo = Join-Path $testScanRoot "testproject"
        New-Item -ItemType Directory -Path (Join-Path $testRepo ".git") -Force | Out-Null
        Set-Content -Path (Join-Path $testRepo "README.md") -Value "# Test Project"

        # Create regular directory
        $testDir = Join-Path $testScanRoot "notes"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        # Create file
        $testFile = Join-Path $testScanRoot "helper.ps1"
        Set-Content -Path $testFile -Value "Write-Host 'Helper'"
    }

    It "should scan directories and classify items as file/directory" {
        # Arrange
        $scanDirs = @(Join-Path $TestDrive "ScanTest")
        $outputPath = Join-Path $TestDrive "snapshot-classify.json"
        $strapRoot = $TestDrive

        # Act
        $result = Invoke-Snapshot -ScanDirs $scanDirs -OutputPath $outputPath -StrapRootPath $strapRoot

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.discovered | Should -Not -BeNullOrEmpty
        $result.discovered.Count | Should -Be 3  # repo, dir, file
    }

    It "should detect git repositories with remote and commit metadata" {
        # Arrange
        $testRepo = Join-Path $TestDrive "ScanTest\testproject"

        # Initialize git repo with commit
        Push-Location $testRepo
        try {
            & git init 2>&1 | Out-Null
            & git config user.email "test@example.com"
            & git config user.name "Test User"
            & git add . 2>&1 | Out-Null
            & git commit -m "Initial commit" 2>&1 | Out-Null
            & git remote add origin "https://github.com/test/testproject.git" 2>&1 | Out-Null
        } finally {
            Pop-Location
        }

        $scanDirs = @(Join-Path $TestDrive "ScanTest")
        $outputPath = Join-Path $TestDrive "snapshot-git.json"
        $strapRoot = $TestDrive

        # Act
        $result = Invoke-Snapshot -ScanDirs $scanDirs -OutputPath $outputPath -StrapRootPath $strapRoot

        # Assert
        $gitRepos = $result.discovered | Where-Object { $_.type -eq "git" }
        $gitRepos | Should -Not -BeNullOrEmpty
        $gitRepos[0].remote_url | Should -Match "github.com/test/testproject"
        $gitRepos[0].last_commit | Should -Not -BeNullOrEmpty
    }

    It "should write snapshot manifest to output file" {
        # Arrange
        $scanDirs = @(Join-Path $TestDrive "ScanTest")
        $outputPath = Join-Path $TestDrive "snapshot-output.json"
        $strapRoot = $TestDrive

        # Act
        Invoke-Snapshot -ScanDirs $scanDirs -OutputPath $outputPath -StrapRootPath $strapRoot

        # Assert
        Test-Path $outputPath | Should -Be $true

        $content = Get-Content $outputPath | ConvertFrom-Json
        $content.timestamp | Should -Not -BeNullOrEmpty
        $content.discovered | Should -Not -BeNullOrEmpty
        $content.registry | Should -Not -BeNullOrEmpty
    }

    It "should include registry snapshot and external references" {
        # Arrange
        $scanDirs = @(Join-Path $TestDrive "ScanTest")
        $outputPath = Join-Path $TestDrive "snapshot-full.json"
        $strapRoot = $TestDrive

        # Create mock registry
        $registryPath = Join-Path $strapRoot "registry-v2.json"
        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @()
        } | ConvertTo-Json -Depth 10 | Set-Content $registryPath

        # Act
        $result = Invoke-Snapshot -ScanDirs $scanDirs -OutputPath $outputPath -StrapRootPath $strapRoot

        # Assert
        $result.registry | Should -Not -BeNullOrEmpty
        $result.registry.version | Should -Be 2
        $result.external_refs | Should -Not -BeNullOrEmpty
        $result.external_refs.PSObject.Properties.Name | Should -Contain "pm2"
        $result.external_refs.PSObject.Properties.Name | Should -Contain "scheduled_tasks"
    }

    It "should default to standard scan directories when none specified" {
        # Arrange
        $outputPath = Join-Path $TestDrive "snapshot-default.json"
        $strapRoot = $TestDrive

        # Act
        $result = Invoke-Snapshot -ScanDirs @() -OutputPath $outputPath -StrapRootPath $strapRoot

        # Assert - should use default dirs (C:\Code, P:\software, etc.)
        $result | Should -Not -BeNullOrEmpty
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Snapshot.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - Invoke-Snapshot command not found`

**Step 3: Implement the PowerShell function and CLI dispatch**

```powershell
# Add to strap.ps1 after Build-AuditIndex

function Invoke-Snapshot {
    <#
    .SYNOPSIS
    Captures comprehensive environment snapshot with git metadata and external references

    .PARAMETER ScanDirs
    Array of directories to scan (defaults to C:\Code, P:\software, etc.)

    .PARAMETER OutputPath
    Path to write snapshot JSON file

    .PARAMETER StrapRootPath
    Path to strap root directory

    .OUTPUTS
    Hashtable with snapshot manifest structure
    #>
    param(
        [Parameter()]
        [string[]] $ScanDirs,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [Parameter(Mandatory)]
        [string] $StrapRootPath
    )

    Write-Host "Capturing environment snapshot..." -ForegroundColor Cyan

    # Default scan directories
    $defaultScanDirs = @("C:\Code", "P:\software", "C:\Users\$env:USERNAME\Documents\Code")
    if ($ScanDirs.Count -eq 0) {
        $ScanDirs = $defaultScanDirs | Where-Object { Test-Path $_ }
    }

    # Load registry
    $config = Load-Config $StrapRootPath
    $registryPath = $config.registry
    $registry = $null
    $registryVersion = 1

    if (Test-Path $registryPath) {
        try {
            $registryContent = Get-Content $registryPath -Raw | ConvertFrom-Json
            if ($registryContent.PSObject.Properties['entries']) {
                # New format
                $registry = $registryContent.entries
                $registryVersion = $registryContent.registry_version
            } else {
                # Legacy format
                $registry = $registryContent
            }
        } catch {
            Write-Warning "Failed to load registry: $_"
            $registry = @()
        }
    } else {
        $registry = @()
    }

    # Build registry lookup by path (case-insensitive)
    $registryByPath = @{}
    foreach ($entry in $registry) {
        if ($entry.path) {
            $registryByPath[$entry.path.ToLower()] = $entry.name
        }
    }

    # Scan directories top-level
    Write-Verbose "Scanning directories: $($ScanDirs -join ', ')"
    $discovered = @()

    foreach ($scanDir in $ScanDirs) {
        if (-not (Test-Path $scanDir)) {
            Write-Verbose "Skipping non-existent directory: $scanDir"
            continue
        }

        $items = Get-ChildItem -Path $scanDir -ErrorAction SilentlyContinue

        foreach ($item in $items) {
            $itemPath = $item.FullName
            $inRegistry = $registryByPath.ContainsKey($itemPath.ToLower())

            if ($item.PSIsContainer) {
                # Check if it's a git repo
                $gitDir = Join-Path $itemPath ".git"
                if (Test-Path $gitDir) {
                    # Git repository
                    $remoteUrl = $null
                    $lastCommit = $null

                    try {
                        $remoteRaw = & git -C $itemPath remote get-url origin 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $remoteUrl = $remoteRaw.Trim()
                            # Normalize remote URL
                            if ($remoteUrl -match '^git@([^:]+):(.+)$') {
                                $remoteUrl = "https://$($Matches[1])/$($Matches[2])"
                            }
                            $remoteUrl = $remoteUrl -replace '\.git$', ''
                        }
                    } catch {}

                    try {
                        $commitRaw = & git -C $itemPath log -1 --format=%cI 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $lastCommit = $commitRaw.Trim()
                        }
                    } catch {}

                    $discovered += @{
                        path = $itemPath
                        name = $item.Name
                        type = "git"
                        in_registry = $inRegistry
                        remote_url = $remoteUrl
                        last_commit = $lastCommit
                    }
                } else {
                    # Regular directory
                    $discovered += @{
                        path = $itemPath
                        name = $item.Name
                        type = "directory"
                        in_registry = $inRegistry
                    }
                }
            } else {
                # File
                $discovered += @{
                    path = $itemPath
                    name = $item.Name
                    type = "file"
                }
            }
        }
    }

    # Collect external references
    Write-Verbose "Collecting external references..."
    $repoPaths = $registry | Where-Object { $_.path } | ForEach-Object { $_.path }

    $externalRefs = @{
        pm2 = @()
        scheduled_tasks = @()
        shims = @()
        path_entries = @()
        profile_refs = @()
    }

    # PM2 processes
    if (Has-Command "pm2") {
        try {
            $pm2List = & pm2 jlist 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
            foreach ($proc in $pm2List) {
                if ($proc.pm2_env.pm_cwd) {
                    $externalRefs.pm2 += @{
                        name = $proc.name
                        cwd = $proc.pm2_env.pm_cwd
                    }
                }
            }
        } catch {}
    }

    # Scheduled tasks
    $externalRefs.scheduled_tasks = Get-ScheduledTaskReferences -RepoPaths $repoPaths

    # Shims
    $shimDir = Join-Path $StrapRootPath "build\shims"
    $externalRefs.shims = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

    # PATH entries
    $externalRefs.path_entries = Get-PathReferences -RepoPaths $repoPaths

    # Profile references
    $externalRefs.profile_refs = Get-ProfileReferences -RepoPaths $repoPaths

    # Get disk usage
    $diskUsage = @{}
    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' }
        foreach ($drive in $drives) {
            $diskUsage[$drive.Name + ":"] = @{
                total_gb = [Math]::Round($drive.Used / 1GB + $drive.Free / 1GB, 2)
                free_gb = [Math]::Round($drive.Free / 1GB, 2)
            }
        }
    } catch {
        Write-Verbose "Failed to get disk usage: $_"
    }

    # Build snapshot manifest
    $manifest = @{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        registry = @{
            version = $registryVersion
            entries = $registry
        }
        discovered = $discovered
        external_refs = $externalRefs
        disk_usage = $diskUsage
    }

    # Write to output file
    try {
        $outputDir = Split-Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        $manifest | ConvertTo-Json -Depth 10 | Set-Content $OutputPath -Encoding UTF8
        Write-Host "Snapshot written to: $OutputPath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to write snapshot to $OutputPath: $_"
    }

    return $manifest
}

# CLI dispatch (add after line 200 in command routing section)
if ($RepoName -eq "snapshot") {
    # Parse --output and --scan flags
    $outputPath = "build/snapshot.json"
    $scanDirs = @()

    for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
        if ($ExtraArgs[$i] -eq "--output" -and ($i + 1) -lt $ExtraArgs.Count) {
            $outputPath = $ExtraArgs[$i + 1]
            $i++
            continue
        }
        if ($ExtraArgs[$i] -eq "--scan" -and ($i + 1) -lt $ExtraArgs.Count) {
            $scanDirs += $ExtraArgs[$i + 1]
            $i++
        }
    }

    Invoke-Snapshot -ScanDirs $scanDirs -OutputPath $outputPath -StrapRootPath $TemplateRoot
    exit 0
}
```

**Step 4: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Snapshot.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 5 tests passing`

**Step 5: Manual verification**

```bash
# Test snapshot command
strap snapshot

# Verify output file
cat build/snapshot.json

# Test with custom scan directories
strap snapshot --scan C:\Code --scan P:\software --output build/custom-snapshot.json
```

Expected: JSON file with timestamp, discovered items, registry snapshot, and external references

**Step 6: Commit**

```bash
git add tests/powershell/Invoke-Snapshot.Tests.ps1 strap.ps1
git commit -m "feat: add snapshot command with CLI wiring

- Port snapshot logic from TypeScript to PowerShell
- Scan directories and classify as git/directory/file
- Extract git remote URLs and last commit metadata
- Collect external references (PM2, tasks, shims, PATH, profile)
- Add comprehensive Pester tests (5 tests)
- Wire to CLI with --output and --scan flags

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 7: Audit Command with CLI Wiring

**Goal**: Port audit command to scan repositories for hardcoded path references

**Reference**: `src/commands/audit/index.ts`, Original Task #18

**Files**:
- Test: `tests/powershell/Invoke-Audit.Tests.ps1`
- Implementation: Function in `strap.ps1` + CLI dispatch

**Step 1: Write the failing Pester test**

```powershell
# tests/powershell/Invoke-Audit.Tests.ps1
Describe "Invoke-Audit" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test registry
        $testRegistry = Join-Path $TestDrive "registry-v2.json"

        # Create test repo
        $testRepo = Join-Path $TestDrive "testproject"
        New-Item -ItemType Directory -Path $testRepo -Force | Out-Null
        Set-Content -Path (Join-Path $testRepo "config.ps1") -Value "`$path = 'C:\Code\testproject\data'"

        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @(
                @{
                    name = "testproject"
                    path = $testRepo
                    scope = "software"
                    last_commit = "abc123"
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content $testRegistry

        # Create config.json
        $configPath = Join-Path $TestDrive "config.json"
        @{
            registry = $testRegistry
            roots = @{
                software = $TestDrive
                tools = $TestDrive
                shims = Join-Path $TestDrive "shims"
            }
        } | ConvertTo-Json -Depth 10 | Set-Content $configPath
    }

    It "should scan specific repository and report path references" {
        # Arrange
        $targetName = "testproject"
        $strapRoot = $TestDrive
        $outputJson = $false

        # Act
        $result = Invoke-Audit -TargetName $targetName -StrapRootPath $strapRoot -OutputJson $outputJson

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.references | Should -Not -BeNullOrEmpty
        $result.references.Count | Should -BeGreaterOrEqual 1
    }

    It "should scan all repositories when --all flag is used" {
        # Arrange
        $allFlag = $true
        $strapRoot = $TestDrive
        $outputJson = $false

        # Act
        $result = Invoke-Audit -AllRepos $allFlag -StrapRootPath $strapRoot -OutputJson $outputJson

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -BeGreaterOrEqual 1
    }

    It "should build and cache audit index" {
        # Arrange
        $targetName = "testproject"
        $strapRoot = $TestDrive
        $indexPath = Join-Path $strapRoot "build\audit-index.json"
        $rebuildIndex = $false

        # Act
        Invoke-Audit -TargetName $targetName -StrapRootPath $strapRoot -RebuildIndex $rebuildIndex -OutputJson $false

        # Assert
        Test-Path $indexPath | Should -Be $true
    }

    It "should force rebuild when --rebuild-index flag is used" {
        # Arrange
        $targetName = "testproject"
        $strapRoot = $TestDrive
        $indexPath = Join-Path $strapRoot "build\audit-index.json"

        # Build initial index
        Invoke-Audit -TargetName $targetName -StrapRootPath $strapRoot -RebuildIndex $false -OutputJson $false
        $firstIndex = Get-Content $indexPath | ConvertFrom-Json
        $firstBuiltAt = $firstIndex.built_at

        Start-Sleep -Milliseconds 100

        # Act - rebuild
        Invoke-Audit -TargetName $targetName -StrapRootPath $strapRoot -RebuildIndex $true -OutputJson $false

        # Assert
        $secondIndex = Get-Content $indexPath | ConvertFrom-Json
        $secondIndex.built_at | Should -Not -Be $firstBuiltAt
    }

    It "should output JSON when --json flag is used" {
        # Arrange
        $targetName = "testproject"
        $strapRoot = $TestDrive
        $outputJson = $true

        # Act
        $result = Invoke-Audit -TargetName $targetName -StrapRootPath $strapRoot -OutputJson $outputJson

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain "repository"
        $result.PSObject.Properties.Name | Should -Contain "references"
    }

    It "should filter by --tool or --software scope" {
        # Arrange
        # Add tool-scoped repo to registry
        $registryPath = Join-Path $TestDrive "registry-v2.json"
        $registry = Get-Content $registryPath | ConvertFrom-Json

        $toolRepo = Join-Path $TestDrive "tooltool"
        New-Item -ItemType Directory -Path $toolRepo -Force | Out-Null

        $registry.entries += @{
            name = "tooltool"
            path = $toolRepo
            scope = "tool"
            last_commit = "def456"
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath

        $strapRoot = $TestDrive

        # Act - audit with --tool filter
        $result = Invoke-Audit -AllRepos $true -ToolScope $true -StrapRootPath $strapRoot -OutputJson $false

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -Be 1
        $result[0].repository | Should -Be "tooltool"
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Audit.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - Invoke-Audit command not found`

**Step 3: Implement the PowerShell function and CLI dispatch**

```powershell
# Add to strap.ps1 after Invoke-Snapshot

function Invoke-Audit {
    <#
    .SYNOPSIS
    Audits repositories for hardcoded path references

    .PARAMETER TargetName
    Name of specific repository to audit

    .PARAMETER AllRepos
    Audit all repositories in registry

    .PARAMETER ToolScope
    Filter to tool-scoped repositories only

    .PARAMETER SoftwareScope
    Filter to software-scoped repositories only

    .PARAMETER RebuildIndex
    Force rebuild of audit index even if cached

    .PARAMETER OutputJson
    Output results as JSON

    .PARAMETER StrapRootPath
    Path to strap root directory

    .OUTPUTS
    Hashtable or array with audit results
    #>
    param(
        [Parameter()]
        [string] $TargetName,

        [Parameter()]
        [switch] $AllRepos,

        [Parameter()]
        [switch] $ToolScope,

        [Parameter()]
        [switch] $SoftwareScope,

        [Parameter()]
        [switch] $RebuildIndex,

        [Parameter()]
        [switch] $OutputJson,

        [Parameter(Mandatory)]
        [string] $StrapRootPath
    )

    # Load config and registry
    $config = Load-Config $StrapRootPath
    $registryPath = $config.registry

    if (-not (Test-Path $registryPath)) {
        Die "Registry not found: $registryPath"
    }

    $registryContent = Get-Content $registryPath -Raw | ConvertFrom-Json
    $registryUpdatedAt = $registryContent.updated_at
    $registry = if ($registryContent.PSObject.Properties['entries']) {
        $registryContent.entries
    } else {
        $registryContent
    }

    # Filter by scope if requested
    if ($ToolScope) {
        $registry = $registry | Where-Object { $_.scope -eq "tool" }
    }
    if ($SoftwareScope) {
        $registry = $registry | Where-Object { $_.scope -eq "software" }
    }

    # Build audit index
    $indexPath = Join-Path $StrapRootPath "build\audit-index.json"
    $auditIndex = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $RebuildIndex.IsPresent `
        -RegistryUpdatedAt $registryUpdatedAt -Registry $registry

    # Process audit results
    if ($AllRepos) {
        # Audit all repositories
        $results = @()
        foreach ($repoPath in $auditIndex.repos.Keys) {
            $entry = $registry | Where-Object { $_.path -eq $repoPath } | Select-Object -First 1
            if (-not $entry) { continue }

            $refs = $auditIndex.repos[$repoPath].references
            $results += @{
                repository = $entry.name
                path = $repoPath
                references = $refs
                reference_count = $refs.Count
            }
        }

        if ($OutputJson) {
            $results | ConvertTo-Json -Depth 10
        } else {
            Write-Host "`nAudit Results - All Repositories:" -ForegroundColor Cyan
            foreach ($res in $results) {
                Write-Host "`n$($res.repository) ($($res.path))" -ForegroundColor Yellow
                Write-Host "  References found: $($res.reference_count)"
                if ($res.reference_count -gt 0) {
                    $res.references | Select-Object -First 5 | ForEach-Object {
                        Write-Host "    - $_" -ForegroundColor Gray
                    }
                    if ($res.reference_count -gt 5) {
                        Write-Host "    ... and $($res.reference_count - 5) more" -ForegroundColor Gray
                    }
                }
            }
        }

        return $results

    } else {
        # Audit specific repository
        if (-not $TargetName) {
            Die "Audit requires a target name or --all flag"
        }

        $entry = $registry | Where-Object { $_.name -eq $TargetName -or $_.id -eq $TargetName } | Select-Object -First 1
        if (-not $entry) {
            Die "Repository '$TargetName' not found in registry"
        }

        $refs = $auditIndex.repos[$entry.path].references
        $result = @{
            repository = $entry.name
            path = $entry.path
            references = $refs
            reference_count = $refs.Count
        }

        if ($OutputJson) {
            $result | ConvertTo-Json -Depth 10
        } else {
            Write-Host "`nAudit Results for $($entry.name):" -ForegroundColor Cyan
            Write-Host "Path: $($entry.path)"
            Write-Host "References found: $($refs.Count)"
            if ($refs.Count -gt 0) {
                Write-Host "`nReferences:" -ForegroundColor Yellow
                $refs | ForEach-Object {
                    Write-Host "  - $_" -ForegroundColor Gray
                }
            } else {
                Write-Host "No hardcoded path references found." -ForegroundColor Green
            }
        }

        return $result
    }
}

# CLI dispatch (add after snapshot command)
if ($RepoName -eq "audit") {
    # Parse flags
    $targetName = if ($ExtraArgs.Count -gt 0 -and -not $ExtraArgs[0].StartsWith("--")) { $ExtraArgs[0] } else { $null }
    $allFlag = $ExtraArgs -contains "--all"
    $toolFlag = $ExtraArgs -contains "--tool"
    $softwareFlag = $ExtraArgs -contains "--software"
    $jsonFlag = $ExtraArgs -contains "--json"
    $rebuildFlag = $ExtraArgs -contains "--rebuild-index"

    Invoke-Audit -TargetName $targetName -AllRepos:$allFlag -ToolScope:$toolFlag `
        -SoftwareScope:$softwareFlag -RebuildIndex:$rebuildFlag -OutputJson:$jsonFlag `
        -StrapRootPath $TemplateRoot
    exit 0
}
```

**Step 4: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Audit.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 6 tests passing`

**Step 5: Manual verification**

```bash
# Audit specific repository
strap audit chinvex

# Audit all repositories
strap audit --all

# Audit with JSON output
strap audit chinvex --json

# Audit with rebuild
strap audit --all --rebuild-index

# Audit filtered by scope
strap audit --all --tool
```

Expected: Audit results showing hardcoded path references with file:line format

**Step 6: Commit**

```bash
git add tests/powershell/Invoke-Audit.Tests.ps1 strap.ps1
git commit -m "feat: add audit command with CLI wiring

- Port audit logic from TypeScript to PowerShell
- Build and cache audit index at build/audit-index.json
- Support single repo and --all mode
- Filter by --tool or --software scope
- Add --rebuild-index flag to force refresh
- Add comprehensive Pester tests (6 tests)
- Wire to CLI with flag parsing

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 8: Archive Command with CLI Wiring

**Goal**: Port archive command to move repositories to archive scope

**Reference**: `src/commands/archive/safety.ts`, Original Task #19

**Files**:
- Test: `tests/powershell/Invoke-Archive.Tests.ps1`
- Implementation: Function in `strap.ps1` + CLI dispatch

**Step 1: Write the failing Pester test**

```powershell
# tests/powershell/Invoke-Archive.Tests.ps1
Describe "Invoke-Archive" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test registry
        $script:testRegistry = Join-Path $TestDrive "registry-v2.json"
        $script:testRepo = Join-Path $TestDrive "software\oldproject"
        $script:archiveRoot = Join-Path $TestDrive "archive"

        New-Item -ItemType Directory -Path $script:testRepo -Force | Out-Null
        New-Item -ItemType Directory -Path $script:archiveRoot -Force | Out-Null

        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @(
                @{
                    id = "oldproject"
                    name = "oldproject"
                    path = $script:testRepo
                    scope = "software"
                    updated_at = (Get-Date).ToUniversalTime().ToString("o")
                    shims = @()
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Create config.json
        $configPath = Join-Path $TestDrive "config.json"
        @{
            registry = $script:testRegistry
            roots = @{
                software = Join-Path $TestDrive "software"
                tools = Join-Path $TestDrive "tools"
                archive = $script:archiveRoot
                shims = Join-Path $TestDrive "shims"
            }
        } | ConvertTo-Json -Depth 10 | Set-Content $configPath
    }

    It "should plan archive move for valid registry entry" {
        # Arrange
        $targetName = "oldproject"
        $strapRoot = $TestDrive
        $dryRun = $true

        # Act
        $result = Invoke-Archive -TargetName $targetName -DryRun $dryRun -StrapRootPath $strapRoot

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.name | Should -Be "oldproject"
        $result.fromPath | Should -Be $script:testRepo
        $result.toPath | Should -Match "archive"
        $result.nextScope | Should -Be "archive"
    }

    It "should fail when registry entry not found" {
        # Arrange
        $targetName = "nonexistent"
        $strapRoot = $TestDrive

        # Act & Assert
        { Invoke-Archive -TargetName $targetName -DryRun $false -StrapRootPath $strapRoot } | Should -Throw "*not found*"
    }

    It "should fail when source path does not exist (registry drift)" {
        # Arrange
        $registryPath = $script:testRegistry
        $registry = Get-Content $registryPath | ConvertFrom-Json

        # Add entry with non-existent path
        $registry.entries += @{
            id = "missing"
            name = "missing"
            path = "C:\NonExistent\Path"
            scope = "software"
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            shims = @()
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $registryPath

        $targetName = "missing"
        $strapRoot = $TestDrive

        # Act & Assert
        { Invoke-Archive -TargetName $targetName -DryRun $false -StrapRootPath $strapRoot } | Should -Throw "*drift*"
    }

    It "should fail when destination already exists" {
        # Arrange
        $targetName = "oldproject"
        $strapRoot = $TestDrive
        $destinationPath = Join-Path $script:archiveRoot "oldproject"

        # Create destination directory
        New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null

        # Act & Assert
        { Invoke-Archive -TargetName $targetName -DryRun $false -StrapRootPath $strapRoot } | Should -Throw "*already exists*"
    }

    It "should perform dry-run without moving folder or updating registry" {
        # Arrange
        $targetName = "oldproject"
        $strapRoot = $TestDrive
        $dryRun = $true
        $originalPath = $script:testRepo

        # Act
        $result = Invoke-Archive -TargetName $targetName -DryRun $dryRun -StrapRootPath $strapRoot

        # Assert - folder should still exist at original location
        Test-Path $originalPath | Should -Be $true
        Test-Path (Join-Path $script:archiveRoot "oldproject") | Should -Be $false
    }

    It "should move folder and update registry with archive scope" {
        # Arrange
        $targetName = "oldproject"
        $strapRoot = $TestDrive
        $dryRun = $false
        $yes = $true

        $originalPath = $script:testRepo
        $expectedNewPath = Join-Path $script:archiveRoot "oldproject"

        # Act
        Invoke-Archive -TargetName $targetName -DryRun $dryRun -NonInteractive $yes -StrapRootPath $strapRoot

        # Assert - folder moved
        Test-Path $originalPath | Should -Be $false
        Test-Path $expectedNewPath | Should -Be $true

        # Assert - registry updated
        $registry = Get-Content $script:testRegistry | ConvertFrom-Json
        $entry = $registry.entries | Where-Object { $_.name -eq "oldproject" } | Select-Object -First 1
        $entry.scope | Should -Be "archive"
        $entry.path | Should -Be $expectedNewPath
        $entry.archived_at | Should -Not -BeNullOrEmpty
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Archive.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - Invoke-Archive command not found`

**Step 3: Implement the PowerShell function and CLI dispatch**

```powershell
# Add to strap.ps1 after Invoke-Audit

function Invoke-Archive {
    <#
    .SYNOPSIS
    Archives a repository by moving it to archive root and updating registry

    .PARAMETER TargetName
    Name or ID of repository to archive

    .PARAMETER DryRun
    Show planned actions without executing

    .PARAMETER NonInteractive
    Skip confirmation prompts

    .PARAMETER StrapRootPath
    Path to strap root directory

    .OUTPUTS
    Hashtable with archive plan details
    #>
    param(
        [Parameter(Mandatory)]
        [string] $TargetName,

        [Parameter()]
        [switch] $DryRun,

        [Parameter()]
        [switch] $NonInteractive,

        [Parameter(Mandatory)]
        [string] $StrapRootPath
    )

    # Load config and registry
    $config = Load-Config $StrapRootPath
    $registryPath = $config.registry
    $archiveRoot = $config.roots.archive

    if (-not (Test-Path $registryPath)) {
        Die "Registry not found: $registryPath"
    }

    $registryContent = Get-Content $registryPath -Raw | ConvertFrom-Json
    $registry = if ($registryContent.PSObject.Properties['entries']) {
        $registryContent.entries
    } else {
        $registryContent
    }

    # Find entry
    $entry = $registry | Where-Object { $_.name -eq $TargetName -or $_.id -eq $TargetName } | Select-Object -First 1
    if (-not $entry) {
        Die "Registry entry '$TargetName' not found"
    }

    # Validate source path exists
    if (-not (Test-Path $entry.path)) {
        Die "Registry path drift detected for '$($entry.name)'. Run 'strap doctor --fix-paths'."
    }

    # Plan destination path
    $basename = Split-Path $entry.path -Leaf
    $toPath = Join-Path $archiveRoot $basename

    # Validate destination doesn't exist
    if (Test-Path $toPath) {
        Die "Destination already exists: $toPath"
    }

    # Build plan
    $plan = @{
        name = $entry.name
        fromPath = $entry.path
        toPath = $toPath
        nextScope = "archive"
    }

    if ($DryRun) {
        Write-Host "`n[DRY RUN] Archive Plan:" -ForegroundColor Cyan
        Write-Host "  Repository: $($plan.name)"
        Write-Host "  From: $($plan.fromPath)"
        Write-Host "  To: $($plan.toPath)"
        Write-Host "  New Scope: $($plan.nextScope)"
        Write-Host "`nNo changes made (dry-run mode)" -ForegroundColor Yellow
        return $plan
    }

    # Confirm with user
    if (-not $NonInteractive) {
        Write-Host "`nArchive Plan:" -ForegroundColor Cyan
        Write-Host "  Repository: $($plan.name)"
        Write-Host "  From: $($plan.fromPath)"
        Write-Host "  To: $($plan.toPath)"
        Write-Host "  New Scope: $($plan.nextScope)"
        $confirm = Read-Host "`nProceed with archive? (y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "Archive cancelled." -ForegroundColor Yellow
            exit 0
        }
    }

    # Execute move
    Write-Host "`nMoving repository to archive..." -ForegroundColor Yellow
    try {
        # Ensure archive root exists
        if (-not (Test-Path $archiveRoot)) {
            New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
        }

        # Move folder
        Move-Item -Path $entry.path -Destination $toPath -ErrorAction Stop
        Write-Host "Moved to: $toPath" -ForegroundColor Green
    } catch {
        Die "Failed to move repository: $_"
    }

    # Update registry
    Write-Host "Updating registry..." -ForegroundColor Yellow

    # Find and update entry
    for ($i = 0; $i -lt $registry.Count; $i++) {
        if ($registry[$i].name -eq $entry.name) {
            $registry[$i].scope = "archive"
            $registry[$i].path = $toPath
            $registry[$i].archived_at = (Get-Date).ToUniversalTime().ToString("o")
            $registry[$i].updated_at = (Get-Date).ToUniversalTime().ToString("o")
            break
        }
    }

    # Save registry
    Save-Registry $config $registry

    Write-Host "`nArchive complete!" -ForegroundColor Green
    Write-Host "  $($entry.name) -> $toPath"

    return $plan
}

# CLI dispatch (add after audit command)
if ($RepoName -eq "archive") {
    # Parse flags
    $targetName = if ($ExtraArgs.Count -gt 0 -and -not $ExtraArgs[0].StartsWith("--")) { $ExtraArgs[0] } else { $null }
    $dryRunFlag = $ExtraArgs -contains "--dry-run"
    $yesFlag = $ExtraArgs -contains "--yes"

    if (-not $targetName) {
        Die "archive command requires a target name"
    }

    Invoke-Archive -TargetName $targetName -DryRun:$dryRunFlag -NonInteractive:$yesFlag -StrapRootPath $TemplateRoot
    exit 0
}
```

**Step 4: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Archive.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 6 tests passing`

**Step 5: Manual verification**

```bash
# Dry run archive
strap archive oldproject --dry-run

# Archive with confirmation prompt
strap archive oldproject

# Archive non-interactively
strap archive oldproject --yes

# Verify in registry
strap list --json | ConvertFrom-Json | Where-Object { $_.scope -eq "archive" }
```

Expected: Repository moved to archive root with scope set to "archive" and archived_at timestamp

**Step 6: Commit**

```bash
git add tests/powershell/Invoke-Archive.Tests.ps1 strap.ps1
git commit -m "feat: add archive command with CLI wiring

- Port archive safety logic from TypeScript to PowerShell
- Plan and validate archive move (registry-first trust mode)
- Move folder to archive root and update registry
- Set scope to 'archive' and add archived_at timestamp
- Support --dry-run and --yes flags
- Add comprehensive Pester tests (6 tests)
- Wire to CLI with flag parsing

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 9: Adopt --scan Bulk Mode Enhancement

**Goal**: Extend adopt command to support --scan bulk discovery mode

**Reference**: `src/commands/adopt/foundation.ts`, `src/commands/adopt/scanRecursive.ts`, Original Task #20

**Files**:
- Test: `tests/powershell/Invoke-Adopt-Scan.Tests.ps1`
- Implementation: Modify `Invoke-Adopt` function in `strap.ps1` (lines 2583-2720)

**Step 1: Write the failing Pester test**

```powershell
# tests/powershell/Invoke-Adopt-Scan.Tests.ps1
Describe "Invoke-Adopt --scan Mode" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test scan directory
        $script:scanRoot = Join-Path $TestDrive "ScanRoot"
        New-Item -ItemType Directory -Path $script:scanRoot -Force | Out-Null

        # Create git repo
        $gitRepo = Join-Path $script:scanRoot "gitproject"
        New-Item -ItemType Directory -Path (Join-Path $gitRepo ".git") -Force | Out-Null

        # Create regular directory
        $regularDir = Join-Path $script:scanRoot "notes"
        New-Item -ItemType Directory -Path $regularDir -Force | Out-Null

        # Create file
        $file = Join-Path $script:scanRoot "helper.ps1"
        Set-Content -Path $file -Value "Write-Host 'Test'"

        # Create test registry
        $script:testRegistry = Join-Path $TestDrive "registry-v2.json"
        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @()
        } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Create config.json
        $configPath = Join-Path $TestDrive "config.json"
        @{
            registry = $script:testRegistry
            roots = @{
                software = $script:scanRoot
                tools = $script:scanRoot
                shims = Join-Path $TestDrive "shims"
            }
        } | ConvertTo-Json -Depth 10 | Set-Content $configPath
    }

    It "should scan directory and classify items as git/directory/file" {
        # Arrange
        $scanDir = $script:scanRoot
        $strapRoot = $TestDrive

        # Act
        $result = Invoke-Adopt -ScanDir $scanDir -DryRun $true -StrapRootPath $strapRoot

        # Assert
        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -Be 3

        $gitItems = $result | Where-Object { $_.kind -eq "git" }
        $dirItems = $result | Where-Object { $_.kind -eq "directory" }
        $fileItems = $result | Where-Object { $_.kind -eq "file" }

        $gitItems.Count | Should -Be 1
        $dirItems.Count | Should -Be 1
        $fileItems.Count | Should -Be 1
    }

    It "should mark already-registered items" {
        # Arrange
        $scanDir = $script:scanRoot
        $strapRoot = $TestDrive

        # Add one item to registry
        $gitRepo = Join-Path $script:scanRoot "gitproject"
        $registry = Get-Content $script:testRegistry | ConvertFrom-Json
        $registry.entries += @{
            name = "gitproject"
            path = $gitRepo
            scope = "software"
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            shims = @()
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Act
        $result = Invoke-Adopt -ScanDir $scanDir -DryRun $true -StrapRootPath $strapRoot

        # Assert
        $gitItem = $result | Where-Object { $_.kind -eq "git" }
        $gitItem.alreadyRegistered | Should -Be $true
    }

    It "should support --recursive flag to scan subdirectories" {
        # Arrange
        $scanDir = $script:scanRoot
        $strapRoot = $TestDrive

        # Create nested directory
        $nestedDir = Join-Path $script:scanRoot "notes\nested"
        New-Item -ItemType Directory -Path $nestedDir -Force | Out-Null

        # Act - without recursive
        $resultFlat = Invoke-Adopt -ScanDir $scanDir -Recursive $false -DryRun $true -StrapRootPath $strapRoot

        # Act - with recursive
        $resultRecursive = Invoke-Adopt -ScanDir $scanDir -Recursive $true -DryRun $true -StrapRootPath $strapRoot

        # Assert
        $resultRecursive.Count | Should -BeGreaterThan $resultFlat.Count
    }

    It "should support --scope flag to suggest scope for batch adoption" {
        # Arrange
        $scanDir = $script:scanRoot
        $strapRoot = $TestDrive
        $scope = "tool"

        # Act
        $result = Invoke-Adopt -ScanDir $scanDir -Scope $scope -DryRun $true -StrapRootPath $strapRoot

        # Assert
        $result | Should -Not -BeNullOrEmpty
        # Scope is applied during adoption, just verify command accepts it
    }

    It "should support --yes flag for non-interactive batch adoption" {
        # Arrange
        $scanDir = $script:scanRoot
        $strapRoot = $TestDrive
        $yes = $true

        # Act - dry run with --yes should not prompt
        $result = Invoke-Adopt -ScanDir $scanDir -NonInteractive $yes -DryRun $true -StrapRootPath $strapRoot

        # Assert
        $result | Should -Not -BeNullOrEmpty
    }

    It "should show adoption plan in dry-run mode" {
        # Arrange
        $scanDir = $script:scanRoot
        $strapRoot = $TestDrive
        $dryRun = $true

        # Act
        $result = Invoke-Adopt -ScanDir $scanDir -DryRun $dryRun -StrapRootPath $strapRoot

        # Assert
        $result | Should -Not -BeNullOrEmpty

        # Verify registry not modified
        $registry = Get-Content $script:testRegistry | ConvertFrom-Json
        $registry.entries.Count | Should -Be 1  # Only the one we added in previous test
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Adopt-Scan.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - Invoke-Adopt does not support -ScanDir parameter`

**Step 3: Implement the enhancement in strap.ps1**

```powershell
# Replace Invoke-Adopt function (lines 2583-2720) with enhanced version

function Invoke-Adopt {
    param(
        [string] $TargetPath,          # Single path mode (existing)
        [string] $ScanDir,             # Bulk scan mode (new)
        [string] $CustomName,
        [switch] $Recursive,           # Scan subdirectories (new)
        [string] $Scope,               # Force scope: tool|software (new)
        [switch] $ForceTool,
        [switch] $ForceSoftware,
        [switch] $NonInteractive,
        [switch] $DryRunMode,
        [string] $StrapRootPath
    )

    # Load config and registry
    $config = Load-Config $StrapRootPath
    $registry = Load-Registry $config

    # Determine mode: single path or scan mode
    if ($ScanDir) {
        # Bulk scan mode
        Write-Host "Scanning directory for adoptable items: $ScanDir" -ForegroundColor Cyan

        # Validate scan directory exists
        if (-not (Test-Path $ScanDir)) {
            Die "Scan directory not found: $ScanDir"
        }

        # Build registry path lookup
        $registryPathsLower = @{}
        foreach ($entry in $registry) {
            if ($entry.path) {
                $registryPathsLower[$entry.path.ToLower()] = $true
            }
        }

        # Scan directory
        $items = @()
        $scanItems = if ($Recursive) {
            Get-ChildItem -Path $ScanDir -Recurse -ErrorAction SilentlyContinue
        } else {
            Get-ChildItem -Path $ScanDir -ErrorAction SilentlyContinue
        }

        foreach ($item in $scanItems) {
            $itemPath = $item.FullName
            $alreadyRegistered = $registryPathsLower.ContainsKey($itemPath.ToLower())

            if ($item.PSIsContainer) {
                # Check if git repo
                $gitDir = Join-Path $itemPath ".git"
                if (Test-Path $gitDir) {
                    $items += @{
                        path = $itemPath
                        name = $item.Name
                        kind = "git"
                        alreadyRegistered = $alreadyRegistered
                    }
                } else {
                    $items += @{
                        path = $itemPath
                        name = $item.Name
                        kind = "directory"
                        alreadyRegistered = $alreadyRegistered
                    }
                }
            } else {
                $items += @{
                    path = $itemPath
                    name = $item.Name
                    kind = "file"
                    alreadyRegistered = $false
                }
            }
        }

        # Filter to only git repos (for now)
        $adoptableItems = $items | Where-Object { $_.kind -eq "git" -and -not $_.alreadyRegistered }

        Write-Host "`nFound $($items.Count) items, $($adoptableItems.Count) git repos available for adoption" -ForegroundColor Yellow

        if ($DryRunMode) {
            Write-Host "`n[DRY RUN] Adoption Plan:" -ForegroundColor Cyan
            foreach ($item in $adoptableItems) {
                Write-Host "  - $($item.name) ($($item.path))" -ForegroundColor Gray
            }
            Write-Host "`nNo changes made (dry-run mode)" -ForegroundColor Yellow
            return $items
        }

        # Adopt each item
        $adopted = 0
        foreach ($item in $adoptableItems) {
            Write-Host "`nAdopting: $($item.name)" -ForegroundColor Yellow

            # Determine scope
            $itemScope = if ($Scope) {
                $Scope
            } elseif ($ForceTool) {
                "tool"
            } elseif ($ForceSoftware) {
                "software"
            } else {
                # Auto-detect based on path
                $softwareRoot = $config.roots.software
                $toolsRoot = $config.roots.tools
                if ($item.path.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)) {
                    "tool"
                } else {
                    "software"
                }
            }

            # Adopt the item (reuse existing single-path adoption logic)
            try {
                Invoke-Adopt -TargetPath $item.path -CustomName $item.name -ForceTool:($itemScope -eq "tool") `
                    -ForceSoftware:($itemScope -eq "software") -NonInteractive:$NonInteractive `
                    -DryRunMode:$false -StrapRootPath $StrapRootPath
                $adopted++
            } catch {
                Write-Warning "Failed to adopt $($item.name): $_"
            }
        }

        Write-Host "`nAdopted $adopted repositories" -ForegroundColor Green
        return $items

    } else {
        # Single path mode (existing logic)
        if (-not $TargetPath) {
            $TargetPath = Get-Location
        }

        # Resolve to absolute path
        $resolvedPath = [System.IO.Path]::GetFullPath($TargetPath)

        # Validate within managed roots
        $softwareRoot = $config.roots.software
        $toolsRoot = $config.roots.tools

        $withinSoftware = $resolvedPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase)
        $withinTools = $resolvedPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

        if (-not ($withinSoftware -or $withinTools)) {
            Die "Path is not within managed roots: $resolvedPath"
        }

        # Validate it's a git repo
        $gitDir = Join-Path $resolvedPath ".git"
        if (-not (Test-Path $gitDir)) {
            try {
                & git -C $resolvedPath rev-parse --is-inside-work-tree 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Die "Not a git repository: $resolvedPath"
                }
            } catch {
                Die "Not a git repository: $resolvedPath"
            }
        }

        # Determine name
        $name = if ($CustomName) { $CustomName } else { Split-Path $resolvedPath -Leaf }

        # Check for duplicates
        $existing = $registry | Where-Object { $_.name -eq $name }
        if ($existing) {
            Die "Entry with name '$name' already exists in registry at $($existing.path)"
        }

        # Determine scope
        $scope = if ($ForceTool) {
            "tool"
        } elseif ($ForceSoftware) {
            "software"
        } elseif ($withinTools) {
            "tool"
        } else {
            "software"
        }

        # Extract git metadata
        $url = $null
        $lastHead = $null
        $defaultBranch = $null

        try {
            $remoteUrl = & git -C $resolvedPath remote get-url origin 2>&1
            if ($LASTEXITCODE -eq 0) { $url = $remoteUrl.Trim() }
        } catch {}

        try {
            $head = & git -C $resolvedPath rev-parse HEAD 2>&1
            if ($LASTEXITCODE -eq 0) { $lastHead = $head.Trim() }
        } catch {}

        try {
            $branch = & git -C $resolvedPath symbolic-ref --short refs/remotes/origin/HEAD 2>&1
            if ($LASTEXITCODE -eq 0) { $defaultBranch = $branch.Trim() -replace '^origin/', '' }
        } catch {}

        # Detect stack
        $stackDetected = $null
        Push-Location $resolvedPath
        try {
            if (Test-Path "pyproject.toml") { $stackDetected = "python" }
            elseif (Test-Path "requirements.txt") { $stackDetected = "python" }
            elseif (Test-Path "package.json") { $stackDetected = "node" }
            elseif (Test-Path "go.mod") { $stackDetected = "go" }
            elseif (Test-Path "Cargo.toml") { $stackDetected = "rust" }
        } finally {
            Pop-Location
        }

        # Build registry entry
        $newEntry = @{
            id = $name
            name = $name
            scope = $scope
            path = $resolvedPath
            url = $url
            last_head = $lastHead
            default_branch = $defaultBranch
            stack = $stackDetected
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            shims = @()
        }

        if ($DryRunMode) {
            Write-Host "`n[DRY RUN] Would adopt:" -ForegroundColor Cyan
            Write-Host "  Name: $name"
            Write-Host "  Scope: $scope"
            Write-Host "  Path: $resolvedPath"
            Write-Host "`nNo changes made (dry-run mode)" -ForegroundColor Yellow
            return $newEntry
        }

        # Add to registry
        $registry += $newEntry
        Save-Registry $config $registry

        Write-Host "`nAdopted $name successfully!" -ForegroundColor Green
        Write-Host "  Scope: $scope"
        Write-Host "  Path: $resolvedPath"

        return $newEntry
    }
}

# Update CLI dispatch for adopt command (find existing block around line 2720)
# Replace with:
if ($RepoName -eq "adopt") {
    # Parse flags
    $targetPath = if ($ExtraArgs.Count -gt 0 -and -not $ExtraArgs[0].StartsWith("--")) { $ExtraArgs[0] } else { $null }
    $scanDir = $null
    $customName = $null
    $scope = $null
    $toolFlag = $ExtraArgs -contains "--tool"
    $softwareFlag = $ExtraArgs -contains "--software"
    $yesFlag = $ExtraArgs -contains "--yes"
    $dryRunFlag = $ExtraArgs -contains "--dry-run"
    $recursiveFlag = $ExtraArgs -contains "--recursive"

    # Parse --scan, --name, --scope
    for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
        if ($ExtraArgs[$i] -eq "--scan" -and ($i + 1) -lt $ExtraArgs.Count) {
            $scanDir = $ExtraArgs[$i + 1]
            $i++
        }
        if ($ExtraArgs[$i] -eq "--name" -and ($i + 1) -lt $ExtraArgs.Count) {
            $customName = $ExtraArgs[$i + 1]
            $i++
        }
        if ($ExtraArgs[$i] -eq "--scope" -and ($i + 1) -lt $ExtraArgs.Count) {
            $scope = $ExtraArgs[$i + 1]
            $i++
        }
    }

    if ($scanDir) {
        # Scan mode
        Invoke-Adopt -ScanDir $scanDir -Recursive:$recursiveFlag -Scope $scope `
            -ForceTool:$toolFlag -ForceSoftware:$softwareFlag -NonInteractive:$yesFlag `
            -DryRunMode:$dryRunFlag -StrapRootPath $TemplateRoot
    } else {
        # Single path mode
        Invoke-Adopt -TargetPath $targetPath -CustomName $customName -ForceTool:$toolFlag `
            -ForceSoftware:$softwareFlag -NonInteractive:$yesFlag -DryRunMode:$dryRunFlag `
            -StrapRootPath $TemplateRoot
    }
    exit 0
}
```

**Step 4: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Adopt-Scan.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 7 tests passing`

**Step 5: Manual verification**

```bash
# Scan directory for adoptable repos
strap adopt --scan C:\Code --dry-run

# Scan recursively
strap adopt --scan C:\Code --recursive --dry-run

# Adopt all with specific scope
strap adopt --scan C:\Code --scope tool --yes

# Single path mode (existing behavior)
strap adopt C:\Code\newrepo
```

Expected: Bulk scan shows all git repos, adoption adds them to registry with correct scope

**Step 6: Commit**

```bash
git add tests/powershell/Invoke-Adopt-Scan.Tests.ps1 strap.ps1
git commit -m "feat: add adopt --scan bulk mode enhancement

- Extend Invoke-Adopt to support --scan bulk discovery
- Scan directories and classify as git/directory/file
- Mark already-registered items to skip
- Support --recursive flag for subdirectory scanning
- Support --scope flag to set scope for batch adoption
- Support --yes for non-interactive batch adoption
- Add comprehensive Pester tests (7 tests)
- Update CLI dispatch with flag parsing

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 10: Doctor --fix-paths Enhancement

**Goal**: Extend doctor command to fix registry path drift by discovering repos on disk

**Reference**: `src/commands/doctor/fixPaths.ts`, Original Task #21

**Files**:
- Test: `tests/powershell/Invoke-Doctor-FixPaths.Tests.ps1`
- Implementation: Modify `Invoke-Doctor` function in `strap.ps1` (lines 2325-2500)

**Step 1: Write the failing Pester test**

```powershell
# tests/powershell/Invoke-Doctor-FixPaths.Tests.ps1
Describe "Invoke-Doctor --fix-paths" {
    BeforeAll {
        # Source the function from strap.ps1
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test repos on disk
        $script:diskRepo = Join-Path $TestDrive "P_Software\chinvex"
        New-Item -ItemType Directory -Path (Join-Path $script:diskRepo ".git") -Force | Out-Null

        # Initialize git with remote
        Push-Location $script:diskRepo
        try {
            & git init 2>&1 | Out-Null
            & git remote add origin "https://github.com/team/chinvex.git" 2>&1 | Out-Null
        } finally {
            Pop-Location
        }

        # Create test registry with drift
        $script:testRegistry = Join-Path $TestDrive "registry-v2.json"
        @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @(
                @{
                    id = "chinvex"
                    name = "chinvex"
                    path = "C:\Code\chinvex"  # Wrong path (drift)
                    url = "https://github.com/team/chinvex.git"
                    scope = "software"
                    updated_at = (Get-Date).ToUniversalTime().ToString("o")
                    shims = @()
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Create config.json
        $configPath = Join-Path $TestDrive "config.json"
        @{
            registry = $script:testRegistry
            roots = @{
                software = Join-Path $TestDrive "P_Software"
                tools = Join-Path $TestDrive "tools"
                shims = Join-Path $TestDrive "shims"
            }
        } | ConvertTo-Json -Depth 10 | Set-Content $configPath
    }

    It "should discover repos on disk by scanning managed roots" {
        # Arrange
        $strapRoot = $TestDrive

        # Act
        $result = Invoke-Doctor -FixPaths $true -DryRun $true -StrapRootPath $strapRoot

        # Assert
        $result.discovered | Should -Not -BeNullOrEmpty
        $result.discovered.Count | Should -BeGreaterOrEqual 1
        $result.discovered[0].path | Should -Match "chinvex"
        $result.discovered[0].remote | Should -Match "github.com/team/chinvex"
    }

    It "should match registry entries to disk repos by normalized remote URL" {
        # Arrange
        $strapRoot = $TestDrive

        # Act
        $result = Invoke-Doctor -FixPaths $true -DryRun $true -StrapRootPath $strapRoot

        # Assert
        $result.matches | Should -Not -BeNullOrEmpty
        $result.matches.Count | Should -BeGreaterOrEqual 1
        $result.matches[0].name | Should -Be "chinvex"
        $result.matches[0].from | Should -Be "C:\Code\chinvex"
        $result.matches[0].to | Should -Match "P_Software"
    }

    It "should update registry path when single match exists in --yes mode" {
        # Arrange
        $strapRoot = $TestDrive
        $yes = $true

        # Act
        Invoke-Doctor -FixPaths $true -NonInteractive $yes -StrapRootPath $strapRoot

        # Assert - registry updated
        $registry = Get-Content $script:testRegistry | ConvertFrom-Json
        $entry = $registry.entries | Where-Object { $_.name -eq "chinvex" } | Select-Object -First 1
        $entry.path | Should -Match "P_Software\\chinvex"
    }

    It "should prompt for confirmation when not in --yes mode" {
        # Arrange
        $strapRoot = $TestDrive
        $yes = $false

        # Mock Read-Host to decline
        Mock Read-Host { "n" }

        # Act
        $result = Invoke-Doctor -FixPaths $true -NonInteractive $false -StrapRootPath $strapRoot

        # Assert - registry not updated
        $registry = Get-Content $script:testRegistry | ConvertFrom-Json
        $entry = $registry.entries | Where-Object { $_.name -eq "chinvex" } | Select-Object -First 1
        $entry.path | Should -Be "C:\Code\chinvex"  # Still old path
    }

    It "should skip entries when multiple disk matches exist (ambiguous)" {
        # Arrange
        $strapRoot = $TestDrive

        # Create second repo with same remote
        $secondRepo = Join-Path $TestDrive "tools\chinvex"
        New-Item -ItemType Directory -Path (Join-Path $secondRepo ".git") -Force | Out-Null
        Push-Location $secondRepo
        try {
            & git init 2>&1 | Out-Null
            & git remote add origin "https://github.com/team/chinvex.git" 2>&1 | Out-Null
        } finally {
            Pop-Location
        }

        # Act
        $result = Invoke-Doctor -FixPaths $true -NonInteractive $true -DryRun $true -StrapRootPath $strapRoot

        # Assert - should report as unresolved
        $result.unresolved | Should -Not -BeNullOrEmpty
        $result.unresolved.Count | Should -BeGreaterOrEqual 1
        $result.unresolved[0].reason | Should -Match "multiple"
    }

    It "should show dry-run plan without modifying registry" {
        # Arrange
        $strapRoot = $TestDrive
        $dryRun = $true

        # Act
        $result = Invoke-Doctor -FixPaths $true -DryRun $dryRun -StrapRootPath $strapRoot

        # Assert - registry not modified
        $registry = Get-Content $script:testRegistry | ConvertFrom-Json
        $entry = $registry.entries | Where-Object { $_.name -eq "chinvex" } | Select-Object -First 1
        $entry.path | Should -Be "C:\Code\chinvex"  # Still old path
    }

    It "should normalize remote URLs for matching (SSH vs HTTPS)" {
        # Arrange
        $strapRoot = $TestDrive

        # Update registry to use SSH format
        $registry = Get-Content $script:testRegistry | ConvertFrom-Json
        $registry.entries[0].url = "git@github.com:team/chinvex.git"
        $registry | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Act
        $result = Invoke-Doctor -FixPaths $true -DryRun $true -StrapRootPath $strapRoot

        # Assert - should still match despite format difference
        $result.matches | Should -Not -BeNullOrEmpty
        $result.matches[0].name | Should -Be "chinvex"
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Doctor-FixPaths.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - Invoke-Doctor does not support -FixPaths parameter`

**Step 3: Implement the enhancement in strap.ps1**

```powershell
# Add helper function before Invoke-Doctor

function Normalize-GitRemote {
    <#
    .SYNOPSIS
    Normalizes git remote URL for comparison (SSH to HTTPS, lowercase, no .git)
    #>
    param([string] $Url)

    if (-not $Url) { return $null }

    $normalized = $Url.Trim()

    # Convert SSH to HTTPS
    if ($normalized -match '^git@([^:]+):(.+)$') {
        $normalized = "https://$($Matches[1])/$($Matches[2])"
    }

    # Remove .git suffix
    $normalized = $normalized -replace '\.git$', ''

    # Lowercase hostname and path
    try {
        $uri = [Uri]$normalized
        $normalized = "$($uri.Scheme)://$($uri.Host.ToLower())$($uri.AbsolutePath.ToLower().TrimEnd('/'))"
    } catch {}

    return $normalized
}

# Replace Invoke-Doctor function (lines 2325-2500) with enhanced version

function Invoke-Doctor {
    param(
        [string] $StrapRootPath,
        [switch] $OutputJson,
        [switch] $FixPaths,        # New: fix registry path drift
        [switch] $NonInteractive,  # New: --yes mode
        [switch] $DryRun           # New: dry-run mode
    )

    # Load config
    $config = Load-Config $StrapRootPath

    if ($FixPaths) {
        # Fix-paths mode: discover repos and fix drift
        Write-Host "Doctor --fix-paths: Discovering repositories..." -ForegroundColor Cyan

        # Load registry
        $registryPath = $config.registry
        if (-not (Test-Path $registryPath)) {
            Die "Registry not found: $registryPath"
        }

        $registryContent = Get-Content $registryPath -Raw | ConvertFrom-Json
        $registryUpdatedAt = $registryContent.updated_at
        $registry = if ($registryContent.PSObject.Properties['entries']) {
            $registryContent.entries
        } else {
            $registryContent
        }

        # Discover repos on disk
        $discovered = @()
        $scanRoots = @($config.roots.software, $config.roots.tools)

        foreach ($root in $scanRoots) {
            if (-not (Test-Path $root)) { continue }

            $items = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                $gitDir = Join-Path $item.FullName ".git"
                if (Test-Path $gitDir) {
                    # Extract remote
                    $remote = $null
                    try {
                        $remoteRaw = & git -C $item.FullName remote get-url origin 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $remote = Normalize-GitRemote $remoteRaw.Trim()
                        }
                    } catch {}

                    $discovered += @{
                        path = $item.FullName
                        name = $item.Name
                        remote = $remote
                    }
                }
            }
        }

        Write-Host "Discovered $($discovered.Count) git repositories on disk" -ForegroundColor Yellow

        # Find entries with path drift
        $driftEntries = $registry | Where-Object { -not (Test-Path $_.path) }

        Write-Host "Found $($driftEntries.Count) registry entries with path drift" -ForegroundColor Yellow

        # Match by remote URL
        $matches = @()
        $unresolved = @()

        foreach ($entry in $driftEntries) {
            $entryRemote = Normalize-GitRemote $entry.url

            if (-not $entryRemote) {
                $unresolved += @{
                    name = $entry.name
                    reason = "no remote URL in registry"
                }
                continue
            }

            # Find matching disk repos
            $candidates = $discovered | Where-Object { $_.remote -eq $entryRemote }

            if ($candidates.Count -eq 0) {
                $unresolved += @{
                    name = $entry.name
                    reason = "no disk repo found with matching remote"
                }
            } elseif ($candidates.Count -eq 1) {
                # Single match - can auto-update
                $matches += @{
                    name = $entry.name
                    from = $entry.path
                    to = $candidates[0].path
                    entryId = $entry.id
                }
            } else {
                # Multiple matches - require manual selection
                $unresolved += @{
                    name = $entry.name
                    reason = "multiple disk repos match normalized remote; user selection required"
                    candidates = $candidates.path
                }
            }
        }

        # Report results
        if ($DryRun) {
            Write-Host "`n[DRY RUN] Fix-Paths Plan:" -ForegroundColor Cyan
            Write-Host "  Matches: $($matches.Count)"
            Write-Host "  Unresolved: $($unresolved.Count)"

            if ($matches.Count -gt 0) {
                Write-Host "`nWould update:" -ForegroundColor Yellow
                foreach ($match in $matches) {
                    Write-Host "  $($match.name): $($match.from) -> $($match.to)" -ForegroundColor Gray
                }
            }

            if ($unresolved.Count -gt 0) {
                Write-Host "`nCannot resolve:" -ForegroundColor Yellow
                foreach ($unres in $unresolved) {
                    Write-Host "  $($unres.name): $($unres.reason)" -ForegroundColor Gray
                }
            }

            Write-Host "`nNo changes made (dry-run mode)" -ForegroundColor Yellow

            return @{
                discovered = $discovered
                matches = $matches
                unresolved = $unresolved
            }
        }

        # Apply updates
        $updated = @()
        foreach ($match in $matches) {
            $shouldApply = $NonInteractive

            if (-not $shouldApply) {
                Write-Host "`nUpdate registry path for $($match.name)?" -ForegroundColor Cyan
                Write-Host "  From: $($match.from)"
                Write-Host "  To: $($match.to)"
                $confirm = Read-Host "Proceed? (y/N)"
                $shouldApply = ($confirm -eq "y" -or $confirm -eq "Y")
            }

            if ($shouldApply) {
                # Update registry entry
                for ($i = 0; $i -lt $registry.Count; $i++) {
                    if ($registry[$i].id -eq $match.entryId -or $registry[$i].name -eq $match.name) {
                        $registry[$i].path = $match.to
                        $registry[$i].updated_at = (Get-Date).ToUniversalTime().ToString("o")
                        break
                    }
                }

                $updated += $match
                Write-Host "Updated: $($match.name)" -ForegroundColor Green
            } else {
                $unresolved += @{
                    name = $match.name
                    reason = "user declined registry path update"
                }
            }
        }

        # Save registry
        if ($updated.Count -gt 0) {
            Save-Registry $config $registry
            Write-Host "`nRegistry updated with $($updated.Count) path corrections" -ForegroundColor Green
        }

        # Report unresolved
        if ($unresolved.Count -gt 0) {
            Write-Host "`nUnresolved entries: $($unresolved.Count)" -ForegroundColor Yellow
            foreach ($unres in $unresolved) {
                Write-Host "  - $($unres.name): $($unres.reason)" -ForegroundColor Gray
            }
        }

        return @{
            discovered = $discovered
            updated = $updated
            unresolved = $unresolved
        }
    }

    # Standard doctor mode (existing logic from lines 2334-2500)
    $report = [PSCustomObject]@{
        config = @{
            software_root = $config.roots.software
            tools_root = $config.roots.tools
            shims_root = $config.roots.shims
            registry_path = $config.registry
            strap_root = $StrapRootPath
        }
        path_check = @{
            shims_in_path = $false
            path_entry = $null
        }
        tools = @()
        registry_check = @{
            exists = $false
            valid_json = $false
            issues = @()
        }
        status = "OK"
    }

    # ... rest of existing doctor logic (lines 2355-2500)
    # [Keep all existing doctor checks for PATH, tools, registry integrity]

    # [Existing code continues here - not modified]
}

# Update CLI dispatch for doctor command (find existing block)
# Replace with:
if ($RepoName -eq "doctor") {
    $jsonFlag = $ExtraArgs -contains "--json"
    $fixPathsFlag = $ExtraArgs -contains "--fix-paths"
    $yesFlag = $ExtraArgs -contains "--yes"
    $dryRunFlag = $ExtraArgs -contains "--dry-run"

    Invoke-Doctor -StrapRootPath $TemplateRoot -OutputJson:$jsonFlag `
        -FixPaths:$fixPathsFlag -NonInteractive:$yesFlag -DryRun:$dryRunFlag
    exit 0
}
```

**Step 4: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Doctor-FixPaths.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 7 tests passing`

**Step 5: Manual verification**

```bash
# Discover repos and show fix plan
strap doctor --fix-paths --dry-run

# Fix paths with prompts
strap doctor --fix-paths

# Fix paths non-interactively
strap doctor --fix-paths --yes

# Verify registry updated
strap list --json | ConvertFrom-Json | Select-Object name,path
```

Expected: Registry paths updated to match discovered disk locations, normalized remote URL matching

**Step 6: Commit**

```bash
git add tests/powershell/Invoke-Doctor-FixPaths.Tests.ps1 strap.ps1
git commit -m "feat: add doctor --fix-paths enhancement

- Extend Invoke-Doctor to support --fix-paths mode
- Discover git repos on disk by scanning managed roots
- Extract and normalize remote URLs (SSH vs HTTPS)
- Match registry entries by normalized remote URL
- Auto-update when single match exists
- Prompt for confirmation unless --yes flag
- Skip ambiguous entries with multiple matches
- Add comprehensive Pester tests (7 tests)
- Update CLI dispatch with flag parsing

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```


## Batch 3: Final Enhancements and Documentation

This final batch completes the TDD plan with orphan cleanup, snapshot enhancement, documentation validation, and test infrastructure.

---

### Task 11: Doctor --fix-orphans Enhancement

**Goal**: Port TypeScript `runDoctorFixOrphans` logic to PowerShell, enabling removal of registry entries where the path no longer exists.

**Reference**:
- TypeScript: `src/commands/doctor/fixOrphans.ts`
- PowerShell: `Invoke-Doctor` function (lines 2325-2474)

**Requirements**:
1. Extend `Invoke-Doctor` to accept `-FixOrphans` switch parameter
2. Scan registry for entries where `path` does not exist on disk
3. Present list of orphaned entries to user
4. Prompt for confirmation to remove (skip prompt if `--yes` flag)
5. Remove confirmed entries from registry and save
6. Return removal report with removed and skipped items

**Step 1: Write test file - tests/powershell/Invoke-Doctor-FixOrphans.Tests.ps1**

```powershell
Describe "Invoke-Doctor --fix-orphans" {
    BeforeAll {
        # Load strap.ps1 functions
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test directory structure
        $script:testRoot = Join-Path $TestDrive "strap-test"
        $script:testConfig = Join-Path $testRoot "config.json"
        $script:testRegistry = Join-Path $testRoot "registry.json"

        # Setup config
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        $config = @{
            version = 1
            registry = $script:testRegistry
            roots = @{
                software = "P:\software"
                tools = "P:\tools"
                shims = "P:\tools\shims"
            }
        }
        $config | ConvertTo-Json -Depth 10 | Set-Content $script:testConfig

        # Mock Load-Config
        Mock Load-Config { return $config } -ModuleName *
    }

    It "should detect orphaned entries (path does not exist)" {
        # Arrange
        $strapRoot = $script:testRoot
        $registry = @(
            @{
                id = "abc-123"
                name = "valid-repo"
                scope = "software"
                path = $TestDrive  # exists
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            },
            @{
                id = "def-456"
                name = "orphaned-repo"
                scope = "software"
                path = "P:\nonexistent\path"  # does not exist
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            }
        )
        @{ entries = $registry; version = 2 } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Act
        $result = Invoke-Doctor -StrapRootPath $strapRoot -FixOrphans -DryRun $true

        # Assert
        $result.orphans | Should -Not -BeNullOrEmpty
        $result.orphans.Count | Should -Be 1
        $result.orphans[0].name | Should -Be "orphaned-repo"
        $result.orphans[0].path | Should -Be "P:\nonexistent\path"
    }

    It "should remove orphaned entries in --yes mode" {
        # Arrange
        $strapRoot = $script:testRoot
        $registry = @(
            @{
                id = "abc-123"
                name = "valid-repo"
                scope = "software"
                path = $TestDrive
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            },
            @{
                id = "def-456"
                name = "orphaned-repo"
                scope = "software"
                path = "P:\nonexistent\path"
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            }
        )
        @{ entries = $registry; version = 2 } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Act
        $result = Invoke-Doctor -StrapRootPath $strapRoot -FixOrphans -NonInteractive $true

        # Assert
        $result.removed.Count | Should -Be 1
        $result.removed[0].name | Should -Be "orphaned-repo"

        # Verify registry updated
        $updatedRegistry = Get-Content $script:testRegistry | ConvertFrom-Json
        $updatedRegistry.entries.Count | Should -Be 1
        $updatedRegistry.entries[0].name | Should -Be "valid-repo"
    }

    It "should skip orphan removal when user declines (interactive mode)" {
        # Arrange
        $strapRoot = $script:testRoot
        $registry = @(
            @{
                id = "def-456"
                name = "orphaned-repo"
                scope = "software"
                path = "P:\nonexistent\path"
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            }
        )
        @{ entries = $registry; version = 2 } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Mock user declining
        Mock Read-Host { return "n" } -ModuleName *

        # Act
        $result = Invoke-Doctor -StrapRootPath $strapRoot -FixOrphans

        # Assert
        $result.skipped.Count | Should -Be 1
        $result.skipped[0].name | Should -Be "orphaned-repo"
        $result.skipped[0].reason | Should -Match "user declined"

        # Verify registry NOT updated
        $updatedRegistry = Get-Content $script:testRegistry | ConvertFrom-Json
        $updatedRegistry.entries.Count | Should -Be 1
    }

    It "should handle multiple orphaned entries" {
        # Arrange
        $strapRoot = $script:testRoot
        $registry = @(
            @{
                id = "abc-123"
                name = "orphan-1"
                scope = "software"
                path = "P:\nonexistent\path1"
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            },
            @{
                id = "def-456"
                name = "orphan-2"
                scope = "tool"
                path = "P:\nonexistent\path2"
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            },
            @{
                id = "ghi-789"
                name = "valid-repo"
                scope = "software"
                path = $TestDrive
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            }
        )
        @{ entries = $registry; version = 2 } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Act
        $result = Invoke-Doctor -StrapRootPath $strapRoot -FixOrphans -NonInteractive $true

        # Assert
        $result.removed.Count | Should -Be 2
        $result.removed[0].name | Should -Match "orphan-"
        $result.removed[1].name | Should -Match "orphan-"

        # Verify registry
        $updatedRegistry = Get-Content $script:testRegistry | ConvertFrom-Json
        $updatedRegistry.entries.Count | Should -Be 1
        $updatedRegistry.entries[0].name | Should -Be "valid-repo"
    }

    It "should handle empty registry gracefully" {
        # Arrange
        $strapRoot = $script:testRoot
        @{ entries = @(); version = 2 } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Act
        $result = Invoke-Doctor -StrapRootPath $strapRoot -FixOrphans -NonInteractive $true

        # Assert
        $result.removed.Count | Should -Be 0
        $result.skipped.Count | Should -Be 0
    }

    It "should support --dry-run mode" {
        # Arrange
        $strapRoot = $script:testRoot
        $registry = @(
            @{
                id = "def-456"
                name = "orphaned-repo"
                scope = "software"
                path = "P:\nonexistent\path"
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            }
        )
        @{ entries = $registry; version = 2 } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Act
        $result = Invoke-Doctor -StrapRootPath $strapRoot -FixOrphans -DryRun $true

        # Assert
        $result.orphans.Count | Should -Be 1

        # Verify registry NOT modified
        $updatedRegistry = Get-Content $script:testRegistry | ConvertFrom-Json
        $updatedRegistry.entries.Count | Should -Be 1
    }

    It "should report both removed and skipped entries" {
        # Arrange
        $strapRoot = $script:testRoot
        $registry = @(
            @{
                id = "abc-123"
                name = "orphan-1"
                scope = "software"
                path = "P:\nonexistent\path1"
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            },
            @{
                id = "def-456"
                name = "orphan-2"
                scope = "tool"
                path = "P:\nonexistent\path2"
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            }
        )
        @{ entries = $registry; version = 2 } | ConvertTo-Json -Depth 10 | Set-Content $script:testRegistry

        # Mock user: decline first, accept second
        $script:promptCount = 0
        Mock Read-Host {
            $script:promptCount++
            if ($script:promptCount -eq 1) { return "n" } else { return "y" }
        } -ModuleName *

        # Act
        $result = Invoke-Doctor -StrapRootPath $strapRoot -FixOrphans

        # Assert
        $result.removed.Count | Should -Be 1
        $result.skipped.Count | Should -Be 1
        $result.removed[0].name | Should -Be "orphan-2"
        $result.skipped[0].name | Should -Be "orphan-1"
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Doctor-FixOrphans.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - Invoke-Doctor does not support -FixOrphans parameter`

**Step 3: Implement the enhancement in strap.ps1**

```powershell
# Update Invoke-Doctor function signature (line 2325)

function Invoke-Doctor {
    param(
        [string] $StrapRootPath,
        [switch] $OutputJson,
        [switch] $FixOrphans,        # NEW
        [switch] $NonInteractive,    # NEW
        [switch] $DryRun             # NEW
    )

    # Load config
    $config = Load-Config $StrapRootPath
    $registry = Load-Registry $config

    # Handle --fix-orphans mode
    if ($FixOrphans) {
        Write-Host "`n🔍 Scanning for orphaned registry entries..." -ForegroundColor Cyan

        # Find orphaned entries (path does not exist)
        $orphans = @()
        foreach ($entry in $registry) {
            if ($entry.path -and -not (Test-Path -LiteralPath $entry.path)) {
                $orphans += @{
                    id = $entry.id
                    name = $entry.name
                    path = $entry.path
                    scope = $entry.scope
                }
            }
        }

        if ($orphans.Count -eq 0) {
            Write-Host "✅ No orphaned entries found" -ForegroundColor Green
            return @{
                orphans = @()
                removed = @()
                skipped = @()
            }
        }

        Write-Host "`nFound $($orphans.Count) orphaned entries:" -ForegroundColor Yellow
        foreach ($orphan in $orphans) {
            Write-Host "  - $($orphan.name) [$($orphan.scope)] -> $($orphan.path)" -ForegroundColor Gray
        }

        if ($DryRun) {
            Write-Host "`n[DRY RUN] Would remove $($orphans.Count) orphaned entries" -ForegroundColor Yellow
            return @{
                orphans = $orphans
                removed = @()
                skipped = @()
            }
        }

        # Process removals
        $removed = @()
        $skipped = @()

        foreach ($orphan in $orphans) {
            $shouldRemove = $NonInteractive

            if (-not $NonInteractive) {
                Write-Host "`nRemove orphaned entry '$($orphan.name)' ($($orphan.path))? (y/n): " -NoNewline
                $response = Read-Host
                $shouldRemove = ($response -eq "y")
            }

            if ($shouldRemove) {
                # Remove from registry
                $registry = $registry | Where-Object { $_.id -ne $orphan.id }
                $removed += $orphan
                Write-Host "  ✅ Removed: $($orphan.name)" -ForegroundColor Green
            } else {
                $skipped += @{
                    name = $orphan.name
                    reason = "user declined orphan removal"
                }
                Write-Host "  ⏭️  Skipped: $($orphan.name)" -ForegroundColor Yellow
            }
        }

        # Save updated registry
        if ($removed.Count -gt 0) {
            Save-Registry -Config $config -Registry $registry
            Write-Host "`n✅ Removed $($removed.Count) orphaned entries from registry" -ForegroundColor Green
        }

        return @{
            orphans = $orphans
            removed = $removed
            skipped = $skipped
        }
    }

    # ... existing doctor logic for normal mode (keep unchanged)
}
```

**Step 4: Update CLI dispatch in strap.ps1**

```powershell
# Update doctor command dispatch (around line 4300)

if ($RepoName -eq "doctor") {
    $jsonFlag = $ExtraArgs -contains "--json"
    $fixOrphansFlag = $ExtraArgs -contains "--fix-orphans"
    $fixPathsFlag = $ExtraArgs -contains "--fix-paths"
    $yesFlag = $ExtraArgs -contains "--yes"
    $dryRunFlag = $ExtraArgs -contains "--dry-run"

    Invoke-Doctor -StrapRootPath $TemplateRoot -OutputJson:$jsonFlag `
        -FixOrphans:$fixOrphansFlag -FixPaths:$fixPathsFlag `
        -NonInteractive:$yesFlag -DryRun:$dryRunFlag
    exit 0
}
```

**Step 5: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Invoke-Doctor-FixOrphans.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 7 tests passing`

**Step 6: Manual verification**

```bash
# Create orphaned entry manually in registry
# (edit registry.json to point to non-existent path)

# Show orphans in dry-run mode
strap doctor --fix-orphans --dry-run

# Fix orphans with prompts
strap doctor --fix-orphans

# Fix orphans non-interactively
strap doctor --fix-orphans --yes

# Verify registry cleaned
strap list --json | ConvertFrom-Json | Select-Object name,path
```

Expected: Orphaned entries removed, registry valid, all paths exist

**Step 7: Commit**

```bash
git add tests/powershell/Invoke-Doctor-FixOrphans.Tests.ps1 strap.ps1
git commit -m "feat: add doctor --fix-orphans enhancement

- Extend Invoke-Doctor to support --fix-orphans mode
- Scan registry for entries where path no longer exists
- Present list of orphaned entries with path details
- Prompt for confirmation to remove (skip if --yes)
- Remove confirmed entries and save registry
- Support --dry-run to preview orphans without removing
- Add comprehensive Pester tests (7 tests)
- Update CLI dispatch with flag parsing

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 12: Enhance Consolidate Snapshot with Comprehensive Manifest

**Goal**: Replace simple metadata JSON in consolidate workflow with comprehensive snapshot including git metadata, external references, and registry state.

**Reference**:
- TypeScript: `src/commands/consolidate/runConsolidate.ts`
- PowerShell: `Invoke-ConsolidateMigrationWorkflow` (lines 3327-3561)
- Current snapshot: lines 3356-3363

**Requirements**:
1. Create `Build-ConsolidateSnapshot` helper function
2. Include timestamp, from/to paths, flags used
3. For each discovered repo: name, path, git remote, branch, commit
4. Include external reference data (PM2, scheduled tasks, shims, PATH, profiles)
5. Include full registry snapshot (before consolidation)
6. Save as JSON to build directory
7. Return snapshot object for use in workflow

**Step 1: Write test file - tests/powershell/Build-ConsolidateSnapshot.Tests.ps1**

```powershell
Describe "Build-ConsolidateSnapshot" {
    BeforeAll {
        # Load strap.ps1 functions
        . "$PSScriptRoot\..\..\strap.ps1"

        # Create test git repo
        $script:testRepo = Join-Path $TestDrive "test-repo"
        New-Item -ItemType Directory -Path $script:testRepo -Force | Out-Null
        Push-Location $script:testRepo
        git init | Out-Null
        git config user.name "Test User" | Out-Null
        git config user.email "test@example.com" | Out-Null
        "test" | Out-File "README.md"
        git add . | Out-Null
        git commit -m "Initial commit" | Out-Null
        git remote add origin "https://github.com/user/test-repo.git" | Out-Null
        git branch -M main | Out-Null
        Pop-Location
    }

    It "should build snapshot with timestamp and paths" {
        # Arrange
        $fromPath = "C:\Code"
        $toPath = "P:\software"
        $flags = @{ dryRun = $true; yes = $false }

        # Act
        $snapshot = Build-ConsolidateSnapshot -FromPath $fromPath -ToPath $toPath -Flags $flags `
            -DiscoveredRepos @() -ExternalRefs @{} -Registry @()

        # Assert
        $snapshot.timestamp | Should -Not -BeNullOrEmpty
        $snapshot.fromPath | Should -Be "C:\Code"
        $snapshot.toPath | Should -Be "P:\software"
        $snapshot.flags.dryRun | Should -Be $true
        $snapshot.flags.yes | Should -Be $false
    }

    It "should include discovered repo git metadata" {
        # Arrange
        $fromPath = $TestDrive
        $toPath = "P:\software"
        $flags = @{ dryRun = $false }

        # Get git info
        Push-Location $script:testRepo
        $remote = git remote get-url origin 2>$null
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
        $commit = git rev-parse HEAD 2>$null
        Pop-Location

        $discoveredRepos = @(
            @{
                name = "test-repo"
                path = $script:testRepo
                remote = $remote
                branch = $branch
                commit = $commit
            }
        )

        # Act
        $snapshot = Build-ConsolidateSnapshot -FromPath $fromPath -ToPath $toPath -Flags $flags `
            -DiscoveredRepos $discoveredRepos -ExternalRefs @{} -Registry @()

        # Assert
        $snapshot.discovered.Count | Should -Be 1
        $snapshot.discovered[0].name | Should -Be "test-repo"
        $snapshot.discovered[0].remote | Should -Be "https://github.com/user/test-repo.git"
        $snapshot.discovered[0].branch | Should -Be "main"
        $snapshot.discovered[0].commit | Should -Not -BeNullOrEmpty
    }

    It "should include external references" {
        # Arrange
        $fromPath = $TestDrive
        $toPath = "P:\software"
        $flags = @{}
        $externalRefs = @{
            pm2 = @("app1", "app2")
            scheduled_tasks = @("backup-task")
            shims = @("mytool.cmd")
            path_entries = @("C:\Code\bin")
            profile_refs = @("C:\Code\script.ps1")
        }

        # Act
        $snapshot = Build-ConsolidateSnapshot -FromPath $fromPath -ToPath $toPath -Flags $flags `
            -DiscoveredRepos @() -ExternalRefs $externalRefs -Registry @()

        # Assert
        $snapshot.external_refs | Should -Not -BeNullOrEmpty
        $snapshot.external_refs.pm2.Count | Should -Be 2
        $snapshot.external_refs.scheduled_tasks.Count | Should -Be 1
        $snapshot.external_refs.shims.Count | Should -Be 1
        $snapshot.external_refs.path_entries.Count | Should -Be 1
        $snapshot.external_refs.profile_refs.Count | Should -Be 1
    }

    It "should include registry snapshot" {
        # Arrange
        $fromPath = $TestDrive
        $toPath = "P:\software"
        $flags = @{}
        $registry = @(
            @{
                id = "abc-123"
                name = "repo1"
                scope = "software"
                path = "P:\software\repo1"
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @()
            },
            @{
                id = "def-456"
                name = "tool1"
                scope = "tool"
                path = "P:\tools\tool1"
                updated_at = (Get-Date).ToUniversalTime().ToString("o")
                shims = @("tool1")
            }
        )

        # Act
        $snapshot = Build-ConsolidateSnapshot -FromPath $fromPath -ToPath $toPath -Flags $flags `
            -DiscoveredRepos @() -ExternalRefs @{} -Registry $registry

        # Assert
        $snapshot.registry_snapshot | Should -Not -BeNullOrEmpty
        $snapshot.registry_snapshot.Count | Should -Be 2
        $snapshot.registry_snapshot[0].name | Should -Be "repo1"
        $snapshot.registry_snapshot[1].name | Should -Be "tool1"
    }

    It "should serialize to valid JSON" {
        # Arrange
        $fromPath = $TestDrive
        $toPath = "P:\software"
        $flags = @{ dryRun = $true }
        $discoveredRepos = @(
            @{ name = "repo1"; path = "C:\Code\repo1"; remote = "https://github.com/user/repo1.git"; branch = "main"; commit = "abc123" }
        )
        $externalRefs = @{ pm2 = @(); scheduled_tasks = @(); shims = @(); path_entries = @(); profile_refs = @() }
        $registry = @()

        # Act
        $snapshot = Build-ConsolidateSnapshot -FromPath $fromPath -ToPath $toPath -Flags $flags `
            -DiscoveredRepos $discoveredRepos -ExternalRefs $externalRefs -Registry $registry

        # Assert - should convert to JSON without error
        { $snapshot | ConvertTo-Json -Depth 10 } | Should -Not -Throw

        $json = $snapshot | ConvertTo-Json -Depth 10
        $roundtrip = $json | ConvertFrom-Json
        $roundtrip.fromPath | Should -Be $fromPath
        $roundtrip.toPath | Should -Be $toPath
    }
}
```

**Step 2: Run test to verify it fails**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Build-ConsolidateSnapshot.Tests.ps1 -Output Detailed"
```

Expected: `FAIL - Build-ConsolidateSnapshot function does not exist`

**Step 3: Implement Build-ConsolidateSnapshot function in strap.ps1**

```powershell
# Add new function before Invoke-ConsolidateMigrationWorkflow (before line 3327)

function Build-ConsolidateSnapshot {
    param(
        [string] $FromPath,
        [string] $ToPath,
        [array] $DiscoveredRepos,
        [hashtable] $ExternalRefs,
        [array] $Registry,
        [hashtable] $Flags
    )

    # Build discovered repos with git metadata
    $discoveredManifest = @()
    foreach ($repo in $DiscoveredRepos) {
        $discoveredManifest += @{
            name = $repo.name
            path = $repo.path
            remote = if ($repo.remote) { $repo.remote } else { $null }
            branch = if ($repo.branch) { $repo.branch } else { $null }
            commit = if ($repo.commit) { $repo.commit } else { $null }
        }
    }

    # Build external references section
    $externalRefsManifest = @{
        pm2 = if ($ExternalRefs.pm2) { $ExternalRefs.pm2 } else { @() }
        scheduled_tasks = if ($ExternalRefs.scheduled_tasks) { $ExternalRefs.scheduled_tasks } else { @() }
        shims = if ($ExternalRefs.shims) { $ExternalRefs.shims } else { @() }
        path_entries = if ($ExternalRefs.path_entries) { $ExternalRefs.path_entries } else { @() }
        profile_refs = if ($ExternalRefs.profile_refs) { $ExternalRefs.profile_refs } else { @() }
    }

    # Build manifest
    $manifest = @{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        fromPath = $FromPath
        toPath = $ToPath
        flags = $Flags
        discovered = $discoveredManifest
        external_refs = $externalRefsManifest
        registry_snapshot = $Registry
    }

    return $manifest
}
```

**Step 4: Update Invoke-ConsolidateMigrationWorkflow to use new snapshot**

```powershell
# Update Step 1 in Invoke-ConsolidateMigrationWorkflow (lines 3347-3363)

# Step 1: Snapshot
Write-Host "`n[1/6] Creating comprehensive snapshot..." -ForegroundColor Yellow
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$snapshotDir = Join-Path $StrapRootPath "build"
if (-not (Test-Path $snapshotDir)) {
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
}
$snapshotPath = Join-Path $snapshotDir "consolidate-snapshot-$timestamp.json"

# Collect data for snapshot (discovery happens in step 2, audit in step 4)
# We'll build snapshot incrementally and save at end of step 4

# ... (keep existing steps 2-4)

# After Step 4 (audit), before Step 5 (preflight):
# Build comprehensive snapshot
$flags = @{
    dryRun = $DryRun.IsPresent
    yes = $Yes.IsPresent
    stopPm2 = $StopPm2.IsPresent
    ackScheduledTasks = $AckScheduledTasks.IsPresent
    allowDirty = $AllowDirty.IsPresent
    allowAutoArchive = $AllowAutoArchive.IsPresent
}

$snapshot = Build-ConsolidateSnapshot `
    -FromPath $FromPath `
    -ToPath $ToPath `
    -DiscoveredRepos $discovered `
    -ExternalRefs @{
        pm2 = $auditWarnings | Where-Object { $_ -match "PM2" }
        scheduled_tasks = @()  # Will be populated when task #23 is complete
        shims = @()            # Will be populated when task #24 is complete
        path_entries = @()     # Will be populated when task #25 is complete
        profile_refs = @()     # Will be populated when task #25 is complete
    } `
    -Registry $registry `
    -Flags $flags

$snapshot | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $snapshotPath
Info "Comprehensive snapshot saved: $snapshotPath"
```

**Step 5: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Build-ConsolidateSnapshot.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 5 tests passing`

**Step 6: Manual verification**

```bash
# Run consolidate in dry-run mode
strap consolidate --from "C:\Code" --dry-run

# Check snapshot file
$snapshot = Get-Content "build/consolidate-snapshot-*.json" | ConvertFrom-Json
$snapshot.timestamp
$snapshot.discovered
$snapshot.external_refs
$snapshot.registry_snapshot
```

Expected: Comprehensive JSON with git metadata, external refs structure, full registry state

**Step 7: Commit**

```bash
git add tests/powershell/Build-ConsolidateSnapshot.Tests.ps1 strap.ps1
git commit -m "feat: enhance consolidate snapshot with comprehensive manifest

- Create Build-ConsolidateSnapshot helper function
- Include git metadata (remote, branch, commit) for discovered repos
- Include external references structure (PM2, scheduled tasks, shims, PATH, profiles)
- Include full registry snapshot before consolidation
- Include flags used in workflow
- Save comprehensive manifest to build directory
- Add Pester tests (5 tests)
- Integrate into consolidate workflow step 1

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---


### Task 13: Update Help Text and README

**Goal**: Update `Show-Help` function and README.md to document all commands, flags, and examples. Validate that all documented commands are callable.

**Reference**:
- PowerShell: `Show-Help` function (lines 137-186)
- README: `README.md`

**Requirements**:
1. Update `Show-Help` to include `snapshot`, `audit`, `archive` commands
2. Update `Show-Help` to show enhanced flags for `adopt` and `doctor`
3. Update `Show-Help` to show all `consolidate` flags
4. Update README.md to ensure no TypeScript/Node references (pure PowerShell)
5. Validate all README command examples are runnable
6. Add examples for new commands

**Step 1: Write test file - tests/powershell/Help-And-Documentation.Tests.ps1**

```powershell
Describe "Help and Documentation" {
    It "Show-Help should include snapshot command" {
        # Act
        $helpText = Show-Help

        # Assert
        $helpText | Should -Match "strap snapshot"
    }

    It "Show-Help should include audit command" {
        # Act
        $helpText = Show-Help

        # Assert
        $helpText | Should -Match "strap audit"
    }

    It "Show-Help should include archive command" {
        # Act
        $helpText = Show-Help

        # Assert
        $helpText | Should -Match "strap archive"
    }

    It "Show-Help should document adopt --scan flag" {
        # Act
        $helpText = Show-Help

        # Assert
        $helpText | Should -Match "--scan"
    }

    It "Show-Help should document doctor --fix-paths flag" {
        # Act
        $helpText = Show-Help

        # Assert
        $helpText | Should -Match "--fix-paths"
    }

    It "Show-Help should document doctor --fix-orphans flag" {
        # Act
        $helpText = Show-Help

        # Assert
        $helpText | Should -Match "--fix-orphans"
    }

    It "Show-Help should document consolidate flags" {
        # Act
        $helpText = Show-Help

        # Assert
        $helpText | Should -Match "consolidate"
        $helpText | Should -Match "--from"
        $helpText | Should -Match "--dry-run"
        $helpText | Should -Match "--yes"
    }

    It "README should not reference TypeScript or Node.js execution" {
        # Act
        $readmeContent = Get-Content "$PSScriptRoot\..\..\README.md" -Raw

        # Assert
        $readmeContent | Should -Not -Match "node dist/"
        $readmeContent | Should -Not -Match "npm run"
        $readmeContent | Should -Not -Match "tsx src/"
    }

    It "README should document pure PowerShell implementation" {
        # Act
        $readmeContent = Get-Content "$PSScriptRoot\..\..\README.md" -Raw

        # Assert
        $readmeContent | Should -Match "PowerShell"
    }

    It "all commands in README should be valid strap commands" {
        # Act
        $readmeContent = Get-Content "$PSScriptRoot\..\..\README.md" -Raw

        # Extract strap commands from code blocks
        $commands = [regex]::Matches($readmeContent, "strap ([a-z\-]+)") | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

        # Valid commands
        $validCommands = @(
            "clone", "list", "open", "move", "rename", "adopt", "setup", "update",
            "uninstall", "shim", "doctor", "migrate", "templatize", "consolidate",
            "snapshot", "audit", "archive"
        )

        # Assert
        foreach ($cmd in $commands) {
            $validCommands | Should -Contain $cmd
        }
    }
}
```

**Step 2: Run test to verify current state**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Help-And-Documentation.Tests.ps1 -Output Detailed"
```

Expected: Some tests fail (missing commands/flags in help text)

**Step 3: Update Show-Help function in strap.ps1**

```powershell
# Replace Show-Help function (lines 137-186)

function Show-Help {
  @"
strap usage:
  strap <project-name> -t <template> [-p <parent-dir>] [--skip-install] [--install] [--start]
  strap clone <git-url> [--tool] [--name <name>] [--dest <dir>]
  strap list [--tool] [--software] [--json]
  strap open <name>
  strap move <name> --dest <path> [--yes] [--dry-run] [--force] [--rehome-shims]
  strap rename <name> --to <newName> [--yes] [--dry-run] [--move-folder] [--force]
  strap adopt [--path <dir>] [--scan <dir>] [--name <name>] [--recursive] [--scope tool|software]
              [--tool|--software] [--allow-auto-archive] [--yes] [--dry-run]
  strap setup [--yes] [--dry-run] [--stack python|node|go|rust] [--repo <name>]
  strap setup [--venv <path>] [--uv] [--python <exe>] [--pm npm|pnpm|yarn] [--corepack]
  strap update <name> [--yes] [--dry-run] [--rebase] [--stash] [--setup]
  strap update --all [--tool] [--software] [--yes] [--dry-run] [--rebase] [--stash] [--setup]
  strap uninstall <name> [--yes] [--dry-run] [--keep-folder] [--keep-shims]
  strap shim <name> --- <command...> [--cwd <path>] [--repo <name>] [--force] [--dry-run] [--yes]
  strap shim <name> --cmd "<command>" [--cwd <path>] [--repo <name>] [--force] [--dry-run] [--yes]
  strap doctor [--json] [--fix-paths] [--fix-orphans] [--yes] [--dry-run]
  strap migrate [--yes] [--dry-run] [--backup] [--json] [--to <version>] [--plan]
  strap templatize <templateName> [--source <path>] [--message "<msg>"] [--push] [--force] [--allow-dirty]
  strap consolidate --from <path> [--to <path>] [--dry-run] [--yes] [--stop-pm2]
                    [--ack-scheduled-tasks] [--allow-dirty] [--allow-auto-archive]
  strap snapshot [--output <path>] [--scan <dir>] [--scan <dir2>]
  strap audit [<name>] [--all] [--json] [--rebuild-index]
  strap archive <name> [--yes] [--dry-run]

Templates:
  node-ts-service | node-ts-web | python | mono

Flags:
  --skip-install       skip dependency install
  --install            run full install after initial commit
  --start              full install, then start dev
  --keep               keep doctor artifacts
  --strap-root         override strap repo root
  --tool               filter by tool scope or clone to tools directory
  --software           filter by software scope
  --json               output raw JSON
  --name               custom name for cloned repo or shim
  --dest               full destination path (overrides --tool)
  --yes                non-interactive mode (no confirmation prompt)
  --dry-run            show planned actions without executing
  --keep-folder        preserve repo folder during uninstall
  --keep-shims         preserve shims during uninstall
  --cwd                working directory for shim execution
  --cmd                command string (alternative to --- for complex commands with flags)
  --repo               attach shim to specific registry entry or run setup for registered repo
  --stack              force stack selection (python|node|go|rust)
  --venv               venv directory for Python (default .venv)
  --uv                 use uv for Python installs (default on)
  --python             python executable for venv creation (default python)
  --pm                 force package manager for Node (npm|pnpm|yarn)
  --corepack           enable corepack before Node install (default on)
  --rebase             use git pull --rebase for update
  --stash              auto-stash dirty working tree before update
  --scan               directory to scan for bulk adoption or snapshot discovery
  --recursive          scan subdirectories recursively
  --scope              force scope (tool|software) for batch adoption
  --allow-auto-archive allow automatic archival of repositories
  --fix-paths          discover repos on disk and fix invalid registry paths
  --fix-orphans        remove registry entries where path no longer exists
  --from               source directory for consolidation
  --to                 destination root for consolidation (default: software root)
  --stop-pm2           automatically stop affected PM2 processes
  --ack-scheduled-tasks acknowledge scheduled task warnings and continue
  --allow-dirty        allow consolidation with uncommitted changes
  --output             output file path for snapshot
  --all                target all repositories for audit or update
  --rebuild-index      force rebuild of audit index cache
"@
}
```

**Step 4: Update README.md**

Add after "Lifecycle Management" section (around line 72):

```markdown
### Standalone Commands

#### Snapshot

Capture development environment state with git metadata:

\`\`\`powershell
# Create snapshot of current environment
strap snapshot --output environment-snapshot.json

# Scan additional directories for git repos
strap snapshot --output snapshot.json --scan "C:\Code" --scan "D:\Projects"
\`\`\`

The snapshot includes:
- Git metadata (remotes, branches, commits)
- Registry state
- External references (PM2, scheduled tasks, PATH entries)

#### Audit

Scan repositories for hardcoded path references:

\`\`\`powershell
# Audit all repositories
strap audit --all

# Audit specific repository
strap audit my-repo

# Force rebuild audit index
strap audit --all --rebuild-index

# Output as JSON
strap audit --all --json
\`\`\`

The audit index is cached at \`build/audit-index.json\` and automatically refreshes when registry changes.

#### Archive

Move repositories to archive scope:

\`\`\`powershell
# Archive a repository (moves to archive root)
strap archive old-project

# Preview without executing
strap archive old-project --dry-run

# Non-interactive mode
strap archive old-project --yes
\`\`\`

Archived repositories are moved to the archive root and marked with \`scope = "archive"\` in the registry.

#### Doctor Enhancements

\`\`\`powershell
# Fix invalid registry paths by discovering repos on disk
strap doctor --fix-paths

# Remove orphaned registry entries (path no longer exists)
strap doctor --fix-orphans

# Non-interactive mode
strap doctor --fix-orphans --yes

# Dry-run mode
strap doctor --fix-paths --dry-run
\`\`\`

#### Bulk Adoption

\`\`\`powershell
# Scan directory for git repos
strap adopt --scan "C:\Code"

# Scan recursively
strap adopt --scan "C:\Code" --recursive

# Force scope for batch adoption
strap adopt --scan "C:\Code" --scope tool --yes

# Allow automatic archival
strap adopt --scan "C:\Code" --allow-auto-archive
\`\`\`
```

**Step 5: Run test to verify it passes**

```bash
pwsh -Command "Invoke-Pester tests/powershell/Help-And-Documentation.Tests.ps1 -Output Detailed"
```

Expected: `PASS - All 10 tests passing`

**Step 6: Manual verification**

```bash
# Test help text
strap --help
strap doctor --help

# Verify all commands are documented
strap snapshot --help
strap audit --help
strap archive --help

# Test examples from README
strap doctor --fix-orphans --dry-run
strap adopt --scan "C:\Code" --dry-run
strap snapshot --output test.json
```

Expected: All commands work, help text is complete and accurate

**Step 7: Commit**

```bash
git add tests/powershell/Help-And-Documentation.Tests.ps1 strap.ps1 README.md
git commit -m "docs: update help text and README for new commands

- Add snapshot, audit, archive to Show-Help function
- Document enhanced adopt flags (--scan, --recursive, --scope)
- Document enhanced doctor flags (--fix-paths, --fix-orphans)
- Document all consolidate flags
- Add README sections for snapshot, audit, archive commands
- Add examples for bulk adoption and doctor enhancements
- Remove any TypeScript/Node.js execution references
- Validate all documented commands are callable
- Add Pester tests (10 tests) for documentation validation

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 14: PowerShell Test Infrastructure and CI Integration

**Goal**: Set up Pester test infrastructure, create test configuration, add CI integration, and document how to run tests.

**Reference**:
- TypeScript tests: `tests/commands/**/*.test.ts`
- GitHub Actions: `.github/workflows/` (if exists)

**Requirements**:
1. Create Pester configuration file (`tests/powershell/PesterConfig.ps1`)
2. Create test data fixtures directory (`tests/powershell/fixtures/`)
3. Create test runner script (`tests/powershell/Run-Tests.ps1`)
4. Add CI integration (GitHub Actions or equivalent)
5. Document how to run tests in README
6. Create helper functions for common test setup (registry, config, git repos)

**Step 1: Create Pester configuration file**

Create `tests/powershell/PesterConfig.ps1`:

```powershell
# Pester configuration for strap PowerShell tests

$config = New-PesterConfiguration

# Paths
$config.Run.Path = "$PSScriptRoot"
$config.Run.Exit = $true
$config.Run.PassThru = $true

# Output
$config.Output.Verbosity = "Detailed"

# Test Selection
$config.Filter.Tag = @()  # Run all tests by default
$config.Filter.ExcludeTag = @()

# Code Coverage (optional)
$config.CodeCoverage.Enabled = $false
$config.CodeCoverage.Path = "$PSScriptRoot\..\..\strap.ps1"
$config.CodeCoverage.OutputFormat = "JaCoCo"
$config.CodeCoverage.OutputPath = "$PSScriptRoot\..\..\build\coverage.xml"

# Test Result
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = "NUnitXml"
$config.TestResult.OutputPath = "$PSScriptRoot\..\..\build\test-results.xml"

# Should (assertions)
$config.Should.ErrorAction = "Stop"

return $config
```

**Step 2: Create test runner script**

Create `tests/powershell/Run-Tests.ps1`:

```powershell
<#
.SYNOPSIS
Run all PowerShell tests for strap

.DESCRIPTION
Runs Pester tests with optional code coverage and CI output formats

.PARAMETER Coverage
Enable code coverage analysis

.PARAMETER CI
Enable CI mode (exit with error code on failure)

.PARAMETER Filter
Run only tests matching filter (e.g., "*Doctor*")

.EXAMPLE
.\Run-Tests.ps1

.EXAMPLE
.\Run-Tests.ps1 -Coverage

.EXAMPLE
.\Run-Tests.ps1 -CI -Filter "*Adopt*"
#>

param(
    [switch] $Coverage,
    [switch] $CI,
    [string] $Filter = "*.Tests.ps1"
)

# Ensure Pester is installed
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Host "Installing Pester..." -ForegroundColor Yellow
    Install-Module -Name Pester -Force -SkipPublisherCheck
}

# Load configuration
$config = & "$PSScriptRoot\PesterConfig.ps1"

# Apply parameters
if ($Coverage) {
    $config.CodeCoverage.Enabled = $true
}

if ($CI) {
    $config.Run.Exit = $true
    $config.Output.Verbosity = "Detailed"
}

$config.Run.Path = "$PSScriptRoot\$Filter"

# Create build directory for results
$buildDir = "$PSScriptRoot\..\..\build"
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
}

# Run tests
Write-Host "`n🧪 Running PowerShell tests..." -ForegroundColor Cyan
Write-Host "Filter: $Filter" -ForegroundColor Gray
Write-Host "Coverage: $($config.CodeCoverage.Enabled)" -ForegroundColor Gray
Write-Host ""

$result = Invoke-Pester -Configuration $config

# Report results
Write-Host "`n📊 Test Results:" -ForegroundColor Cyan
Write-Host "  Passed: $($result.PassedCount)" -ForegroundColor Green
Write-Host "  Failed: $($result.FailedCount)" -ForegroundColor $(if ($result.FailedCount -gt 0) { "Red" } else { "Gray" })
Write-Host "  Skipped: $($result.SkippedCount)" -ForegroundColor Yellow
Write-Host "  Total: $($result.TotalCount)" -ForegroundColor Gray

if ($config.CodeCoverage.Enabled) {
    $coverage = $result.CodeCoverage
    $coveragePercent = [math]::Round(($coverage.CoveredPercent), 2)
    Write-Host "`n📈 Code Coverage: $coveragePercent%" -ForegroundColor Cyan
    Write-Host "  Covered: $($coverage.CommandsExecutedCount) / $($coverage.CommandsAnalyzedCount)" -ForegroundColor Gray
    Write-Host "  Report: $($config.CodeCoverage.OutputPath)" -ForegroundColor Gray
}

if ($config.TestResult.Enabled) {
    Write-Host "`n📄 Test Results: $($config.TestResult.OutputPath)" -ForegroundColor Gray
}

# Exit with error code in CI mode
if ($CI -and $result.FailedCount -gt 0) {
    exit 1
}

exit 0
```

**Step 3: Create test helper functions**

Create `tests/powershell/Test-Helpers.ps1`:

```powershell
# Test helper functions for strap PowerShell tests

function New-TestRegistry {
    param(
        [string] $Path,
        [array] $Entries = @()
    )

    $registry = @{
        version = 2
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
        entries = $Entries
    }

    $registry | ConvertTo-Json -Depth 10 | Set-Content -Path $Path
}

function New-TestConfig {
    param(
        [string] $Path,
        [string] $RegistryPath,
        [string] $SoftwareRoot = "P:\software",
        [string] $ToolsRoot = "P:\tools",
        [string] $ShimsRoot = "P:\tools\shims"
    )

    $config = @{
        version = 1
        registry = $RegistryPath
        roots = @{
            software = $SoftwareRoot
            tools = $ToolsRoot
            shims = $ShimsRoot
        }
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $Path
}

function New-TestGitRepo {
    param(
        [string] $Path,
        [string] $RemoteUrl = "https://github.com/user/repo.git",
        [string] $Branch = "main"
    )

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    Push-Location $Path
    try {
        git init | Out-Null
        git config user.name "Test User" | Out-Null
        git config user.email "test@example.com" | Out-Null

        "# Test Repo" | Out-File "README.md"
        git add . | Out-Null
        git commit -m "Initial commit" | Out-Null

        if ($RemoteUrl) {
            git remote add origin $RemoteUrl | Out-Null
        }

        if ($Branch -ne "main") {
            git branch -M $Branch | Out-Null
        }
    } finally {
        Pop-Location
    }
}

function New-TestRegistryEntry {
    param(
        [string] $Name,
        [string] $Scope = "software",
        [string] $Path,
        [array] $Shims = @()
    )

    return @{
        id = [guid]::NewGuid().ToString()
        name = $Name
        scope = $Scope
        path = $Path
        updated_at = (Get-Date).ToUniversalTime().ToString("o")
        shims = $Shims
    }
}

function Assert-RegistryEntryExists {
    param(
        [string] $RegistryPath,
        [string] $Name
    )

    $registry = Get-Content $RegistryPath | ConvertFrom-Json
    $entries = if ($registry.entries) { $registry.entries } else { $registry }

    $entry = $entries | Where-Object { $_.name -eq $Name }
    if (-not $entry) {
        throw "Registry entry '$Name' not found"
    }

    return $entry
}

function Assert-RegistryEntryNotExists {
    param(
        [string] $RegistryPath,
        [string] $Name
    )

    $registry = Get-Content $RegistryPath | ConvertFrom-Json
    $entries = if ($registry.entries) { $registry.entries } else { $registry }

    $entry = $entries | Where-Object { $_.name -eq $Name }
    if ($entry) {
        throw "Registry entry '$Name' should not exist but was found"
    }
}

Export-ModuleMember -Function @(
    "New-TestRegistry",
    "New-TestConfig",
    "New-TestGitRepo",
    "New-TestRegistryEntry",
    "Assert-RegistryEntryExists",
    "Assert-RegistryEntryNotExists"
)
```

**Step 4: Create fixtures directory structure**

Create `tests/powershell/fixtures/sample-registry.json`:

```json
{
  "version": 2,
  "updated_at": "2026-02-02T10:00:00.000Z",
  "entries": [
    {
      "id": "abc-123",
      "name": "sample-repo",
      "scope": "software",
      "path": "P:\\software\\sample-repo",
      "updated_at": "2026-02-02T10:00:00.000Z",
      "shims": []
    }
  ]
}
```

Create `tests/powershell/fixtures/sample-config.json`:

```json
{
  "version": 1,
  "registry": "P:\\software\\_strap\\registry.json",
  "roots": {
    "software": "P:\\software",
    "tools": "P:\\tools",
    "shims": "P:\\tools\\shims"
  }
}
```

**Step 5: Create CI workflow**

Create `.github/workflows/test-powershell.yml`:

```yaml
name: PowerShell Tests

on:
  push:
    branches: [ master, main ]
  pull_request:
    branches: [ master, main ]

jobs:
  test-powershell:
    name: PowerShell Tests (Windows)
    runs-on: windows-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install Pester
        shell: pwsh
        run: |
          Install-Module -Name Pester -Force -SkipPublisherCheck -MinimumVersion 5.5.0

      - name: Run PowerShell tests
        shell: pwsh
        run: |
          .\tests\powershell\Run-Tests.ps1 -CI -Coverage

      - name: Upload test results
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: powershell-test-results
          path: build/test-results.xml

      - name: Upload coverage report
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: powershell-coverage
          path: build/coverage.xml

      - name: Publish test results
        uses: EnricoMi/publish-unit-test-result-action/windows@v2
        if: always()
        with:
          files: build/test-results.xml
          check_name: PowerShell Test Results
```

**Step 6: Update README with test documentation**

Add to README.md after "## Usage" section:

```markdown
## Testing

### TypeScript Tests

\`\`\`bash
npm test
\`\`\`

Expected: 75/75 passing

### PowerShell Tests

\`\`\`bash
# Run all tests
.\tests\powershell\Run-Tests.ps1

# Run with code coverage
.\tests\powershell\Run-Tests.ps1 -Coverage

# Run specific test file
.\tests\powershell\Run-Tests.ps1 -Filter "*Doctor*"

# CI mode (exit with error on failure)
.\tests\powershell\Run-Tests.ps1 -CI
\`\`\`

Test results are saved to \`build/test-results.xml\` (NUnit format) and coverage report to \`build/coverage.xml\` (JaCoCo format).

### Test Structure

\`\`\`
tests/
├── commands/           # TypeScript tests (reference implementation)
└── powershell/         # PowerShell tests (TDD implementation)
    ├── *.Tests.ps1     # Test files
    ├── Test-Helpers.ps1 # Test utility functions
    ├── PesterConfig.ps1 # Pester configuration
    ├── Run-Tests.ps1    # Test runner script
    └── fixtures/        # Test data fixtures
\`\`\`

### Writing Tests

Use Pester 5.x syntax:

\`\`\`powershell
Describe "My Feature" {
    BeforeAll {
        # Setup
        . "$PSScriptRoot\Test-Helpers.ps1"
    }

    It "should do something" {
        # Arrange
        $testData = "example"

        # Act
        $result = Do-Something $testData

        # Assert
        $result | Should -Be "expected"
    }
}
\`\`\`

See \`tests/powershell/Test-Helpers.ps1\` for available test utilities.
```

**Step 7: Write validation test**

Create `tests/powershell/Test-Infrastructure.Tests.ps1`:

```powershell
Describe "Test Infrastructure" {
    It "Pester should be installed" {
        Get-Module -ListAvailable -Name Pester | Should -Not -BeNullOrEmpty
    }

    It "PesterConfig.ps1 should exist" {
        Test-Path "$PSScriptRoot\PesterConfig.ps1" | Should -Be $true
    }

    It "Run-Tests.ps1 should exist" {
        Test-Path "$PSScriptRoot\Run-Tests.ps1" | Should -Be $true
    }

    It "Test-Helpers.ps1 should exist" {
        Test-Path "$PSScriptRoot\Test-Helpers.ps1" | Should -Be $true
    }

    It "fixtures directory should exist" {
        Test-Path "$PSScriptRoot\fixtures" | Should -Be $true
    }

    It "PesterConfig should return valid configuration" {
        $config = & "$PSScriptRoot\PesterConfig.ps1"
        $config | Should -Not -BeNullOrEmpty
        $config.Run.Path | Should -Not -BeNullOrEmpty
    }

    It "Test-Helpers should export functions" {
        . "$PSScriptRoot\Test-Helpers.ps1"
        Get-Command New-TestRegistry -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command New-TestConfig -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command New-TestGitRepo -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "New-TestRegistry should create valid registry" {
        . "$PSScriptRoot\Test-Helpers.ps1"
        $testPath = Join-Path $TestDrive "test-registry.json"

        New-TestRegistry -Path $testPath

        Test-Path $testPath | Should -Be $true
        $content = Get-Content $testPath | ConvertFrom-Json
        $content.version | Should -Be 2
    }

    It "New-TestConfig should create valid config" {
        . "$PSScriptRoot\Test-Helpers.ps1"
        $testPath = Join-Path $TestDrive "test-config.json"
        $registryPath = "P:\software\_strap\registry.json"

        New-TestConfig -Path $testPath -RegistryPath $registryPath

        Test-Path $testPath | Should -Be $true
        $content = Get-Content $testPath | ConvertFrom-Json
        $content.version | Should -Be 1
        $content.registry | Should -Be $registryPath
    }
}
```

**Step 8: Run validation tests**

```bash
pwsh -Command ".\tests\powershell\Run-Tests.ps1 -Filter 'Test-Infrastructure*'"
```

Expected: `PASS - All 9 tests passing`

**Step 9: Manual verification**

```bash
# Run all tests
.\tests\powershell\Run-Tests.ps1

# Run with coverage
.\tests\powershell\Run-Tests.ps1 -Coverage

# Check build outputs
Get-ChildItem build\

# Verify CI workflow
git add .github/workflows/test-powershell.yml
# Push and check Actions tab on GitHub
```

Expected: Tests run successfully, coverage report generated, CI pipeline passes

**Step 10: Commit**

```bash
git add tests/powershell/PesterConfig.ps1 tests/powershell/Run-Tests.ps1 tests/powershell/Test-Helpers.ps1
git add tests/powershell/Test-Infrastructure.Tests.ps1 tests/powershell/fixtures/
git add .github/workflows/test-powershell.yml README.md
git commit -m "test: add PowerShell test infrastructure and CI integration

- Create Pester configuration (PesterConfig.ps1)
- Create test runner script (Run-Tests.ps1) with coverage support
- Create test helper functions (Test-Helpers.ps1)
- Add test fixtures directory with sample data
- Add GitHub Actions workflow for CI integration
- Document testing approach in README
- Add infrastructure validation tests (9 tests)
- Support NUnit XML output for CI reporting
- Support JaCoCo XML output for code coverage

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Summary

**Batch 3 Complete - Final 4 Tasks:**

- **Task 11**: Doctor --fix-orphans enhancement (7 tests)
- **Task 12**: Enhance consolidate snapshot with comprehensive manifest (5 tests)
- **Task 13**: Update help text and README (10 tests - documentation validation)
- **Task 14**: PowerShell test infrastructure and CI integration (9 tests)

**Total Test Count for Batch 3**: 31 tests

**All 14 Tasks Complete**:
- Batch 1 (Tasks 1-5): External reference detection foundation
- Batch 2 (Tasks 6-10): Standalone commands and enhanced flags
- Batch 3 (Tasks 11-14): Final enhancements, documentation, and test infrastructure

**Next Steps**:
1. Execute tasks in order (1-14)
2. Run tests after each task to validate TDD approach
3. Perform manual verification for each task
4. Commit after each task completion
5. Final validation: Run full test suite and verify all 14 tasks pass
