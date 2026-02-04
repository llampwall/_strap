$content = Get-Content "docs\plans\strap-chinvex-integration-plan-tdd.md" -Raw
$pattern = "(?s)(### Task 5:.*?)(?=### Task 6:|$)"
$match = [regex]::Match($content, $pattern)
if ($match.Success) {
    $match.Groups[1].Value | Set-Content ".batch-current.md" -NoNewline
    Write-Host "Extracted Task 5"
} else {
    Write-Host "ERROR: Could not extract Task 5"
    exit 1
}
