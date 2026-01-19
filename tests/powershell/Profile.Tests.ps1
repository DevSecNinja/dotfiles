#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for PowerShell profile configuration.

.DESCRIPTION
    Tests for PowerShell profile settings including winget tab completion,
    functions, aliases, and profile loading.

.NOTES
    Tests profile configuration without actually loading the profile to avoid side effects.
#>

BeforeAll {
    # Setup: Navigate to repository root
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    # Define paths
    $script:ProfilePath = Join-Path $script:RepoRoot "home\dot_config\powershell\profile.ps1"
    $script:FunctionsPath = Join-Path $script:RepoRoot "home\dot_config\powershell\functions.ps1"
    $script:AliasesPath = Join-Path $script:RepoRoot "home\dot_config\powershell\aliases.ps1"
}

AfterAll {
    Pop-Location
}

Describe "PowerShell Profile Files" {
    It "profile.ps1 file should exist" {
        $script:ProfilePath | Should -Exist
    }

    It "functions.ps1 file should exist" {
        $script:FunctionsPath | Should -Exist
    }

    It "aliases.ps1 file should exist" {
        $script:AliasesPath | Should -Exist
    }

    It "profile.ps1 should not be empty" {
        $content = Get-Content $script:ProfilePath -Raw
        $content | Should -Not -BeNullOrEmpty
        $content.Length | Should -BeGreaterThan 100
    }
}

Describe "PowerShell Completions" {
    BeforeAll {
        $script:CompletionsPath = Join-Path $script:RepoRoot "home\dot_config\powershell\completions"
        $script:WingetCompletionPath = Join-Path $script:CompletionsPath "winget.ps1"
        $script:ProfileContent = Get-Content $script:ProfilePath -Raw
    }

    Context "Completions Directory" {
        It "Completions directory should exist" {
            $script:CompletionsPath | Should -Exist
        }

        It "Profile should load completions from completions folder" {
            $script:ProfileContent | Should -Match "completions"
        }

        It "Profile should iterate through completion files" {
            $script:ProfileContent | Should -Match "Get-ChildItem.*\.ps1"
        }
    }

    Context "WinGet Completion" {
        It "Winget completion file should exist" {
            $script:WingetCompletionPath | Should -Exist
        }

        It "Winget completion should check for winget command" {
            $content = Get-Content $script:WingetCompletionPath -Raw
            $content | Should -Match "Get-Command winget"
        }

        It "Winget completion should register argument completer" {
            $content = Get-Content $script:WingetCompletionPath -Raw
            $content | Should -Match "Register-ArgumentCompleter.*-CommandName winget"
        }

        It "Winget completion should use winget complete command" {
            $content = Get-Content $script:WingetCompletionPath -Raw
            $content | Should -Match "winget complete"
        }

        It "Winget completion should handle UTF-8 encoding" {
            $content = Get-Content $script:WingetCompletionPath -Raw
            $content | Should -Match "System\.Text\.Utf8Encoding"
        }

        It "Winget completion should create completion results" {
            $content = Get-Content $script:WingetCompletionPath -Raw
            $content | Should -Match "System\.Management\.Automation\.CompletionResult"
        }
    }
}

Describe "Profile Configuration" {
    BeforeAll {
        $script:ProfileContent = Get-Content $script:ProfilePath -Raw
    }

    It "Profile should set UTF-8 encoding" {
        $script:ProfileContent | Should -Match "System\.Text\.Encoding::UTF8"
    }

    It "Profile should load functions.ps1" {
        $script:ProfileContent | Should -Match "\. \`$PSScriptRoot\\functions\.ps1"
    }

    It "Profile should load aliases.ps1" {
        $script:ProfileContent | Should -Match "\. \`$PSScriptRoot\\aliases\.ps1"
    }

    It "Profile should define custom prompt function" {
        $script:ProfileContent | Should -Match "function prompt"
    }

    It "Profile should include git branch in prompt" {
        $script:ProfileContent | Should -Match "git rev-parse --abbrev-ref HEAD"
    }

    It "Profile should display welcome message" {
        $script:ProfileContent | Should -Match "PowerShell Profile Loaded"
    }
}

Describe "PowerShell Functions" {
    BeforeAll {
        $script:FunctionsContent = Get-Content $script:FunctionsPath -Raw
    }

    It "Should define Chezmoi utility functions" {
        $script:FunctionsContent | Should -Match "function Reset-ChezmoiScripts"
        $script:FunctionsContent | Should -Match "function Reset-ChezmoiEntries"
        $script:FunctionsContent | Should -Match "function Invoke-ChezmoiSigning"
    }

    It "Should define navigation helpers" {
        $script:FunctionsContent | Should -Match "function Set-LocationUp"
        $script:FunctionsContent | Should -Match "function Set-LocationUpUp"
    }

    It "Should define system utilities" {
        $script:FunctionsContent | Should -Match "function which"
        $script:FunctionsContent | Should -Match "function touch"
        $script:FunctionsContent | Should -Match "function mkcd"
    }

    It "Reset-ChezmoiScripts should delete scriptState bucket" {
        $script:FunctionsContent | Should -Match "delete-bucket --bucket=scriptState"
    }

    It "Reset-ChezmoiEntries should delete entryState bucket" {
        $script:FunctionsContent | Should -Match "delete-bucket --bucket=entryState"
    }
}

Describe "PowerShell Aliases" {
    BeforeAll {
        $script:AliasesContent = Get-Content $script:AliasesPath -Raw
    }

    It "Should define navigation aliases" {
        $script:AliasesContent | Should -Match "Set-Alias.*\.\."
    }

    It "Should define ll alias for directory listing" {
        $script:AliasesContent | Should -Match "Set-Alias ll"
    }

    It "Should define aliases function to list all aliases" {
        $script:AliasesContent | Should -Match "function aliases"
    }

    It "Aliases function should retrieve custom aliases" {
        $script:AliasesContent | Should -Match "Get-Alias.*Where-Object"
    }
}

Describe "Profile Syntax Validation" {
    It "profile.ps1 should have valid PowerShell syntax" {
        { 
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $script:ProfilePath -Raw), 
                [ref]$null
            )
        } | Should -Not -Throw
    }

    It "functions.ps1 should have valid PowerShell syntax" {
        { 
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $script:FunctionsPath -Raw), 
                [ref]$null
            )
        } | Should -Not -Throw
    }

    It "aliases.ps1 should have valid PowerShell syntax" {
        { 
            $null = [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $script:AliasesPath -Raw), 
                [ref]$null
            )
        } | Should -Not -Throw
    }
}
