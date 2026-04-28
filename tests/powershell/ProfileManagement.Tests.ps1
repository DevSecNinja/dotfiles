#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for ProfileManagement functions in the DotfilesHelpers module.

.DESCRIPTION
    Tests Edit-Profile, Import-Profile, and Show-Aliases. The tests inspect
    function bodies and (where safe) execute the function with output captured.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking
}

AfterAll {
    Pop-Location
}

Describe "Edit-Profile Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Edit-Profile -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Function body should reference the \$PROFILE variable" {
        $body = (Get-Command Edit-Profile).ScriptBlock.ToString()
        $body | Should -Match '\$PROFILE'
    }

    It "Function body should invoke 'code' editor" {
        $body = (Get-Command Edit-Profile).ScriptBlock.ToString()
        $body | Should -Match '\bcode\b'
    }
}

Describe "Import-Profile Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Import-Profile -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Function body should dot-source \$PROFILE" {
        $body = (Get-Command Import-Profile).ScriptBlock.ToString()
        # Should include '. $PROFILE' (dot-sourcing)
        $body | Should -Match '\.\s*\$PROFILE'
    }

    It "Function body should report success to user" {
        $body = (Get-Command Import-Profile).ScriptBlock.ToString()
        $body | Should -Match 'Profile reloaded'
    }
}

Describe "Show-Aliases Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Show-Aliases -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should not throw when invoked" {
        { Show-Aliases 6>&1 | Out-Null } | Should -Not -Throw
    }

    It "Should output information about Navigation, Git, and File Operations" {
        # Capture host output via Information stream redirection (6>&1)
        $output = Show-Aliases 6>&1 | Out-String
        $output | Should -Match 'Navigation'
        $output | Should -Match 'Git'
        $output | Should -Match 'File Operations'
    }

    It "Should mention common aliases like 'gs', 'll', 'mkcd'" {
        $output = Show-Aliases 6>&1 | Out-String
        $output | Should -Match 'gs'
        $output | Should -Match 'll'
        $output | Should -Match 'mkcd'
    }
}
