# modules/References.ps1
# Functions for finding external references to repositories

# Dependencies
$ModulesPath = $PSScriptRoot
. (Join-Path $ModulesPath "Core.ps1")
. (Join-Path $ModulesPath "Utils.ps1")
. (Join-Path $ModulesPath "Path.ps1")
. (Join-Path $ModulesPath "Config.ps1")

function Get-ScheduledTaskReferences {
    <#
    .SYNOPSIS
    Detects Windows scheduled tasks that reference repository paths

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'name' and 'path' properties
    #>
    param(
        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    try {
        # Get all scheduled tasks as CSV
        $csv = & schtasks /query /fo csv /v 2>$null
        if (-not $csv) { return @() }

        # Parse CSV output
        $tasks = $csv | ConvertFrom-Csv -ErrorAction SilentlyContinue
        if (-not $tasks) { return @() }

        # Normalize repo paths for comparison
        $normalizedRepoPaths = $RepoPaths | ForEach-Object {
            $_.Replace('/', '\').TrimEnd('\').ToLower()
        }

        # Scan each task for path references
        $references = [System.Collections.ArrayList]::new()
        foreach ($task in $tasks) {
            # Combine task name, command, and arguments for path extraction
            $searchText = "$($task.TaskName) $($task.'Task To Run')"

            # Extract Windows paths (e.g., C:\path\to\file)
            $pathMatches = [regex]::Matches($searchText, '[A-Za-z]:\\[^\s,\"]+')

            foreach ($match in $pathMatches) {
                $extractedPath = $match.Value.TrimEnd('\').ToLower()

                # Check if path starts with any repo path
                $matchesRepo = $normalizedRepoPaths | Where-Object {
                    $extractedPath.StartsWith($_)
                }

                if ($matchesRepo) {
                    $null = $references.Add(@{
                        name = $task.TaskName
                        path = $match.Value
                    })
                    break  # Only add task once even if multiple paths match
                }
            }
        }

        return ,$references.ToArray()

    } catch {
        # schtasks failed or not available - return empty array
        Write-Verbose "Failed to query scheduled tasks: $_"
        return @()
    }
}

function Get-ShimReferences {
    <#
    .SYNOPSIS
    Detects .cmd shim files that reference repository paths

    .PARAMETER ShimDir
    Directory containing shim files (typically build/shims)

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'name' and 'target' properties
    #>
    param(
        [Parameter(Mandatory)]
        [string] $ShimDir,

        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    # Check if shim directory exists
    if (-not (Test-Path $ShimDir)) {
        Write-Verbose "Shim directory not found: $ShimDir"
        return @()
    }

    # Normalize repo paths for comparison
    $normalizedRepoPaths = $RepoPaths | ForEach-Object {
        $_.Replace('/', '\').TrimEnd('\').ToLower()
    }

    # Scan all .cmd files in shim directory
    $references = [System.Collections.ArrayList]::new()
    $shimFiles = Get-ChildItem -Path $ShimDir -Filter "*.cmd" -ErrorAction SilentlyContinue

    foreach ($shimFile in $shimFiles) {
        try {
            # Read shim content
            $content = Get-Content $shimFile.FullName -Raw -ErrorAction Stop

            # Extract Windows paths from content
            $pathMatches = [regex]::Matches($content, '[A-Za-z]:\\[^\r\n\"]+')

            foreach ($match in $pathMatches) {
                $extractedPath = $match.Value.TrimEnd('\').ToLower()

                # Check if path starts with any repo path
                $matchesRepo = $normalizedRepoPaths | Where-Object {
                    $extractedPath.StartsWith($_)
                }

                if ($matchesRepo) {
                    $null = $references.Add(@{
                        name = $shimFile.BaseName
                        target = $match.Value
                    })
                    break  # Only add shim once even if multiple paths match
                }
            }
        } catch {
            Write-Verbose "Failed to read shim file $($shimFile.FullName): $_"
            continue
        }
    }

    return ,$references.ToArray()
}

function Get-PathReferences {
    <#
    .SYNOPSIS
    Detects PATH environment variable entries that reference repository paths

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'type' and 'path' properties
    #>
    param(
        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    # Normalize repo paths for comparison
    $normalizedRepoPaths = $RepoPaths | ForEach-Object {
        $_.Replace('/', '\').TrimEnd('\').ToLower()
    }

    # Get User and Machine PATH variables
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")

    # Combine and split by semicolon
    $allPathEntries = @()
    if ($userPath) { $allPathEntries += $userPath -split ';' }
    if ($machinePath) { $allPathEntries += $machinePath -split ';' }

    # Find matching entries
    $references = [System.Collections.ArrayList]::new()
    foreach ($pathEntry in $allPathEntries) {
        if ([string]::IsNullOrWhiteSpace($pathEntry)) { continue }

        $normalizedEntry = $pathEntry.TrimEnd('\').ToLower()

        # Check if entry starts with any repo path
        $matchesRepo = $normalizedRepoPaths | Where-Object {
            $normalizedEntry.StartsWith($_)
        }

        if ($matchesRepo) {
            $null = $references.Add(@{
                type = "PATH"
                path = $pathEntry
            })
        }
    }

    return ,$references.ToArray()
}

function Get-ProfileReferences {
    <#
    .SYNOPSIS
    Detects PowerShell profile references to repository paths

    .PARAMETER ProfilePath
    Path to PowerShell profile file (defaults to $PROFILE)

    .PARAMETER RepoPaths
    Array of repository paths to check for references

    .OUTPUTS
    Array of hashtables with 'type' and 'path' properties
    #>
    param(
        [Parameter()]
        [string] $ProfilePath = $PROFILE,

        [Parameter(Mandatory)]
        [string[]] $RepoPaths
    )

    # Check if profile exists
    if (-not (Test-Path $ProfilePath)) {
        Write-Verbose "Profile not found: $ProfilePath"
        return @()
    }

    try {
        # Read profile content
        $content = Get-Content $ProfilePath -Raw -ErrorAction Stop

        # Normalize repo paths for comparison
        $normalizedRepoPaths = $RepoPaths | ForEach-Object {
            $_.Replace('/', '\').TrimEnd('\').ToLower()
        }

        # Extract Windows paths from content
        $pathMatches = [regex]::Matches($content, '[A-Za-z]:\\[^\s\r\n\"\'']+')

        # Find matching paths
        $references = [System.Collections.ArrayList]::new()
        foreach ($match in $pathMatches) {
            $extractedPath = $match.Value.TrimEnd('\').ToLower()

            # Check if path starts with any repo path
            $matchesRepo = $normalizedRepoPaths | Where-Object {
                $extractedPath.StartsWith($_)
            }

            if ($matchesRepo) {
                $null = $references.Add(@{
                    type = "profile"
                    path = $match.Value
                })
            }
        }

        return ,$references.ToArray()

    } catch {
        Write-Verbose "Failed to read profile $ProfilePath`: $_"
        return @()
    }
}

