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
  strap doctor [--strap-root <path>] [--keep]
  strap templatize <templateName> [--source <path>] [--message "<msg>"] [--push] [--force] [--allow-dirty]

Templates:
  node-ts-service | node-ts-web | python | mono

Flags:
  --skip-install  skip dependency install
  --install       run full install after initial commit
  --start         full install, then start dev
  --keep          keep doctor artifacts
  --strap-root    override strap repo root
  --source        source repo for templatize
  --message       commit message for templatize
  --push          push after templatize commit
  --force         overwrite existing template folder
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
    [string] $RootPath,
    [switch] $KeepArtifacts
  )

  $psExe = if (Has-Command pwsh) { "pwsh" } else { "powershell" }
  $doctorBase = Join-Path $RootPath "_doctor"
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $runRoot = Join-Path $doctorBase $stamp
  New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

  $templates = @(
    @{ Name = "node-ts-service"; Repo = "doctor-svc" },
    @{ Name = "node-ts-web"; Repo = "doctor-web" },
    @{ Name = "python"; Repo = "doctor-py" },
    @{ Name = "mono"; Repo = "doctor-mono" }
  )

  $results = @()

  try {
    foreach ($t in $templates) {
      $repoPath = Join-Path $runRoot $t.Repo
      $createArgs = @(
        "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath,
        $t.Repo,
        "-Template", $t.Name,
        "-Path", $runRoot,
        "-SkipInstall"
      )

      & $psExe @createArgs | Out-Null
      $createOk = ($LASTEXITCODE -eq 0) -and (Test-Path $repoPath)

      $tokenOk = $false
      if ($createOk) {
        $matches = Get-TokenMatches $repoPath
        $tokenOk = (-not $matches -or $matches.Count -eq 0)
        if (-not $tokenOk) {
          Warn "Doctor: unresolved tokens in $repoPath"
          $matches | ForEach-Object { Warn ("  {0}:{1} -> {2}" -f $_.Path, $_.Line, $_.Match) }
        }
      }

      $testOk = $false
      if ($createOk -and $tokenOk) {
        switch ($t.Name) {
          "node-ts-service" {
            & $psExe -NoLogo -NoProfile -Command "Set-Location '$repoPath'; pnpm install --prefer-offline; pnpm -s test" | Out-Null
            $testOk = ($LASTEXITCODE -eq 0)

            if ($testOk) {
              $envFile = Join-Path $repoPath ".env.example"
              $vars = Read-EnvDefaults $envFile
              $port = [int]($vars["SERVER_PORT"] | ForEach-Object { $_ })
              if (-not $port) { $port = 6969 }

              $portToUse = Get-FreePort $port
              if ($portToUse -ne $port) { Warn "Doctor: port $port in use, using $portToUse" }
              $cmd = "set SERVER_HOST=0.0.0.0&& set SERVER_PORT=$portToUse&& node dist\src\index.js"
              $proc = Start-Process -FilePath "cmd.exe" -ArgumentList @('/c', $cmd) -WorkingDirectory $repoPath -PassThru
              $ok = Wait-For-Health $portToUse
              Stop-ProcessTree $proc.Id
              if (-not $ok) { $testOk = $false }
            }
          }
          "node-ts-web" {
            & $psExe -NoLogo -NoProfile -Command "Set-Location '$repoPath'; pnpm install --prefer-offline; pnpm -s build" | Out-Null
            $testOk = ($LASTEXITCODE -eq 0)
          }
          "python" {
            & $psExe -NoLogo -NoProfile -Command "Set-Location '$repoPath'; python -m pip install -e . pytest; python -m pytest" | Out-Null
            $testOk = ($LASTEXITCODE -eq 0)
          }
          "mono" {
            & $psExe -NoLogo -NoProfile -Command "Set-Location '$repoPath'; pnpm install --prefer-offline; pnpm -s -w test" | Out-Null
            $testOk = ($LASTEXITCODE -eq 0)

            if ($testOk) {
              $envFile = Join-Path $repoPath ".env.example"
              $vars = Read-EnvDefaults $envFile
              $port = [int]($vars["SERVER_PORT"] | ForEach-Object { $_ })
              if (-not $port) { $port = 6969 }

              $portToUse = Get-FreePort $port
              if ($portToUse -ne $port) { Warn "Doctor: port $port in use, using $portToUse" }
              $cmd = "set SERVER_HOST=0.0.0.0&& set SERVER_PORT=$portToUse&& node dist\src\index.js"
              $proc = Start-Process -FilePath "cmd.exe" -ArgumentList @('/c', $cmd) -WorkingDirectory (Join-Path $repoPath "apps\server") -PassThru
              $ok = Wait-For-Health $portToUse
              Stop-ProcessTree $proc.Id
              if (-not $ok) { $testOk = $false }
            }
          }
        }
      }

      $results += [pscustomobject]@{
        Template = $t.Name
        Created = $createOk
        Tokens  = $tokenOk
        Tests   = $testOk
      }
    }
  } finally {
    if (-not $KeepArtifacts) {
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $runRoot
    } else {
      Info "Doctor artifacts kept at $runRoot"
    }
  }

  Write-Host ""
  Write-Host "strap doctor summary:"
  foreach ($r in $results) {
    $status = if ($r.Created -and $r.Tokens -and $r.Tests) { "PASS" } else { "FAIL" }
    Write-Host ("  {0,-14} {1}" -f $r.Template, $status)
  }

  if ($results | Where-Object { -not ($_.Created -and $_.Tokens -and $_.Tests) }) {
    exit 1
  }
}

if ($RepoName -eq "templatize") {
  $templateName = Get-TemplateNameFromArgs $ExtraArgs
  Invoke-Templatize -TemplateName $templateName -SourcePath $Source -RootPath $TemplateRoot -ForceTemplate:$Force.IsPresent -AllowDirtyWorktree:$AllowDirty.IsPresent -MessageText $Message -DoPush:$Push.IsPresent
  exit 0
}

if ($RepoName -eq "doctor") {
  Invoke-Doctor -RootPath $TemplateRoot -KeepArtifacts:$Keep.IsPresent
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
