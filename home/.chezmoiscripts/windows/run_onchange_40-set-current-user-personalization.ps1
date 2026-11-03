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
            Id = "show-battery-percentage"; Setting = "Taskbar battery percentage"; SettingType = "Registry"; Phase = "BeforeCulture"
            Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name = "IsBatteryPercentageEnabled"
            Value = 1; Kind = "DWord"; Command = $null
            Description = "Shows the battery percentage next to the taskbar battery icon on supported Windows 11 builds."
            Rationale = "Makes remaining battery charge visible without hovering. Older Windows builds or devices without a battery ignore this community-documented preference."
            Citation = "https://www.elevenforum.com/t/enable-or-disable-show-battery-percentage-on-taskbar-in-windows-11.32691/"
            EvidenceGrade = 3
            Reversal = "Set IsBatteryPercentageEnabled to 0, delete the value, or turn off Battery percentage in Settings > System > Power & battery."
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD1IoMY/zzBhlOh
# rGsUPB+MZg6p/CYhsxS2D2P/644CoKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# oW2jNrbM1pD2T7m3XDCCBu0wggTVoAMCAQICEAhP3DNPfkVO28MPj/mSGDUwDQYJ
# KoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBS
# U0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNjA4MDUwMDAwMDBaFw0zNzExMDQy
# MzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7
# MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3Bv
# bmRlciAyMDI2IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2e6by
# yf7NSvjUm0xls/04xjD4fAkOkbnGQi7+Wpx81iYxfzViaxSIctuH3KSl5YEYpMuF
# gGsA31N2D9ATMbfZdw5uaAhuWevQKhDdZIB4NnqcfpfpWQXJiQnDdAElETC+bhSE
# vNLGbA8DtwUpFMQ4yyYQSPqomT92osQAv6hBi47ATZS6JfVWe6XxhF4jJZ3iSAuf
# 2Cros1czRSmWRHqMv9AfGZvp8ygYElhudpQjtcPpwoOl6QrZJUyV3iINvN4cO05p
# rGV0fkjG426xDr2d3z9lcSIHkdvGPdGUrXdxfVbgOUVcp2/8ISEzwKPW++Wa+E2u
# jI91EZtukGWDJ/xZ27k3oHKEXBRGfRTqjOU+jE3ba/5++JSE/7oNHnjs5mekExYN
# 96LV/mxUbCKJb8pBNY4r3uD7hEmk/M81XhVgwDA7aMzYC3LZBg9WY5BMmbSay5ec
# mtJuXaB/0nKWmQmVZeqTVDgsmzHP5MQuhAJkiWNuC9MmCg9TZHXbJ2/yLVSov9p1
# 6UDTLtT0+aa1vN71fHeu1qMLlLNB3WOB/ADCxr3S/1hxI92Z6jKgEED/btwIvbfu
# XkNNhg8MtDg43c4tMZae9FvqMOt/9PvmAxF9TNIsIFB8G6yb36ZJZGUL8N/pL971
# DyLXcK6HM5PYnH5X+eVtczhCgHCVQCF6XDAlPQIDAQABo4IBlTCCAZEwDAYDVR0T
# AQH/BAIwADAdBgNVHQ4EFgQUFMljijAu1Er7bpTz5uNAfvXszeIwHwYDVR0jBBgw
# FoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB
# /wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdS
# U0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
# L2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAjcU6YR6dUgrfmawJgH59KECx
# a9Ji8sEi2g10CBDaMiqsaxWyW5cwlT/6ZF5sFznazqVsoC85U9dqLOYqQwst+UQQ
# oNlDHgKRLa3xoc+OReFreFhnTXSG0Vrd2E2CZqUfm+5a+He1MJ/h+tNLuA+0Zzhn
# /Fo+FDYAHWZHx4R79ZsfRFYe9UiXpXBDf6DkUo183Y38NYmR/XfDYf7YZ+oR9t3f
# lbDwK+hgGMs0gNNp1w9Z2CyOyI5or/sSwomAuNQ0hWC9xoU4stD8aWsD7RkcmgVR
# s6vlIk3zPKQ+ylcheWkMlj+CoVRlFE55pv0ZWCaFt04lwP/rdGHE9qEVQZtyRE42
# ox7oNgC/r+Y4bSlZ3dw9K2x1xLtu6PkPKeLBFjzKigwfqm3Hm+k/+lnME8F5kPZT
# giy2HLEHklpryqs6QHnPXrRNeIzkAMyylnRN8P0wmirS0WkU+ywpEWFZ4QNg+9xS
# 43tTuW9x0eXh7NDc1P/sV+zWxHXKH8tFt1ncHdVzqrZaYPyYMLSn2TOXajveJW1L
# 3joiQSPsWRGxkbDDW15jERFE4LvjnGu2O9zD1nLJSMdlYZEikl4w2w+q4IN/R+TI
# e0H4ngCI1moJCTbevGH4punIxM1Uoi0nmX3ZK+XbRT01uowE5ViXWHng0RgsmrX/
# EdYUo80r3TfMlkD0/YMxggYTMIIGDwIBATA3MCMxITAfBgNVBAMMGEplYW4tUGF1
# bCB2YW4gUmF2ZW5zYmVyZwIQELbg9grCcadOf9RJU4Fg9DANBglghkgBZQMEAgEF
# AKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgor
# BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3
# DQEJBDEiBCDN34cSv8u3v1NveC4HXccEeooNRN9+4yIuSFcxDNiu2zANBgkqhkiG
# 9w0BAQEFAASCAgC1YJmsvEmiSshACO7+VpFCDbdGON2VftTPqrfsFhayYTkGqqXJ
# 8XBKt48Wa1nMevegLfMaYp9sObAejOqZyPIlR2zFPFaHaMe29H3C5n2iejjveeX8
# 1m4bcX8QD5cfEXABw/p0gZc7CJdEWVFevk6sSwFvwawQXiUMjJ3KJFsb08uXF98u
# Ycgn9EFoW44abIJPjfCp/P9MeKp3fNb+EyQPh2ITa9w1gK28/lyVR8QrJ5orQqHG
# +EfMVuAJD/VosVg6B9XFVkLj/qTTw4PDyRAp1k6PS/5h4l0QACXuUwY6N27x/LWs
# 0hdla6CLSKLeevSpxnJhF0YXRQbLMfTMxNz6D0H+qS8Uq/Q3aMm1VOp5NY/yfjPP
# 6/HkNSeFKttORFHrvcVd9bLPKXF2sJ9NqVSJpf0ht9GfuaM7/KQz9xBXuNPtiTk5
# UIDL4z/FhRqKWCgZj5XTqu9BbDIbw4AA/FSn7mE31imrMRAg20xkmivo2SFl5Byj
# eVWFkbZkZLyTd4dm8BRuNESHelcOXk7vlzjkHXcAXxWIZhwYWk0+hr4gXj+kTwEt
# YAboCdr6hoviU5VArCbb8Dyge8W3tFdnMnZ0wxts1LJWyHo4L7zAb3Gft/bo+9PK
# r3yNO4O0/5v5RRnVO4ADe8hOA/AzPOhgzTDE02xWUCMm38QEFOtE15VSuaGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO
# 28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjEwMzAxNDU1NDNaMC8GCSqGSIb3DQEJBDEi
# BCCrs6Z1w8nFJQBxgcFsiI9OUs5xKxbui3cTdxcW2w1XaDANBgkqhkiG9w0BAQEF
# AASCAgBKpREMYrJqNlvwIb8NFpaKn71DshPxRphhf613Bu13ifujxlIvKUHfs9vq
# 1OM0AMHbgUJhypQRkv6mxvMpX7/5SVUQOJdp+MQo8AwONBqbwuoMuV2uMW6yUyAH
# 6oTs92QPmgmOYUc44uJohQeUB+plxQiQkDgp43Yy3rbwCDCWqzCcmy1AVwCbFpka
# Vdqj/pse/U601COcxCmeOobUj9Le1yKIUWjxyHsQHTJviTDrzPuciSp0kg8Lxx6s
# Q/VB5NByLZc0yWOzHjtm40LOztZgW1nLrrsESmoVd6vVqdqTehgzw2w/fGfeqbgC
# mJ3xeTL+FIDV06Da0QiWZ2rWAmu6HuDUqusAYzTuVvtlWye6AIUj4uPh+/pGoNuN
# MlxMDruSXbansMg3Ktm+yuA0fP6vcgiVXlWFbIIYg7xuBjxf7jJxN4ZxCs5ZvD25
# bUlcuUz58LPof5HKo7iJ9Bp1NcF0iQxqB4nHh0cYRzOt7wHvGz8oeRfUj3CoyS4S
# XH1n/bkYsKyg+rIv26K5AWiaIH3UyXSXZrmMuMXIyqAZRfzD7/Ga10jlmn980/EE
# l1+7oTpqt6NVd0zGxu2mG+t6cSeMUmiNaF3v6jKDT8pfmfcalRkzwKm1MFRoiydu
# XgYt74OR04q/d9/0mveM9J2u/w01I6XmGwOeJZ/mIcUP9+IlkA==
# SIG # End signature block
