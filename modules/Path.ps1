# Path.ps1
# Path utilities and git URL parsing for strap

# Dot-source dependencies
. "$PSScriptRoot\Core.ps1"

function Normalize-Path {
  param([string] $Path)
  if (-not $Path) { return "" }
  return [System.IO.Path]::GetFullPath($Path).ToLowerInvariant().Replace('/', '\').TrimEnd('\')
}

function Test-PathWithinRoot {
  param(
    [string] $Path,
    [string] $RootPath
  )
  if (-not $Path -or -not $RootPath) { return $false }
  $normalizedPath = Normalize-Path $Path
  $normalizedRoot = Normalize-Path $RootPath
  return $normalizedPath.StartsWith($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)
}

function Find-DuplicatePaths {
  param([array] $Paths)

  $seen = @{}
  foreach ($path in $Paths) {
    if (-not $path) { continue }
    $key = $path.ToLowerInvariant()
    if ($seen.ContainsKey($key) -and $seen[$key] -ne $path) {
      return "$($seen[$key]) <-> $path"
    }
    $seen[$key] = $path
  }
  return $null
}

function Parse-GitUrl($url) {
  # Extract repo name from git URL
  # Examples:
  #   https://github.com/user/repo.git -> repo
  #   https://github.com/user/repo -> repo
  #   git@github.com:user/repo.git -> repo
  #   https://github.com/user/repo/ -> repo
  #   https://github.com/user/repo.git?foo=bar -> repo

  $url = $url.Trim()

  # Remove query string if present
  if ($url -match '\?') {
    $url = $url.Substring(0, $url.IndexOf('?'))
  }

  # Remove trailing slashes
  $url = $url.TrimEnd('/')

  # Remove .git suffix if present
  if ($url.EndsWith(".git")) {
    $url = $url.Substring(0, $url.Length - 4)
  }

  # Extract last segment (handle both / and : separators for SSH URLs)
  $segments = $url -split '[/:]'
  $name = $segments[-1]

  if (-not $name) {
    Die "Could not parse repo name from URL: $url"
  }

  return $name
}

# Functions are automatically available when dot-sourced
