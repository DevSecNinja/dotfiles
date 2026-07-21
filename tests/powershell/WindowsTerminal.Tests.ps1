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

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDYixwP5PljjoZc
# gZKOyexecqD+k8E3sP1l0bKhxjmnTqCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
# p05/1ElTgWD0MA0GCSqGSIb3DQEBCwUAMCMxITAfBgNVBAMMGEplYW4tUGF1bCB2
# YW4gUmF2ZW5zYmVyZzAeFw0yNjAxMTQxMjU3MjBaFw0zMTAxMTQxMzA2NDdaMCMx
# ITAfBgNVBAMMGEplYW4tUGF1bCB2YW4gUmF2ZW5zYmVyZzCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAMm6cmnzWkwTZJW3lpa98k2eQDQJB6Twyr5U/6cU
# bXWG2xNCGTZCxH3a/77uGX5SDh4g/6x9+fSuhkGkjVcCmP2qpfeHOqafOByrzg6p
# /oI4Zdn4eAHRdhFV+IDmP68zaLtG9oai2k4Ilsc9qINOKPesVZdJd7sxtrutZS8e
# UqBmQr3rYD96pBZXt2YpJXmqSZdS9KdrboVms6Y11naZCSoBbi+XhbyfDZzgN65i
# NZCTahRj6RkJECzU7FXsV4qhuJca4fGHue2Lc027w0A/ZxZkbXkVnTtZbP3x0Q6v
# wkH0r3lfeRcFtKisHKFfDdsIlS+H9cQ8u2NMNWK3375By4yUnQm1NJjVFDZNAZI/
# A/Os3DpRXGyW8gxlSb+CGqHUQU0+YtrSuaXaLc5x0K+QcBmNBzCB/gQArY95g5dn
# rO3m2+XWhHmP6zP/fBMZW1BPLXTFbK/tXY/rFuWZ77MRka12Enu8EbhzK+Mfn00m
# ts6TL7AtV6qksjCc+aJPhgPVABMCDkD4QXHvENbE8s99LrjgsJwSyalOxgWovQl+
# 4r4DbReaHfapy4+j/Rxba65YQBSN35dwWqhb8YxyzCEcJ7q1TTvoVEntV0SeC8Lh
# 4rhqdHhyigZUSptw6LMry3bEdDrCAJ8FeW1LdTb+00bayq/J4RTZd4OLiIf07mot
# KTmJAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcD
# AzAdBgNVHQ4EFgQUDt+a1J2KwjQ4CPd2E5gJ3OpVld4wDQYJKoZIhvcNAQELBQAD
# ggIBAFu1W92GGmGvSOOFXMIs/Lu+918MH1rX1UNYdgI1H8/2gDAwfV6eIy+Gu1MK
# rDolIGvdV8eIuu2qGbELnfoeS0czgY0O6uFf6JF1IR/0Rh9Pw1qDmWD+WdI+m4+y
# gPBGz4F/crK+1L8wgfV+tuxCfSJmtu0Ce71DFI+0wvwXWSjhTFxboldsmvOsz+Bp
# X0j4xU6qAsiZK7Tp0VrrLeJEuqE4hC2sTWCJJyP7qmxUjkCqoaiqhci6qSvpg1mJ
# qM4SYkE0FE59z+++4m4DiiNiCzSr/O3uKsfEl2MwZWoZgqLKbMC33I+e/o//EH9/
# HYPWKlEFzXbVj2c3vCRZf2hZZuvfLDoT7i8eZGg3vsTsFnC+ZXKwQTaXqS++q9f3
# rDNYAD+9+GwVyHqVVqwgSME91OgbJ6qfx7H/5VqHHhoJiifSgPiIOSyhvGu9JbcY
# mHkZS3h2P3BU8n/nuqF4eMcQ6LeZDsWCzvHOaHKisRKzSX0yWxjGygp7trqpIi3C
# A3DpBGHXa9r1fwleRfWUeyX/y7pJxT0RRlxNDip4VhK0RRxmE6PL0cq8i92Qs7HA
# csVkGkrIkSYUYhJxemehXwBnwJ1PfDqjvZVpjQdUeP1TTDSNrR3EqiVP5n+nWRYV
# NkoMe75v2tBqXHfq05ryGO9ivXORcmh/MFMgWSR9WYTjZRy3MIIFjTCCBHWgAwIB
# AgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJV
# UzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQu
# Y29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIw
# ODAxMDAwMDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYD
# VQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Y
# q3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lX
# FllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxe
# TsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbu
# yntd463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I
# 9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmg
# Z92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse
# 5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKy
# Ebe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwh
# HbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/
# Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwID
# AQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM
# 3y5nP+e6mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYD
# VR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDov
# L29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+
# MDwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3Vy
# ZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUA
# A4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSI
# d229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7U
# z9FDRJtDIeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxA
# GTVGamlUsLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAID
# yyCwrFigDkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW
# /VvRXKwYw02fc7cBqZ9Xql4o4rmUMIIGtDCCBJygAwIBAgIQDcesVwX/IZkuQEMi
# DDpJhjANBgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcNMzgwMTE0
# MjM1OTU5WjBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAtHgx0wqYQXK+PEbAHKx126NGaHS0URedTa2NDZS1mZaDLFTtQ2oRjzUXMmxC
# qvkbsDpz4aH+qbxeLho8I6jY3xL1IusLopuW2qftJYJaDNs1+JH7Z+QdSKWM06qc
# hUP+AbdJgMQB3h2DZ0Mal5kYp77jYMVQXSZH++0trj6Ao+xh/AS7sQRuQL37QXbD
# hAktVJMQbzIBHYJBYgzWIjk8eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0Xm+nt5pn
# YJU3Gmq6bNMI1I7Gb5IBZK4ivbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQVESYOszFI
# 2Wv82wnJRfN20VRS3hpLgIR4hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2qHxJ0ucS
# 638ZxqU14lDnki7CcoKCz6eum5A19WZQHkqUJfdkDjHkccpL6uoG8pbF0LJAQQZx
# st7VvwDDjAmSFTUms+wV/FbWBqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgxCZSKi17y
# Vp2NL+cnT6Toy+rN+nM8M7LnLqCrO2JP3oW//1sfuZDKiDEb1AQ8es9Xr/u6bDTn
# YCTKIsDq1BtmXUqEG1NqzJKS4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7OgWmnhFr4
# yUozZtqgPrHRVHhGNKlYzyjlroPxul+bgIspzOwbtmsgY1MCAwEAAaOCAV0wggFZ
# MBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFO9vU0rp5AZ8esrikFb2L9RJ
# 7MtOMB8GA1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQE
# AwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0
# cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5j
# cnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJ
# YIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEwvb4LyLU0
# pn/N0IfFiBowf0/Dm1wGc/Do7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8G0iP5kvN
# 2n7Jd2E4/iEIUBO41P5F448rSYJ59Ib61eoalhnd6ywFLerycvZTAz40y8S4F3/a
# +Z1jEMK/DMm/axFSgoR8n6c3nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCDA/JYsq7p
# GdogP8HRtrYfctSLANEBfHU16r3J05qX3kId+ZOczgj5kjatVB+NdADVZKON/gnZ
# ruMvNYY2o1f4MXRJDMdTSlOLh0HCn2cQLwQCqjFbqrXuvTPSegOOzr4EWj7PtspI
# HBldNE2K9i697cvaiIo2p61Ed2p8xMJb82Yosn0z4y25xUbI7GIN/TpVfHIqQ6Ku
# /qjTY6hc3hsXMrS+U0yy+GWqAXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0c1ugMZyZ
# Zd/BdHLiRu7hAWE6bTEm4XYRkA6Tl4KSFLFk43esaUeqGkH/wyW4N7OigizwJWeu
# kcyIPbAvjSabnf7+Pu0VrFgoiovRDiyx3zEdmcif/sYQsfch28bZeUz2rtY/9TCA
# 6TD8dC3JE3rYkrhLULy7Dc90G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz0scmbKvF
# oW2jNrbM1pD2T7m3XDCCBu0wggTVoAMCAQICEAqA7xhLjfEFgtHEdqeVdGgwDQYJ
# KoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBS
# U0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNTA2MDQwMDAwMDBaFw0zNjA5MDMy
# MzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7
# MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3Bv
# bmRlciAyMDI1IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDQRqwt
# Esae0OquYFazK1e6b1H/hnAKAd/KN8wZQjBjMqiZ3xTWcfsLwOvRxUwXcGx8AUjn
# i6bz52fGTfr6PHRNv6T7zsf1Y/E3IU8kgNkeECqVQ+3bzWYesFtkepErvUSbf+EI
# YLkrLKd6qJnuzK8Vcn0DvbDMemQFoxQ2Dsw4vEjoT1FpS54dNApZfKY61HAldytx
# NM89PZXUP/5wWWURK+IfxiOg8W9lKMqzdIo7VA1R0V3Zp3DjjANwqAf4lEkTlCDQ
# 0/fKJLKLkzGBTpx6EYevvOi7XOc4zyh1uSqgr6UnbksIcFJqLbkIXIPbcNmA98Os
# kkkrvt6lPAw/p4oDSRZreiwB7x9ykrjS6GS3NR39iTTFS+ENTqW8m6THuOmHHjQN
# C3zbJ6nJ6SXiLSvw4Smz8U07hqF+8CTXaETkVWz0dVVZw7knh1WZXOLHgDvundrA
# tuvz0D3T+dYaNcwafsVCGZKUhQPL1naFKBy1p6llN3QgshRta6Eq4B40h5avMcpi
# 54wm0i2ePZD5pPIssoszQyF4//3DoK2O65Uck5Wggn8O2klETsJ7u8xEehGifgJY
# i+6I03UuT1j7FnrqVrOzaQoVJOeeStPeldYRNMmSF3voIgMFtNGh86w3ISHNm0Ia
# adCKCkUe2LnwJKa8TIlwCUNVwppwn4D3/Pt5pwIDAQABo4IBlTCCAZEwDAYDVR0T
# AQH/BAIwADAdBgNVHQ4EFgQU5Dv88jHt/f3X85FxYxlQQ89hjOgwHwYDVR0jBBgw
# FoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB
# /wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdS
# U0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
# L2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAZSqt8RwnBLmuYEHs0QhEnmNA
# ciH45PYiT9s1i6UKtW+FERp8FgXRGQ/YAavXzWjZhY+hIfP2JkQ38U+wtJPBVBaj
# YfrbIYG+Dui4I4PCvHpQuPqFgqp1PzC/ZRX4pvP/ciZmUnthfAEP1HShTrY+2DE5
# qjzvZs7JIIgt0GCFD9ktx0LxxtRQ7vllKluHWiKk6FxRPyUPxAAYH2Vy1lNM4kze
# kd8oEARzFAWgeW3az2xejEWLNN4eKGxDJ8WDl/FQUSntbjZ80FU3i54tpx5F/0Kr
# 15zW/mJAxZMVBrTE2oi0fcI8VMbtoRAmaaslNXdCG1+lqvP4FbrQ6IwSBXkZagHL
# hFU9HCrG/syTRLLhAezu/3Lr00GrJzPQFnCEH1Y58678IgmfORBPC1JKkYaEt2Od
# Dh4GmO0/5cHelAK2/gTlQJINqDr6JfwyYHXSd+V08X1JUPvB4ILfJdmL+66Gp3CS
# BXG6IwXMZUXBhtCyIaehr0XkBoDIGMUG1dUtwq1qmcwbdUfcSYCn+OwncVUXf53V
# JUNOaMWMts0VlRYxe5nK+At+DI96HAlXHAL5SlfYxJ7La54i71McVWRP66bW+yER
# NpbJCjyCYG2j+bdpxo/1Cy4uPcU3AWVPGrbn5PhDBf3Froguzzhk++ami+r3Qrx5
# bIbY3TVzgiFI7Gq3zWcxggYTMIIGDwIBATA3MCMxITAfBgNVBAMMGEplYW4tUGF1
# bCB2YW4gUmF2ZW5zYmVyZwIQELbg9grCcadOf9RJU4Fg9DANBglghkgBZQMEAgEF
# AKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgor
# BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3
# DQEJBDEiBCBkwWuMH1eXRuXWqMlHsUXpNEMVTqmU00OGL0dHkvwz7DANBgkqhkiG
# 9w0BAQEFAASCAgA0jU6S9b3H8X8ho65CYcPBl1PuMucpC7iP50Dq8h28qv35T0sp
# wYGR7coMLysx1R0aebBszYL9HCcNbcYw2QcYjh6xdSgw0wA5l2ZRGu4DvJf28hka
# qtj8OdS+TbSN/wLKXtYul7ihOBYVCiv/AJ6O6RvrNbLq6Cmm1Fmf6rkIWGTwkPxF
# XnwM/yqoKY5C5kZh3GjkjkqiniScXviYXY8R++DjvKVQu+GHX9Yp1Six2E1B/3Q8
# o4XHMNwwX4U0pKDHNOjeGMcNkgJlK9GLI45zjO/qgNSdaSNUndH4QalMfwzv1BMf
# RqNSlIQQ/w5KBDlM8FXKSep4+im16UBuFxvoncN4CIFLZvj71v7QK0tuAn3pFH+x
# 9COAws0/lrcTqeTXhXazhsvQbonk8hN4miCFUR/pOJSMU/2U9+Gn1F8VmYE8iqWv
# 3ewOFxaOVx1tLMoCek+55WKkTzbB4zQkCcxORuIwvGvU5bEhujibHbsa2kIUob8v
# anMiZRiiZcfTNlJkTTiJipi6UhdjX/t8kGJx4WxpHNEKvnDeYWzKRILzECwAPU8w
# knh/D8ncKPIpJO286AYMe0LOtrL/TzZZocBnCWNFqmteDF+LX/B5MeOa+nCXEAkB
# pt0rz3lXjiV6Pwit6+ASmA98PqURArPxyd1ahlGadRH9yaWZuG9WEHaVI6GCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MjExNzU1MzNaMC8GCSqGSIb3DQEJBDEi
# BCCWDsaRZrbhS5WktBNpVGaYgg8HqjPqXpiT24bov0mUDDANBgkqhkiG9w0BAQEF
# AASCAgAQgXR7lKQZqlFL21Z1hkrDJq6lr+WOaWBUlmEvCTHSZ1uxgJFRo3A5eg9E
# W0jxaSqfpgbFG7X+Bg3eAbwoW5R6xyimzHSQrPWWxzNHRNE1TkJjvact0tEWbtU0
# f3aIPHF0zRcHl/loM0kEnNd7Z379JBROzEJ1jItR+jV0hr8EY1ldeLXo8qdQC01i
# YKoxec8PZw+0MEPEThCfowf1DRwmiLrmYdv0bQa/r1/vkshzKyuMV8LkXv3pMKv4
# pq5/2BjbAiNDt3mVyX9DsdqWgKZd8917yeD0L8cbRX1bncl2ybUMbu4+4eoGc8mJ
# yJjrCqkJBg9gi6xuBF2OImkH304JZ/zoOUVhs/q8LtvZ3iIfYubUx2hRq0Y503qi
# GFslQKln+r4kEwxHieIVu7KuyipxQNbpHxvGu5osjM2iNvSXou5J6K8FYNXKZOSH
# p868vOIr6CgnLQ3CncqEY3MxzF5HinckOnjtTOaWx5E45JT1RmP6A577k3Z7ZlHB
# XhqCnpkzHvuMyqVWMG4xBlIkY74qnyptoJC5bVyiTG/odB5ZvxqC9bvdh0fAb7NJ
# Ph9pTFy8rx8a8sQYBPP/0NHDEExH7oEds0xebBGwUH+GA7H3s89utF/udGWVnmJR
# Gq8QSFNQPTv/RKruplySKbct+n36e2i/FCGGwrMD/K1ssisxfw==
# SIG # End signature block
