# Core.ps1
# Core utility functions for strap

# Unsafe commands list (disabled pending review)
$script:UNSAFE_COMMANDS = @(
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

function Assert-CommandSafe {
    param([string]$CommandName)
    if ($CommandName -in $script:UNSAFE_COMMANDS) {
        Write-Warning "[DISABLED] '$CommandName' is disabled pending review."
        Write-Warning "See: docs/incidents/2026-02-02-environment-corruption.md"
        return $false
    }
    return $true
}

function Die($msg) { throw $msg }
function Info($msg) { Write-Host "➡️  $msg" }
function Ok($msg) { Write-Host "✅ $msg" }
function Warn($msg) { Write-Warning $msg }

# Functions and variables are automatically available when dot-sourced

# Functions extracted from strap.ps1
function Ensure-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { Die "Missing required command: $name" }
}

