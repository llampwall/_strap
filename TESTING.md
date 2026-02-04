# Testing Guide

This project uses Pester 5 for PowerShell testing.

## Prerequisites

Install Pester 5.0 or higher:

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck
```

## Run All Tests

```powershell
pwsh -File scripts\run_tests.ps1
```

Or from within PowerShell:

```powershell
Import-Module Pester -MinimumVersion 5.0.0
$config = New-PesterConfiguration
$config.Run.Path = 'tests\powershell'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Normal'
Invoke-Pester -Configuration $config
```

## Run Specific Test File

```powershell
Import-Module Pester -MinimumVersion 5.0.0
Invoke-Pester tests\powershell\YourTest.Tests.ps1 -Output Detailed
```

## Test Structure

All test files are located in `tests\powershell\` and follow the naming convention `*.Tests.ps1`.

## Migration to Pester 5

This project was migrated from Pester 3.4 to Pester 5 with the following changes:

### Assertion Syntax
Pester 5 requires dashes before operators:
- `Should Be` → `Should -Be`
- `Should Not Be` → `Should -Not -Be`
- `Should Match` → `Should -Match`
- `Should Contain` → `Should -Contain`

### Mock Assertions
- `Assert-MockCalled` → `Should -Invoke` (preferred in Pester 5)

### Invoke-Pester Usage
Pester 5 uses configuration objects instead of parameters:

**Pester 3.4:**
```powershell
$result = Invoke-Pester -Path tests\ -PassThru -Quiet
Write-Host "Passed: $($result.PassedCount)"
```

**Pester 5:**
```powershell
$config = New-PesterConfiguration
$config.Run.Path = 'tests\'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Minimal'
$result = Invoke-Pester -Configuration $config
Write-Host "Passed: $($result.Passed.Count)"
```

### Result Properties
- `.PassedCount` → `.Passed.Count`
- `.FailedCount` → `.Failed.Count`
- `.SkippedCount` → `.Skipped.Count`
- `.TotalCount` remains the same

## Test Utilities

Several utility scripts are available in the `scripts\` directory:

- `scripts\run_tests.ps1` - Run all tests with minimal output
- `scripts\final_test_summary.ps1` - Run all tests with detailed summary
- `scripts\quick_test_count.ps1` - Quick test count
- `scripts\get_test_summary.ps1` - Get test summary
- `scripts\get_detailed_results.ps1` - Get detailed test results
- `scripts\test_three_files.ps1` - Test specific files
- `scripts\test_batch.ps1` - Run batch tests

## Continuous Integration

To run tests in CI/CD pipelines:

```powershell
pwsh -Command "Import-Module Pester -MinimumVersion 5.0.0; $config = New-PesterConfiguration; $config.Run.Path = 'tests\powershell'; $config.Run.PassThru = $true; $config.Output.Verbosity = 'Minimal'; $result = Invoke-Pester -Configuration $config; exit $result.Failed.Count"
```

This will exit with a non-zero code if any tests fail.
