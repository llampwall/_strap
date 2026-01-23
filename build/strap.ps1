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

  [Parameter(ValueFromRemainingArguments=$true)]
  [string[]] $ExtraArgs
)

$ErrorActionPreference = "Stop"

function Die($msg) { Write-Error "❌ $msg"; exit 1 }
function Info($msg) { Write-Host "➡️  $msg" }
function Ok($msg) { Write-Host "✅ $msg" }
function Warn($msg) { Write-Warning $msg }

$TemplateRoot = Split-Path $PSScriptRoot -Parent
$DefaultBranch = if ($env:BOOTSTRAP_BRANCH) { $env:BOOTSTRAP_BRANCH } else { "main" }

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
    Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force
  }
}

function Is-ProbablyTextFile($path) {
  $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
  $binary = @(".png",".jpg",".jpeg",".gif",".ico",".pdf",".zip",".gz",".tgz",".woff",".woff2",".ttf",".eot",".exe",".dll")
  return -not ($binary -contains $ext)
}

function Replace-Tokens($root, $tokens) {
  Get-ChildItem -LiteralPath $root -Recurse -File -Force | ForEach-Object {
    $p = $_.FullName
    if (-not (Is-ProbablyTextFile $p)) { return }

    $content = Get-Content -LiteralPath $p -Raw
    if ($null -eq $content) { $content = "" }
    foreach ($k in $tokens.Keys) {
      $content = $content.Replace($k, $tokens[$k])
    }
    # Normalize to LF and write UTF-8 without BOM
    $content = $content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($p, $content, (New-Object System.Text.UTF8Encoding($false)))
  }
}

function Get-TokenFiles($root) {
  $pattern = "\{\{REPO_NAME\}\}|\{\{PY_PACKAGE\}\}|<REPO_NAME>|<PY_PACKAGE>"
  $files = @()

  if (Has-Command rg) {
    $args = @(
      "-l",
      "--glob", "!**/.git/**",
      "--glob", "!**/node_modules/**",
      "--glob", "!**/dist/**",
      "--glob", "!**/build/**",
      "--glob", "!**/coverage/**",
      "--glob", "!**/.venv/**",
      "--glob", "!**/__pycache__/**",
      $pattern,
      $root
    )
    $files = & rg @args
  } else {
    $matches = Get-ChildItem -LiteralPath $root -Recurse -File |
      Where-Object {
        $_.FullName -notmatch "[\\/]\.git[\\/]" -and
        $_.FullName -notmatch "[\\/]node_modules[\\/]" -and
        $_.FullName -notmatch "[\\/]dist[\\/]" -and
        $_.FullName -notmatch "[\\/]build[\\/]" -and
        $_.FullName -notmatch "[\\/]coverage[\\/]" -and
        $_.FullName -notmatch "[\\/]\.venv[\\/]" -and
        $_.FullName -notmatch "[\\/]__pycache__[\\/]"
      } |
      Select-String -Pattern $pattern -ErrorAction SilentlyContinue
    $files = $matches | ForEach-Object { $_.Path } | Sort-Object -Unique
  }

  $files = $files | Where-Object { $_ -notmatch "[\\/]\.git[\\/]" }
  return $files
}

function Replace-Tokens-InFiles($files, $tokens) {
  if (-not $files) { return }
  foreach ($file in $files) {
    $content = Get-Content -LiteralPath $file -Raw
    if ($null -eq $content) { $content = "" }
    foreach ($k in $tokens.Keys) {
      $content = $content.Replace($k, $tokens[$k])
    }
    $content = $content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($file, $content, (New-Object System.Text.UTF8Encoding($false)))
  }
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

function Get-TokenNamePaths($root) {
  $pattern = "\{\{REPO_NAME\}\}|\{\{PY_PACKAGE\}\}|<REPO_NAME>|<PY_PACKAGE>"
  $entries = Get-ChildItem -LiteralPath $root -Recurse -Force
  return $entries | Where-Object { $_.Name -match $pattern } | ForEach-Object { $_.FullName }
}

function Resolve-RemainingTokens($root, $tokens) {
  Replace-Tokens $root $tokens
  Replace-TokenNames $root $tokens

  $remaining = Get-TokenFiles $root
  if ($remaining) {
    Replace-Tokens-InFiles $remaining $tokens
  }
  $remaining = Get-TokenFiles $root
  $remainingNames = Get-TokenNamePaths $root
  $allRemaining = @()
  if ($remaining) { $allRemaining += $remaining }
  if ($remainingNames) { $allRemaining += $remainingNames }
  $allRemaining = $allRemaining | Sort-Object -Unique
  if ($allRemaining -and $allRemaining.Count -gt 0) {
    Warn "Unresolved template tokens remain in:"
    $allRemaining | ForEach-Object { Warn "  $_" }
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

function Apply-ExtraArgs {
  param([string[]] $ArgsList)

  if (-not $ArgsList) { return }

  for ($i = 0; $i -lt $ArgsList.Count; $i++) {
    $arg = $ArgsList[$i]
    switch ($arg) {
      "--start" { $script:Start = $true; continue }
      "--install" { $script:Install = $true; continue }
      "--skip-install" { $script:SkipInstall = $true; continue }
      "--template" { if ($i + 1 -lt $ArgsList.Count) { $script:Template = $ArgsList[$i + 1]; $i++; continue } }
      "-t" { if ($i + 1 -lt $ArgsList.Count) { $script:Template = $ArgsList[$i + 1]; $i++; continue } }
      "--path" { if ($i + 1 -lt $ArgsList.Count) { $script:Path = $ArgsList[$i + 1]; $i++; continue } }
      "-p" { if ($i + 1 -lt $ArgsList.Count) { $script:Path = $ArgsList[$i + 1]; $i++; continue } }
      default { }
    }
  }
}

Apply-ExtraArgs $ExtraArgs

if (-not $Template) { $Template = Prompt-Template }

$ProfileDir = $Template

if (-not (Test-Path $Path)) {
  New-Item -ItemType Directory -Path $Path | Out-Null
}

$Dest = Join-Path $Path $RepoName
if (Test-Path $Dest) { Die "Path exists: $Dest" }

Info "Creating repo: $RepoName ($Template)"
New-Item -ItemType Directory -Path $Dest | Out-Null

$CommonDir = Join-Path $TemplateRoot "common"
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
Replace-Tokens $Dest $tokens
Replace-TokenNames $Dest $tokens

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

Get-ChildItem -LiteralPath $Dest -Recurse -Force -File -Filter ".keep" | Remove-Item -Force -ErrorAction SilentlyContinue

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

Resolve-RemainingTokens $Dest $tokens

git add . | Out-Null
git commit -m "chore: init repo from $Template template" 2>$null | Out-Null
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
