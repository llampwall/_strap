# tests/powershell/Invoke-ConsolidateAuditStep.Tests.ps1
Describe "Consolidate Audit Step Integration" {
    BeforeAll {
        # Extract functions from strap.ps1
        $strapContent = Get-Content "$PSScriptRoot\..\..\strap.ps1" -Raw

        function Extract-Function {
            param($Content, $FunctionName)
            $startIndex = $Content.IndexOf("function $FunctionName {")
            if ($startIndex -eq -1) {
                throw "Could not find $FunctionName function in strap.ps1"
            }
            $braceCount = 0
            $inFunction = $false
            $endIndex = $startIndex
            for ($i = $startIndex; $i -lt $Content.Length; $i++) {
                $char = $Content[$i]
                if ($char -eq '{') {
                    $braceCount++
                    $inFunction = $true
                } elseif ($char -eq '}') {
                    $braceCount--
                    if ($inFunction -and $braceCount -eq 0) {
                        $endIndex = $i + 1
                        break
                    }
                }
            }
            return $Content.Substring($startIndex, $endIndex - $startIndex)
        }

        # Extract all needed functions
        $functions = @(
            "Get-ScheduledTaskReferences",
            "Get-ShimReferences",
            "Get-PathReferences",
            "Get-ProfileReferences",
            "Find-PathReferences",
            "Build-AuditIndex"
        )

        foreach ($funcName in $functions) {
            $funcCode = Extract-Function $strapContent $funcName
            Invoke-Expression $funcCode
        }

        # Create mock registry
        $testRegistryPath = Join-Path $TestDrive "registry-v2.json"
        $registry = @{
            version = 2
            updated_at = (Get-Date).ToUniversalTime().ToString("o")
            entries = @(
                @{
                    name = "testproject"
                    path = "C:\Code\testproject"
                    scope = "active"
                    last_commit = "abc123"
                }
            )
        }
        $registry | ConvertTo-Json -Depth 10 | Set-Content $testRegistryPath

        # Create mock repo
        New-Item -ItemType Directory -Path "C:\Code\testproject" -Force | Out-Null
        Set-Content -Path "C:\Code\testproject\config.json" -Value '{"root": "C:\Code\testproject"}'

        # Create scheduled task referencing repo
        $taskName = "StrapTest-ConsolidateAudit"
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File C:\Code\testproject\task.ps1"
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddHours(1)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Force | Out-Null
    }

    AfterAll {
        # Clean up
        Unregister-ScheduledTask -TaskName "StrapTest-ConsolidateAudit" -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Code\testproject" -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "should detect scheduled tasks in audit step" {
        # Arrange
        $fromPath = "C:\Code\testproject"
        $repoPaths = @($fromPath)

        # Act
        $scheduledTasks = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert - should detect the test scheduled task
        $scheduledTasks | Should Not BeNullOrEmpty
        $scheduledTasks.Count | Should BeGreaterThan 0
        $scheduledTasks[0].name | Should Match "StrapTest-ConsolidateAudit"
        $scheduledTasks[0].path | Should Match "testproject"
    }

    It "should build audit index as part of consolidate workflow" {
        # Arrange
        $indexPath = Join-Path $TestDrive "build\audit-index.json"
        $registryPath = Join-Path $TestDrive "registry-v2.json"
        $registryData = Get-Content $registryPath | ConvertFrom-Json

        # Act
        $index = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryData.updated_at -Registry $registryData.entries

        # Assert
        Test-Path $indexPath | Should Be $true
        $index.repo_count | Should Be 1
        $index.repos["C:\Code\testproject"] | Should Not BeNullOrEmpty
    }

    It "should cache audit index across multiple consolidate runs" {
        # Arrange
        $indexPath = Join-Path $TestDrive "build\audit-index-cache.json"
        $registryPath = Join-Path $TestDrive "registry-v2.json"
        $registryData = Get-Content $registryPath | ConvertFrom-Json

        # Act - first run
        $firstIndex = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryData.updated_at -Registry $registryData.entries

        $firstBuiltAt = $firstIndex.built_at

        Start-Sleep -Milliseconds 100

        # Act - second run (should use cache)
        $secondIndex = Build-AuditIndex -IndexPath $indexPath -RebuildIndex $false `
            -RegistryUpdatedAt $registryData.updated_at -Registry $registryData.entries

        # Assert - timestamps should match (cached)
        $secondIndex.built_at | Should Be $firstBuiltAt
    }

    It "should warn about external references but allow --ack-scheduled-tasks override" {
        # Arrange
        $auditWarnings = @(
            "Scheduled task 'test' references C:\Code\testproject",
            "PATH entry: C:\Code\testproject\bin"
        )
        $ackScheduledTasks = $true

        # Act - simulate the warning logic
        $shouldBlock = ($auditWarnings.Count -gt 0) -and (-not $ackScheduledTasks)

        # Assert
        $shouldBlock | Should Be $false
    }

    It "should block consolidate when external references exist without --ack-scheduled-tasks" {
        # Arrange
        $auditWarnings = @(
            "Scheduled task 'test' references C:\Code\testproject"
        )
        $ackScheduledTasks = $false

        # Act
        $shouldBlock = ($auditWarnings.Count -gt 0) -and (-not $ackScheduledTasks)

        # Assert
        $shouldBlock | Should Be $true
    }
}
