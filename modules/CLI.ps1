# CLI.ps1
# Command-line parsing and dispatch functions

function Parse-GlobalFlags {
  <#
  .SYNOPSIS
      Extracts chinvex-related global flags from command line arguments.
  .DESCRIPTION
      Parses --no-chinvex, --tool, and --software flags.
      Returns a hashtable with flag values and remaining arguments.
  .PARAMETER Arguments
      The full argument list from CLI.
  .OUTPUTS
      [hashtable] with keys: NoChinvex, IsTool, IsSoftware, RemainingArgs
  #>
  param(
      [string[]] $Arguments
  )

  $result = @{
      NoChinvex = $false
      IsTool = $false
      IsSoftware = $false
      RemainingArgs = @()
  }

  foreach ($arg in $Arguments) {
      switch ($arg) {
          "--no-chinvex" { $result.NoChinvex = $true }
          "--tool" { $result.IsTool = $true }
          "--software" { $result.IsSoftware = $true }
          default { $result.RemainingArgs += $arg }
      }
  }

  return $result
}

# Functions are automatically available when dot-sourced
