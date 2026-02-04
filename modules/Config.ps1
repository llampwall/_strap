# Config.ps1
# Configuration and registry management for strap

# Dot-source Core for utility functions
. "$PSScriptRoot\Core.ps1"

# Registry version constant
$script:LATEST_REGISTRY_VERSION = 1

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
  if ($null -eq $json.tools_root) {
    $json | Add-Member -NotePropertyName tools_root -NotePropertyValue "P:\software\_scripts" -Force
  }

  return $json
}

function Load-Registry($configObj) {
  $registryPath = $configObj.registry
  if (-not (Test-Path $registryPath)) {
    # Create empty registry if it doesn't exist
    $parentDir = Split-Path $registryPath -Parent
    if (-not (Test-Path $parentDir)) {
      New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    "[]" | Set-Content -LiteralPath $registryPath -NoNewline
    return @()
  }
  $content = Get-Content -LiteralPath $registryPath -Raw
  if ($content.Trim() -eq "[]") {
    return @()
  }
  $json = $content | ConvertFrom-Json

  # Handle both legacy (array) and new (object) formats
  if ($json -is [System.Array]) {
    # Legacy format: bare array
    return @($json)
  } elseif ($json.PSObject.Properties['entries']) {
    # New format: object with entries property
    $entries = $json.entries
    if ($entries -is [System.Array]) {
      return @($entries)
    } else {
      return @($entries)
    }
  } else {
    # Unknown format or single object: wrap in array
    return @($json)
  }
}

function Save-Registry($configObj, $entries) {
  $registryPath = $configObj.registry
  $tmpPath = "$registryPath.tmp"

  # Always write in versioned format (V1)
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $registryObj = [PSCustomObject]@{
    registry_version = 1
    updated_at = $timestamp
    entries = @($entries)
  }

  $json = $registryObj | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($tmpPath, $json, (New-Object System.Text.UTF8Encoding($false)))

  # Atomic move (overwrites destination)
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
    if (-not $entry.PSObject.Properties['scope'] -or $entry.scope -notin @('tool', 'software')) {
      $issues += "Entry ${idx}: missing or invalid 'scope' (must be 'tool' or 'software')"
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

# Functions and variables are automatically available when dot-sourced

# Functions extracted from strap.ps1
function Load-Registry($configObj) {
  $registryPath = $configObj.registry
  if (-not (Test-Path $registryPath)) {
    # Create empty registry if it doesn't exist
    $parentDir = Split-Path $registryPath -Parent
    if (-not (Test-Path $parentDir)) {
      New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    "[]" | Set-Content -LiteralPath $registryPath -NoNewline
    return @()
  }
  $content = Get-Content -LiteralPath $registryPath -Raw
  if ($content.Trim() -eq "[]") {
    return @()
  }
  $json = $content | ConvertFrom-Json

  # Handle both legacy (array) and new (object) formats
  if ($json -is [System.Array]) {
    # Legacy format: bare array
    return @($json)
  } elseif ($json.PSObject.Properties['entries']) {
    # New format: object with entries property
    $entries = $json.entries
    if ($entries -is [System.Array]) {
      return @($entries)
    } else {
      return @($entries)
    }
  } else {
    # Unknown format or single object: wrap in array
    return @($json)
  }
}


function Save-Registry($configObj, $entries) {
  $registryPath = $configObj.registry
  $tmpPath = "$registryPath.tmp"

  # Always write in versioned format (V1)
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $registryObj = [PSCustomObject]@{
    registry_version = 1
    updated_at = $timestamp
    entries = @($entries)
  }

  $json = $registryObj | ConvertTo-Json -Depth 10
  [System.IO.File]::WriteAllText($tmpPath, $json, (New-Object System.Text.UTF8Encoding($false)))

  # Atomic move (overwrites destination)
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
    if (-not $entry.PSObject.Properties['scope'] -or $entry.scope -notin @('tool', 'software')) {
      $issues += "Entry ${idx}: missing or invalid 'scope' (must be 'tool' or 'software')"
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

