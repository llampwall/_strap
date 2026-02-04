# modules/Audit.ps1
# Functions for auditing repositories and creating snapshots

# Dependencies
$ModulesPath = $PSScriptRoot
. (Join-Path $ModulesPath "Core.ps1")
. (Join-Path $ModulesPath "Utils.ps1")
. (Join-Path $ModulesPath "Path.ps1")
. (Join-Path $ModulesPath "Config.ps1")
. (Join-Path $ModulesPath "References.ps1")

function Find-PathReferences {
    <#
    .SYNOPSIS
    Scans repository files for hardcoded Windows path references

    .PARAMETER RepoPath
    Path to repository to scan

    .OUTPUTS
    Array of strings in format "filepath:linenum"
    #>
    param(
        [Parameter(Mandatory)]
        [string] $RepoPath
    )

    # Check if repo exists
    if (-not (Test-Path $RepoPath)) {
        Write-Verbose "Repository not found: $RepoPath"
        return @()
    }

    try {
        # Scan common file types for path references
        $fileExtensions = @('*.ps1', '*.js', '*.ts', '*.json', '*.yml', '*.yaml', '*.md', '*.txt', '*.config')
        $files = Get-ChildItem -Path $RepoPath -Recurse -File -Include $fileExtensions -ErrorAction SilentlyContinue

        $references = @()

        foreach ($file in $files) {
            try {
                $lineNum = 0
                $lines = Get-Content $file.FullName -ErrorAction Stop

                foreach ($line in $lines) {
                    $lineNum++

                    # Check if line contains Windows path pattern
                    if ($line -match '[A-Za-z]:\\[^\s\r\n\"\'']+') {
                        $references += "$($file.FullName):$lineNum"
                    }
                }
            } catch {
                Write-Verbose "Failed to read file $($file.FullName): $_"
                continue
            }
        }

        return $references

    } catch {
        Write-Verbose "Failed to scan repository $RepoPath`: $_"
        return @()
    }
}

function Build-AuditIndex {
    <#
    .SYNOPSIS
    Builds or loads cached audit index of path references across all repositories

    .PARAMETER IndexPath
    Path to audit index JSON file

    .PARAMETER RebuildIndex
    Force rebuild even if cached index is fresh

    .PARAMETER RegistryUpdatedAt
    ISO8601 timestamp of registry last update

    .PARAMETER Registry
    Array of registry entries (hashtables with 'name', 'path', 'last_commit')

    .OUTPUTS
    Hashtable with audit index structure
    #>
    param(
        [Parameter(Mandatory)]
        [string] $IndexPath,

        [Parameter(Mandatory)]
        [bool] $RebuildIndex,

        [Parameter(Mandatory)]
        [string] $RegistryUpdatedAt,

        [Parameter(Mandatory)]
        [array] $Registry
    )

    # Check if existing index is fresh
    if ((Test-Path $IndexPath) -and -not $RebuildIndex) {
        try {
            $existingJson = Get-Content $IndexPath -Raw | ConvertFrom-Json

            # Check if cached index is still valid
            # Note: ConvertFrom-Json converts ISO8601 strings to DateTime in local timezone
            # We need to compare UTC times to handle timezone differences
            $existingTime = $null
            $inputTime = $null

            if ($existingJson.registry_updated_at -is [DateTime]) {
                $existingTime = $existingJson.registry_updated_at.ToUniversalTime()
            } else {
                $existingTime = ([DateTime]::Parse($existingJson.registry_updated_at)).ToUniversalTime()
            }

            $inputTime = ([DateTime]::Parse($RegistryUpdatedAt)).ToUniversalTime()

            $isFresh = ($existingTime -eq $inputTime) -and
                       ($existingJson.repo_count -eq $Registry.Count)

            if ($isFresh) {
                Write-Verbose "Using cached audit index"

                # Convert PSCustomObject to hashtable for consistency
                # Convert DateTime objects back to ISO8601 strings
                $builtAtStr = $existingJson.built_at
                if ($builtAtStr -is [DateTime]) {
                    $builtAtStr = $builtAtStr.ToUniversalTime().ToString("o")
                }

                $regUpdatedAtStr = $existingJson.registry_updated_at
                if ($regUpdatedAtStr -is [DateTime]) {
                    $regUpdatedAtStr = $regUpdatedAtStr.ToUniversalTime().ToString("o")
                }

                $existing = @{
                    built_at = $builtAtStr
                    registry_updated_at = $regUpdatedAtStr
                    repo_count = $existingJson.repo_count
                    repos = @{}
                }

                # Convert repos object to hashtable
                $existingJson.repos.PSObject.Properties | ForEach-Object {
                    $repoRefs = @()
                    if ($_.Value.references) {
                        $repoRefs = @($_.Value.references)
                    }
                    $existing.repos[$_.Name] = @{
                        references = $repoRefs
                    }
                }

                return $existing
            }
        } catch {
            Write-Verbose "Failed to read existing index, rebuilding"
        }
    }

    # Build new index
    Write-Host "Building audit index for $($Registry.Count) repositories..." -ForegroundColor Cyan

    $repos = @{}
    foreach ($entry in $Registry) {
        Write-Verbose "Scanning $($entry.name) at $($entry.path)"

        # Scan repo for path references
        $references = Find-PathReferences -RepoPath $entry.path

        $repos[$entry.path] = @{
            references = $references
        }
    }

    # Build index structure
    $index = @{
        built_at = (Get-Date).ToUniversalTime().ToString("o")
        registry_updated_at = $RegistryUpdatedAt
        repo_count = $Registry.Count
        repos = $repos
    }

    # Write to disk
    try {
        $indexDir = Split-Path $IndexPath -Parent
        if ($indexDir -and -not (Test-Path $indexDir)) {
            New-Item -ItemType Directory -Path $indexDir -Force | Out-Null
        }

        $index | ConvertTo-Json -Depth 10 | Set-Content $IndexPath -Encoding UTF8
        Write-Verbose "Audit index written to $IndexPath"
    } catch {
        Write-Warning "Failed to write audit index to disk: $_"
    }

    return $index
}

function Invoke-Snapshot {
    <#
    .SYNOPSIS
    Captures comprehensive environment snapshot with git metadata and external references

    .PARAMETER ScanDirs
    Array of directories to scan (defaults to C:\Code, P:\software, etc.)

    .PARAMETER OutputPath
    Path to write snapshot JSON file

    .PARAMETER StrapRootPath
    Path to strap root directory

    .OUTPUTS
    Hashtable with snapshot manifest structure
    #>
    param(
        [Parameter()]
        [string[]] $ScanDirs,

        [Parameter(Mandatory)]
        [string] $OutputPath,

        [Parameter(Mandatory)]
        [string] $StrapRootPath
    )
    if (-not (Assert-CommandSafe 'Invoke-Snapshot')) { return }

    Write-Host "Capturing environment snapshot..." -ForegroundColor Cyan

    # Default scan directories
    $defaultScanDirs = @("C:\Code", "P:\software", "C:\Users\$env:USERNAME\Documents\Code")
    if ($ScanDirs.Count -eq 0) {
        $ScanDirs = $defaultScanDirs | Where-Object { Test-Path $_ }
    }

    # Load registry
    $config = Load-Config $StrapRootPath
    $registryPath = $config.registry
    $registry = $null
    $registryVersion = 1

    if (Test-Path $registryPath) {
        try {
            $registryContent = Get-Content $registryPath -Raw | ConvertFrom-Json
            if ($registryContent.PSObject.Properties['entries']) {
                # New format
                $registry = $registryContent.entries
                $registryVersion = $registryContent.version
            } else {
                # Legacy format
                $registry = $registryContent
            }
        } catch {
            Write-Warning "Failed to load registry: $_"
            $registry = @()
        }
    } else {
        $registry = @()
    }

    # Build registry lookup by path (case-insensitive)
    $registryByPath = @{}
    foreach ($entry in $registry) {
        if ($entry.path) {
            $registryByPath[$entry.path.ToLower()] = $entry.name
        }
    }

    # Scan directories top-level
    Write-Verbose "Scanning directories: $($ScanDirs -join ', ')"
    $discovered = @()

    foreach ($scanDir in $ScanDirs) {
        if (-not (Test-Path $scanDir)) {
            Write-Verbose "Skipping non-existent directory: $scanDir"
            continue
        }

        $items = Get-ChildItem -Path $scanDir -ErrorAction SilentlyContinue

        foreach ($item in $items) {
            $itemPath = $item.FullName
            $inRegistry = $registryByPath.ContainsKey($itemPath.ToLower())

            if ($item.PSIsContainer) {
                # Check if it's a git repo
                $gitDir = Join-Path $itemPath ".git"
                if (Test-Path $gitDir) {
                    # Git repository
                    $remoteUrl = $null
                    $lastCommit = $null

                    try {
                        $remoteRaw = & git -C $itemPath remote get-url origin 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $remoteUrl = $remoteRaw.Trim()
                            # Normalize remote URL
                            if ($remoteUrl -match '^git@([^:]+):(.+)$') {
                                $remoteUrl = "https://$($Matches[1])/$($Matches[2])"
                            }
                            $remoteUrl = $remoteUrl -replace '\.git$', ''
                        }
                    } catch {}

                    try {
                        $commitRaw = & git -C $itemPath log -1 --format=%cI 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $lastCommit = $commitRaw.Trim()
                        }
                    } catch {}

                    $discovered += @{
                        path = $itemPath
                        name = $item.Name
                        type = "git"
                        in_registry = $inRegistry
                        remote_url = $remoteUrl
                        last_commit = $lastCommit
                    }
                } else {
                    # Regular directory
                    $discovered += @{
                        path = $itemPath
                        name = $item.Name
                        type = "directory"
                        in_registry = $inRegistry
                    }
                }
            } else {
                # File
                $discovered += @{
                    path = $itemPath
                    name = $item.Name
                    type = "file"
                }
            }
        }
    }

    # Collect external references
    Write-Verbose "Collecting external references..."
    $repoPaths = @($registry | Where-Object { $_.path } | ForEach-Object { $_.path })

    $externalRefs = @{
        pm2 = @()
        scheduled_tasks = @()
        shims = @()
        path_entries = @()
        profile_refs = @()
    }

    # PM2 processes
    if (Has-Command "pm2") {
        try {
            $pm2List = & pm2 jlist 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
            foreach ($proc in $pm2List) {
                if ($proc.pm2_env.pm_cwd) {
                    $externalRefs.pm2 += @{
                        name = $proc.name
                        cwd = $proc.pm2_env.pm_cwd
                    }
                }
            }
        } catch {}
    }

    # Only collect references if we have repos to check
    if ($repoPaths.Count -gt 0) {
        # Scheduled tasks
        $externalRefs.scheduled_tasks = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Shims
        $shimDir = Join-Path $StrapRootPath "build\shims"
        $externalRefs.shims = Get-ShimReferences -ShimDir $shimDir -RepoPaths $repoPaths

        # PATH entries
        $externalRefs.path_entries = Get-PathReferences -RepoPaths $repoPaths

        # Profile references
        $externalRefs.profile_refs = Get-ProfileReferences -RepoPaths $repoPaths
    }

    # Get disk usage
    $diskUsage = @{}
    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' }
        foreach ($drive in $drives) {
            $diskUsage[$drive.Name + ":"] = @{
                total_gb = [Math]::Round($drive.Used / 1GB + $drive.Free / 1GB, 2)
                free_gb = [Math]::Round($drive.Free / 1GB, 2)
            }
        }
    } catch {
        Write-Verbose "Failed to get disk usage: $_"
    }

    # Build snapshot manifest
    $manifest = @{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        registry = @{
            version = $registryVersion
            entries = $registry
        }
        discovered = $discovered
        external_refs = $externalRefs
        disk_usage = $diskUsage
    }

    # Write to output file
    try {
        $outputDir = Split-Path $OutputPath -Parent
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        $manifest | ConvertTo-Json -Depth 10 | Set-Content $OutputPath -Encoding UTF8
        Write-Host "Snapshot written to: $OutputPath" -ForegroundColor Green
    } catch {
        Write-Error "Failed to write snapshot to $OutputPath`: $_"
    }

    return $manifest
}

function Invoke-Audit {
    <#
    .SYNOPSIS
    Audits repositories for hardcoded path references

    .PARAMETER TargetName
    Name of specific repository to audit

    .PARAMETER AllRepos
    Audit all repositories in registry

    .PARAMETER ToolScope
    Filter to tool-scoped repositories only

    .PARAMETER SoftwareScope
    Filter to software-scoped repositories only

    .PARAMETER RebuildIndex
    Force rebuild of audit index even if cached

    .PARAMETER OutputJson
    Output results as JSON

    .PARAMETER StrapRootPath
    Path to strap root directory

    .OUTPUTS
    Hashtable or array with audit results
    #>
    param(
        [Parameter()]
        [string] $TargetName,

        [Parameter()]
        [switch] $AllRepos,

        [Parameter()]
        [switch] $ToolScope,

        [Parameter()]
        [switch] $SoftwareScope,

        [Parameter()]
        [switch] $RebuildIndex,

        [Parameter()]
        [switch] $OutputJson,

        [Parameter(Mandatory)]
        [string] $StrapRootPath
    )
    if (-not (Assert-CommandSafe 'Invoke-Audit')) { return }

    # Load config and registry
    $config = Load-Config $StrapRootPath
    $registryPath = $config.registry

    if (-not (Test-Path $registryPath)) {
        Die "Registry not found: $registryPath"
    }

    $registryContent = Get-Content $registryPath -Raw | ConvertFrom-Json
    $registryUpdatedAt = $registryContent.updated_at
    $registry = if ($registryContent.PSObject.Properties['entries']) {
        $registryContent.entries
    } else {
        $registryContent
    }

    # Filter by scope if requested
    if ($ToolScope) {
        $registry = $registry | Where-Object { $_.scope -eq "tool" }
    }
    if ($SoftwareScope) {
        $registry = $registry | Where-Object { $_.scope -eq "software" }
    }

    # Build audit index
    $indexPath = Join-Path $StrapRootPath "build\audit-index.json"
    $auditIndex = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $RebuildIndex.IsPresent `
        -RegistryUpdatedAt $registryUpdatedAt -Registry $registry

    # Process audit results
    if ($AllRepos) {
        # Audit all repositories
        $results = @()
        foreach ($repoPath in $auditIndex.repos.Keys) {
            $entry = $registry | Where-Object { $_.path -eq $repoPath } | Select-Object -First 1
            if (-not $entry) { continue }

            $refs = $auditIndex.repos[$repoPath].references
            $results += @{
                repository = $entry.name
                path = $repoPath
                references = $refs
                reference_count = $refs.Count
            }
        }

        if ($OutputJson) {
            $results | ConvertTo-Json -Depth 10
        } else {
            Write-Host "`nAudit Results - All Repositories:" -ForegroundColor Cyan
            foreach ($res in $results) {
                Write-Host "`n$($res.repository) ($($res.path))" -ForegroundColor Yellow
                Write-Host "  References found: $($res.reference_count)"
                if ($res.reference_count -gt 0) {
                    $res.references | Select-Object -First 5 | ForEach-Object {
                        Write-Host "    - $_" -ForegroundColor Gray
                    }
                    if ($res.reference_count -gt 5) {
                        Write-Host "    ... and $($res.reference_count - 5) more" -ForegroundColor Gray
                    }
                }
            }
        }

        return $results

    } else {
        # Audit specific repository
        if (-not $TargetName) {
            Die "Audit requires a target name or --all flag"
        }

        $entry = $registry | Where-Object { $_.name -eq $TargetName -or $_.id -eq $TargetName } | Select-Object -First 1
        if (-not $entry) {
            Die "Repository '$TargetName' not found in registry"
        }

        $refs = $auditIndex.repos[$entry.path].references
        $result = @{
            repository = $entry.name
            path = $entry.path
            references = $refs
            reference_count = $refs.Count
        }

        if ($OutputJson) {
            $result | ConvertTo-Json -Depth 10
        } else {
            Write-Host "`nAudit Results for $($entry.name):" -ForegroundColor Cyan
            Write-Host "Path: $($entry.path)"
            Write-Host "References found: $($refs.Count)"
            if ($refs.Count -gt 0) {
                Write-Host "`nReferences:" -ForegroundColor Yellow
                $refs | ForEach-Object {
                    Write-Host "  - $_" -ForegroundColor Gray
                }
            } else {
                Write-Host "No hardcoded path references found." -ForegroundColor Green
            }
        }

        return $result
    }
}

function Should-ExcludePath($fullPath, $root) {
  if (-not (Assert-CommandSafe 'Should-ExcludePath')) { return $false }
  $rel = $fullPath.Substring($root.Length).TrimStart('\\','/')
  if (-not $rel) { return $false }
  if ($rel -match '(?i)^[^\\/]*\\.git(\\|/|$)') { return $true }
  if ($rel -match '(?i)(\\|/)(\.git|node_modules|dist|build|\.turbo|\.vite|\.next|coverage|\.pytest_cache|__pycache__|\.venv|venv|\.pnpm-store|pnpm-store)(\\|/|$)') { return $true }
  if ($rel -match '(?i)\.(log|tmp)$') { return $true }
  return $false
}

function Copy-RepoSnapshot($src, $dest) {
  if (-not (Assert-CommandSafe 'Copy-RepoSnapshot')) { return $false }
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

