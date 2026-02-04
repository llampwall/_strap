# open.ps1
# Command: Invoke-Open

function Invoke-Open {
  param(
    [string] $NameToOpen,
    [string] $StrapRootPath
  )

  if (-not $NameToOpen) { Die "open requires <name>" }

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Find entry by name
  $entry = $registry | Where-Object { $_.name -eq $NameToOpen }
  if (-not $entry) {
    Die "No entry found with name '$NameToOpen'. Use 'strap list' to see all entries."
  }

  $repoPath = $entry.path
  if (-not $repoPath) {
    Die "Registry entry has no path field"
  }

  if (-not (Test-Path $repoPath)) {
    Warn "Path does not exist: $repoPath"
    Die "Cannot open non-existent path"
  }

  Info "Opening: $repoPath"
  & explorer.exe $repoPath
}

