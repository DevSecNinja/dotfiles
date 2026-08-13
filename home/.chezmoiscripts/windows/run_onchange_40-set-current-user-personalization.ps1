#!/usr/bin/env pwsh
# Apply opinionated Windows personalization to the invoking user's profile.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    "PSAvoidUsingWriteHost",
    "",
    Justification = "Matches existing chezmoi setup script progress output."
)]
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipApply
)

$ErrorActionPreference = "Stop"

function Get-WindowsPersonalizationSetting {
    $settings = @(
        [pscustomobject]@{
            Id = "dark-mode-apps"; Setting = "Dark mode for apps"; SettingType = "Registry"; Phase = "BeforeCulture"
            Path = "Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"; Name = "AppsUseLightTheme"
            Value = 0; Kind = "DWord"; Command = $null
            Description = "Selects the dark theme for applications."
            Rationale = "Keeps application surfaces in the preferred dark theme. The registry mapping is community-documented, not an official policy contract."
            Citation = "https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/apply-windows-themes"
            EvidenceGrade = 3
            Reversal = "Set AppsUseLightTheme to 1, delete the value, or choose Light in Settings > Personalization > Colors."
        }
        [pscustomobject]@{
            Id = "dark-mode-system"; Setting = "Dark mode for Windows"; SettingType = "Registry"; Phase = "BeforeCulture"
            Path = "Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"; Name = "SystemUsesLightTheme"
            Value = 0; Kind = "DWord"; Command = $null
            Description = "Selects the dark theme for the taskbar, Start, and other Windows surfaces."
            Rationale = "Keeps system surfaces in the preferred dark theme. The registry mapping is community-documented, not an official policy contract."
            Citation = "https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/apply-windows-themes"
            EvidenceGrade = 3
            Reversal = "Set SystemUsesLightTheme to 1, delete the value, or choose Light in Settings > Personalization > Colors."
        }
        [pscustomobject]@{
            Id = "disable-lockscreen-spotlight-overlay"; Setting = "Lock-screen Spotlight overlays"; SettingType = "Registry"; Phase = "BeforeCulture"
            Path = "Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "RotatingLockScreenOverlayEnabled"
            Value = 0; Kind = "DWord"; Command = $null
            Description = "Disables Windows Spotlight lock-screen fun-fact, suggestion, and advertising overlays."
            Rationale = "Reduces promotional content on the lock screen. This per-user mapping is documented by Microsoft Community rather than an official registry policy."
            Citation = "https://learn.microsoft.com/en-us/answers/questions/1326668/how-to-disable-windows-spotlight-via-registry"
            EvidenceGrade = 3
            Reversal = "Set RotatingLockScreenOverlayEnabled to 1, delete the value, or re-enable lock-screen tips in Settings."
        }
        [pscustomobject]@{
            Id = "hide-task-view"; Setting = "Task View button"; SettingType = "Registry"; Phase = "BeforeCulture"
            Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "ShowTaskViewButton"
            Value = 0; Kind = "DWord"; Command = $null
            Description = "Hides the Task View button while leaving the Win+Tab shortcut available."
            Rationale = "Removes an unused taskbar control without disabling Task View."
            Citation = "https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11"
            EvidenceGrade = 1
            Reversal = "Set ShowTaskViewButton to 1, delete the value, or enable Task view in Settings > Personalization > Taskbar."
        }
        [pscustomobject]@{
            Id = "hide-taskbar-search"; Setting = "Taskbar search"; SettingType = "Registry"; Phase = "BeforeCulture"
            Path = "Software\Microsoft\Windows\CurrentVersion\Search"; Name = "SearchboxTaskbarMode"
            Value = 0; Kind = "DWord"; Command = $null
            Description = "Hides the taskbar search box and icon."
            Rationale = "Removes an unused taskbar control; Windows Search remains available from Start. The value mirrors documented modes but is not itself a documented policy."
            Citation = "https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11"
            EvidenceGrade = 2
            Reversal = "Set SearchboxTaskbarMode to 3, delete the value, or select Search box in Settings > Personalization > Taskbar."
        }
        [pscustomobject]@{
            Id = "show-file-extensions"; Setting = "File-name extensions"; SettingType = "Registry"; Phase = "BeforeCulture"
            Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "HideFileExt"
            Value = 0; Kind = "DWord"; Command = $null
            Description = "Shows known file-type extensions in File Explorer."
            Rationale = "Improves clarity and helps expose misleading names such as invoice.pdf.exe. The exact registry mapping has no retained authoritative citation."
            Citation = "Unverified"
            EvidenceGrade = 3
            Reversal = "Set HideFileExt to 1, delete the value, or clear View > Show > File name extensions in File Explorer."
        }
        [pscustomobject]@{
            Id = "show-hidden-items"; Setting = "Hidden files and folders"; SettingType = "Registry"; Phase = "BeforeCulture"
            Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "Hidden"
            Value = 1; Kind = "DWord"; Command = $null
            Description = "Shows hidden files and folders in File Explorer."
            Rationale = "Makes configuration and development files directly accessible. The exact registry mapping has no retained authoritative citation."
            Citation = "Unverified"
            EvidenceGrade = 3
            Reversal = "Set Hidden to 2, delete the value, or clear View > Show > Hidden items in File Explorer."
        }
        [pscustomobject]@{
            Id = "spotlight-desktop-background"; Setting = "Desktop background"; SettingType = "Registry"; Phase = "BeforeCulture"
            Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers"; Name = "BackgroundType"
            Value = 3; Kind = "DWord"; Command = $null
            Description = "Selects Windows Spotlight as the desktop background."
            Rationale = "Uses the rotating Spotlight image. Microsoft documents Spotlight as wallpaper kind 3, but this per-user registry mirror is best-effort and community-grade."
            Citation = "https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11"
            EvidenceGrade = 3
            Reversal = "Set BackgroundType to 1, delete the value, or choose another background in Settings > Personalization > Background."
        }
        [pscustomobject]@{
            Id = "culture-nl"; Setting = "Regional format"; SettingType = "Cmdlet"; Phase = "Culture"
            Path = $null; Name = "Culture"; Value = "nl-NL"; Kind = $null; Command = "Set-Culture"
            Description = "Sets the current user's regional format to Dutch (Netherlands), including 24-hour time and day-month-year dates."
            Rationale = "Uses the supported per-user cmdlet without changing the English display language. Set-Culture rewrites regional overrides, so number separators must run afterward."
            Citation = "https://learn.microsoft.com/en-us/powershell/module/international/set-culture"
            EvidenceGrade = 1
            Reversal = "Run Set-Culture -CultureInfo en-US or select another Regional format in Settings > Time & language > Language & region."
        }
        [pscustomobject]@{
            Id = "home-location-nl"; Setting = "Home location"; SettingType = "Cmdlet"; Phase = "Culture"
            Path = $null; Name = "HomeLocation"; Value = 176; Kind = $null; Command = "Set-WinHomeLocation"
            Description = "Sets the current user's home location GeoID to 176 (Netherlands)."
            Rationale = "Aligns Region > Country or region with the Dutch regional format through the supported per-user cmdlet."
            Citation = "https://learn.microsoft.com/en-us/powershell/module/international/set-winhomelocation"
            EvidenceGrade = 1
            Reversal = "Run Set-WinHomeLocation -GeoId 244 for the United States or choose another Country or region in Settings."
        }
        [pscustomobject]@{
            Id = "language-list-us-international"; Setting = "Languages and keyboards"; SettingType = "Cmdlet"; Phase = "Culture"
            Path = $null; Name = "LanguageList"
            Value = "en-US:0409:00020409; nl-NL:0413:00020409"; Kind = $null; Command = "Set-WinUserLanguageList"
            Description = "Sets exactly en-US then nl-NL, both using the United States-International keyboard layout."
            Rationale = "Keeps English first while removing the unwanted plain-US layout. The supported cmdlet avoids hand-editing the serialized per-user language profile."
            Citation = "https://learn.microsoft.com/en-us/powershell/module/international/set-winuserlanguagelist"
            EvidenceGrade = 1
            Reversal = "Use Settings > Time & language > Language & region, or run Set-WinUserLanguageList en-US -Force, to restore a normal single-language list."
        }
        [pscustomobject]@{
            Id = "number-format-decimal-us"; Setting = "Decimal separator"; SettingType = "Registry"; Phase = "AfterCulture"
            Path = "Control Panel\International"; Name = "sDecimal"; Value = "."; Kind = "String"; Command = $null
            Description = "Uses a dot as the decimal symbol."
            Rationale = "A comma CSV delimiter requires the decimal symbol to differ from the list separator. Applied after Set-Culture because that cmdlet restores nl-NL defaults."
            Citation = "https://learn.microsoft.com/en-us/windows/win32/intl/locale-custom-constants"
            EvidenceGrade = 2
            Reversal = "Set sDecimal to ',' to restore the nl-NL default, or choose another Regional format."
        }
        [pscustomobject]@{
            Id = "number-format-thousands-us"; Setting = "Thousands separator"; SettingType = "Registry"; Phase = "AfterCulture"
            Path = "Control Panel\International"; Name = "sThousand"; Value = ","; Kind = "String"; Command = $null
            Description = "Uses a comma as the digit-grouping symbol."
            Rationale = "Completes the preferred US-style number format after the decimal symbol becomes a dot. Applied after Set-Culture because that cmdlet restores nl-NL defaults."
            Citation = "https://learn.microsoft.com/en-us/windows/win32/intl/locale-custom-constants"
            EvidenceGrade = 2
            Reversal = "Set sThousand to '.' to restore the nl-NL default, or choose another Regional format."
        }
        [pscustomobject]@{
            Id = "number-format-list-us"; Setting = "List separator"; SettingType = "Registry"; Phase = "AfterCulture"
            Path = "Control Panel\International"; Name = "sList"; Value = ","; Kind = "String"; Command = $null
            Description = "Uses a comma as the list separator for comma-delimited CSV files."
            Rationale = "Excel uses the user list separator for CSV columns. Applied after Set-Culture, and after sDecimal, because Windows does not allow list and decimal separators to match."
            Citation = "https://learn.microsoft.com/en-us/windows/win32/intl/locale-custom-constants"
            EvidenceGrade = 2
            Reversal = "Set sList to ';' to restore the nl-NL default, or choose another Regional format."
        }
    )

    return $settings
}

function Get-WindowsPersonalizationRegistrySetting {
    return @(Get-WindowsPersonalizationSetting | Where-Object {
            $_.SettingType -eq "Registry" -and $_.Phase -eq "BeforeCulture"
        })
}

function Get-WindowsNumberFormatRegistrySetting {
    return @(Get-WindowsPersonalizationSetting | Where-Object {
            $_.SettingType -eq "Registry" -and $_.Phase -eq "AfterCulture"
        })
}

function Test-WindowsLanguageListDesired {
    param(
        [AllowNull()]
        [object[]]$LanguageList
    )

    $languages = @($LanguageList)
    if ($languages.Count -ne 2) {
        return $false
    }

    $expected = @(
        @{ LanguageTag = "en-US"; InputMethodTip = "0409:00020409" }
        @{ LanguageTag = "nl-NL"; InputMethodTip = "0413:00020409" }
    )

    for ($index = 0; $index -lt $expected.Count; $index++) {
        $inputMethodTips = @($languages[$index].InputMethodTips)
        if ($languages[$index].LanguageTag -ne $expected[$index].LanguageTag -or
            $inputMethodTips.Count -ne 1 -or
            $inputMethodTips[0] -ne $expected[$index].InputMethodTip) {
            return $false
        }
    }

    return $true
}

function Set-WindowsCurrentUserPersonalization {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [scriptblock]$GetRegistryValue = {
            param([string]$Path, [string]$Name)

            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path, $false)
            try {
                if (-not $key -or $Name -notin $key.GetValueNames()) {
                    return [pscustomobject]@{ Exists = $false; Value = $null; Kind = $null }
                }

                return [pscustomobject]@{
                    Exists = $true
                    Value  = $key.GetValue($Name, $null)
                    Kind   = $key.GetValueKind($Name).ToString()
                }
            }
            finally {
                if ($key) {
                    $key.Dispose()
                }
            }
        },

        [scriptblock]$SetRegistryValue = {
            param([string]$Path, [string]$Name, [object]$Value, [string]$Kind)

            $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Path)
            try {
                if (-not $key) {
                    throw "Unable to open or create HKCU\$Path."
                }

                $registryKind = [Microsoft.Win32.RegistryValueKind]::$Kind
                $key.SetValue($Name, $Value, $registryKind)
            }
            finally {
                if ($key) {
                    $key.Dispose()
                }
            }
        },

        [scriptblock]$GetCultureName = {
            (Get-Culture -ErrorAction Stop).Name
        },

        [scriptblock]$SetCulture = {
            Set-Culture -CultureInfo "nl-NL" -ErrorAction Stop
        },

        [scriptblock]$GetHomeGeoId = {
            (Get-WinHomeLocation -ErrorAction Stop).GeoId
        },

        [scriptblock]$SetHomeLocation = {
            Set-WinHomeLocation -GeoId 176 -ErrorAction Stop
        },

        [scriptblock]$GetLanguageList = {
            @(Get-WinUserLanguageList -ErrorAction Stop)
        },

        [scriptblock]$SetLanguageList = {
            $languages = New-WinUserLanguageList -Language "en-US"
            $languages[0].InputMethodTips.Clear()
            $languages[0].InputMethodTips.Add("0409:00020409")
            $languages.Add("nl-NL")
            $languages[1].InputMethodTips.Clear()
            $languages[1].InputMethodTips.Add("0413:00020409")
            Set-WinUserLanguageList -LanguageList $languages -Force -ErrorAction Stop
        }
    )

    $results = @()

    foreach ($setting in Get-WindowsPersonalizationRegistrySetting) {
        $current = & $GetRegistryValue -Path $setting.Path -Name $setting.Name
        if ($current.Exists -and $current.Value -eq $setting.Value -and $current.Kind -eq $setting.Kind) {
            $results += [pscustomobject]@{ Setting = $setting.Name; Status = "AlreadySet"; Changed = $false }
            continue
        }

        if ($PSCmdlet.ShouldProcess("HKCU\$($setting.Path)\$($setting.Name)", "Set value to '$($setting.Value)'")) {
            & $SetRegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Kind $setting.Kind
            $results += [pscustomobject]@{ Setting = $setting.Name; Status = "Updated"; Changed = $true }
        }
        else {
            $results += [pscustomobject]@{ Setting = $setting.Name; Status = "WhatIf"; Changed = $false }
        }
    }

    $cultureName = & $GetCultureName
    if ($cultureName -eq "nl-NL") {
        $results += [pscustomobject]@{ Setting = "Culture"; Status = "AlreadySet"; Changed = $false }
    }
    elseif ($PSCmdlet.ShouldProcess("Current user culture", "Set culture to nl-NL")) {
        & $SetCulture
        $results += [pscustomobject]@{ Setting = "Culture"; Status = "Updated"; Changed = $true }
    }
    else {
        $results += [pscustomobject]@{ Setting = "Culture"; Status = "WhatIf"; Changed = $false }
    }

    $homeGeoId = & $GetHomeGeoId
    if ($homeGeoId -eq 176) {
        $results += [pscustomobject]@{ Setting = "HomeLocation"; Status = "AlreadySet"; Changed = $false }
    }
    elseif ($PSCmdlet.ShouldProcess("Current user home location", "Set GeoId to 176 (Netherlands)")) {
        & $SetHomeLocation
        $results += [pscustomobject]@{ Setting = "HomeLocation"; Status = "Updated"; Changed = $true }
    }
    else {
        $results += [pscustomobject]@{ Setting = "HomeLocation"; Status = "WhatIf"; Changed = $false }
    }

    $languageList = @(& $GetLanguageList)
    if (Test-WindowsLanguageListDesired -LanguageList $languageList) {
        $results += [pscustomobject]@{ Setting = "LanguageList"; Status = "AlreadySet"; Changed = $false }
    }
    elseif ($PSCmdlet.ShouldProcess("Current user language list", "Set en-US and nl-NL to United States-International")) {
        & $SetLanguageList
        $results += [pscustomobject]@{ Setting = "LanguageList"; Status = "Updated"; Changed = $true }
    }
    else {
        $results += [pscustomobject]@{ Setting = "LanguageList"; Status = "WhatIf"; Changed = $false }
    }

    # Set-Culture replaces these overrides, so separators must always be checked last.
    foreach ($setting in Get-WindowsNumberFormatRegistrySetting) {
        $current = & $GetRegistryValue -Path $setting.Path -Name $setting.Name
        if ($current.Exists -and $current.Value -eq $setting.Value -and $current.Kind -eq $setting.Kind) {
            $results += [pscustomobject]@{ Setting = $setting.Name; Status = "AlreadySet"; Changed = $false }
            continue
        }

        if ($PSCmdlet.ShouldProcess("HKCU\$($setting.Path)\$($setting.Name)", "Set value to '$($setting.Value)'")) {
            & $SetRegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Kind $setting.Kind
            $results += [pscustomobject]@{ Setting = $setting.Name; Status = "Updated"; Changed = $true }
        }
        else {
            $results += [pscustomobject]@{ Setting = $setting.Name; Status = "WhatIf"; Changed = $false }
        }
    }

    return $results
}

if (-not $SkipApply) {
    Write-Host "Applying current-user Windows personalization..." -ForegroundColor Cyan
    $results = @(Set-WindowsCurrentUserPersonalization -WhatIf:$WhatIfPreference)
    $updatedCount = @($results | Where-Object { $_.Changed }).Count
    Write-Host "[OK] Windows personalization complete ($updatedCount setting(s) changed)." -ForegroundColor Green
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBTIAy5ec4FYHTV
# kjjqheDY+gDhtTWKV368iMyvYs1gH6CCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCCC1pJWjtaTCVHvADaAuVPJC+FNBByk6cMpw8pSH2oPATANBgkqhkiG
# 9w0BAQEFAASCAgA63qJhft0gNSjZEzGZx4B4wsFvxOKcb4wJShxIp8O+wNUK8BIe
# wG9vBt8fH2SgtlJOT0xIT/RbkO4h89DrzScH/VmtJbJ2g6Bv/zeV97tJzlKb8JdT
# 5fnp4EwOtL4xwUXYfhRYT5Mqzf/syskwe1aL2UxURWdFZ2wNYsmNRyBJdDcEnU3x
# 2HO4cfODASvL2whpgSG557Xfckd584VUIILLtTfoV1K6GsyepZEoX+FfxjYPICdP
# 2zAuDPaONLMmKvP3CY1mBwfRfXtXIojkA7KsXozJnhMLrzIZDBQ2vkfo3Q9mndvH
# cbI4AY6R26byIHagiyiTcJQCnWcTYz75YxD9aep7wLaU2Z/4oX1GnZlY4p4DlXE6
# 1emhwAClb7sWP6vNtW1NLinRdfJVkEmjFzZ8NWSfJekDy8YCm67usHgN5DqLNZXt
# 7gXYCvXykhuw9c7/jje/0xry/Cuh7LMsx82z1tVJORqzmc/PBCXdtxk+0FF57td8
# WPCdg9d3iuJhHLlhQnzjVgC8coUm1LMCBpk1ylIKzZhIznATKPhqOAjMb/d3ULwB
# rcEAhY8NrL6W9LEdHqzFN1V/q0z2JtflpKnKLz11EA5tUomnAW4D8+1V2+pdxut1
# kmkGED/njok2seBceIGkh7uuEPLH2Ajr1Hqh5E0eq69VgeC/XXoBXi3mAKGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA4MTMxNjU3MThaMC8GCSqGSIb3DQEJBDEi
# BCBUlfrgwfFni9iH2PEEF60JfDGPuO+zfber3A4BaJx7njANBgkqhkiG9w0BAQEF
# AASCAgBJPz8u2Va3z53Bll+T22dQ/qUdsG0eRi4Nd0I6e0RplWwgvL9zmS3u2UxC
# PYFVFwycjv7yLPrIGdnoXWavZrwWaaRHs7XHqaNMJsWl552ToGQO5sYwZPjXXBBG
# Fn6t2pGqlOREc2rqzer/rcmL2qBkmCaBEXR006Lt6MH8ogOu3H5Ni2EmDOJyjDvK
# lMVIBQDE5PLMPUeSR+XXlYNtlUeaK3eCW+AZ0yM7Zb73g00hP6pl7/hsTTH3k5nx
# wiVW/qgnb4AlEYY8qFNtWNbiWQgs293OkBm4PlSf1NIqFvvXKXlZfncpJ/UhG6nF
# 8tlzJApMwPvEeVIjqIJmequhdpquEnwsiCL1OH+kGRsSlLuttmm7HiShhHM7rpSp
# wA4zCUyxGQQkeT3w2S9/dhN6o4bEzUjwfAEqh8O+KvWPDbYTdAjhbDubZwMrP3gQ
# ySruYPzvT2uxWsFerusINqrGl5E1FwbASpLmLLqNOwShWI/NoZ1Fk3keGmkUdpP4
# azZB5G+uhgJB6B2wmpUaT9dvzQDJoIewk9vn4ODoVo8N/cS0QBsJBF+uUIy2gpcc
# EdSSSI3DrtvsekFROn1WOyvdRRo0ibvz0FKwPr1137jIuTZQZvTpiDqe73OS4P/h
# /Y+ILy1pr8jg6wuhcDPA/set0+WBvWtrq7LePRnx068QvLcm3w==
# SIG # End signature block
