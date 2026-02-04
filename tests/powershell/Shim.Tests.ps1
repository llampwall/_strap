BeforeAll {
    . "$PSScriptRoot/../../modules/Core.ps1"
    . "$PSScriptRoot/../../modules/Commands/Shim.ps1"
}

Describe "Parse-ShimCommandLine" {
    Context "JSON array parsing" {
        It "parses simple JSON array" {
            $result = Parse-ShimCommandLine '["python", "-m", "mytool"]'
            $result.exe | Should -Be "python"
            $result.baseArgs | Should -HaveCount 2
            $result.baseArgs[0] | Should -Be "-m"
            $result.baseArgs[1] | Should -Be "mytool"
        }

        It "handles paths with spaces in JSON" {
            $result = Parse-ShimCommandLine '["C:\\Program Files\\tool.exe", "--flag"]'
            $result.exe | Should -Be "C:\Program Files\tool.exe"
            $result.baseArgs | Should -HaveCount 1
        }

        It "errors on empty JSON array" {
            { Parse-ShimCommandLine '[]' } | Should -Throw "*Empty*"
        }
    }

    Context "Tokenizer parsing" {
        It "parses simple command" {
            $result = Parse-ShimCommandLine "python -m mytool"
            $result.exe | Should -Be "python"
            $result.baseArgs | Should -HaveCount 2
        }

        It "handles quoted arguments" {
            $result = Parse-ShimCommandLine 'python -m "my tool"'
            $result.baseArgs[1] | Should -Be "my tool"
        }

        It "handles paths with spaces" {
            $result = Parse-ShimCommandLine '"C:\Program Files\tool.exe" --flag'
            $result.exe | Should -Be "C:\Program Files\tool.exe"
        }

        It "blocks pipe operators" {
            { Parse-ShimCommandLine "python | grep" } | Should -Throw "*direct exec*"
        }

        It "blocks redirects" {
            { Parse-ShimCommandLine "python > out.txt" } | Should -Throw "*direct exec*"
        }

        It "blocks semicolons" {
            { Parse-ShimCommandLine "python; echo" } | Should -Throw "*direct exec*"
        }

        It "blocks && operators" {
            { Parse-ShimCommandLine "python && echo" } | Should -Throw "*direct exec*"
        }
    }
}
