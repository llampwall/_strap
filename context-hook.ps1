$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  $root = & git rev-parse --show-toplevel 2>$null
  if (-not $root) { return $null }
  return $root.Trim()
}

function Get-GitDir([string]$repoRoot) {
  $gitDirRaw = (& git rev-parse --git-dir).Trim()
  if ([IO.Path]::IsPathRooted($gitDirRaw)) { return $gitDirRaw }
  return (Join-Path $repoRoot $gitDirRaw)
}

function Resolve-CodexPath {
  $envBin = $env:CODEX_BIN
  if ($envBin -and $envBin.Trim() -ne '') { return $envBin }
  $machineBin = [Environment]::GetEnvironmentVariable('CODEX_BIN','Machine')
  if ($machineBin -and $machineBin.Trim() -ne '') { return $machineBin }
  $userBin = [Environment]::GetEnvironmentVariable('CODEX_BIN','User')
  if ($userBin -and $userBin.Trim() -ne '') { return $userBin }
  $cmd = Get-Command codex.cmd -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $cmd = Get-Command codex -ErrorAction SilentlyContinue
  if ($cmd -and -not $cmd.Source.ToLower().EndsWith('.ps1')) { return $cmd.Source }
  $cmd = Get-Command codex.cmd -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

function Write-Log([string]$logFile, [string]$msg) {
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  Add-Content -Path $logFile -Value "[$ts] $msg"
}

function ShouldSkipCommit([string]$logFile) {
  $subject = (& git log -1 --pretty=%s 2>&1).ToString().Trim()
  if ($subject -eq '...') {
    Write-Log $logFile 'skipping: subject "..."'
    return $true
  }
  if ($subject -match '\[skip maintainer\]') {
    Write-Log $logFile 'skipping: [skip maintainer]'
    return $true
  }
  if ($subject -match '^(docs|notes):') {
    Write-Log $logFile ("skipping maintainer for notes commit: " + $subject)
    return $true
  }
  if ($subject -match '^(chore|ci|style|refactor|test)(\([^)]+\))?:') {
    Write-Log $logFile ("skipping maintainer for low-signal commit: " + $subject)
    return $true
  }
  if ($subject -match '(?i)\b(release|bump version)\b') {
    Write-Log $logFile ("skipping maintainer for release/bump: " + $subject)
    return $true
  }
  if ($subject -match '(?i)\b(dependabot|renovate)\b') {
    Write-Log $logFile ("skipping maintainer for bot commit: " + $subject)
    return $true
  }
  $parents = (& git show -s --pretty=%P 2>$null).ToString().Trim()
  if ($parents -and ($parents -split '\s+').Count -gt 1) {
    Write-Log $logFile 'skipping: merge commit'
    return $true
  }
  $changed = & git show -1 --name-only 2>$null
  if ($changed -and ($changed | Where-Object { $_ -notmatch '^\.githooks[\\/]' }) -eq $null) {
    Write-Log $logFile 'skipping: .githooks-only commit'
    return $true
  }
  if ($changed -and ($changed | Where-Object { $_ -notmatch '^(docs/project_notes/|AGENTS\.md$|CLAUDE\.md$)' }) -eq $null) {
    Write-Log $logFile 'skipping: notes/agents-only commit'
    return $true
  }
  if ($changed -and ($changed | Where-Object { $_ -notmatch '\.md$' }) -eq $null -and ($changed | Where-Object { $_ -match '^docs/project_notes/' }) -eq $null) {
    Write-Log $logFile 'skipping: docs-only commit outside project_notes'
    return $true
  }
  $lockfiles = @(
    'package-lock.json',
    'pnpm-lock.yaml',
    'yarn.lock',
    'bun.lockb',
    'npm-shrinkwrap.json',
    'composer.lock',
    'poetry.lock',
    'Pipfile.lock',
    'Cargo.lock',
    'Gemfile.lock',
    'go.sum'
  )
  if ($changed -and ($changed | Where-Object { $lockfiles -notcontains $_ }) -eq $null) {
    Write-Log $logFile 'skipping: lockfiles-only commit'
    return $true
  }
  return $false
}

function Run-Maintainer([string]$repoRoot, [string]$logFile, [string]$mode) {
  if (ShouldSkipCommit $logFile) { return }

  $env:CODE_HOME = 'C:\Users\Jordan\.codex'

  $binPath = Resolve-CodexPath
  if (-not $binPath) {
    Write-Log $logFile 'Codex binary not found. Ensure codex.cmd is on PATH or set CODEX_BIN.'
    return
  }
  $binPath = ([string]$binPath).Trim()
  $binPath = $binPath.Trim('"')
  $binPath = $binPath -replace '[\r\n\0]+',''

  $requiredRel = @(
    'AGENTS.md',
    'CLAUDE.md',
    'docs/project_notes/operating_brief.md',
    'docs/project_notes/key_facts.md',
    'docs/project_notes/adrs.md',
    'docs/project_notes/bugs.md',
    'docs/project_notes/worklog.md'
  )
  $missing = $requiredRel | Where-Object { -not (Test-Path (Join-Path $repoRoot $_)) }
  if ($missing) {
    $bootstrapPrompt = (
      'You are a non-interactive maintainer. Use the project-context skill to create/update AGENTS.md and CLAUDE.md files in the root, and create/update the specified context files in docs/project_notes/. Do not touch any other paths.'
    )
    Write-Log $logFile 'bootstrapping docs/project_notes'
    $bootstrapOut = & $binPath exec --full-auto --sandbox workspace-write $bootstrapPrompt 2>&1
    if ($bootstrapOut) { $bootstrapOut | Add-Content -Path $logFile }
  }

  if ($mode -eq 'manual') {
    $staged = & git diff --cached --name-only 2>$null
    if ($staged) {
      $summary = & git diff --cached --name-status --stat --no-color 2>&1
      $full = & git diff --cached --unified=0 --no-color 2>&1
    } else {
      $summary = & git show -1 --name-status --stat --no-color 2>&1
      $full = & git show -1 --unified=0 --no-color 2>&1
    }
  } else {
    $summary = & git show -1 --name-status --stat --no-color 2>&1
    $full = & git show -1 --unified=0 --no-color 2>&1
  }

  $promptLines = @(
    'You are a non-interactive maintainer. Use the project-context skill to create/update AGENTS.md and CLAUDE.md files in the root, and create/update the specified context files in docs/project_notes/.',
    'Rules:',
    '- Only edit those files (plus AGENTS.md and CLAUDE.md if the project-context skill requires them); do not touch anything else.',
    '- If nothing meaningful changed for the notes, make no edits.',
    '- Enforce no duplication: worklog links should not repeat; ADRs are constraints; key_facts are lookup truths; bugs are recurring/scary only.',
    '',
    'Change summary:',
    ($summary | ForEach-Object { Strip-Ansi $_ }) -join "`n",
    '',
    'Change diff:',
    ($full | ForEach-Object { Strip-Ansi $_ }) -join "`n"
  )
  $prompt = $promptLines -join "`n"
  $maxPromptChars = 40000
  if ($prompt.Length -gt $maxPromptChars) {
    $keep = [Math]::Max(0, $maxPromptChars - 200)
    $prompt = $prompt.Substring(0, $keep) + "`n...[truncated]..."
  }

  Write-Log $logFile 'running maintainer'
  $out = & $binPath exec --full-auto --sandbox workspace-write $prompt 2>&1
  if ($out) { $out | Add-Content -Path $logFile }
}

function Run-Guarded([string]$repoRoot, [string]$mode) {
  $gitDir = Get-GitDir $repoRoot
  $lockFile = Join-Path $gitDir 'maintainer-hook.lock'
  $logFile = Join-Path $gitDir 'maintainer-hook.log'

  if ($env:EVERYCODE_MAINTAINER_RUNNING -eq '1') { return }
  if (Test-Path $lockFile) { return }

  $env:EVERYCODE_MAINTAINER_RUNNING = '1'
  New-Item -ItemType File -Force -Path $lockFile | Out-Null

  try {
    Write-Log $logFile ("maintainer " + $mode + " start")
    Run-Maintainer $repoRoot $logFile $mode
    Write-Log $logFile ("maintainer " + $mode + " end")
  }
  catch {
    Write-Log $logFile ("error: " + $_.Exception.Message)
  }
  finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $lockFile
    Remove-Item Env:EVERYCODE_MAINTAINER_RUNNING -ErrorAction SilentlyContinue
  }
}

function Install-Hook([string]$repoRoot) {
  $hooksDir = Join-Path $repoRoot '.githooks'
  New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null

  $npmBin = 'C:\Users\Jordan\AppData\Roaming\npm'
  $env:Path = $env:Path + ';' + $npmBin
  $coderResolved = (Resolve-CodexPath)
  if (-not $coderResolved) {
    Write-Error 'Codex binary not found. Ensure codex.cmd is on PATH or set CODEX_BIN.'
    exit 1
  }
  $coderResolved = ($coderResolved | Select-Object -First 1)
  $coderResolved = ([string]$coderResolved).Trim()
  $coderResolved = $coderResolved.Trim('"')
  $coderResolved = ($coderResolved -replace '[\r\n\0]+','')
  Write-Host ('Codex resolved to: ' + $coderResolved)
  $coderExt = ([IO.Path]::GetExtension($coderResolved).ToLower() -replace '[\r\n\0]+','')
  $coderPathEscaped = ($coderResolved -replace '[\r\n\0]+','') -replace "'", "''"
  $coderExtEscaped = ($coderExt -replace '[\r\n\0]+','') -replace "'", "''"

  $postCommitShLines = @(
    '#!/bin/sh',
    'ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"',
    'if [ -z "$ROOT" ]; then',
    '  exit 0',
    'fi',
    'HOOK="$ROOT/.githooks/post-commit.ps1"',
    'if command -v pwsh >/dev/null 2>&1; then',
    '  pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOOK"',
    'else',
    '  powershell -NoProfile -ExecutionPolicy Bypass -File "$HOOK"',
    'fi',
    'exit 0'
  )
  $postCommitSh = $postCommitShLines -join "`n"

  $postCommitPs1Lines = @(
    '$ErrorActionPreference = ''Stop''',
    '',
    '$env:CODE_HOME = ''C:\Users\Jordan\.codex''',
    '',
    'function Get-RepoRoot {',
    '  $root = & git rev-parse --show-toplevel 2>$null',
    '  if (-not $root) { return $null }',
    '  return $root.Trim()',
    '}',
    '',
    '$repoRoot = Get-RepoRoot',
    'if (-not $repoRoot) { exit 0 }',
    'Set-Location $repoRoot',
    '',
    '$gitDirRaw = (& git rev-parse --git-dir).Trim()',
    'if ([IO.Path]::IsPathRooted($gitDirRaw)) {',
    '  $gitDir = $gitDirRaw',
    '} else {',
    '  $gitDir = Join-Path $repoRoot $gitDirRaw',
    '}',
    '',
    '$lockFile = Join-Path $gitDir ''maintainer-hook.lock''',
    '$logFile = Join-Path $gitDir ''maintainer-hook.log''',
    '',
    'function Resolve-CodexPath {',
    '  if ($env:CODEX_BIN -and $env:CODEX_BIN.Trim() -ne '''') { return $env:CODEX_BIN }',
    '  $cmd = Get-Command codex.cmd -ErrorAction SilentlyContinue',
    '  if ($cmd) { return $cmd.Source }',
    '  $cmd = Get-Command codex -ErrorAction SilentlyContinue',
    '  if ($cmd -and -not $cmd.Source.ToLower().EndsWith(''.ps1'')) { return $cmd.Source }',
    '  $cmd = Get-Command codex.cmd -ErrorAction SilentlyContinue',
    '  if ($cmd) { return $cmd.Source }',
    '  return $null',
    '}',
    '',
    '$coderPath = Resolve-CodexPath',
    'if ($coderPath) { $coderPath = ($coderPath -replace ''[\r\n\0]+'','''').Trim() }',
    '$coderExt = if ($coderPath) { ([IO.Path]::GetExtension($coderPath).ToLower() -replace ''[\r\n\0]+'','''').Trim() } else { '''' }',
    '',
    'function Write-LogLine([string]$line) {',
    '  if ([string]::IsNullOrWhiteSpace($line)) { return }',
    '  $maxAttempts = 10',
    '  for ($i = 0; $i -lt $maxAttempts; $i++) {',
    '    try {',
    '      $fs = [System.IO.File]::Open($logFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)',
    '      try {',
    '        $sw = New-Object System.IO.StreamWriter($fs)',
    '        $sw.WriteLine($line)',
    '        $sw.Flush()',
    '      } finally {',
    '        if ($sw) { $sw.Dispose() }',
    '        $fs.Dispose()',
    '      }',
    '      break',
    '    } catch {',
    '      Start-Sleep -Milliseconds 200',
    '    }',
    '  }',
    '}',
    '',
    'function Log([string]$msg) {',
    '  $ts = Get-Date -Format ''yyyy-MM-dd HH:mm:ss''',
    '  $line = "[$ts] $msg"',
    '  Write-LogLine $line',
    '  if ($env:MAINTAINER_HOOK_ECHO -eq ''1'') { Write-Host $line }',
    '}',
    '',
    'function Strip-Ansi([string]$text) {',
    '  if ($null -eq $text) { return $null }',
    '  $t = [string]$text',
    '  $t = $t -replace ''\x1b\[[0-9;?]*[ -/]*[@-~]'', ''''',
    '  $t = $t -replace ''\x1b\][^\x07]*\x07'', ''''',
    '  return $t',
    '}',
    '',
    'function Write-OutputLines([string]$text) {',
    '  if ([string]::IsNullOrWhiteSpace($text)) { return }',
    '  $text -split "`r?`n" | ForEach-Object {',
    '    $clean = Strip-Ansi $_',
    '    if ($clean) {',
    '      Write-LogLine $clean',
    '      if ($env:MAINTAINER_HOOK_ECHO -eq ''1'') { Write-Host $clean }',
    '    }',
    '  }',
    '}',
    '',
    'function Invoke-Coder([string]$prompt, [int]$timeoutSec) {',
    '  $psi = New-Object System.Diagnostics.ProcessStartInfo',
    '  $psi.FileName = $coderPath',
    '  $psi.UseShellExecute = $false',
    '  $psi.RedirectStandardInput = $true',
    '  $psi.RedirectStandardOutput = $false',
    '  $psi.RedirectStandardError = $false',
    '  $psi.CreateNoWindow = $true',
    '  $psi.Environment[''CI''] = ''1''',
    '  $psi.Environment[''TERM''] = ''dumb''',
    '  $psi.Environment[''NO_COLOR''] = ''1''',
    '  if ($env:CODE_HOME -and $env:CODE_HOME.Trim() -ne '''') { $psi.Environment[''CODE_HOME''] = $env:CODE_HOME }',
    '  $quotedPrompt = ''"'' + ($prompt -replace ''"'',''""'') + ''"''',
    '  $argString = ''exec --full-auto --sandbox workspace-write '' + $quotedPrompt',
    '  Log ("codex args: " + $argString)',
    '  Log ("codex cwd: " + $repoRoot)',
    '  $psi.FileName = ''cmd.exe''',
    '  $psi.Arguments = ''/c ""'' + $coderPath + ''" '' + $argString + '' >> "'' + $logFile + ''" 2>>&1"''',
    '  $psi.WorkingDirectory = $repoRoot',
    '  $p = New-Object System.Diagnostics.Process',
    '  $p.StartInfo = $psi',
    '  $null = $p.Start()',
    '  if (-not $p.WaitForExit($timeoutSec * 1000)) {',
    '    try { & taskkill /T /F /PID $p.Id | Out-Null } catch { try { $p.Kill() } catch {} }',
    '    Log (''codex timed out after '' + $timeoutSec + ''s (killed process tree)'')',
    '    Remove-Item -Force -ErrorAction SilentlyContinue $lockFile',
    '    return 124',
    '  }',
    '  return $p.ExitCode',
    '}',
    '',
    'function Commit-NotesIfChanged([string]$message) {',
    '  $paths = @(',
    '    ''docs/project_notes/operating_brief.md'',',
    '    ''docs/project_notes/key_facts.md'',',
    '    ''docs/project_notes/adrs.md'',',
    '    ''docs/project_notes/bugs.md'',',
    '    ''docs/project_notes/worklog.md'',',
    '    ''AGENTS.md'',',
    '    ''CLAUDE.md''',
    '  )',
    '  $changes = & git status --porcelain -- $paths 2>$null',
    '  if (-not $changes) { return $false }',
    '  & git add -- $paths 2>$null | Out-Null',
    '  & git diff --cached --quiet 2>$null',
    '  if ($LASTEXITCODE -eq 0) { return $false }',
    '  & git commit -m $message 2>$null | Out-Null',
    '  if ($LASTEXITCODE -eq 0) {',
    '    Log ("auto-committed notes: " + $message)',
    '    return $true',
    '  }',
    '  return $false',
    '}',
    '',
    '$lockAgeMinutes = 10',
    'if (Test-Path $lockFile) {',
    '  $age = (Get-Date) - (Get-Item $lockFile).LastWriteTime',
    '  if ($age.TotalMinutes -gt $lockAgeMinutes) {',
    '    Remove-Item -Force -ErrorAction SilentlyContinue $lockFile',
    '    Log "removed stale lock (older than $lockAgeMinutes minutes)"',
    '  }',
    '}',
    '',
    '$env:Path = $env:Path + '';C:\Users\Jordan\AppData\Roaming\npm''',
    '',
    '$subject = (& git log -1 --pretty=%s 2>&1).ToString().Trim()',
    'if ($subject -eq ''...'') { Log ''skipping: subject "..."''; exit 0 }',
    'if ($subject -match ''\\[skip maintainer\\]'') { Log ''skipping: [skip maintainer]''; exit 0 }',
    'if ($subject -match ''^(docs|notes):'') { Log ("skipping maintainer for notes commit: " + $subject); exit 0 }',
    'if ($subject -match ''^(chore|ci|style|refactor|test)(\([^)]+\))?:'') { Log ("skipping maintainer for low-signal commit: " + $subject); exit 0 }',
    'if ($subject -match ''(?i)\b(release|bump version)\b'') { Log ("skipping maintainer for release/bump: " + $subject); exit 0 }',
    'if ($subject -match ''(?i)\b(dependabot|renovate)\b'') { Log ("skipping maintainer for bot commit: " + $subject); exit 0 }',
    '$parents = (& git show -s --pretty=%P 2>$null).ToString().Trim()',
    'if ($parents -and ($parents -split ''\s+'').Count -gt 1) { Log ''skipping: merge commit''; exit 0 }',
    '$changed = & git show -1 --name-only 2>$null',
    'if ($changed -and ($changed | Where-Object { $_ -notmatch ''^\\.githooks[\\\\/]'' }) -eq $null) { Log ''skipping: .githooks-only commit''; exit 0 }',
    'if ($changed -and ($changed | Where-Object { $_ -notmatch ''^(docs/project_notes/|AGENTS\\.md$|CLAUDE\\.md$)'' }) -eq $null) { Log ''skipping: notes/agents-only commit''; exit 0 }',
    'if ($changed -and ($changed | Where-Object { $_ -notmatch ''\.md$'' }) -eq $null -and ($changed | Where-Object { $_ -match ''^docs/project_notes/'' }) -eq $null) { Log ''skipping: docs-only commit outside project_notes''; exit 0 }',
    '$lockfiles = @(',
    '  ''package-lock.json'',''pnpm-lock.yaml'',''yarn.lock'',''bun.lockb'',''npm-shrinkwrap.json'',''composer.lock'',''poetry.lock'',''Pipfile.lock'',''Cargo.lock'',''Gemfile.lock'',''go.sum''',
    ')',
    'if ($changed -and ($changed | Where-Object { $lockfiles -notcontains $_ }) -eq $null) { Log ''skipping: lockfiles-only commit''; exit 0 }',
    'if ($env:MAINTAINER_SKIP -eq ''1'') { Log ''skipping: MAINTAINER_SKIP=1''; exit 0 }',
    'if (-not $env:MAINTAINER_ASYNC -or $env:MAINTAINER_ASYNC.Trim() -eq '''') { $env:MAINTAINER_ASYNC = ''1'' }',
    'if ($env:MAINTAINER_ASYNC -ne ''0'' -and $env:MAINTAINER_ASYNC_CHILD -ne ''1'') {',
    '  Log ''spawning async maintainer''',
    '  $env:MAINTAINER_ASYNC_CHILD = ''1''',
    '  $ps = if (Get-Command pwsh -ErrorAction SilentlyContinue) { ''pwsh'' } else { ''powershell'' }',
    '  Start-Process -FilePath $ps -ArgumentList (''-NoProfile -ExecutionPolicy Bypass -File "'' + $PSCommandPath + ''"'') -WindowStyle Hidden | Out-Null',
    '  exit 0',
    '}',
    '',
    'if ($env:EVERYCODE_MAINTAINER_RUNNING -eq ''1'') { Log ''skipping: maintainer already running''; exit 0 }',
    'if (Test-Path $lockFile) { Log ''skipping: lock file present''; exit 0 }',
    '',
    '$env:EVERYCODE_MAINTAINER_RUNNING = ''1''',
    'New-Item -ItemType File -Force -Path $lockFile | Out-Null',
    '',
    'try {',
    "  Log 'post-commit hook start'",
    '  $env:CODE_HOME = ''C:\Users\Jordan\.codex''',
    '  Log ("CODE_HOME=" + $env:CODE_HOME)',
    '  if (-not (Test-Path $coderPath)) { Log ("Codex not found: " + $coderPath); return }',
    '  Log ("codex bin: " + $coderPath)',
    '  Log ("codex ext: " + $coderExt)',
    '  $subject = (& git log -1 --pretty=%s 2>&1).ToString().Trim()',
    '  if ($subject -eq ''...'') {',
    '    Log ''skipping: subject "..."''',
    '    return',
    '  }',
    '  if ($subject -match ''\\[skip maintainer\\]'') {',
    '    Log ''skipping: [skip maintainer]''',
    '    return',
    '  }',
    '  if ($subject -match ''^(docs|notes):'') {',
    '    Log ("skipping maintainer for notes commit: " + $subject)',
    '    return',
    '  }',
    '  if ($subject -match ''^(chore|ci|style|refactor|test)(\([^)]+\))?:'') {',
    '    Log ("skipping maintainer for low-signal commit: " + $subject)',
    '    return',
    '  }',
    '  if ($subject -match ''(?i)\b(release|bump version)\b'') {',
    '    Log ("skipping maintainer for release/bump: " + $subject)',
    '    return',
    '  }',
    '  if ($subject -match ''(?i)\b(dependabot|renovate)\b'') {',
    '    Log ("skipping maintainer for bot commit: " + $subject)',
    '    return',
    '  }',
    '  $parents = (& git show -s --pretty=%P 2>$null).ToString().Trim()',
    '  if ($parents -and ($parents -split ''\s+'').Count -gt 1) {',
    '    Log ''skipping: merge commit''',
    '    return',
    '  }',
    '  $changed = & git show -1 --name-only 2>$null',
    '  if ($changed -and ($changed | Where-Object { $_ -notmatch ''^\\.githooks[\\\\/]'' }) -eq $null) {',
    '    Log ''skipping: .githooks-only commit''',
    '    return',
    '  }',
    '  if ($changed -and ($changed | Where-Object { $_ -notmatch ''^(docs/project_notes/|AGENTS\\.md$|CLAUDE\\.md$)'' }) -eq $null) {',
    '    Log ''skipping: notes/agents-only commit''',
    '    return',
    '  }',
    '  if ($changed -and ($changed | Where-Object { $_ -notmatch ''\.md$'' }) -eq $null -and ($changed | Where-Object { $_ -match ''^docs/project_notes/'' }) -eq $null) {',
    '    Log ''skipping: docs-only commit outside project_notes''',
    '    return',
    '  }',
    '  $lockfiles = @(',
    '    ''package-lock.json'',''pnpm-lock.yaml'',''yarn.lock'',''bun.lockb'',''npm-shrinkwrap.json'',''composer.lock'',''poetry.lock'',''Pipfile.lock'',''Cargo.lock'',''Gemfile.lock'',''go.sum''',
    '  )',
    '  if ($changed -and ($changed | Where-Object { $lockfiles -notcontains $_ }) -eq $null) {',
    '    Log ''skipping: lockfiles-only commit''',
    '    return',
    '  }',
    '',
    '  $requiredRel = @(',
    '    ''AGENTS.md'',',
    '    ''CLAUDE.md'',',
    '    ''docs/project_notes/operating_brief.md'',',
    '    ''docs/project_notes/key_facts.md'',',
    '    ''docs/project_notes/adrs.md'',',
    '    ''docs/project_notes/bugs.md'',',
    '    ''docs/project_notes/worklog.md''',
    '  )',
    '  $missing = $requiredRel | Where-Object { -not (Test-Path (Join-Path $repoRoot $_)) }',
    '  if ($missing) {',
    '    $bootstrapPrompt = (',
    '      ''You are a non-interactive maintainer. Use the project-context skill to create/update AGENTS.md and CLAUDE.md files in the root, and create/update the specified context files in docs/project_notes/.'' +',
    '      '' Do not touch any other paths.''',
    '    )',
    "    Log 'bootstrapping docs/project_notes'",
    '    Log ("bootstrapping using: " + $coderPath)',
    '    $exitCode = Invoke-Coder $bootstrapPrompt 600',
    '    Log ("bootstrap exit code: " + $exitCode)',
    '  }',
    '',
    '  $summary = & git show -1 --name-status --stat --no-color 2>&1',
    '  $full = & git show -1 --unified=0 --no-color 2>&1',
    '  $summaryText = ($summary | ForEach-Object { Strip-Ansi $_ }) -join "`n"',
    '  $fullText = ($full | ForEach-Object { Strip-Ansi $_ }) -join "`n"',
    '  Log "commit summary:"',
    '  $summary | ForEach-Object {',
    '    $clean = Strip-Ansi $_',
    '    if ($clean) {',
    '      Write-LogLine $clean',
    '      if ($env:MAINTAINER_HOOK_ECHO -eq ''1'') { Write-Host $clean }',
    '    }',
    '  }',
    '',
    '  $promptLines = @(',
    '    ''You are a non-interactive maintainer. Use the project-context skill to create/update AGENTS.md and CLAUDE.md files in the root, and create/update the specified context files in docs/project_notes/.'',',
    '    ''Rules:'',',
    '    ''- Only edit those files (plus AGENTS.md and CLAUDE.md if required by the skill); do not touch anything else.'',',
    '    ''- If nothing meaningful changed for the notes, make no edits.'',',
    '    ''- Enforce no duplication: worklog links should not repeat; ADRs are constraints; key_facts are lookup truths; bugs are recurring/scary only.'',',
    '    '''',',
    '    ''Commit summary:'',',
    '    $summaryText,',
    '    '''',',
    '    ''Commit diff:'',',
    '    $fullText',
    '  )',
    '  $prompt = $promptLines -join "`n"',
    '  $maxPromptChars = 40000',
    '  if ($prompt.Length -gt $maxPromptChars) {',
    '    $keep = [Math]::Max(0, $maxPromptChars - 200)',
    '    $prompt = $prompt.Substring(0, $keep) + "`n...[truncated]..."',
    '  }',
    '',
    "  Log 'running maintainer'",
    '  Log ("maintainer using: " + $coderPath)',
    '  $exitCode = Invoke-Coder $prompt 240',
    '  Log ("maintainer exit code: " + $exitCode)',
    '  Commit-NotesIfChanged ''docs: update project notes [skip maintainer]'' | Out-Null',
    "  Log 'post-commit hook end'",
    '}',
    'catch {',
    '  Log ("error: " + $_.Exception.Message)',
    '}',
    'finally {',
    '  Remove-Item -Force -ErrorAction SilentlyContinue $lockFile',
    '  Remove-Item Env:EVERYCODE_MAINTAINER_RUNNING -ErrorAction SilentlyContinue',
    '}'
  )
  $postCommitPs1 = $postCommitPs1Lines -join "`n"

  Set-Content -Path (Join-Path $hooksDir 'post-commit') -Value $postCommitSh
  Set-Content -Path (Join-Path $hooksDir 'post-commit.ps1') -Value $postCommitPs1

  function Test-GeneratedHook([string]$hookPath) {
    $content = Get-Content -Path $hookPath
    $text = $content -join "`n"
    if ($text -notmatch '\$ts\s*=\s*Get-Date') { Write-Host 'Test-GeneratedHook failed: missing $ts assignment.'; return $false }
    if ($text -notmatch '\$coderPath\s*=') { Write-Host 'Test-GeneratedHook failed: missing $coderPath assignment.'; return $false }
    if ($text -notmatch '--full-auto') { Write-Host 'Test-GeneratedHook failed: missing --full-auto.'; return $false }
    if ($text -notmatch '--sandbox\s+workspace-write') { Write-Host 'Test-GeneratedHook failed: missing --sandbox workspace-write.'; return $false }
    if ($text -notmatch '\bexec\b') { Write-Host 'Test-GeneratedHook failed: missing exec subcommand.'; return $false }
    if ($text -notmatch '\$requiredRel\s*=\s*@\(') { Write-Host 'Test-GeneratedHook failed: missing $requiredRel list.'; return $false }
    if ($text -notmatch '\$subject\s*=\s*\(\&\s*git\s+log') { Write-Host 'Test-GeneratedHook failed: missing $subject assignment.'; return $false }
    if ($text -notmatch 'if\s*\(\$subject\s*-match\s*''\^\(docs\|notes\):''\)') { Write-Host 'Test-GeneratedHook failed: missing notes skip check.'; return $false }
    if ($text -match '^\s*=\s' -or $text -match '^\s*-match\s') { Write-Host 'Test-GeneratedHook failed: malformed assignment or match line.'; return $false }
    return $true
  }

  $hookPath = Join-Path $hooksDir 'post-commit.ps1'
  if (-not (Test-GeneratedHook $hookPath)) {
    Write-Error 'Generated post-commit.ps1 failed validation. Aborting install.'
    exit 1
  }

  & git config core.hooksPath .githooks

  Write-Host 'Maintainer hook installed.'
}

function Test-Hook([string]$repoRoot) {
  $hooksDir = Join-Path $repoRoot '.githooks'
  $hookPath = Join-Path $hooksDir 'post-commit.ps1'
  $gitDir = Get-GitDir $repoRoot
  $logFile = Join-Path $gitDir 'maintainer-hook.log'
  $lockFile = Join-Path $gitDir 'maintainer-hook.lock'
  Remove-Item -Force -ErrorAction SilentlyContinue $lockFile

  if (-not (Test-Path $hookPath)) {
    Write-Error 'post-commit.ps1 not found. Run install first.'
    exit 1
  }

  $content = Get-Content -Path $hookPath
  $text = $content -join "`n"
  if ($text -notmatch '\$ts\s*=\s*Get-Date') { Write-Error 'Missing $ts assignment.'; exit 1 }
  if ($text -notmatch '\$coderPath\s*=') { Write-Error 'Missing $coderPath assignment.'; exit 1 }
  if ($text -notmatch '\$requiredRel\s*=\s*@\(') { Write-Error 'Missing $requiredRel list.'; exit 1 }
  if ($text -notmatch '\$subject\s*=\s*\(\&\s*git\s+log') { Write-Error 'Missing $subject assignment.'; exit 1 }
  if ($text -notmatch 'if\s*\(\$subject\s*-match\s*''\^\(docs\|notes\):''\)') { Write-Error 'Missing notes skip check.'; exit 1 }
  if ($text -match '^\s*=\s' -or $text -match '^\s*-match\s') { Write-Error 'Found malformed assignment or match line.'; exit 1 }
  if ($text -notmatch '--full-auto') { Write-Error 'Missing --full-auto flag.'; exit 1 }
  if ($text -notmatch '--sandbox\s+workspace-write') { Write-Error 'Missing --sandbox workspace-write flag.'; exit 1 }
  if ($text -notmatch '\bexec\b') { Write-Error 'Missing exec subcommand.'; exit 1 }

  $preLines = 0
  if (Test-Path $logFile) {
    $preLines = (Get-Content -Path $logFile).Count
  }

  $prevEvery = $env:CODEX_BIN
  $env:CODEX_BIN = '__missing__'
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $hookPath
  if ($prevEvery) {
    $env:CODEX_BIN = $prevEvery
  } else {
    Remove-Item Env:CODEX_BIN -ErrorAction SilentlyContinue
  }

  $postLines = 0
  if (Test-Path $logFile) {
    $postLines = (Get-Content -Path $logFile).Count
  }

  if ($postLines -le $preLines) {
    Write-Error 'Hook did not write to log.'
    exit 1
  }

  $newLines = Get-Content -Path $logFile | Select-Object -Skip $preLines
  $newText = $newLines -join "`n"
  if ($newText -match 'error:' -or $newText -match 'ParserError' -or $newText -match 'unexpected argument' -or $newText -match '-match is not recognized') {
    Write-Error 'Hook logged an error. Check maintainer-hook.log.'
    exit 1
  }

  if ($newText -notmatch 'Codex not found: __missing__') {
    Write-Error 'Hook did not run to the Codex check.'
    exit 1
  }

  Write-Host 'Maintainer hook test passed.'
}

function Uninstall-Hook([string]$repoRoot) {
  $hooksPathRaw = & git config --get core.hooksPath 2>$null
  $hooksPath = if ($hooksPathRaw) { $hooksPathRaw.Trim() } else { '' }

  if ($hooksPath -eq '.githooks') {
    & git config --unset core.hooksPath
    Write-Host 'Unset core.hooksPath (was .githooks).'
  } elseif ($hooksPath) {
    Write-Host ("core.hooksPath left unchanged: " + $hooksPath)
  } else {
    Write-Host 'core.hooksPath was not set.'
  }

  $hooksDir = Join-Path $repoRoot '.githooks'
  $postCommit = Join-Path $hooksDir 'post-commit'
  $postCommitPs1 = Join-Path $hooksDir 'post-commit.ps1'

  if (Test-Path $postCommit) {
    Remove-Item -Force $postCommit
    Write-Host 'Removed .githooks/post-commit.'
  } else {
    Write-Host 'No .githooks/post-commit found.'
  }

  if (Test-Path $postCommitPs1) {
    Remove-Item -Force $postCommitPs1
    Write-Host 'Removed .githooks/post-commit.ps1.'
  } else {
    Write-Host 'No .githooks/post-commit.ps1 found.'
  }

  if (Test-Path $hooksDir) {
    $remaining = Get-ChildItem -Path $hooksDir -Force
    if ($remaining.Count -eq 0) {
      Remove-Item -Force $hooksDir
      Write-Host 'Removed empty .githooks directory.'
    } else {
      Write-Host 'Left .githooks directory (not empty).'
    }
  }
}

$repoRoot = Get-RepoRoot
if (-not $repoRoot) {
  Write-Error 'Not inside a git repository.'
  exit 1
}
Set-Location $repoRoot

if ($args.Count -lt 1) {
  Write-Host 'Usage: context-hook <install|uninstall|run|test>'
  exit 1
}

switch ($args[0]) {
  'install' { Install-Hook $repoRoot }
  'uninstall' { Uninstall-Hook $repoRoot }
  'run' { Run-Guarded $repoRoot 'manual'; Write-Host 'Maintainer run complete.' }
  'test' { Install-Hook $repoRoot; Test-Hook $repoRoot }
  default { Write-Host 'Usage: context-hook <install|uninstall|run|test>'; exit 1 }
}
