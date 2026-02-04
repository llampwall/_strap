# Test function extraction
. "$PSScriptRoot\TestHelpers.ps1"

Write-Host "Testing extraction..."
Extract-StrapFunction "Parse-GlobalFlags"

if (Get-Command Parse-GlobalFlags -ErrorAction SilentlyContinue) {
    Write-Host "SUCCESS: Parse-GlobalFlags extracted!" -ForegroundColor Green

    # Test it
    $result = Parse-GlobalFlags @("clone", "repo", "--no-chinvex")
    Write-Host "Test result: NoChinvex=$($result.NoChinvex)"
} else {
    Write-Host "FAILED: Parse-GlobalFlags not found" -ForegroundColor Red
}
