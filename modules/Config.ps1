# Config.ps1
# Configuration and registry management for strap

# Dot-source Core for utility functions
. "$PSScriptRoot\Core.ps1"

# Registry version constant
$script:LATEST_REGISTRY_VERSION = 3

function Load-Config($strapRoot) {
  $configPath = Join-Path $strapRoot "config.json"
  if (-not (Test-Path $configPath)) {
    Die "Config not found: $configPath"
  }
  $json = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json

  # Apply chinvex integration defaults (new fields)
  if ($null -eq $json.chinvex_integration) {
    $json | Add-Member -NotePropertyName chinvex_integration -NotePropertyValue $true -Force
  }
  if ($null -eq $json.chinvex_whitelist) {
    $json | Add-Member -NotePropertyName chinvex_whitelist -NotePropertyValue @("tools", "archive") -Force
  }
  if ($null -eq $json.software_root) {
    $json | Add-Member -NotePropertyName software_root -NotePropertyValue "P:\software" -Force
  }

  # Apply defaults for shims and nodeTools roots
  if (-not $json.roots.shims) {
    $json.roots | Add-Member -NotePropertyName shims -NotePropertyValue "P:\software\bin" -Force
  }
  if (-not $json.roots.nodeTools) {
    $json.roots | Add-Member -NotePropertyName nodeTools -NotePropertyValue "P:\software\_node-tools" -Force
  }

  # Apply defaults for pwshExe and nodeExe
  if (-not $json.defaults) {
    $json | Add-Member -NotePropertyName defaults -NotePropertyValue ([PSCustomObject]@{}) -Force
  }
  if (-not $json.defaults.pwshExe) {
    $json.defaults | Add-Member -NotePropertyName pwshExe -NotePropertyValue "C:\Program Files\PowerShell\7\pwsh.exe" -Force
  }
  if (-not $json.defaults.nodeExe) {
    $json.defaults | Add-Member -NotePropertyName nodeExe -NotePropertyValue "C:\nvm4w\nodejs\node.exe" -Force
  }

  return $json
}

function Load-Registry($configObj) {
  $registryPath = $configObj.registry
  if (-not (Test-Path $registryPath)) {
    # Create empty v2 registry
    $parentDir = Split-Path $registryPath -Parent
    if (-not (Test-Path $parentDir)) {
      New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    $empty = @{ version = $script:LATEST_REGISTRY_VERSION; repos = @() } | ConvertTo-Json -Depth 10
    $empty | Set-Content -LiteralPath $registryPath -NoNewline
    return @()
  }

  $json = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json

  # Handle legacy array format (v1)
  if ($json -is [System.Array]) {
    return ,@($json | ForEach-Object { $_ })
  }

  # Check version
  if ($json.version -and $json.version -gt $script:LATEST_REGISTRY_VERSION) {
    Die "Registry version $($json.version) requires newer strap (supports v$script:LATEST_REGISTRY_VERSION)"
  }

  # V2/V3 format
  if ($json.PSObject.Properties['repos']) {
    # V2→V3 migration
    if ($json.version -eq 2) {
      foreach ($entry in $json.repos) {
        # Determine new field values based on old scope
        $depth = 'full'
        $status = 'active'
        $tags = @()

        if ($entry.scope -eq 'archive') {
          $depth = 'index'
          $status = 'dormant'
        }
        elseif ($entry.scope -eq 'tool') {
          $depth = 'light'
          $status = 'stable'
          $tags = @('third-party')
        }

        # Add new fields if missing
        if (-not $entry.PSObject.Properties['chinvex_depth']) {
          $entry | Add-Member -NotePropertyName chinvex_depth -NotePropertyValue $depth -Force
        }
        if (-not $entry.PSObject.Properties['status']) {
          $entry | Add-Member -NotePropertyName status -NotePropertyValue $status -Force
        }
        if (-not $entry.PSObject.Properties['tags']) {
          $entry | Add-Member -NotePropertyName tags -NotePropertyValue $tags -Force
        }

        # Remove scope field
        $entry.PSObject.Properties.Remove('scope')
      }
      # Auto-save migrated registry
      $json.version = 3
      Save-Registry $configObj $json.repos
    }

    # Force array output using comma operator (prevents PS from unwrapping single-element arrays)
    return ,@($json.repos | ForEach-Object { $_ })
  }

  # Legacy v1 with entries field
  if ($json.entries) {
    return ,@($json.entries | ForEach-Object { $_ })
  }

  # Legacy v1 single object (when JSON array with 1 item is serialized/deserialized)
  if ($json.PSObject.Properties['name'] -and $json.PSObject.Properties['path']) {
    return ,@($json)
  }

  Die "Unrecognized registry format"
}

function Save-Registry($configObj, $entries) {
  $registryPath = $configObj.registry
  $tmpPath = "$registryPath.tmp"

  $registryObj = [PSCustomObject]@{
    version = $script:LATEST_REGISTRY_VERSION
    repos = @($entries)
  }

  $json = $registryObj | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($tmpPath, $json, (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -LiteralPath $tmpPath -Destination $registryPath -Force
}

function Get-RegistryVersion($registryPath) {
  if (-not (Test-Path $registryPath)) {
    return $null
  }

  $content = Get-Content -LiteralPath $registryPath -Raw
  if ($content.Trim() -eq "[]") {
    return 0
  }

  try {
    $json = $content | ConvertFrom-Json
  } catch {
    throw "Invalid JSON in registry"
  }

  # If it's an array, it's version 0
  if ($json -is [System.Array]) {
    return 0
  }

  # If it has registry_version, use it
  if ($json.PSObject.Properties['registry_version']) {
    return $json.registry_version
  }

  # Otherwise it's a legacy object, version 0
  return 0
}

function Validate-RegistrySchema {
  param([array] $Entries)

  $issues = @()

  for ($i = 0; $i -lt $Entries.Count; $i++) {
    $entry = $Entries[$i]
    $idx = $i + 1

    # Required fields
    if (-not $entry.PSObject.Properties['name'] -or -not $entry.name) {
      $issues += "Entry ${idx}: missing required field 'name'"
    }
    if (-not $entry.PSObject.Properties['id'] -or -not $entry.id) {
      $issues += "Entry ${idx}: missing required field 'id'"
    }
    # V3 metadata fields
    if (-not $entry.PSObject.Properties['chinvex_depth'] -or
        $entry.chinvex_depth -notin @('full', 'light', 'index')) {
      $issues += "Entry ${idx}: missing or invalid 'chinvex_depth' (must be 'full', 'light', or 'index')"
    }
    if (-not $entry.PSObject.Properties['status'] -or
        $entry.status -notin @('active', 'stable', 'dormant')) {
      $issues += "Entry ${idx}: missing or invalid 'status' (must be 'active', 'stable', or 'dormant')"
    }
    if (-not $entry.PSObject.Properties['tags']) {
      $issues += "Entry ${idx}: missing required field 'tags' (must be array)"
    }
    if (-not $entry.PSObject.Properties['path'] -or -not $entry.path) {
      $issues += "Entry ${idx}: missing required field 'path'"
    }
    if (-not $entry.PSObject.Properties['shims']) {
      $issues += "Entry ${idx}: missing required field 'shims'"
    }
    if (-not $entry.PSObject.Properties['created_at'] -or -not $entry.created_at) {
      $issues += "Entry ${idx}: missing required field 'created_at'"
    }
    if (-not $entry.PSObject.Properties['updated_at'] -or -not $entry.updated_at) {
      $issues += "Entry ${idx}: missing required field 'updated_at'"
    }
  }

  return $issues
}
