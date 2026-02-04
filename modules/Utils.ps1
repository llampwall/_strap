# Utils.ps1
# General utility functions for strap

function Has-Command($name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Test-ProcessRunning {
  param([int] $ProcessId)
  try {
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    return $null -ne $process
  } catch {
    return $false
  }
}

function Get-DirectorySize {
  param([string] $Path)
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  try {
    $size = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
      Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    if ($size) { return [long]$size } else { return 0 }
  } catch {
    return 0
  }
}

# Functions are automatically available when dot-sourced
