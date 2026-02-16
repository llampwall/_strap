# verify.ps1
# Command: Invoke-Verify
# Validate shims and setup for a repo with tiered checks

function Invoke-Verify {
  param(
    [Parameter(Mandatory)][string]$RepoName,
    [switch]$Tier1Only,
    [switch]$Tier2Only,
    [switch]$DeepDiagnostics,  # Include Tier 3
    [int]$TimeoutSeconds = 5,
    [switch]$Json,
    [string]$StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Find repo entry
  $repoEntry = $registry | Where-Object { $_.name -eq $RepoName -or $_.id -eq $RepoName }
  if (-not $repoEntry) {
    Die "Registry entry not found: '$RepoName'. Use 'strap list' to see all entries."
  }

  # Determine which tiers to run
  $tiers = @()
  if ($Tier1Only) {
    $tiers = @(1)
  } elseif ($Tier2Only) {
    $tiers = @(2)
  } elseif ($DeepDiagnostics) {
    $tiers = @(1, 2, 3)
  } else {
    # Default: Tier 1 + 2
    $tiers = @(1, 2)
  }

  Write-Host "Verifying: $($repoEntry.name)" -ForegroundColor Cyan
  Write-Host "Path: $($repoEntry.path)" -ForegroundColor Gray
  Write-Host "Stack: $($repoEntry.stack ? $repoEntry.stack : 'none')" -ForegroundColor Gray
  Write-Host ""

  # Show tier info
  $tierDescription = @{
    1 = "Tier 1: Filesystem checks (fast, always safe)"
    2 = "Tier 2: Conservative invocation (--version/--help)"
    3 = "Tier 3: Deep diagnostics (import tests, build checks)"
  }

  Write-Host "Running validation tiers:" -ForegroundColor Cyan
  foreach ($tier in $tiers) {
    Write-Host "  - $($tierDescription[$tier])" -ForegroundColor Gray
  }
  Write-Host ""

  # Run validation
  $validationSummary = Invoke-RepoValidation `
    -RepoEntry $repoEntry `
    -Config $config `
    -Tiers $tiers `
    -TimeoutSeconds $TimeoutSeconds `
    -Quiet:$false

  # Summary
  Write-Host ""
  Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
  Write-Host "Total shims: $($validationSummary.shimCount)"
  Write-Host "Passed: $($validationSummary.passedCount)" -ForegroundColor Green
  if ($validationSummary.failedCount -gt 0) {
    Write-Host "Failed: $($validationSummary.failedCount)" -ForegroundColor Red
  }

  # Tier 3 summary
  if ($validationSummary.tier3) {
    if ($validationSummary.tier3.passed) {
      Write-Host "Deep diagnostics: Passed" -ForegroundColor Green
    } else {
      Write-Host "Deep diagnostics: Failed" -ForegroundColor Red
    }
  }

  # JSON output
  if ($Json) {
    Write-Host ""
    Write-Host ($validationSummary | ConvertTo-Json -Depth 10)
  }

  # Exit code
  if ($validationSummary.failedCount -gt 0 -or ($validationSummary.tier3 -and -not $validationSummary.tier3.passed)) {
    exit 1
  } else {
    exit 0
  }
}
