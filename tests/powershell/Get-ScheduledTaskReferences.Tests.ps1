# tests/powershell/Get-ScheduledTaskReferences.Tests.ps1
Describe "Get-ScheduledTaskReferences" {
    BeforeAll {
        # Extract and source just the function from strap.ps1
        $strapContent = Get-Content "$PSScriptRoot\..\..\strap.ps1" -Raw

        # Find function start
        $startIndex = $strapContent.IndexOf('function Get-ScheduledTaskReferences {')
        if ($startIndex -eq -1) {
            throw "Could not find Get-ScheduledTaskReferences function in strap.ps1"
        }

        # Find function end by counting braces
        $braceCount = 0
        $inFunction = $false
        $endIndex = $startIndex

        for ($i = $startIndex; $i -lt $strapContent.Length; $i++) {
            $char = $strapContent[$i]
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

        # Extract and execute function
        $functionCode = $strapContent.Substring($startIndex, $endIndex - $startIndex)
        Invoke-Expression $functionCode

        # Create test scheduled task
        $testTaskName = "StrapTest-MorningBrief"
        $testScriptPath = "C:\Code\chinvex\scripts\morning_brief.ps1"

        # Create task action and register task
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File `"$testScriptPath`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddHours(1)
        Register-ScheduledTask -TaskName $testTaskName -Action $action -Trigger $trigger -Force | Out-Null
    }

    AfterAll {
        # Clean up test task
        Unregister-ScheduledTask -TaskName "StrapTest-MorningBrief" -Confirm:$false -ErrorAction SilentlyContinue
    }

    It "should detect scheduled tasks referencing repository paths" {
        # Arrange
        $repoPaths = @("C:\Code\chinvex")

        # Act
        $result = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert
        $result | Should Not BeNullOrEmpty
        $result.Count | Should BeGreaterThan 0
        $matchingTask = $result | Where-Object { $_.name -like "*MorningBrief*" }
        $matchingTask | Should Not BeNullOrEmpty
        $matchingTask.path | Should Match "C:\\Code\\chinvex"
    }

    It "should return empty array when no tasks reference repo paths" {
        # Arrange
        $repoPaths = @("C:\NonExistent\Path")

        # Act
        $result = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert
        $result | Should BeNullOrEmpty
    }

    It "should normalize paths and match case-insensitively" {
        # Arrange
        $repoPaths = @("c:\code\chinvex")  # lowercase

        # Act
        $result = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert
        $result | Should Not BeNullOrEmpty
    }

    It "should return empty array when no scheduled tasks exist for non-existent paths" {
        # Arrange
        $repoPaths = @("Z:\CompletelyNonExistent\Path\That\NoTaskWouldEverReference")

        # Act
        $result = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert
        $result | Should BeNullOrEmpty
    }
}
