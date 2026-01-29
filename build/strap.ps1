param(
  [Parameter(Mandatory=$true, Position=0)]
  [string] $RepoName,

  [Alias("t")]
  [ValidateSet("node-ts-service","node-ts-web","python","mono")]
  [string] $Template,

  [Alias("p")]
  [string] $Path = "P:\\software",

  [Alias("skip-install")]
  [switch] $SkipInstall,

  [switch] $Install,

  [switch] $Start,

  [switch] $Keep,

  [string] $StrapRoot,

  [string] $Source,
  [string] $Message,
  [switch] $Push,
  [switch] $Force,
  [switch] $AllowDirty,

  [switch] $Tool,
  [string] $Name,
  [string] $Dest,

  [switch] $Software,
  [switch] $Json,

  [switch] $Yes,
  [switch] $DryRun,
  [switch] $KeepFolder,
  [switch] $KeepShims,

  [string] $Cwd,
  [string] $Repo,
  [string] $Cmd,

  [switch] $Rebase,
  [switch] $Stash,
  [switch] $Setup,
  [switch] $All,

  [ValidateSet("python", "node", "go", "rust")]
  [string] $Stack,
  [string] $Venv,
  [switch] $Uv,
  [string] $Python,
  [ValidateSet("npm", "pnpm", "yarn")]
  [string] $Pm,
  [switch] $Corepack,

  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]] $ExtraArgs
)

$ErrorActionPreference = "Stop"

function Die($msg) { Write-Error "❌ $msg"; exit 1 }
function Info($msg) { Write-Host "➡️  $msg" }
function Ok($msg) { Write-Host "✅ $msg" }
function Warn($msg) { Write-Warning $msg }

function Apply-ExtraArgs {
  param([string[]] $ArgsList)

  if (-not $ArgsList) { return }

  for ($i = 0; $i -lt $ArgsList.Count; $i++) {
    $arg = $ArgsList[$i]
    switch ($arg) {
      "--start" { $script:Start = $true; continue }
      "--install" { $script:Install = $true; continue }
      "--skip-install" { $script:SkipInstall = $true; continue }
      "--keep" { $script:Keep = $true; continue }
      "--strap-root" { if ($i + 1 -lt $ArgsList.Count) { $script:StrapRoot = $ArgsList[$i + 1]; $i++; continue } }
      "--template" { if ($i + 1 -lt $ArgsList.Count) { $script:Template = $ArgsList[$i + 1]; $i++; continue } }
      "-t" { if ($i + 1 -lt $ArgsList.Count) { $script:Template = $ArgsList[$i + 1]; $i++; continue } }
      "--path" { if ($i + 1 -lt $ArgsList.Count) { $script:Path = $ArgsList[$i + 1]; $i++; continue } }
      "-p" { if ($i + 1 -lt $ArgsList.Count) { $script:Path = $ArgsList[$i + 1]; $i++; continue } }
      "--source" { if ($i + 1 -lt $ArgsList.Count) { $script:Source = $ArgsList[$i + 1]; $i++; continue } }
      "--message" { if ($i + 1 -lt $ArgsList.Count) { $script:Message = $ArgsList[$i + 1]; $i++; continue } }
      "--push" { $script:Push = $true; continue }
      "--force" { $script:Force = $true; continue }
      "--allow-dirty" { $script:AllowDirty = $true; continue }
      "--tool" { $script:Tool = $true; continue }
      "--name" { if ($i + 1 -lt $ArgsList.Count) { $script:Name = $ArgsList[$i + 1]; $i++; continue } }
      "--dest" { if ($i + 1 -lt $ArgsList.Count) { $script:Dest = $ArgsList[$i + 1]; $i++; continue } }
      "--software" { $script:Software = $true; continue }
      "--json" { $script:Json = $true; continue }
      "--yes" { $script:Yes = $true; continue }
      "--dry-run" { $script:DryRun = $true; continue }
      "--keep-folder" { $script:KeepFolder = $true; continue }
      "--keep-shims" { $script:KeepShims = $true; continue }
      "--cwd" { if ($i + 1 -lt $ArgsList.Count) { $script:Cwd = $ArgsList[$i + 1]; $i++; continue } }
      "--repo" { if ($i + 1 -lt $ArgsList.Count) { $script:Repo = $ArgsList[$i + 1]; $i++; continue } }
      "--cmd" { if ($i + 1 -lt $ArgsList.Count) { $script:Cmd = $ArgsList[$i + 1]; $i++; continue } }
      "--rebase" { $script:Rebase = $true; continue }
      "--stash" { $script:Stash = $true; continue }
      "--setup" { $script:Setup = $true; continue }
      "--all" { $script:All = $true; continue }
      "--stack" { if ($i + 1 -lt $ArgsList.Count) { $script:Stack = $ArgsList[$i + 1]; $i++; continue } }
      "--venv" { if ($i + 1 -lt $ArgsList.Count) { $script:Venv = $ArgsList[$i + 1]; $i++; continue } }
      "--uv" { $script:Uv = $true; continue }
      "--python" { if ($i + 1 -lt $ArgsList.Count) { $script:Python = $ArgsList[$i + 1]; $i++; continue } }
      "--pm" { if ($i + 1 -lt $ArgsList.Count) { $script:Pm = $ArgsList[$i + 1]; $i++; continue } }
      "--corepack" { $script:Corepack = $true; continue }
      default { }
    }
  }
}

Apply-ExtraArgs $ExtraArgs

$TemplateRoot = if ($StrapRoot) { $StrapRoot } else { Split-Path $PSScriptRoot -Parent }
$DefaultBranch = if ($env:BOOTSTRAP_BRANCH) { $env:BOOTSTRAP_BRANCH } else { "main" }

function Show-Help {
  @"
strap usage:
  strap <project-name> -t <template> [-p <parent-dir>] [--skip-install] [--install] [--start]
  strap clone <git-url> [--tool] [--name <name>] [--dest <dir>]
  strap list [--tool] [--software] [--json]
  strap adopt [--path <dir>] [--name <name>] [--tool|--software] [--yes] [--dry-run]
  strap setup [--yes] [--dry-run] [--stack python|node|go|rust] [--repo <name>]
  strap setup [--venv <path>] [--uv] [--python <exe>] [--pm npm|pnpm|yarn] [--corepack]
  strap update <name> [--yes] [--dry-run] [--rebase] [--stash] [--setup]
  strap update --all [--tool] [--software] [--yes] [--dry-run] [--rebase] [--stash] [--setup]
  strap uninstall <name> [--yes] [--dry-run] [--keep-folder] [--keep-shims]
  strap shim <name> --- <command...> [--cwd <path>] [--repo <name>] [--force] [--dry-run] [--yes]
  strap shim <name> --cmd "<command>" [--cwd <path>] [--repo <name>] [--force] [--dry-run] [--yes]
  strap doctor [--json]
  strap templatize <templateName> [--source <path>] [--message "<msg>"] [--push] [--force] [--allow-dirty]

Templates:
  node-ts-service | node-ts-web | python | mono

Flags:
  --skip-install  skip dependency install
  --install       run full install after initial commit
  --start         full install, then start dev
  --keep          keep doctor artifacts
  --strap-root    override strap repo root
  --tool          filter by tool scope or clone to tools directory
  --software      filter by software scope
  --json          output raw JSON
  --name          custom name for cloned repo or shim
  --dest          full destination path (overrides --tool)
  --yes           non-interactive mode (no confirmation prompt)
  --dry-run       show planned actions without executing
  --keep-folder   preserve repo folder during uninstall
  --keep-shims    preserve shims during uninstall
  --cwd           working directory for shim execution
  --cmd           command string (alternative to --- for complex commands with flags)
  --repo          attach shim to specific registry entry or run setup for registered repo
  --stack         force stack selection (python|node|go|rust)
  --venv          venv directory for Python (default .venv)
  --uv            use uv for Python installs (default on)
  --python        python executable for venv creation (default python)
  --pm            force package manager for Node (npm|pnpm|yarn)
  --corepack      enable corepack before Node install (default on)
  --rebase        use git pull --rebase for update
  --stash         auto-stash dirty working tree before update
  --setup         run strap setup after successful update
  --all           update all registered repos (filtered by --tool/--software)
  --source        source repo for templatize
  --message       commit message for templatize
  --push          push after templatize commit
  --force         overwrite existing file/template
  --allow-dirty   allow templatize when strap repo is dirty
"@ | Write-Host
}

if ($RepoName -in @("--help","-h","help")) {
  Show-Help
  exit 0
}

function Ensure-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { Die "Missing required command: $name" }
}

function Has-Command($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Load-Config($strapRoot) {
  $configPath = Join-Path $strapRoot "config.json"
  if (-not (Test-Path $configPath)) {
    Die "Config not found: $configPath"
  }
  $json = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  return $json
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
  # Ensure we return an array even if there's only one item
  if ($json -is [System.Array]) {
    return @($json)
  } else {
    return @($json)
  }
}

function Save-Registry($configObj, $entries) {
  $registryPath = $configObj.registry
  $tmpPath = "$registryPath.tmp"

  # Write to temp file first
  # Handle empty array case explicitly
  if ($entries.Count -eq 0) {
    $json = "[]"
  } else {
    $json = $entries | ConvertTo-Json -Depth 10
  }
  [System.IO.File]::WriteAllText($tmpPath, $json, (New-Object System.Text.UTF8Encoding($false)))

  # Atomic move (overwrites destination)
  Move-Item -LiteralPath $tmpPath -Destination $registryPath -Force
}

function Copy-TemplateDir($src, $dest) {
  if (-not (Test-Path $src)) { Die "Template dir missing: $src" }
  Get-ChildItem -LiteralPath $src -Force | ForEach-Object {
    $target = Join-Path $dest $_.Name
    if ($_.PSIsContainer) {
      if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target | Out-Null }
      Get-ChildItem -LiteralPath $_.FullName -Force | ForEach-Object {
        $childTarget = Join-Path $target $_.Name
        Copy-Item -LiteralPath $_.FullName -Destination $childTarget -Recurse -Force
      }
    } else {
      Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
  }
}

function Is-ProbablyTextFile($path) {
  $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
  $binary = @(".png",".jpg",".jpeg",".gif",".ico",".pdf",".zip",".gz",".tgz",".woff",".woff2",".ttf",".eot",".exe",".dll")
  return -not ($binary -contains $ext)
}

function Normalize-TextFiles($root) {
  Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
    $p = $_.FullName
    if (-not (Is-ProbablyTextFile $p)) { return }

    $content = Get-Content -LiteralPath $p -Raw
    if ($null -eq $content) { $content = "" }
    $content = $content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($p, $content, (New-Object System.Text.UTF8Encoding($false)))
  }
}

function Replace-Tokens($root, $tokens) {
  Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
    $p = $_.FullName
    if (-not (Is-ProbablyTextFile $p)) { return }

    $content = Get-Content -LiteralPath $p -Raw
    if ($null -eq $content) { $content = "" }
    foreach ($k in $tokens.Keys) {
      $content = $content.Replace($k, $tokens[$k])
    }
    $content = $content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($p, $content, (New-Object System.Text.UTF8Encoding($false)))
  }
}

function Get-TokenMatches($root) {
  $pattern = "\{\{REPO_NAME\}\}|\{\{PY_PACKAGE\}\}|<REPO_NAME>|<PY_PACKAGE>"
  $ignoreGlobs = @(
    "!**/.git/**",
    "!**/node_modules/**",
    "!**/dist/**",
    "!**/build/**",
    "!**/coverage/**",
    "!**/.venv/**",
    "!**/__pycache__/**",
    "!**/.turbo/**",
    "!**/.vite/**",
    "!**/.pnpm-store/**"
  )

  $results = @()

  if (Has-Command rg) {
    $args = @("-n","-o") + ($ignoreGlobs | ForEach-Object { @("--glob", $_) }) + @($pattern, $root)
    $lines = & rg @args
    foreach ($line in $lines) {
      if ($line -match "^(.*?):(\\d+):(.*)$") {
        $results += [pscustomobject]@{ Path = $matches[1]; Line = [int]$matches[2]; Match = $matches[3] }
      }
    }
  } else {
    $files = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
      $_.FullName -notmatch "[\\/]\.git[\\/]" -and
      $_.FullName -notmatch "[\\/]node_modules[\\/]" -and
      $_.FullName -notmatch "[\\/]dist[\\/]" -and
      $_.FullName -notmatch "[\\/]build[\\/]" -and
      $_.FullName -notmatch "[\\/]coverage[\\/]" -and
      $_.FullName -notmatch "[\\/]\.venv[\\/]" -and
      $_.FullName -notmatch "[\\/]__pycache__[\\/]" -and
      $_.FullName -notmatch "[\\/]\.turbo[\\/]" -and
      $_.FullName -notmatch "[\\/]\.vite[\\/]" -and
      $_.FullName -notmatch "[\\/]\.pnpm-store[\\/]"
    }
    foreach ($file in $files) {
      $matches = Select-String -LiteralPath $file.FullName -Pattern $pattern -AllMatches -ErrorAction SilentlyContinue
      foreach ($m in $matches) {
        foreach ($one in $m.Matches) {
          $results += [pscustomobject]@{ Path = $m.Path; Line = $m.LineNumber; Match = $one.Value }
        }
      }
    }
  }

  $results | Where-Object { $_.Path -notmatch "[\\/]\.git[\\/]" }
}

function Replace-TokenNames($root, $tokens) {
  $entries = Get-ChildItem -LiteralPath $root -Recurse -Force
  $sorted = $entries | Sort-Object { $_.FullName.Length } -Descending

  foreach ($item in $sorted) {
    $name = $item.Name
    $newName = $name
    foreach ($k in $tokens.Keys) {
      $newName = $newName.Replace($k, $tokens[$k])
    }

    if ($newName -ne $name) {
      Rename-Item -LiteralPath $item.FullName -NewName $newName -Force
    }
  }
}

function Resolve-RemainingTokens($root, $tokens) {
  Replace-Tokens $root $tokens
  Replace-TokenNames $root $tokens
  Normalize-TextFiles $root

  $matches = Get-TokenMatches $root
  if ($matches -and $matches.Count -gt 0) {
    Warn "Unresolved template tokens remain:"
    $matches | ForEach-Object { Warn ("  {0}:{1} -> {2}" -f $_.Path, $_.Line, $_.Match) }
    exit 1
  }
}

function Prompt-Template() {
  Write-Host "Select template:"
  Write-Host "  1) node-ts-service"
  Write-Host "  2) node-ts-web"
  Write-Host "  3) python"
  Write-Host "  4) mono (pnpm workspace)"
  $choice = Read-Host ">"

  switch ($choice) {
    "1" { return "node-ts-service" }
    "2" { return "node-ts-web" }
    "3" { return "python" }
    "4" { return "mono" }
    default { Die "Invalid choice" }
  }
}

function Stop-ProcessTree($processId) {
  $children = Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $processId }
  foreach ($child in $children) {
    Stop-ProcessTree $child.ProcessId
  }
  try { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue } catch { }
}

function Wait-For-Health($port) {
  $deadline = (Get-Date).AddSeconds(10)
  while ((Get-Date) -lt $deadline) {
    try {
      $resp = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri ("http://127.0.0.1:{0}/health" -f $port)
      if ($resp.StatusCode -eq 200) { return $true }
    } catch { }
    Start-Sleep -Milliseconds 500
  }
  return $false
}

function Get-FreePort($preferred) {
  $port = $preferred
  for ($i = 0; $i -lt 20; $i++) {
    try {
      $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
      $listener.Start()
      $listener.Stop()
      return $port
    } catch {
      $port = $port + 1
    }
  }
  return $preferred
}

function Read-EnvDefaults($path) {
  $vars = @{}
  if (-not (Test-Path $path)) { return $vars }
  Get-Content -LiteralPath $path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#")) { return }
    $parts = $line.Split("=", 2)
    if ($parts.Count -eq 2) {
      $vars[$parts[0].Trim()] = $parts[1].Trim()
    }
  }
  return $vars
}

function Resolve-GitRoot($path) {
  $p = (Resolve-Path -LiteralPath $path).Path
  $gitRoot = & git -C $p rev-parse --show-toplevel 2>$null
  if (-not $gitRoot) { return $null }
  return $gitRoot.Trim()
}

function Get-TemplateNameFromArgs([string[]] $ArgsList) {
  if (-not $ArgsList) { return $null }
  $skipNext = $false
  foreach ($arg in $ArgsList) {
    if ($skipNext) { $skipNext = $false; continue }
    switch -Regex ($arg) {
      '^(--source|--message)$' { $skipNext = $true; continue }
      '^(--push|--force|--allow-dirty)$' { continue }
      '^-{1,2}.*' { continue }
      default { return $arg }
    }
  }
  return $null
}

function Should-ExcludePath($fullPath, $root) {
  $rel = $fullPath.Substring($root.Length).TrimStart('\\','/')
  if (-not $rel) { return $false }
  if ($rel -match '(?i)^[^\\/]*\\.git(\\|/|$)') { return $true }
  if ($rel -match '(?i)(\\|/)(\.git|node_modules|dist|build|\.turbo|\.vite|\.next|coverage|\.pytest_cache|__pycache__|\.venv|venv|\.pnpm-store|pnpm-store)(\\|/|$)') { return $true }
  if ($rel -match '(?i)\.(log|tmp)$') { return $true }
  return $false
}

function Copy-RepoSnapshot($src, $dest) {
  if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
  if (Has-Command robocopy) {
    $xd = @('.git','node_modules','dist','build','.turbo','.vite','.next','coverage','.pytest_cache','__pycache__','.venv','venv','.pnpm-store','pnpm-store')
    $xf = @('*.log','*.tmp')
    $args = @($src, $dest, '/E','/SL','/XJ','/R:2','/W:1','/NFL','/NDL','/NJH','/NJS','/NP')
    foreach ($d in $xd) { $args += '/XD'; $args += $d }
    foreach ($f in $xf) { $args += '/XF'; $args += $f }
    & robocopy @args | Out-Null
    $code = $LASTEXITCODE
    if ($code -ge 8) { return $false }
    return $true
  }

  $items = Get-ChildItem -LiteralPath $src -Recurse -Force
  foreach ($item in $items) {
    $full = $item.FullName
    if (Should-ExcludePath $full $src) { continue }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }

    $rel = $full.Substring($src.Length).TrimStart('\\','/')
    $target = Join-Path $dest $rel

    if ($item.PSIsContainer) {
      if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target | Out-Null }
    } else {
      $parent = Split-Path $target -Parent
      if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
      Copy-Item -LiteralPath $full -Destination $target -Force
    }
  }
  return $true
}

function Invoke-Clone {
  param(
    [string] $GitUrl,
    [string] $CustomName,
    [string] $DestPath,
    [switch] $IsTool,
    [string] $StrapRootPath
  )

  Ensure-Command git

  if (-not $GitUrl) { Die "clone requires a git URL" }

  # Load config
  $config = Load-Config $StrapRootPath

  # Parse repo name from URL
  $repoName = if ($CustomName) { $CustomName } else { Parse-GitUrl $GitUrl }

  # Determine destination
  $destPath = if ($DestPath) {
    $DestPath
  } elseif ($IsTool) {
    Join-Path $config.roots.tools $repoName
  } else {
    Join-Path $config.roots.software $repoName
  }

  # Check if destination already exists
  if (Test-Path $destPath) {
    Die "Destination already exists: $destPath"
  }

  # Load registry and check for duplicate name BEFORE cloning
  $registry = Load-Registry $config
  $existing = $registry | Where-Object { $_.name -eq $repoName }
  if ($existing) {
    Die "Entry with name '$repoName' already exists in registry at $($existing.path). Use --name to specify a different name."
  }

  Info "Cloning $GitUrl -> $destPath"

  # Clone the repo (capture output for error reporting)
  $gitOutput = & git clone $GitUrl $destPath 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Git clone failed with output:"
    Write-Host $gitOutput
    Die "Git clone failed"
  }

  Ok "Cloned to $destPath"

  # Resolve to absolute path for registry
  $absolutePath = (Resolve-Path -LiteralPath $destPath).Path

  # Create new entry with ID
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $entry = [PSCustomObject]@{
    id         = $repoName
    name       = $repoName
    url        = $GitUrl
    path       = $absolutePath
    scope      = if ($IsTool) { "tool" } else { "software" }
    shims      = @()
    stack      = @()
    created_at = $timestamp
    updated_at = $timestamp
  }

  # Add to registry
  $newRegistry = @()
  foreach ($item in $registry) {
    $newRegistry += $item
  }
  $newRegistry += $entry
  Save-Registry $config $newRegistry

  Ok "Added to registry"

  # TODO: Offer to run setup / create shim
  Info "Next steps:"
  Info "  cd $absolutePath"
  Info "  strap setup (to install dependencies)"
  Info "  strap shim <name> -- <command> (to create a launcher)"
}

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

function Invoke-Uninstall {
  param(
    [string] $NameToRemove,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [switch] $PreserveFolder,
    [switch] $PreserveShims,
    [string] $StrapRootPath
  )

  if (-not $NameToRemove) { Die "uninstall requires <name>" }

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Find entry by name
  $entry = $registry | Where-Object { $_.name -eq $NameToRemove }
  if (-not $entry) {
    Die "No entry found with name '$NameToRemove'. Use 'strap list' to see all entries."
  }

  # Safety validation - check managed roots
  $softwareRoot = $config.roots.software
  $toolsRoot = $config.roots.tools
  $shimsRoot = $config.roots.shims

  # Validate repo path
  $repoPath = $entry.path
  if (-not $repoPath) {
    Die "Registry entry has no path field"
  }

  # Check that path is within managed roots
  $pathIsManaged = $repoPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase) -or
                   $repoPath.StartsWith($toolsRoot, [StringComparison]::OrdinalIgnoreCase)

  if (-not $pathIsManaged) {
    Die "Path is not within managed roots: $repoPath"
  }

  # Disallow deleting the root directories themselves
  if ($repoPath -eq $softwareRoot -or $repoPath -eq $toolsRoot) {
    Die "Cannot delete root directory: $repoPath"
  }

  # Validate shim paths
  $shimsToDelete = @()
  if (-not $PreserveShims -and $entry.shims) {
    foreach ($shim in $entry.shims) {
      # Must be absolute
      if (-not [System.IO.Path]::IsPathRooted($shim)) {
        Die "Shim path is not absolute: $shim"
      }

      # Must be within shims root
      if (-not $shim.StartsWith($shimsRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Die "Shim path is not within shims root: $shim"
      }

      # Must not be the root directory itself
      if ($shim -eq $shimsRoot) {
        Die "Cannot delete shims root directory: $shim"
      }

      # Must be a file path (ends with .cmd, .ps1, etc., not a directory)
      if (Test-Path $shim) {
        $item = Get-Item -LiteralPath $shim
        if ($item.PSIsContainer) {
          Die "Shim path is a directory, not a file: $shim"
        }
      }

      $shimsToDelete += $shim
    }
  }

  # Preview
  Write-Host ""
  Write-Host "=== UNINSTALL PREVIEW ===" -ForegroundColor Cyan
  Write-Host "Entry:  $($entry.name) ($($entry.scope))"
  if ($entry.url) {
    Write-Host "URL:    $($entry.url)"
  }
  Write-Host "Path:   $repoPath"

  if ($shimsToDelete.Count -gt 0) {
    Write-Host ""
    Write-Host "Will remove shims:" -ForegroundColor Yellow
    foreach ($shim in $shimsToDelete) {
      Write-Host "  - $shim"
    }
  } elseif ($PreserveShims -and $entry.shims -and $entry.shims.Count -gt 0) {
    Write-Host ""
    Write-Host "Will keep shims (--keep-shims):" -ForegroundColor Green
    foreach ($shim in $entry.shims) {
      Write-Host "  - $shim"
    }
  }

  if (-not $PreserveFolder) {
    Write-Host ""
    Write-Host "Will remove folder:" -ForegroundColor Yellow
    Write-Host "  - $repoPath"
  } else {
    Write-Host ""
    Write-Host "Will keep folder (--keep-folder):" -ForegroundColor Green
    Write-Host "  - $repoPath"
  }

  Write-Host ""
  Write-Host "Will remove registry entry: $($entry.name)" -ForegroundColor Yellow

  if ($DryRunMode) {
    Write-Host ""
    Write-Host "DRY RUN - no changes will be made" -ForegroundColor Cyan
    return
  }

  # Confirmation
  if (-not $NonInteractive) {
    Write-Host ""
    $response = Read-Host "Proceed? (y/n)"
    if ($response -ne "y") {
      Info "Aborted by user"
      exit 1
    }
  }

  Write-Host ""

  # Execute deletions
  # 1. Remove shims
  if ($shimsToDelete.Count -gt 0) {
    Info "Removing shims..."
    foreach ($shim in $shimsToDelete) {
      if (-not (Test-Path $shim)) {
        Write-Host "  skip (not found): $shim" -ForegroundColor Gray
      } else {
        try {
          Remove-Item -LiteralPath $shim -Force -ErrorAction Stop
          Write-Host "  deleted: $shim" -ForegroundColor Green
        } catch {
          Write-Host "  ERROR deleting $shim : $_" -ForegroundColor Red
          Die "Failed to delete shim: $shim"
        }
      }
    }
  }

  # 2. Remove folder
  if (-not $PreserveFolder) {
    Info "Removing folder..."
    if (-not (Test-Path $repoPath)) {
      Write-Host "  skip (not found): $repoPath" -ForegroundColor Gray
    } else {
      try {
        Remove-Item -LiteralPath $repoPath -Recurse -Force -ErrorAction Stop
        Write-Host "  deleted: $repoPath" -ForegroundColor Green
      } catch {
        Write-Host "  ERROR deleting $repoPath : $_" -ForegroundColor Red
        Die "Failed to delete folder: $repoPath"
      }
    }
  }

  # 3. Remove registry entry
  Info "Updating registry..."
  $newRegistry = @()
  foreach ($item in $registry) {
    if ($item.name -ne $NameToRemove) {
      $newRegistry += $item
    }
  }

  try {
    Save-Registry $config $newRegistry
    Ok "Registry updated"
  } catch {
    Write-Host "ERROR updating registry: $_" -ForegroundColor Red
    exit 3
  }

  Write-Host ""
  Ok "Uninstalled '$NameToRemove'"
}

function Invoke-Shim {
  param(
    [string] $ShimName,
    [string] $CommandLine,
    [string] $WorkingDir,
    [string] $RegistryEntryName,
    [switch] $ForceOverwrite,
    [switch] $DryRunMode,
    [switch] $NonInteractive,
    [string] $StrapRootPath
  )

  if (-not $ShimName) { Die "shim requires <name>" }
  if (-not $CommandLine) { Die "shim requires a command (use --- <command...> or --cmd `"<command>`")" }

  # Validate shim name (no path separators or reserved chars)
  if ($ShimName -match '[\\/:*?"<>|]') {
    Die "Invalid shim name: '$ShimName' (contains path separators or reserved characters)"
  }

  # Normalize name (trim, replace spaces with -)
  $ShimName = $ShimName.Trim() -replace '\s+', '-'

  # Load config
  $config = Load-Config $StrapRootPath
  $shimsRoot = $config.roots.shims

  # Determine shim path
  $shimPath = Join-Path $shimsRoot "$ShimName.cmd"
  $shimPathResolved = [System.IO.Path]::GetFullPath($shimPath)

  # Safety: ensure shimPath is within shimsRoot
  $shimsRootResolved = [System.IO.Path]::GetFullPath($shimsRoot)
  if (-not $shimPathResolved.StartsWith($shimsRootResolved, [StringComparison]::OrdinalIgnoreCase)) {
    Die "Shim path is not within shims root: $shimPathResolved"
  }

  # Load registry
  $registry = Load-Registry $config

  # Determine registry attachment
  $attachedEntry = $null

  if ($RegistryEntryName) {
    # User specified --repo
    $attachedEntry = $registry | Where-Object { $_.name -eq $RegistryEntryName }
    if (-not $attachedEntry) {
      Die "Registry entry not found: '$RegistryEntryName'. Use 'strap list' to see all entries."
    }
  } else {
    # Try to match current directory to a registry entry
    $currentDir = (Get-Location).Path
    $currentDirResolved = [System.IO.Path]::GetFullPath($currentDir)

    foreach ($entry in $registry) {
      $entryPathResolved = [System.IO.Path]::GetFullPath($entry.path)

      # Check if current dir equals or is inside entry path
      if ($currentDirResolved -eq $entryPathResolved -or
          $currentDirResolved.StartsWith("$entryPathResolved\", [StringComparison]::OrdinalIgnoreCase)) {
        $attachedEntry = $entry
        break
      }
    }

    if (-not $attachedEntry) {
      Die "No registry entry found for current directory. Run from inside a registered repo or use --repo <name>."
    }
  }

  # Preview
  Write-Host ""
  Write-Host "=== SHIM PREVIEW ===" -ForegroundColor Cyan
  Write-Host "Shim name:      $ShimName"
  Write-Host "Shim path:      $shimPathResolved"
  Write-Host "Attached repo:  $($attachedEntry.name) ($($attachedEntry.scope))"
  Write-Host "Repo path:      $($attachedEntry.path)"
  Write-Host "Command:        $CommandLine"
  if ($WorkingDir) {
    Write-Host "Working dir:    $WorkingDir"
  }

  # Check if shim already exists
  if (Test-Path $shimPathResolved) {
    if (-not $ForceOverwrite) {
      Write-Host ""
      Write-Host "Shim already exists at: $shimPathResolved" -ForegroundColor Yellow
      Die "Use --force to overwrite"
    }
    Write-Host ""
    Write-Host "Will overwrite existing shim (--force)" -ForegroundColor Yellow
  }

  if ($DryRunMode) {
    Write-Host ""
    Write-Host "DRY RUN - no changes will be made" -ForegroundColor Cyan
    return
  }

  # Confirmation
  if (-not $NonInteractive) {
    Write-Host ""
    $response = Read-Host "Proceed? (y/n)"
    if ($response -ne "y") {
      Info "Aborted by user"
      exit 1
    }
  }

  Write-Host ""

  # Generate shim content
  $shimContent = @"
@echo off
setlocal

"@

  if ($WorkingDir) {
    $shimContent += @"
pushd "$WorkingDir" >nul

"@
  }

  $shimContent += @"
$CommandLine %*
set "EC=%ERRORLEVEL%"

"@

  if ($WorkingDir) {
    $shimContent += @"
popd >nul

"@
  }

  $shimContent += @"
exit /b %EC%
"@

  # Write shim file
  Info "Creating shim..."
  try {
    # Ensure shims directory exists
    if (-not (Test-Path $shimsRoot)) {
      New-Item -ItemType Directory -Path $shimsRoot -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($shimPathResolved, $shimContent, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  created: $shimPathResolved" -ForegroundColor Green
  } catch {
    Write-Host "  ERROR creating shim: $_" -ForegroundColor Red
    exit 2
  }

  # Update registry entry
  Info "Updating registry..."

  # Find the entry in the registry array (we need to work with the original array)
  $entryIndex = -1
  for ($i = 0; $i -lt $registry.Count; $i++) {
    if ($registry[$i].name -eq $attachedEntry.name) {
      $entryIndex = $i
      break
    }
  }

  if ($entryIndex -eq -1) {
    Die "Internal error: could not find entry in registry after validation"
  }

  # Ensure shims array exists
  if (-not $registry[$entryIndex].shims) {
    $registry[$entryIndex] | Add-Member -NotePropertyName "shims" -NotePropertyValue @() -Force
  }

  # Add shim path if not already present
  $shimsList = @($registry[$entryIndex].shims)
  if ($shimPathResolved -notin $shimsList) {
    $shimsList += $shimPathResolved
    $registry[$entryIndex].shims = $shimsList
  }

  # Update timestamp
  $registry[$entryIndex].updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

  # Save registry
  try {
    Save-Registry $config $registry
    Ok "Registry updated"
  } catch {
    Write-Host "ERROR updating registry: $_" -ForegroundColor Red
    exit 3
  }

  Write-Host ""
  Ok "Shim created: $ShimName"
  Info "You can now run '$ShimName' from anywhere"
}

function Invoke-Setup {
  param(
    [string] $RepoNameOrPath,
    [string] $ForceStack,
    [string] $VenvPath,
    [switch] $UseUv,
    [string] $PythonExe,
    [string] $PackageManager,
    [switch] $EnableCorepack,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Determine repo path
  $repoPath = $null
  $registryEntry = $null

  if ($RepoNameOrPath) {
    # Look up in registry
    $registryEntry = $registry | Where-Object { $_.name -eq $RepoNameOrPath -or $_.id -eq $RepoNameOrPath }
    if (-not $registryEntry) {
      Die "Registry entry not found: '$RepoNameOrPath'. Use 'strap list' to see all entries."
    }
    $repoPath = $registryEntry.path
    Info "Setting up registered repo: $RepoNameOrPath"
    Info "Path: $repoPath"
  } else {
    # Use current directory
    $repoPath = Get-Location
    Info "Setting up current directory: $repoPath"

    # Try to find matching registry entry
    $registryEntry = $registry | Where-Object { $_.path -eq $repoPath }
  }

  # Safety validation: ensure path is within managed roots
  $resolvedPath = [System.IO.Path]::GetFullPath($repoPath)
  $softwareRoot = "P:\software"
  $scriptsRoot = "P:\software\_scripts"

  $withinSoftware = $resolvedPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase)
  $withinScripts = $resolvedPath.StartsWith($scriptsRoot, [StringComparison]::OrdinalIgnoreCase)

  if (-not ($withinSoftware -or $withinScripts)) {
    Die "Path is not within managed roots: $resolvedPath"
  }

  # Change to repo directory
  Push-Location $resolvedPath

  try {
    # Stack detection
    $detectedStacks = @()

    if (Test-Path "pyproject.toml") { $detectedStacks += "python" }
    elseif (Test-Path "requirements.txt") { $detectedStacks += "python" }

    if (Test-Path "package.json") { $detectedStacks += "node" }
    if (Test-Path "Cargo.toml") { $detectedStacks += "rust" }
    if (Test-Path "go.mod") { $detectedStacks += "go" }

    $dockerDetected = $false
    if ((Test-Path "Dockerfile") -or (Test-Path "compose.yaml") -or (Test-Path "docker-compose.yml")) {
      $dockerDetected = $true
    }

    # Determine stack to use
    $stack = $null
    if ($ForceStack) {
      $stack = $ForceStack
      Info "Forced stack: $stack"
    } elseif ($detectedStacks.Count -eq 0) {
      if ($dockerDetected) {
        Write-Host ""
        Write-Host "Docker detected; not auto-running containers (manual step)." -ForegroundColor Yellow
        Pop-Location
        exit 0
      } else {
        Die "No recognized stack detected. Use --stack to force selection."
      }
    } elseif ($detectedStacks.Count -gt 1) {
      Write-Host ""
      Write-Host "Multiple stacks detected: $($detectedStacks -join ', ')" -ForegroundColor Yellow
      Write-Host "Use --stack <stack> to select one" -ForegroundColor Yellow
      Pop-Location
      exit 1
    } else {
      $stack = $detectedStacks[0]
      Info "Detected stack: $stack"
    }

    if ($dockerDetected -and -not $ForceStack) {
      Write-Host "  (Docker also detected; not auto-running)" -ForegroundColor Yellow
    }

    # Generate install plan
    $plan = @()

    switch ($stack) {
      "python" {
        # Defaults
        $venvDir = if ($VenvPath) { $VenvPath } else { ".venv" }
        $pythonCmd = if ($PythonExe) { $PythonExe } else { "python" }
        $useUvFlag = if ($PSBoundParameters.ContainsKey('UseUv')) { $UseUv } else { $true }

        $venvPython = Join-Path $venvDir "Scripts\python.exe"

        # Step 1: Create venv if missing
        if (-not (Test-Path $venvPython)) {
          $plan += @{
            Description = "Create Python virtual environment"
            Command = "$pythonCmd -m venv $venvDir"
          }
        }

        # Step 2: Install/upgrade pip and uv
        if ($useUvFlag) {
          $plan += @{
            Description = "Install/upgrade pip and uv in venv"
            Command = "$venvPython -m pip install -U pip uv"
          }
        } else {
          $plan += @{
            Description = "Install/upgrade pip in venv"
            Command = "$venvPython -m pip install -U pip"
          }
        }

        # Step 3: Install dependencies
        if (Test-Path "pyproject.toml") {
          if ($useUvFlag) {
            $plan += @{
              Description = "Install dependencies via uv sync"
              Command = "$venvPython -m uv sync"
            }
          } else {
            $plan += @{
              Description = "Install dependencies via pip (editable)"
              Command = "$venvPython -m pip install -e ."
            }
          }
        } elseif (Test-Path "requirements.txt") {
          if ($useUvFlag) {
            $plan += @{
              Description = "Install dependencies from requirements.txt via uv"
              Command = "$venvPython -m uv pip install -r requirements.txt"
            }
          } else {
            $plan += @{
              Description = "Install dependencies from requirements.txt via pip"
              Command = "$venvPython -m pip install -r requirements.txt"
            }
          }
        }
      }

      "node" {
        # Defaults
        $enableCorepackFlag = if ($PSBoundParameters.ContainsKey('EnableCorepack')) { $EnableCorepack } else { $true }
        $pm = $PackageManager

        # Step 1: Enable corepack if requested
        if ($enableCorepackFlag) {
          $plan += @{
            Description = "Enable corepack"
            Command = "corepack enable"
          }
        }

        # Step 2: Determine package manager and install
        if (-not $pm) {
          if (Test-Path "pnpm-lock.yaml") {
            $pm = "pnpm"
          } elseif (Test-Path "yarn.lock") {
            $pm = "yarn"
          } else {
            $pm = "npm"
          }
        }

        $plan += @{
          Description = "Install Node dependencies via $pm"
          Command = "$pm install"
        }
      }

      "rust" {
        $plan += @{
          Description = "Build Rust project"
          Command = "cargo build"
        }
      }

      "go" {
        $plan += @{
          Description = "Download Go modules"
          Command = "go mod download"
        }
      }

      default {
        Die "Unsupported stack: $stack"
      }
    }

    # Print plan preview
    Write-Host ""
    Write-Host "=== SETUP PLAN ===" -ForegroundColor Cyan
    Write-Host "Repo path:  $resolvedPath"
    Write-Host "Stack:      $stack"
    Write-Host ""
    Write-Host "Commands to execute:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $plan.Count; $i++) {
      Write-Host "  $($i + 1). $($plan[$i].Description)" -ForegroundColor Yellow
      Write-Host "     $($plan[$i].Command)" -ForegroundColor Gray
    }
    Write-Host ""

    if ($DryRunMode) {
      Write-Host "DRY RUN - no changes will be made" -ForegroundColor Yellow
      Pop-Location
      exit 0
    }

    # Confirmation
    if (-not $NonInteractive) {
      $response = Read-Host "Proceed with setup? (y/n)"
      if ($response -ne "y") {
        Info "Aborted by user"
        Pop-Location
        exit 1
      }
    }

    # Execute plan
    Write-Host "=== EXECUTING ===" -ForegroundColor Cyan
    foreach ($step in $plan) {
      Info $step.Description
      Write-Host "  > $($step.Command)" -ForegroundColor Gray

      # Execute command
      $output = Invoke-Expression $step.Command 2>&1
      if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "ERROR: Command failed with exit code $LASTEXITCODE" -ForegroundColor Red
        Write-Host $output
        Pop-Location
        exit 2
      }
    }

    Write-Host ""
    Ok "Setup completed successfully"

    # Update registry if entry exists
    if ($registryEntry) {
      Info "Updating registry metadata..."

      # Find entry index
      $entryIndex = -1
      for ($i = 0; $i -lt $registry.Count; $i++) {
        if ($registry[$i].id -eq $registryEntry.id) {
          $entryIndex = $i
          break
        }
      }

      if ($entryIndex -ne -1) {
        $currentEntry = $registry[$entryIndex]

        # Update timestamp
        $currentEntry.updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

        # Add/update setup metadata
        if ($currentEntry.PSObject.Properties['stack_detected']) {
          $currentEntry.stack_detected = $stack
        } else {
          $currentEntry | Add-Member -NotePropertyName 'stack_detected' -NotePropertyValue $stack -Force
        }

        if ($currentEntry.PSObject.Properties['setup_last_run_at']) {
          $currentEntry.setup_last_run_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        } else {
          $currentEntry | Add-Member -NotePropertyName 'setup_last_run_at' -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")) -Force
        }

        if ($currentEntry.PSObject.Properties['setup_status']) {
          $currentEntry.setup_status = "success"
        } else {
          $currentEntry | Add-Member -NotePropertyName 'setup_status' -NotePropertyValue "success" -Force
        }

        # Save registry
        try {
          Save-Registry $config $registry
          Write-Host "  registry updated" -ForegroundColor Green
        } catch {
          Write-Host "  ERROR updating registry: $_" -ForegroundColor Red
          Pop-Location
          exit 3
        }
      }
    }

    Pop-Location
    exit 0

  } catch {
    Write-Host ""
    Write-Host "ERROR: $_" -ForegroundColor Red
    Pop-Location
    exit 2
  }
}

function Invoke-Update {
  param(
    [string] $NameToUpdate,
    [switch] $UpdateAll,
    [switch] $FilterTool,
    [switch] $FilterSoftware,
    [switch] $UseRebase,
    [switch] $AutoStash,
    [switch] $RunSetup,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  if (-not $registry -or $registry.Count -eq 0) {
    Info "No entries in registry"
    exit 0
  }

  # Determine which entries to update
  $entriesToUpdate = @()

  if ($UpdateAll) {
    # Filter by scope if requested
    $entriesToUpdate = $registry | Where-Object {
      if ($FilterTool -and $_.scope -ne "tool") { return $false }
      if ($FilterSoftware -and $_.scope -ne "software") { return $false }
      return $true
    }

    if ($entriesToUpdate.Count -eq 0) {
      Info "No entries match filter criteria"
      exit 0
    }
  } else {
    # Find single entry by name
    if (-not $NameToUpdate) {
      Die "update requires <name> or --all flag"
    }

    $entry = $registry | Where-Object { $_.name -eq $NameToUpdate -or $_.id -eq $NameToUpdate }
    if (-not $entry) {
      Die "Registry entry not found: '$NameToUpdate'. Use 'strap list' to see all entries."
    }

    $entriesToUpdate = @($entry)
  }

  # Counters for summary
  $updated = 0
  $skippedDirty = 0
  $failed = 0
  $dryRunCount = 0

  foreach ($entry in $entriesToUpdate) {
    $entryName = $entry.name
    $entryPath = $entry.path
    $entryScope = if ($entry.scope) { $entry.scope } else { "unknown" }

    Write-Host ""
    Write-Host "=== UPDATE: $entryName ($entryScope) ===" -ForegroundColor Cyan

    # Safety validation: ensure path is absolute and within managed roots
    if (-not [System.IO.Path]::IsPathRooted($entryPath)) {
      Write-Host "  ERROR: Path is not absolute: $entryPath" -ForegroundColor Red
      $failed++
      continue
    }

    $resolvedPath = [System.IO.Path]::GetFullPath($entryPath)
    $softwareRoot = "P:\software"
    $scriptsRoot = "P:\software\_scripts"

    $withinSoftware = $resolvedPath.StartsWith($softwareRoot, [StringComparison]::OrdinalIgnoreCase)
    $withinScripts = $resolvedPath.StartsWith($scriptsRoot, [StringComparison]::OrdinalIgnoreCase)

    if (-not ($withinSoftware -or $withinScripts)) {
      Write-Host "  ERROR: Path is not within managed roots: $resolvedPath" -ForegroundColor Red
      $failed++
      continue
    }

    # Reject root directories themselves
    if ($resolvedPath -eq $softwareRoot -or $resolvedPath -eq $scriptsRoot) {
      Write-Host "  ERROR: Cannot update root directory: $resolvedPath" -ForegroundColor Red
      $failed++
      continue
    }

    # Check git presence
    $gitDir = Join-Path $resolvedPath ".git"
    if (-not (Test-Path $gitDir)) {
      Write-Host "  WARN: No .git directory found, skipping" -ForegroundColor Yellow
      $skippedDirty++
      continue
    }

    # Preview
    Write-Host "Path:           $resolvedPath"
    $pullCommand = if ($UseRebase) { "pull --rebase" } else { "pull" }
    Write-Host "Operation:      git $pullCommand"

    # Check dirty status
    $dirtyOutput = & git -C $resolvedPath status --porcelain 2>&1
    $isDirty = $dirtyOutput -and ($dirtyOutput.Count -gt 0)

    if ($isDirty) {
      Write-Host "Status:         DIRTY (uncommitted changes)" -ForegroundColor Yellow
      if ($AutoStash) {
        Write-Host "Policy:         auto-stash before pull" -ForegroundColor Yellow
      } else {
        Write-Host "Policy:         abort (use --stash to allow)" -ForegroundColor Yellow
        if ($UpdateAll) {
          Write-Host "  SKIP: Working tree is dirty" -ForegroundColor Yellow
          $skippedDirty++
          continue
        } else {
          Die "Working tree is dirty. Use --stash to auto-stash, or commit/stash changes manually."
        }
      }
    } else {
      Write-Host "Status:         clean"
    }

    if ($RunSetup) {
      Write-Host "Follow-on:      strap setup (after successful pull)"
    }

    if ($DryRunMode) {
      Write-Host ""
      Write-Host "DRY RUN - no changes will be made" -ForegroundColor Yellow
      $dryRunCount++
      continue
    }

    # Confirmation
    if (-not $NonInteractive) {
      $response = Read-Host "`nProceed updating $entryName? (y/n)"
      if ($response -ne "y") {
        Info "Skipped by user"
        continue
      }
    }

    Write-Host ""

    # Stash if needed
    $stashCreated = $false
    if ($isDirty -and $AutoStash) {
      Info "Stashing changes..."
      & git -C $resolvedPath stash push -u -m "strap update" 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) {
        $stashCreated = $true
        Write-Host "  stashed" -ForegroundColor Green
      } else {
        Write-Host "  ERROR: stash failed" -ForegroundColor Red
        $failed++
        continue
      }
    }

    # Git fetch
    Info "Fetching..."
    $fetchOutput = & git -C $resolvedPath fetch --all --prune 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  ERROR: fetch failed" -ForegroundColor Red
      Write-Host $fetchOutput

      # Try to restore stash
      if ($stashCreated) {
        Info "Restoring stash..."
        & git -C $resolvedPath stash pop 2>&1 | Out-Null
      }

      $failed++
      continue
    }

    # Git pull
    Info "Pulling..."
    if ($UseRebase) {
      $pullOutput = & git -C $resolvedPath pull --rebase 2>&1
    } else {
      $pullOutput = & git -C $resolvedPath pull 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
      Write-Host "  ERROR: pull failed" -ForegroundColor Red
      Write-Host $pullOutput

      # Try to restore stash
      if ($stashCreated) {
        Info "Restoring stash..."
        & git -C $resolvedPath stash pop 2>&1 | Out-Null
      }

      $failed++
      continue
    }

    Write-Host "  pulled" -ForegroundColor Green

    # Restore stash
    if ($stashCreated) {
      Info "Restoring stash..."
      $popOutput = & git -C $resolvedPath stash pop 2>&1
      if ($LASTEXITCODE -eq 0) {
        Write-Host "  stash restored" -ForegroundColor Green
      } else {
        Write-Host "  WARN: stash pop failed (may have conflicts)" -ForegroundColor Yellow
        Write-Host $popOutput
      }
    }

    # Update registry metadata
    Info "Updating registry..."

    # Get current HEAD
    $headHash = & git -C $resolvedPath rev-parse HEAD 2>&1
    $remoteHash = & git -C $resolvedPath rev-parse "@{u}" 2>&1

    # Find entry index
    $entryIndex = -1
    for ($i = 0; $i -lt $registry.Count; $i++) {
      if ($registry[$i].name -eq $entryName) {
        $entryIndex = $i
        break
      }
    }

    if ($entryIndex -eq -1) {
      Write-Host "  ERROR: Registry entry not found after update" -ForegroundColor Red
      $failed++
      continue
    }

    # Update metadata (add properties if they don't exist)
    $currentEntry = $registry[$entryIndex]

    # Update existing timestamp
    $currentEntry.updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Add or update last_pull_at
    if ($currentEntry.PSObject.Properties['last_pull_at']) {
      $currentEntry.last_pull_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    } else {
      $currentEntry | Add-Member -NotePropertyName 'last_pull_at' -NotePropertyValue ((Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")) -Force
    }

    # Add or update last_head
    if ($headHash -and $LASTEXITCODE -eq 0) {
      $headValue = $headHash.Trim()
      if ($currentEntry.PSObject.Properties['last_head']) {
        $currentEntry.last_head = $headValue
      } else {
        $currentEntry | Add-Member -NotePropertyName 'last_head' -NotePropertyValue $headValue -Force
      }
    }

    # Add or update last_remote
    if ($remoteHash -and $LASTEXITCODE -eq 0) {
      $remoteValue = $remoteHash.Trim()
      if ($currentEntry.PSObject.Properties['last_remote']) {
        $currentEntry.last_remote = $remoteValue
      } else {
        $currentEntry | Add-Member -NotePropertyName 'last_remote' -NotePropertyValue $remoteValue -Force
      }
    }

    # Save registry
    try {
      Save-Registry $config $registry
      Write-Host "  registry updated" -ForegroundColor Green
    } catch {
      Write-Host "  ERROR updating registry: $_" -ForegroundColor Red
      $failed++
      continue
    }

    $updated++
    Ok "Updated $entryName"

    # Run setup if requested
    if ($RunSetup) {
      Write-Host ""
      Info "Running setup..."
      # TODO: Implement strap setup command
      Write-Host "  WARN: strap setup not yet implemented" -ForegroundColor Yellow
    }
  }

  # Summary for --all
  if ($UpdateAll -and $entriesToUpdate.Count -gt 1) {
    Write-Host ""
    Write-Host "=== UPDATE SUMMARY ===" -ForegroundColor Cyan
    Write-Host "Updated:       $updated"
    if ($skippedDirty -gt 0) {
      Write-Host "Skipped dirty: $skippedDirty" -ForegroundColor Yellow
    }
    if ($failed -gt 0) {
      Write-Host "Failed:        $failed" -ForegroundColor Red
    }
  }

  # Exit code logic
  if ($failed -gt 0) {
    exit 2
  }

  # If dry run, exit success if we processed at least one entry
  if ($DryRunMode -and $dryRunCount -gt 0) {
    exit 0
  }

  if ($updated -eq 0 -and $skippedDirty -eq 0 -and $dryRunCount -eq 0) {
    exit 1
  }
}

function Invoke-Templatize {
  param(
    [string] $TemplateName,
    [string] $SourcePath,
    [string] $RootPath,
    [switch] $ForceTemplate,
    [switch] $AllowDirtyWorktree,
    [string] $MessageText,
    [switch] $DoPush
  )

  Ensure-Command git

  if (-not $TemplateName) { Die "templatize requires <templateName>" }

  $sourceBase = if ($SourcePath) { $SourcePath } else { (Get-Location).Path }
  $srcRoot = Resolve-GitRoot $sourceBase
  if (-not $srcRoot) { Die "Source path is not a git repo: $sourceBase" }

  $strapRoot = if ($RootPath) { $RootPath } else { Split-Path $PSScriptRoot -Parent }
  if (-not (Test-Path $strapRoot)) { Die "strap root not found: $strapRoot" }

  $dirty = & git -C $strapRoot status --porcelain
  if ($dirty -and -not $AllowDirtyWorktree) {
    Die "strap repo is dirty; commit/stash or use --allow-dirty"
  }

  $dest = Join-Path $strapRoot (Join-Path "templates" $TemplateName)
  if (Test-Path $dest) {
    if (-not $ForceTemplate) { Die "Template already exists: $dest (use --force to overwrite)" }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $dest
  }

  Info "Templatizing from $srcRoot -> $dest"
  $ok = Copy-RepoSnapshot $srcRoot $dest
  if (-not $ok) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $dest
    Die "Copy failed"
  }

  $rel = (Resolve-Path -LiteralPath $dest).Path.Substring($strapRoot.Length + 1)
  & git -C $strapRoot add -- $rel | Out-Null

  & git -C $strapRoot diff --staged --quiet
  if ($LASTEXITCODE -eq 0) {
    Warn "No changes to commit for $rel"
    return
  }

  $srcName = Split-Path $srcRoot -Leaf
  $msg = if ($MessageText) { $MessageText } else { "templates: templatize $TemplateName from $srcName" }
  & git -C $strapRoot commit -m $msg | Out-Null
  Ok "templatize commit created"

  if ($DoPush) {
    & git -C $strapRoot push | Out-Null
    Ok "pushed"
  }
}

function Invoke-Doctor {
  param(
    [string] $StrapRootPath,
    [switch] $OutputJson
  )

  # Load config
  $config = Load-Config $StrapRootPath

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

  # Check PATH for shims
  $processPath = $env:PATH -split ';'
  $shimsRoot = $config.roots.shims
  $foundInPath = $processPath | Where-Object { $_ -like "*$shimsRoot*" } | Select-Object -First 1
  $report.path_check.shims_in_path = ($null -ne $foundInPath)
  $report.path_check.path_entry = if ($foundInPath) { $foundInPath } else { "missing" }

  # Check tool availability
  function Get-ToolInfo {
    param([string]$Command, [string]$VersionArg = "--version")

    $result = @{
      name = $Command
      found = $false
      path = $null
      version = $null
    }

    try {
      $cmd = Get-Command $Command -ErrorAction SilentlyContinue
      if ($cmd) {
        $result.found = $true
        $result.path = $cmd.Source

        # Try to get version
        $versionOutput = & $Command $VersionArg 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
          $result.version = ($versionOutput -split "`n")[0].Trim()
        }
      }
    } catch {}

    return [PSCustomObject]$result
  }

  $report.tools += Get-ToolInfo "git"
  $report.tools += Get-ToolInfo "pwsh" "-v"
  $report.tools += Get-ToolInfo "python"

  # Check uv (try both standalone and python -m)
  $uvInfo = Get-ToolInfo "uv"
  if (-not $uvInfo.found) {
    try {
      $versionOutput = & python -m uv --version 2>&1 | Out-String
      if ($LASTEXITCODE -eq 0) {
        $uvInfo.found = $true
        $uvInfo.path = "python -m uv"
        $uvInfo.version = ($versionOutput -split "`n")[0].Trim()
      }
    } catch {}
  }
  $report.tools += $uvInfo

  $report.tools += Get-ToolInfo "node"
  $report.tools += Get-ToolInfo "npm"
  $report.tools += Get-ToolInfo "pnpm"
  $report.tools += Get-ToolInfo "yarn"
  $report.tools += Get-ToolInfo "corepack"
  $report.tools += Get-ToolInfo "go" "version"
  $report.tools += Get-ToolInfo "cargo"

  # Check registry integrity
  $registryPath = $config.registry
  $report.registry_check.exists = (Test-Path $registryPath)

  if ($report.registry_check.exists) {
    try {
      $content = Get-Content -LiteralPath $registryPath -Raw
      if ($content.Trim() -eq "[]") {
        $registry = @()
      } else {
        $registry = $content | ConvertFrom-Json
        # Ensure array
        if ($registry -isnot [array]) {
          $registry = @($registry)
        }
      }
      $report.registry_check.valid_json = $true

      if ($registry.Count -gt 0) {
        # Check each entry
        $seenNames = @{}
        foreach ($entry in $registry) {
          # Check required fields
          $required = @('name', 'scope', 'path', 'updated_at', 'shims')
          foreach ($field in $required) {
            if (-not $entry.PSObject.Properties[$field]) {
              $report.registry_check.issues += "Entry missing required field '$field': $($entry.name)"
            }
          }

          # Check for duplicate names
          if ($seenNames.ContainsKey($entry.name)) {
            $report.registry_check.issues += "Duplicate name: $($entry.name)"
            $report.status = "WARN"
          }
          $seenNames[$entry.name] = $true

          # Check if path exists
          if ($entry.path -and -not (Test-Path $entry.path)) {
            $report.registry_check.issues += "Path does not exist: $($entry.name) -> $($entry.path)"
            $report.status = "WARN"
          }

          # Check if shims exist
          if ($entry.shims) {
            foreach ($shim in $entry.shims) {
              if (-not (Test-Path $shim)) {
                $report.registry_check.issues += "Shim does not exist: $($entry.name) -> $shim"
                $report.status = "WARN"
              }
            }
          }
        }
      }
    } catch {
      $report.registry_check.valid_json = $false
      $report.registry_check.issues += "Invalid JSON: $_"
      $report.status = "FAIL"
    }
  }

  # Adjust status based on warnings
  $missingCriticalTools = $report.tools | Where-Object { $_.name -in @('git', 'pwsh') -and -not $_.found }
  if ($missingCriticalTools) {
    $report.status = "WARN"
  }

  if (-not $report.path_check.shims_in_path) {
    $report.status = "WARN"
  }

  # Output
  if ($OutputJson) {
    $report | ConvertTo-Json -Depth 10
  } else {
    Write-Host ""
    Write-Host "=== STRAP DOCTOR ===" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Config paths:" -ForegroundColor Yellow
    Write-Host "  software_root:  $($report.config.software_root)"
    Write-Host "  tools_root:     $($report.config.tools_root)"
    Write-Host "  shims_root:     $($report.config.shims_root)"
    Write-Host "  registry_path:  $($report.config.registry_path)"
    Write-Host "  strap_root:     $($report.config.strap_root)"
    Write-Host ""

    Write-Host "PATH check:" -ForegroundColor Yellow
    if ($report.path_check.shims_in_path) {
      Write-Host "  ✓ shims_root in PATH: $($report.path_check.path_entry)" -ForegroundColor Green
    } else {
      Write-Host "  ✗ shims_root NOT in PATH" -ForegroundColor Red
    }
    Write-Host ""

    Write-Host "Tool availability:" -ForegroundColor Yellow
    foreach ($tool in $report.tools) {
      if ($tool.found) {
        Write-Host "  ✓ $($tool.name.PadRight(10)) $($tool.version)" -ForegroundColor Green
      } else {
        Write-Host "  ✗ $($tool.name.PadRight(10)) not found" -ForegroundColor Red
      }
    }
    Write-Host ""

    Write-Host "Registry integrity:" -ForegroundColor Yellow
    if (-not $report.registry_check.exists) {
      Write-Host "  Registry: missing (ok if new)" -ForegroundColor Yellow
    } elseif (-not $report.registry_check.valid_json) {
      Write-Host "  ✗ Invalid JSON" -ForegroundColor Red
      foreach ($issue in $report.registry_check.issues) {
        Write-Host "    - $issue" -ForegroundColor Red
      }
    } else {
      Write-Host "  ✓ Valid JSON" -ForegroundColor Green
      if ($report.registry_check.issues.Count -eq 0) {
        Write-Host "  ✓ No issues found" -ForegroundColor Green
      } else {
        Write-Host "  Issues:" -ForegroundColor Yellow
        foreach ($issue in $report.registry_check.issues) {
          Write-Host "    - $issue" -ForegroundColor Yellow
        }
      }
    }
    Write-Host ""

    $statusColor = switch ($report.status) {
      "OK" { "Green" }
      "WARN" { "Yellow" }
      "FAIL" { "Red" }
    }
    Write-Host "Status: $($report.status)" -ForegroundColor $statusColor
  }

  # Exit code
  if ($report.status -eq "FAIL") {
    exit 1
  } else {
    exit 0
  }
}

function Invoke-Adopt {
  param(
    [string] $TargetPath,
    [string] $CustomName,
    [switch] $ForceTool,
    [switch] $ForceSoftware,
    [switch] $NonInteractive,
    [switch] $DryRunMode,
    [string] $StrapRootPath
  )

  # Load config and registry
  $config = Load-Config $StrapRootPath
  $registry = Load-Registry $config

  # Determine target path
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
    # Try git command
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

  # Extract git metadata (best-effort)
  $url = $null
  $lastHead = $null
  $defaultBranch = $null

  try {
    $remoteUrl = & git -C $resolvedPath remote get-url origin 2>&1
    if ($LASTEXITCODE -eq 0) {
      $url = $remoteUrl.Trim()
    }
  } catch {}

  try {
    $head = & git -C $resolvedPath rev-parse HEAD 2>&1
    if ($LASTEXITCODE -eq 0) {
      $lastHead = $head.Trim()
    }
  } catch {}

  try {
    $branch = & git -C $resolvedPath symbolic-ref --short refs/remotes/origin/HEAD 2>&1
    if ($LASTEXITCODE -eq 0) {
      $defaultBranch = $branch.Trim() -replace '^origin/', ''
    }
  } catch {}

  # Detect stack (best-effort)
  $stackDetected = $null
  Push-Location $resolvedPath
  try {
    if (Test-Path "pyproject.toml") { $stackDetected = "python" }
    elseif (Test-Path "requirements.txt") { $stackDetected = "python" }
    elseif (Test-Path "package.json") { $stackDetected = "node" }
    elseif (Test-Path "Cargo.toml") { $stackDetected = "rust" }
    elseif (Test-Path "go.mod") { $stackDetected = "go" }
  } finally {
    Pop-Location
  }

  # Create entry
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $entry = [PSCustomObject]@{
    id         = $name
    name       = $name
    scope      = $scope
    path       = $resolvedPath
    url        = $url
    shims      = @()
    created_at = $timestamp
    updated_at = $timestamp
  }

  if ($lastHead) {
    $entry | Add-Member -NotePropertyName 'last_head' -NotePropertyValue $lastHead -Force
  }

  if ($stackDetected) {
    $entry | Add-Member -NotePropertyName 'stack_detected' -NotePropertyValue $stackDetected -Force
  }

  # Preview
  Write-Host ""
  Write-Host "=== ADOPT PREVIEW ===" -ForegroundColor Cyan
  Write-Host "Name:     $name"
  Write-Host "Scope:    $scope"
  Write-Host "Path:     $resolvedPath"
  if ($url) { Write-Host "URL:      $url" }
  if ($stackDetected) { Write-Host "Stack:    $stackDetected" }
  if ($lastHead) { Write-Host "HEAD:     $lastHead" }
  Write-Host ""

  if ($DryRunMode) {
    Write-Host "DRY RUN - no changes will be made" -ForegroundColor Yellow
    exit 0
  }

  # Confirmation
  if (-not $NonInteractive) {
    $response = Read-Host "Adopt this repo into registry? (y/n)"
    if ($response -ne "y") {
      Info "Aborted by user"
      exit 1
    }
  }

  # Add to registry
  $registry += $entry

  # Save registry
  try {
    Save-Registry $config $registry
    Write-Host ""
    Ok "Adopted '$name' -> $resolvedPath"
    Write-Host ""
    Info "Next steps:"
    if ($stackDetected) {
      Info "  strap setup --repo $name  (install dependencies)"
    }
    Info "  strap shim <cmd> --- <command>  (create launcher)"
    Info "  strap update $name  (pull latest changes)"
  } catch {
    Write-Host ""
    Write-Host "ERROR writing registry: $_" -ForegroundColor Red
    exit 3
  }

  exit 0
}

if ($RepoName -eq "templatize") {
  $templateName = Get-TemplateNameFromArgs $ExtraArgs
  Invoke-Templatize -TemplateName $templateName -SourcePath $Source -RootPath $TemplateRoot -ForceTemplate:$Force.IsPresent -AllowDirtyWorktree:$AllowDirty.IsPresent -MessageText $Message -DoPush:$Push.IsPresent
  exit 0
}

if ($RepoName -eq "doctor") {
  Invoke-Doctor -StrapRootPath $TemplateRoot -OutputJson:$Json.IsPresent
  exit 0
}

if ($RepoName -eq "adopt") {
  # Check if --path was explicitly provided in ExtraArgs
  $pathProvided = $false
  if ($ExtraArgs) {
    for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
      if ($ExtraArgs[$i] -eq "--path" -or $ExtraArgs[$i] -eq "-p") {
        $pathProvided = $true
        break
      }
    }
  }

  $targetPath = if ($pathProvided) { $Path } else { $null }
  Invoke-Adopt -TargetPath $targetPath -CustomName $Name -ForceTool:$Tool.IsPresent -ForceSoftware:$Software.IsPresent -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "clone") {
  # Extract git URL from ExtraArgs
  $gitUrl = $null
  if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    foreach ($arg in $ExtraArgs) {
      if ($arg -notmatch '^--') {
        $gitUrl = $arg
        break
      }
    }
  }
  Invoke-Clone -GitUrl $gitUrl -CustomName $Name -DestPath $Dest -IsTool:$Tool.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "list") {
  Invoke-List -FilterTool:$Tool.IsPresent -FilterSoftware:$Software.IsPresent -OutputJson:$Json.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "setup") {
  Invoke-Setup -RepoNameOrPath $Repo -ForceStack $Stack -VenvPath $Venv -UseUv:$Uv.IsPresent -PythonExe $Python -PackageManager $Pm -EnableCorepack:$Corepack.IsPresent -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "update") {
  # Extract name from ExtraArgs (if not using --all)
  $nameToUpdate = $null
  if (-not $All -and $ExtraArgs -and $ExtraArgs.Count -gt 0) {
    foreach ($arg in $ExtraArgs) {
      if ($arg -notmatch '^--') {
        $nameToUpdate = $arg
        break
      }
    }
  }
  Invoke-Update -NameToUpdate $nameToUpdate -UpdateAll:$All.IsPresent -FilterTool:$Tool.IsPresent -FilterSoftware:$Software.IsPresent -UseRebase:$Rebase.IsPresent -AutoStash:$Stash.IsPresent -RunSetup:$Setup.IsPresent -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "uninstall") {
  # Extract name from ExtraArgs
  $nameToRemove = $null
  if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
    foreach ($arg in $ExtraArgs) {
      if ($arg -notmatch '^--') {
        $nameToRemove = $arg
        break
      }
    }
  }
  Invoke-Uninstall -NameToRemove $nameToRemove -NonInteractive:$Yes.IsPresent -DryRunMode:$DryRun.IsPresent -PreserveFolder:$KeepFolder.IsPresent -PreserveShims:$KeepShims.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if ($RepoName -eq "shim") {
  # Two input modes:
  # 1. --cmd "<command>" - command passed as string (avoids PowerShell parameter binding)
  # 2. strap shim <name> --- <command...> - command parsed from args (uses --- to avoid conflicts)

  $shimName = $null
  $commandLine = $null

  if ($Cmd) {
    # --cmd mode: command already provided as string
    # Extract shim name from ExtraArgs (first non-flag arg)
    if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
      foreach ($arg in $ExtraArgs) {
        if ($arg -notmatch '^--' -and -not $shimName) {
          $shimName = $arg
          break
        }
      }
    }
    $commandLine = $Cmd
  } else {
    # --- mode: parse separator and extract args
    $commandArgs = @()
    $foundSeparator = $false

    if ($ExtraArgs -and $ExtraArgs.Count -gt 0) {
      for ($i = 0; $i -lt $ExtraArgs.Count; $i++) {
        $arg = $ExtraArgs[$i]

        if ($arg -eq "---" -or $arg -eq "--") {
          $foundSeparator = $true
          # Everything after --- is the command
          if ($i + 1 -lt $ExtraArgs.Count) {
            $commandArgs = $ExtraArgs[($i + 1)..($ExtraArgs.Count - 1)]
          }
          break
        }

        # Before ---, look for the shim name (first non-flag arg)
        if (-not $foundSeparator -and $arg -notmatch '^--' -and -not $shimName) {
          $shimName = $arg
        }
      }
    }

    if ($commandArgs.Count -gt 0) {
      $commandLine = $commandArgs -join ' '
    }
  }

  Invoke-Shim -ShimName $shimName -CommandLine $commandLine -WorkingDir $Cwd -RegistryEntryName $Repo -ForceOverwrite:$Force.IsPresent -DryRunMode:$DryRun.IsPresent -NonInteractive:$Yes.IsPresent -StrapRootPath $TemplateRoot
  exit 0
}

if (-not $Template) { $Template = Prompt-Template }

$ProfileDir = Join-Path "templates" $Template

if (-not (Test-Path $Path)) {
  New-Item -ItemType Directory -Path $Path | Out-Null
}

$Dest = Join-Path $Path $RepoName
if (Test-Path $Dest) { Die "Path exists: $Dest" }

Info "Creating repo: $RepoName ($Template)"
New-Item -ItemType Directory -Path $Dest | Out-Null

$CommonDir = Join-Path $TemplateRoot "templates\common"
$ProfilePath = Join-Path $TemplateRoot $ProfileDir

Info "Copying templates from $TemplateRoot"
Copy-TemplateDir $CommonDir $Dest
Copy-TemplateDir $ProfilePath $Dest

$year = (Get-Date).Year
$pyPackage = ($RepoName -replace "-", "_")
$tokens = @{
  "{{REPO_NAME}}" = $RepoName
  "{{PY_PACKAGE}}" = $pyPackage
  "<REPO_NAME>" = $RepoName
  "<PY_PACKAGE>" = $pyPackage
  "{{YEAR}}"      = "$year"
}

if ($Template -eq "python" -and $pyPackage -eq $RepoName) {
  $conflictPath = Join-Path (Join-Path $Dest "src") "{{REPO_NAME}}"
  if (Test-Path $conflictPath) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $conflictPath
  }
}

Resolve-RemainingTokens $Dest $tokens

if ($Template -eq "python") {
  $legacyPath = Join-Path $Dest $RepoName
  if (Test-Path $legacyPath) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $legacyPath
  }
  $legacySrcPath = Join-Path (Join-Path $Dest "src") $RepoName
  if (Test-Path $legacySrcPath) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $legacySrcPath
  }
}

$envExample = Join-Path $Dest ".env.example"
if (-not (Test-Path $envExample)) {
  Set-Content -LiteralPath $envExample -NoNewline -Value "# Example environment variables`n# FOO=bar`n"
}

Get-ChildItem -LiteralPath $Dest -Recurse -File -Filter ".keep" | Remove-Item -Force -ErrorAction SilentlyContinue

Ensure-Command git
Push-Location $Dest

git init | Out-Null
git checkout -b $DefaultBranch 2>$null | Out-Null
Ok "git initialized ($DefaultBranch)"

$env:CI = "1"
if ($Start.IsPresent -and $SkipInstall.IsPresent) {
  Warn "Both --start and --skip-install were provided; skipping --start."
  $Start = $false
}

$fullInstall = $Install.IsPresent -or $Start.IsPresent
if ($SkipInstall.IsPresent) {
  Info "Skipping install (--skip-install)"
} else {
  switch ($Template) {
    "node-ts-service" {
      if (Has-Command pnpm) {
        pnpm install --lockfile-only | Out-Null
      } else {
        Warn "pnpm not found. install with corepack enable / npm i -g pnpm, or rerun strap with --skip-install"
      }
    }
    "node-ts-web" {
      if (Has-Command pnpm) {
        pnpm install --lockfile-only | Out-Null
      } else {
        Warn "pnpm not found. install with corepack enable / npm i -g pnpm, or rerun strap with --skip-install"
      }
    }
    "mono" {
      if (Has-Command pnpm) {
        pnpm install --lockfile-only | Out-Null
      } else {
        Warn "pnpm not found. install with corepack enable / npm i -g pnpm, or rerun strap with --skip-install"
      }
    }
    "python" {
      Ensure-Command python
      python -m pip install -e . ruff pytest | Out-Null
    }
  }
}

$ContextHookCmd = Join-Path $TemplateRoot "build\\context-hook.cmd"
$ContextHookPs1 = Join-Path $TemplateRoot "build\\context-hook.ps1"
if (Test-Path $ContextHookCmd) {
  & $ContextHookCmd install | Out-Null
} elseif (Test-Path $ContextHookPs1) {
  & $ContextHookPs1 install | Out-Null
} else {
  Die "context-hook not found in build/"
}

Normalize-TextFiles $Dest

git add . | Out-Null
git commit -m "init repo from $Template template" 2>$null | Out-Null
Ok "initial commit created"

if (-not $SkipInstall.IsPresent -and $fullInstall) {
  switch ($Template) {
    "node-ts-service" { if (Has-Command pnpm) { pnpm install | Out-Null } }
    "node-ts-web" { if (Has-Command pnpm) { pnpm install | Out-Null } }
    "mono" { if (Has-Command pnpm) { pnpm install | Out-Null } }
    "python" { }
  }
}

if (-not $SkipInstall.IsPresent -and $Start.IsPresent) {
  switch ($Template) {
    "node-ts-service" { if (Has-Command pnpm) { pnpm dev } }
    "node-ts-web" { if (Has-Command pnpm) { pnpm dev } }
    "mono" { if (Has-Command pnpm) { pnpm dev } }
    "python" { python -m $pyPackage }
  }
}

Pop-Location
Ok "Done."
Write-Host "Next:"
Write-Host "  cd $Dest"
switch ($Template) {
  "node-ts-service" { Write-Host "  pnpm dev" }
  "node-ts-web" { Write-Host "  pnpm dev" }
  "mono" { Write-Host "  pnpm dev" }
  "python" { Write-Host "  $pyPackage --help" }
}
