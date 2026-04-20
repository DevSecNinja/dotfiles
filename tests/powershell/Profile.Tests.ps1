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
    $script:AliasesPath = Join-Path $script:RepoRoot "home\dot_config\powershell\aliases.ps1"
    $script:ModulePath = Join-Path $script:RepoRoot "home\dot_config\powershell\modules\DotfilesHelpers"
    $script:ModulePublicPath = Join-Path $script:ModulePath "Public"
}

AfterAll {
    Pop-Location
}

Describe "PowerShell Profile Files" {
    It "profile.ps1 file should exist" {
        $script:ProfilePath | Should -Exist
    }

    It "DotfilesHelpers module directory should exist" {
        $script:ModulePath | Should -Exist
    }

    It "DotfilesHelpers module manifest should exist" {
        Join-Path $script:ModulePath "DotfilesHelpers.psd1" | Should -Exist
    }

    It "DotfilesHelpers module loader should exist" {
        Join-Path $script:ModulePath "DotfilesHelpers.psm1" | Should -Exist
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


    It "Profile should import DotfilesHelpers module" {
        $script:ProfileContent | Should -Match "DotfilesHelpers"
        $script:ProfileContent | Should -Match "Import-Module"
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

    It "Profile should check VS Code environment before changing directory" {
        # Verify the profile skips directory change in VS Code
        $script:ProfileContent | Should -Match 'TERM_PROGRAM.*vscode'
    }

    It "Profile should check current path for 'projects' directory" {
        # Verify the profile checks if path contains 'projects'
        $script:ProfileContent | Should -Match 'currentPath -notlike.*projects'
    }

    It "Profile should set location to projects folder" {
        # Verify the profile constructs projects path and changes to it
        $script:ProfileContent | Should -Match 'Join-Path.*USERPROFILE.*projects'
        $script:ProfileContent | Should -Match 'Set-Location.*projectsPath'
    }

    It "Profile should verify projects folder exists before changing" {
        # Verify the profile tests for directory existence
        $script:ProfileContent | Should -Match 'Test-Path.*projectsPath'
    }
}

Describe "DotfilesHelpers Module" {
    BeforeAll {
        # Read all module public function files
        $script:ModuleContent = Get-ChildItem -Path $script:ModulePublicPath -Filter "*.ps1" |
            ForEach-Object { Get-Content $_.FullName -Raw } | Out-String
    }

    It "Module manifest should be importable" {
        { Test-ModuleManifest -Path (Join-Path $script:ModulePath "DotfilesHelpers.psd1") } | Should -Not -Throw
    }

    It "Module should export expected functions" {
        $manifest = Test-ModuleManifest -Path (Join-Path $script:ModulePath "DotfilesHelpers.psd1")
        $manifest.ExportedFunctions.Keys | Should -Contain 'Set-LocationUp'
        $manifest.ExportedFunctions.Keys | Should -Contain 'Reset-ChezmoiScripts'
        $manifest.ExportedFunctions.Keys | Should -Contain 'Test-WingetUpdates'
        $manifest.ExportedFunctions.Keys | Should -Contain 'Invoke-WingetUpgrade'
        $manifest.ExportedFunctions.Keys | Should -Contain 'Show-Aliases'
    }

    It "Should define Chezmoi utility functions" {
        $script:ModuleContent | Should -Match "function Reset-ChezmoiScripts"
        $script:ModuleContent | Should -Match "function Reset-ChezmoiEntries"
        $script:ModuleContent | Should -Match "function Invoke-ChezmoiSigning"
    }

    It "Should define navigation helpers" {
        $script:ModuleContent | Should -Match "function Set-LocationUp"
        $script:ModuleContent | Should -Match "function Set-LocationUpUp"
    }

    It "Should define system utilities" {
        $script:ModuleContent | Should -Match "function which"
        $script:ModuleContent | Should -Match "function touch"
        $script:ModuleContent | Should -Match "function mkcd"
    }

    It "Reset-ChezmoiScripts should delete scriptState bucket" {
        $script:ModuleContent | Should -Match "delete-bucket --bucket=scriptState"
    }

    It "Reset-ChezmoiEntries should delete entryState bucket" {
        $script:ModuleContent | Should -Match "delete-bucket --bucket=entryState"
    }

    It "Public directory should contain expected function files" {
        $publicFiles = Get-ChildItem -Path $script:ModulePublicPath -Filter "*.ps1" | Select-Object -ExpandProperty Name
        $publicFiles | Should -Contain 'Navigation.ps1'
        $publicFiles | Should -Contain 'SystemUtilities.ps1'
        $publicFiles | Should -Contain 'ChezmoiUtilities.ps1'
        $publicFiles | Should -Contain 'WingetUtilities.ps1'
        $publicFiles | Should -Contain 'ProfileManagement.ps1'
        $publicFiles | Should -Contain 'ModuleInstallation.ps1'
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
        $script:AliasesContent | Should -Match "function ll"
    }

    It "Should define aliases function to list all aliases" {
        $script:AliasesContent | Should -Match "Set-Alias.*aliases.*Show-Aliases"
    }

    It "Show-Aliases function should exist in DotfilesHelpers module" {
        $moduleContent = Get-ChildItem -Path $script:ModulePublicPath -Filter "*.ps1" |
            ForEach-Object { Get-Content $_.FullName -Raw } | Out-String
        $moduleContent | Should -Match "function Show-Aliases"
    }
}

Describe "Profile horizonfetch timeout guard" {
    BeforeAll {
        $script:ProfileContent = Get-Content $script:ProfilePath -Raw
    }

    It "Profile should invoke horizonfetch with a timeout guard" {
        # Ensure the raw bare invocation has been replaced by a guarded one.
        # A bare `horizonfetch` call that is not preceded by a CommandType check
        # would allow a hang to block the profile.
        $script:ProfileContent | Should -Match 'Start-Process'
        $script:ProfileContent | Should -Match 'WaitForExit'
    }

    It "Profile should kill horizonfetch when the timeout elapses" {
        $script:ProfileContent | Should -Match '\$horizonfetchProc\.Kill\(\)'
    }

    It "Profile should support overriding the horizonfetch timeout via env var" {
        $script:ProfileContent | Should -Match 'HORIZONFETCH_TIMEOUT_MS'
    }

    It "Profile should only start horizonfetch for Application or ExternalScript commands" {
        $script:ProfileContent | Should -Match 'CommandTypes\]::Application'
        $script:ProfileContent | Should -Match 'CommandTypes\]::ExternalScript'
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

    It "All DotfilesHelpers module files should have valid PowerShell syntax" {
        $moduleFiles = Get-ChildItem -Path $script:ModulePath -Filter "*.ps1" -Recurse
        $moduleFiles += Get-ChildItem -Path $script:ModulePath -Filter "*.psm1"
        foreach ($file in $moduleFiles) {
            {
                $null = [System.Management.Automation.PSParser]::Tokenize(
                    (Get-Content $file.FullName -Raw),
                    [ref]$null
                )
            } | Should -Not -Throw -Because "$($file.Name) should have valid syntax"
        }
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
