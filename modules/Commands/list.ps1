# list.ps1
# Command: Invoke-List

function Invoke-List {
  param(
    [switch] $FilterTool,
    [switch] $FilterSoftware,
    [switch] $OutputJson,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Apply filters
  $filtered = $registry
  if ($FilterTool) {
    $filtered = $filtered | Where-Object { $_.scope -eq "tool" }
  }
  if ($FilterSoftware) {
    $filtered = $filtered | Where-Object { $_.scope -eq "software" }
  }

  # Output
  if ($OutputJson) {
    $json = $filtered | ConvertTo-Json -Depth 10
    Write-Host $json
  } else {
    if ($filtered.Count -eq 0) {
      Info "No entries found"
      return
    }

    # Format as table
    Write-Host ""
    Write-Host ("NAME" + (" " * 20) + "SCOPE" + (" " * 5) + "PATH" + (" " * 40) + "URL" + (" " * 40) + "UPDATED")
    Write-Host ("-" * 150)

    foreach ($entry in $filtered) {
      $name = if ($entry.name.Length -gt 20) { $entry.name.Substring(0, 17) + "..." } else { $entry.name.PadRight(24) }
      $scope = $entry.scope.PadRight(10)
      $path = if ($entry.path.Length -gt 40) { "..." + $entry.path.Substring($entry.path.Length - 37) } else { $entry.path.PadRight(44) }
      $url = if ($entry.url.Length -gt 40) { $entry.url.Substring(0, 37) + "..." } else { $entry.url.PadRight(44) }
      $updated = if ($entry.updated_at) { $entry.updated_at } else { "N/A" }

      Write-Host "$name$scope$path$url$updated"
    }
    Write-Host ""
    Write-Host "Total: $($filtered.Count) entries"
  }
}

