# tests/powershell/Get-ScheduledTaskReferences.Tests.ps1
Describe "Get-ScheduledTaskReferences" {
    BeforeAll {
        # Dot-source all strap modules
        $modulesPath = "$PSScriptRoot\..\..\modules"
        . "$modulesPath\Core.ps1"
        . "$modulesPath\Utils.ps1"
        . "$modulesPath\Path.ps1"
        . "$modulesPath\Config.ps1"
        . "$modulesPath\Chinvex.ps1"
        . "$modulesPath\CLI.ps1"
        . "$modulesPath\References.ps1"
        . "$modulesPath\Audit.ps1"
        . "$modulesPath\Consolidate.ps1"
        $commandsPath = Join-Path $modulesPath "Commands"
        Get-ChildItem -Path $commandsPath -Filter "*.ps1" | ForEach-Object {
            . $_.FullName
        }

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
        $result | Should -Not -BeNullOrEmpty
        $result.Count | Should -BeGreaterThan 0
        $matchingTask = $result | Where-Object { $_.name -like "*MorningBrief*" }
        $matchingTask | Should -Not -BeNullOrEmpty
        $matchingTask.path | Should -Match "C:\\Code\\chinvex"
    }

    It "should return empty array when no tasks reference repo paths" {
        # Arrange
        $repoPaths = @("C:\NonExistent\Path")

        # Act
        $result = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert
        $result | Should -BeNullOrEmpty
    }

    It "should normalize paths and match case-insensitively" {
        # Arrange
        $repoPaths = @("c:\code\chinvex")  # lowercase

        # Act
        $result = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert
        $result | Should -Not -BeNullOrEmpty
    }

    It "should return empty array when no scheduled tasks exist for non-existent paths" {
        # Arrange
        $repoPaths = @("Z:\CompletelyNonExistent\Path\That\NoTaskWouldEverReference")

        # Act
        $result = Get-ScheduledTaskReferences -RepoPaths $repoPaths

        # Assert
        $result | Should -BeNullOrEmpty
    }
}
