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

  # Apply filters (legacy support)
  $filtered = $registry
  if ($FilterTool) {
    # Legacy: filter by third-party tag
    $filtered = $filtered | Where-Object { $_.tags -contains "third-party" }
  }
  if ($FilterSoftware) {
    # Legacy: filter by NOT third-party
    $filtered = $filtered | Where-Object { $_.tags -notcontains "third-party" }
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
    Write-Host ("NAME" + (" " * 20) + "STATUS" + (" " * 5) + "DEPTH" + (" " * 3) + "HEALTH" + (" " * 4) + "PATH" + (" " * 26) + "UPDATED")
    Write-Host ("-" * 150)

    foreach ($entry in $filtered) {
      $name = if ($entry.name.Length -gt 20) { $entry.name.Substring(0, 17) + "..." } else { $entry.name.PadRight(24) }
      $status = if ($entry.status) { $entry.status.PadRight(11) } else { "N/A".PadRight(11) }
      $depth = if ($entry.chinvex_depth) { $entry.chinvex_depth.PadRight(8) } else { "N/A".PadRight(8) }

      # Health status with color coding
      $healthText = "N/A"
      $healthColor = "Gray"
      if ($entry.PSObject.Properties['setup'] -and $entry.setup) {
        switch ($entry.setup.result) {
          "succeeded" { $healthText = "OK"; $healthColor = "Green" }
          "failed" { $healthText = "FAIL"; $healthColor = "Red" }
          "skipped" { $healthText = "SKIP"; $healthColor = "Yellow" }
          default { $healthText = "N/A"; $healthColor = "Gray" }
        }
      }
      $health = $healthText.PadRight(10)

      $path = if ($entry.path.Length -gt 31) { "..." + $entry.path.Substring($entry.path.Length - 28) } else { $entry.path.PadRight(30) }
      $updated = if ($entry.updated_at) { $entry.updated_at } else { "N/A" }

      Write-Host "$name$status$depth" -NoNewline
      Write-Host $health -ForegroundColor $healthColor -NoNewline
      Write-Host "$path$updated"
    }
    Write-Host ""
    Write-Host "Total: $($filtered.Count) entries"
  }
}

