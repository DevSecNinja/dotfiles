#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for Windows Terminal settings.json utilities
    (Set-WindowsTerminalFont, Set-WindowsTerminalDefaultProfile) in the
    DotfilesHelpers module.

.DESCRIPTION
    Validates the surgical, non-destructive patching of Windows Terminal
    settings.json against real temporary files: only the targeted value is
    changed, JSONC (comments / trailing commas) parses, and missing files or
    missing profiles are skipped without error.
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
    $script:TestDir = New-Item -ItemType Directory -Path (Join-Path $tmpRoot "wt-settings-tests-$(Get-Random)") -Force
}

AfterAll {
    Pop-Location
    if (Test-Path $script:TestDir) {
        Remove-Item -Recurse -Force $script:TestDir.FullName -ErrorAction SilentlyContinue
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

Describe "Set-WindowsTerminalDefaultProfile Function" -Tag "Unit" {
    BeforeEach {
        $script:settingsPath = Join-Path $script:TestDir.FullName "settings-$(Get-Random).json"
    }

    AfterEach {
        Remove-Item -LiteralPath $script:settingsPath -ErrorAction SilentlyContinue
    }

    BeforeAll {
        # A realistic settings.json with PowerShell Core, Windows PowerShell and a
        # WSL profile. Windows PowerShell is the current default so a change is
        # required to switch to PowerShell Core.
        $script:SampleSettings = @'
{
    "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "profiles": {
        "defaults": { "font": { "face": "FiraCode Nerd Font" } },
        "list": [
            {
                "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
                "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
                "name": "Windows PowerShell"
            },
            {
                "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
                "name": "PowerShell",
                "source": "Windows.Terminal.PowershellCore"
            },
            {
                "guid": "{36f9ac1f-0a96-55ed-952d-57a0df08d14f}",
                "name": "Debian",
                "source": "Microsoft.WSL"
            }
        ]
    }
}
'@
    }

    It "Should be available with a Source parameter defaulting to PowerShell Core" {
        $cmd = Get-Command Set-WindowsTerminalDefaultProfile
        $cmd | Should -Not -BeNullOrEmpty
        $cmd.Parameters.ContainsKey('Source') | Should -Be $true
        $cmd.Parameters.ContainsKey('ProfileName') | Should -Be $true
    }

    It "Should support ShouldProcess (WhatIf)" {
        (Get-Command Set-WindowsTerminalDefaultProfile).Parameters.ContainsKey("WhatIf") | Should -Be $true
    }

    It "Should set defaultProfile to the PowerShell Core GUID by default" {
        $script:SampleSettings | Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalDefaultProfile -SettingsPath $script:settingsPath

        $result.Status | Should -Be 'Updated'
        $result.Guid | Should -Be '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
        $result.MatchedProfile | Should -Be 'PowerShell'

        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.defaultProfile | Should -Be '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    }

    It "Should preserve the rest of the config when updating defaultProfile" {
        $script:SampleSettings | Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        Set-WindowsTerminalDefaultProfile -SettingsPath $script:settingsPath | Out-Null

        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.profiles.defaults.font.face | Should -Be 'FiraCode Nerd Font'
        $json.profiles.list.Count | Should -Be 3
        $json.profiles.list[2].name | Should -Be 'Debian'
    }

    It "Should be idempotent when the default profile is already correct" {
        $already = $script:SampleSettings -replace '\{61c54bbd-c2c6-5271-96e7-009a87ff44bf\}', '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
        $already | Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalDefaultProfile -SettingsPath $script:settingsPath

        $result.Status | Should -Be 'AlreadySet'
        $result.Changed | Should -Be $false
    }

    It "Should skip (ProfileNotFound) when PowerShell Core is not installed" {
        $noCore = @'
{
    "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "profiles": {
        "list": [
            {
                "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
                "name": "Windows PowerShell"
            }
        ]
    }
}
'@
        $noCore | Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalDefaultProfile -SettingsPath $script:settingsPath

        $result.Status | Should -Be 'ProfileNotFound'
        $result.Changed | Should -Be $false

        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.defaultProfile | Should -Be '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
    }

    It "Should match a profile by name via -ProfileName" {
        $script:SampleSettings | Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalDefaultProfile -ProfileName 'Debian' -SettingsPath $script:settingsPath

        $result.Status | Should -Be 'Updated'
        $result.Guid | Should -Be '{36f9ac1f-0a96-55ed-952d-57a0df08d14f}'

        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.defaultProfile | Should -Be '{36f9ac1f-0a96-55ed-952d-57a0df08d14f}'
    }

    It "Should add defaultProfile when it is missing" {
        $noDefault = @'
{
    "profiles": {
        "list": [
            {
                "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
                "name": "PowerShell",
                "source": "Windows.Terminal.PowershellCore"
            }
        ]
    }
}
'@
        $noDefault | Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalDefaultProfile -SettingsPath $script:settingsPath

        $result.Status | Should -Be 'Updated'
        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.defaultProfile | Should -Be '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    }

    It "Should parse JSONC (comments and trailing commas)" {
        $jsonc = @'
{
    // this machine defaults to Windows PowerShell
    "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "profiles": {
        "list": [
            { "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}", "name": "Windows PowerShell" },
            {
                "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
                "name": "PowerShell",
                "source": "Windows.Terminal.PowershellCore"
            },
        ]
    }
}
'@
        $jsonc | Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalDefaultProfile -SettingsPath $script:settingsPath

        $result.Status | Should -Be 'Updated'
        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.defaultProfile | Should -Be '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
    }

    It "Should skip paths that do not exist" {
        $missing = Join-Path $script:TestDir.FullName "does-not-exist-$(Get-Random).json"

        $result = Set-WindowsTerminalDefaultProfile -SettingsPath $missing

        $result | Should -BeNullOrEmpty
    }

    It "Should not write under -WhatIf" {
        $script:SampleSettings | Set-Content -LiteralPath $script:settingsPath -Encoding utf8

        $result = Set-WindowsTerminalDefaultProfile -SettingsPath $script:settingsPath -WhatIf

        $result.Status | Should -Be 'WhatIf'
        $json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
        $json.defaultProfile | Should -Be '{61c54bbd-c2c6-5271-96e7-009a87ff44bf}'
    }
}
