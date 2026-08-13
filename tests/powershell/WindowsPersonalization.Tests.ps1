#Requires -Version 7.0
<#
.SYNOPSIS
    Tests current-user Windows personalization.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:ScriptPath = Join-Path $script:RepoRoot `
        "home\.chezmoiscripts\windows\run_onchange_40-set-current-user-personalization.ps1"

    . $script:ScriptPath -SkipApply

    function New-TestLanguageList {
        param(
            [string]$FirstTip = "0409:00020409",
            [string]$SecondTip = "0413:00020409"
        )

        return @(
            [pscustomobject]@{ LanguageTag = "en-US"; InputMethodTips = @($FirstTip) }
            [pscustomobject]@{ LanguageTag = "nl-NL"; InputMethodTips = @($SecondTip) }
        )
    }

    function Invoke-TestPersonalization {
        param(
            [hashtable]$Registry,
            [string]$Culture = "en-US",
            [int]$GeoId = 244,
            [object[]]$Languages = @([pscustomobject]@{
                    LanguageTag = "en-US"
                    InputMethodTips = @("0409:00000409")
                }),
            [switch]$WhatIf
        )

        $script:Events = @()
        $script:RegistryWrites = @()
        $script:CultureSetCount = 0
        $script:HomeSetCount = 0
        $script:LanguageSetCount = 0

        Set-WindowsCurrentUserPersonalization `
            -GetRegistryValue {
                param($Path, $Name)
                $key = "$Path|$Name"
                if ($Registry.ContainsKey($key)) {
                    return $Registry[$key]
                }
                [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
            } `
            -SetRegistryValue {
                param($Path, $Name, $Value, $Kind)
                $script:Events += "Registry:$Name"
                $script:RegistryWrites += [pscustomobject]@{
                    Path = $Path; Name = $Name; Value = $Value; Kind = $Kind
                }
            } `
            -GetCultureName { $Culture } `
            -SetCulture {
                $script:Events += "Culture"
                $script:CultureSetCount++
            } `
            -GetHomeGeoId { $GeoId } `
            -SetHomeLocation {
                $script:Events += "HomeLocation"
                $script:HomeSetCount++
            } `
            -GetLanguageList { $Languages } `
            -SetLanguageList {
                $script:Events += "LanguageList"
                $script:LanguageSetCount++
            } `
            -WhatIf:$WhatIf
    }
}

Describe "Current-user Windows personalization script" -Tag "Unit" {
    It "exists as a native run_onchange PowerShell script with valid syntax" {
        $script:ScriptPath | Should -Exist
        $script:ScriptPath | Should -Match "run_onchange_"
        $script:ScriptPath | Should -Not -Match "\.tmpl$"

        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ScriptPath,
            [ref]$null,
            [ref]$errors
        ) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It "declares every migrated registry value with its exact desired state" {
        $settings = @(
            Get-WindowsPersonalizationRegistrySetting
            Get-WindowsNumberFormatRegistrySetting
        )
        $actual = @{}
        foreach ($setting in $settings) {
            $actual[$setting.Name] = "$($setting.Value)|$($setting.Kind)"
        }

        $actual.AppsUseLightTheme | Should -Be "0|DWord"
        $actual.SystemUsesLightTheme | Should -Be "0|DWord"
        $actual.RotatingLockScreenOverlayEnabled | Should -Be "0|DWord"
        $actual.ShowTaskViewButton | Should -Be "0|DWord"
        $actual.SearchboxTaskbarMode | Should -Be "0|DWord"
        $actual.HideFileExt | Should -Be "0|DWord"
        $actual.Hidden | Should -Be "1|DWord"
        $actual.BackgroundType | Should -Be "3|DWord"
        $actual.sDecimal | Should -Be ".|String"
        $actual.sThousand | Should -Be ",|String"
        $actual.sList | Should -Be ",|String"
    }

    It "keeps audit metadata attached to every applied registry setting" {
        $allSettings = @(Get-WindowsPersonalizationSetting)
        $registrySettings = @($allSettings | Where-Object SettingType -eq "Registry")
        $appliedRegistrySettings = @(
            Get-WindowsPersonalizationRegistrySetting
            Get-WindowsNumberFormatRegistrySetting
        )

        $registrySettings.Count | Should -Be 11
        $appliedRegistrySettings.Count | Should -Be $registrySettings.Count
        foreach ($setting in $appliedRegistrySettings) {
            $setting.Setting | Should -Not -BeNullOrEmpty
            $setting.Path | Should -Not -BeNullOrEmpty
            $setting.Name | Should -Not -BeNullOrEmpty
            $setting.Kind | Should -Not -BeNullOrEmpty
            $setting.Description | Should -Not -BeNullOrEmpty
            $setting.Rationale | Should -Not -BeNullOrEmpty
            $setting.Citation | Should -Not -BeNullOrEmpty
            $setting.EvidenceGrade | Should -BeIn @(1, 2, 3)
            $setting.Reversal | Should -Not -BeNullOrEmpty
        }
    }

    It "documents cmdlet settings and the post-culture ordering dependency" {
        $settings = @(Get-WindowsPersonalizationSetting)
        $cmdletSettings = @($settings | Where-Object SettingType -eq "Cmdlet")
        $afterCulture = @($settings | Where-Object Phase -eq "AfterCulture")

        $cmdletSettings.Count | Should -Be 3
        foreach ($setting in $cmdletSettings) {
            $setting.Command | Should -Not -BeNullOrEmpty
            $setting.Description | Should -Not -BeNullOrEmpty
            $setting.Rationale | Should -Not -BeNullOrEmpty
            $setting.Citation | Should -Match "^https://learn\.microsoft\.com/"
            $setting.Reversal | Should -Not -BeNullOrEmpty
        }
        $afterCulture.Count | Should -Be 3
        foreach ($setting in $afterCulture) {
            $setting.Rationale | Should -Match "after Set-Culture"
        }
    }

    It "accepts only the exact ordered language and keyboard list" {
        Test-WindowsLanguageListDesired -LanguageList (New-TestLanguageList) |
            Should -BeTrue
        Test-WindowsLanguageListDesired -LanguageList @(
            [pscustomobject]@{ LanguageTag = "nl-NL"; InputMethodTips = @("0413:00020409") }
            [pscustomobject]@{ LanguageTag = "en-US"; InputMethodTips = @("0409:00020409") }
        ) | Should -BeFalse
        Test-WindowsLanguageListDesired -LanguageList (
            New-TestLanguageList -FirstTip "0409:00000409"
        ) | Should -BeFalse
    }

    It "updates drifted settings with locale before the number separators" {
        $results = @(Invoke-TestPersonalization -Registry @{})

        @($results | Where-Object Changed).Count | Should -Be 14
        $script:CultureSetCount | Should -Be 1
        $script:HomeSetCount | Should -Be 1
        $script:LanguageSetCount | Should -Be 1
        $script:Events.IndexOf("Culture") |
            Should -BeLessThan $script:Events.IndexOf("Registry:sDecimal")
        $script:Events.IndexOf("Registry:sDecimal") |
            Should -BeLessThan $script:Events.IndexOf("Registry:sThousand")
        $script:Events.IndexOf("Registry:sThousand") |
            Should -BeLessThan $script:Events.IndexOf("Registry:sList")
    }

    It "is idempotent when every setting already has the desired value and kind" {
        $registry = @{}
        foreach ($setting in @(
                Get-WindowsPersonalizationRegistrySetting
                Get-WindowsNumberFormatRegistrySetting
            )) {
            $registry["$($setting.Path)|$($setting.Name)"] = [pscustomobject]@{
                Exists = $true
                Value  = $setting.Value
                Kind   = $setting.Kind
            }
        }

        $results = @(Invoke-TestPersonalization `
                -Registry $registry `
                -Culture "nl-NL" `
                -GeoId 176 `
                -Languages (New-TestLanguageList))

        @($results).Count | Should -Be 14
        @($results | Where-Object { $_.Status -ne "AlreadySet" }) |
            Should -BeNullOrEmpty
        $script:RegistryWrites | Should -BeNullOrEmpty
        $script:CultureSetCount | Should -Be 0
        $script:HomeSetCount | Should -Be 0
        $script:LanguageSetCount | Should -Be 0
    }

    It "does not write any setting under WhatIf" {
        $results = @(Invoke-TestPersonalization -Registry @{} -WhatIf)

        @($results).Count | Should -Be 14
        @($results | Where-Object { $_.Status -ne "WhatIf" }) |
            Should -BeNullOrEmpty
        $script:RegistryWrites | Should -BeNullOrEmpty
        $script:CultureSetCount | Should -Be 0
        $script:HomeSetCount | Should -Be 0
        $script:LanguageSetCount | Should -Be 0
    }

    It "uses only current-user registry and supported per-user cmdlets" {
        $content = Get-Content -LiteralPath $script:ScriptPath -Raw

        $content | Should -Match "Registry\]::CurrentUser"
        $content | Should -Match "Set-Culture"
        $content | Should -Match "Set-WinHomeLocation"
        $content | Should -Match "Set-WinUserLanguageList"
        $content | Should -Not -Match "HKLM|LocalMachine|RunOnce|ScheduledTask|Start-Process.+RunAs"
        $content | Should -Not -Match "WindowsPrincipal|Administrator|#Requires -RunAsAdministrator"
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD5OoMdSKIo0LLQ
# Ygbi4LgorXWcYIl9K9TqZSPsIM9NNaCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCCBMYKO7fUt9DH5AW/N+kedzmZpdrADhKn6oBO7aCyIBTANBgkqhkiG
# 9w0BAQEFAASCAgBgp/A46eXDz6ImmKxunfv1zcL5NtMeQle2Zsz5l+yomhYzmn3e
# rZVyD4WjHISzuyCT+DVgdAyJmTh+nCXurBdyDp8G0h/TPVj0HSPp2JXkwewOIs2s
# J4iK7EH/iTNWxLCbF+qwhgDNyJil/5dxVyU6UNqwlDV+DUMPJcxcwacs3wUs4oYD
# 12DNjwxpbNl/IUTlVZBXKpHHN9SclBuMgHtpDSGrAGc3CXnoYy9Z7MWPaUugbME7
# a2E+l3X6VPs8o8yKG+7tdnc1HAw/u41lTPyL0ebRIZYw1zHUy+7LiziSet0Nm2Xu
# Efv63uMbSKjtwOkwEflxDr2DBFuy1d4EIZwjn4+9+9Eonvm7ho7QNKUEiaYUZHNu
# VSiaBYor3XQsT2BSAVTyPfKtk3oT32+XjHpzFWHtcPLaEA6qR8bpSEhXyqqtp4vB
# yg9e28ly52xviZ8+wZh0EXMoYDWTVFIL5cV64Hqw6pI+mvAeC8950MOwpedUdWIX
# HLjwbb/T1xmEAhvOJQAM8M4WemEWmKQ0H7AeJEaSor4JHgZ1EOyV23X3wcVLhYMq
# a46mRe7uFiJArHU9DSteD63rhdsvO0rfwyPEyprRYWyTcuzg/Cn7v5zKkrMQRlG+
# st1M88m+3jeb8TNuasUYr6SPXNJEeSDtMcmd4RzxzFf0t+WRqLrUsoOt/qGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA4MTMxNjU3MjJaMC8GCSqGSIb3DQEJBDEi
# BCD+L4mjutVdYOj7s+8LX7ez19fAxJVrL4K5idEArjmEPzANBgkqhkiG9w0BAQEF
# AASCAgCROxQDaicRnd5T7uAuj9JUeLC7CO1B0lgo4AWEu2q98kK6/rtdJXRF2PSu
# 4MdPw4CCPkVSuaH8FZhxWrjh8Vn6s2d8Q0aK8oN1YNaQKcwe0rLyUW+Vdgppb8UB
# pirfnmlu9dYFsHYJXRYCxSkySr4jiHYpPzaM/p4efjS07D1jIzP8aCbbOZ/fgJf2
# Dtrmh8ON2KKdarOUSHWJTvR1K38RwFRviH5zkAQKQrLmskGD+b+Zt0qtESWVJsxT
# Ug3/2q2/Vd7c/NvXpx3gnmeXv7IsXAL3K1I/TpBrT21WqvoDJUCVYem1fVHMvkP8
# HLseV7imXEz4l5RmaB1CdGCw4GR+6b4F+occUc/rcsQrvDwcyKErvMK/FsmYvxJb
# gwKFFohjNwrNLYzUpURGLvkndwgVkP+7B8ah0fvns9JME9q6EehWGrNbcaKh2Z8b
# 7576GKKzPxSRu14QvO0nCAPkFA/Fwbe+5NQda2WoctBmBP1Nd4a6nk6CM/KiuJBS
# hT58bO1zfeJCZHbF3jZLBOH67yHvQi9bQbUemK0hAI5Vrbp/zgRb4dYrC3QfUMZw
# GOEyXKCnr5xHcXTKtzSlAtrof17iUwnKJzP55gV8spkLaj1bJFQcUgQwssdaXuEf
# 0Vx98tWvJzM8zBXtSZroVWRa4nb6ijmuB4ELHV4ZRloiyXt7Lg==
# SIG # End signature block
