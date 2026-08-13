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
