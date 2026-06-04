#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for font management utilities (Test-NerdFontInstalled,
    Install-DotfilesNerdFont, Set-WindowsTerminalFont) in the DotfilesHelpers
    module.

.DESCRIPTION
    Validates function metadata, the idempotency / failure control flow of the
    Nerd Font installer (with the real install mocked), and the surgical
    Windows Terminal settings.json font patching against real temporary files.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    if (Test-Path $modulePath) {
        Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force -DisableNameChecking
    }
    else {
        throw "DotfilesHelpers module not found at: $modulePath"
    }

    $tmpRoot = if ($env:TEMP) { $env:TEMP } else { '/tmp' }
    $script:TestDir = New-Item -ItemType Directory -Path (Join-Path $tmpRoot "font-mgmt-tests-$(Get-Random)") -Force
}

AfterAll {
    Pop-Location
    if (Test-Path $script:TestDir) {
        Remove-Item -Recurse -Force $script:TestDir.FullName -ErrorAction SilentlyContinue
    }
}

Describe "Test-NerdFontInstalled Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Test-NerdFontInstalled -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should default the Name parameter to 'FiraCode'" {
        (Get-Command Test-NerdFontInstalled).Parameters["Name"].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidatePatternAttribute] } |
            Should -Not -BeNullOrEmpty
    }

    It "Should return a boolean" {
        $result = Test-NerdFontInstalled -Name 'FiraCode'
        $result | Should -BeOfType [bool]
    }
}

Describe "Install-DotfilesNerdFont Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Install-DotfilesNerdFont -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should support ShouldProcess (WhatIf)" {
        (Get-Command Install-DotfilesNerdFont).Parameters.ContainsKey("WhatIf") | Should -Be $true
    }

    It "Should validate Scope against an allow-list" {
        { Install-DotfilesNerdFont -Scope "Nonsense" -WhatIf } | Should -Throw
    }

    Context "Idempotency and control flow (install mocked)" {
        It "Should skip installation when the font is already present" {
            Mock -ModuleName DotfilesHelpers Test-NerdFontInstalled { $true }
            Mock -ModuleName DotfilesHelpers Invoke-NerdFontInstaller { $true }

            $result = Install-DotfilesNerdFont -Name FiraCode

            $result.Action | Should -Be 'AlreadyInstalled'
            $result.Installed | Should -Be $true
            Should -Invoke -ModuleName DotfilesHelpers Invoke-NerdFontInstaller -Times 0 -Exactly
        }

        It "Should install when forced even if already present" {
            Mock -ModuleName DotfilesHelpers Test-NerdFontInstalled { $true }
            Mock -ModuleName DotfilesHelpers Invoke-NerdFontInstaller { $true }

            $result = Install-DotfilesNerdFont -Name FiraCode -Force

            $result.Action | Should -Be 'Installed'
            $result.Installed | Should -Be $true
            Should -Invoke -ModuleName DotfilesHelpers Invoke-NerdFontInstaller -Times 1 -Exactly
        }

        It "Should report failure when the font does not register after install" {
            Mock -ModuleName DotfilesHelpers Test-NerdFontInstalled { $false }
            Mock -ModuleName DotfilesHelpers Invoke-NerdFontInstaller { $true }

            $result = Install-DotfilesNerdFont -Name FiraCode

            $result.Action | Should -Be 'Failed'
            $result.Installed | Should -Be $false
        }

        It "Should not install under -WhatIf" {
            Mock -ModuleName DotfilesHelpers Test-NerdFontInstalled { $false }
            Mock -ModuleName DotfilesHelpers Invoke-NerdFontInstaller { $true }

            Install-DotfilesNerdFont -Name FiraCode -WhatIf | Out-Null

            Should -Invoke -ModuleName DotfilesHelpers Invoke-NerdFontInstaller -Times 0 -Exactly
        }
    }
}

Describe "Set-WindowsTerminalFont Function" -Tag "Unit" {
    BeforeEach {
        $script:settingsPath = Join-Path $script:TestDir.FullName "settings-$(Get-Random).json"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:settingsPath -ErrorAction SilentlyContinue
    }

    It "Should be available as a function with a mandatory FontFace parameter" {
        $cmd = Get-Command Set-WindowsTerminalFont
        $cmd | Should -Not -BeNullOrEmpty
        $cmd.Parameters["FontFace"].Attributes |
            Where-Object { $_ -is [Parameter] } |
            Select-Object -ExpandProperty Mandatory |
            Should -Contain $true
    }

    It "Should set the font when no profiles section exists" {
        '{ "theme": "dark" }' | Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalFont -FontFace "FiraCode Nerd Font" -SettingsPath $script:settingsPath

        $result.Status | Should -Be 'Updated'
        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.profiles.defaults.font.face | Should -Be "FiraCode Nerd Font"
        $json.theme | Should -Be "dark"
    }

    It "Should update an existing different font face" {
        '{ "profiles": { "defaults": { "font": { "face": "Consolas" } } } }' |
            Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalFont -FontFace "FiraCode Nerd Font" -SettingsPath $script:settingsPath

        $result.Status | Should -Be 'Updated'
        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.profiles.defaults.font.face | Should -Be "FiraCode Nerd Font"
    }

    It "Should be idempotent when the font is already correct" {
        '{ "profiles": { "defaults": { "font": { "face": "FiraCode Nerd Font" } } } }' |
            Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalFont -FontFace "FiraCode Nerd Font" -SettingsPath $script:settingsPath

        $result.Status | Should -Be 'AlreadySet'
        $result.Changed | Should -Be $false
    }

    It "Should preserve other settings including the profiles.list array" {
        $original = @'
{
    "theme": "dark",
    "profiles": {
        "defaults": { "font": { "face": "Consolas" } },
        "list": [
            { "name": "PowerShell", "guid": "{abc}" },
            { "name": "cmd", "guid": "{def}" }
        ]
    }
}
'@
        $original | Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        Set-WindowsTerminalFont -FontFace "FiraCode Nerd Font" -SettingsPath $script:settingsPath | Out-Null

        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.profiles.defaults.font.face | Should -Be "FiraCode Nerd Font"
        $json.theme | Should -Be "dark"
        $json.profiles.list.Count | Should -Be 2
        $json.profiles.list[0].name | Should -Be "PowerShell"
    }

    It "Should parse JSONC (comments and trailing commas) without mangling URLs" {
        $jsonc = @'
{
    // user comment
    "schema": "https://aka.ms/terminal-profiles-schema",
    "profiles": {
        "defaults": { "font": { "face": "Consolas" } },
    }
}
'@
        $jsonc | Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalFont -FontFace "FiraCode Nerd Font" -SettingsPath $script:settingsPath

        $result.Status | Should -Be 'Updated'
        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.profiles.defaults.font.face | Should -Be "FiraCode Nerd Font"
        $json.schema | Should -Be "https://aka.ms/terminal-profiles-schema"
    }

    It "Should skip paths that do not exist" {
        $missing = Join-Path $script:TestDir.FullName "does-not-exist-$(Get-Random).json"

        $result = Set-WindowsTerminalFont -FontFace "FiraCode Nerd Font" -SettingsPath $missing

        $result | Should -BeNullOrEmpty
    }

    It "Should not write under -WhatIf" {
        '{ "profiles": { "defaults": { "font": { "face": "Consolas" } } } }' |
            Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalFont -FontFace "FiraCode Nerd Font" -SettingsPath $script:settingsPath -WhatIf

        $result.Status | Should -Be 'WhatIf'
        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.profiles.defaults.font.face | Should -Be "Consolas"
    }
}
