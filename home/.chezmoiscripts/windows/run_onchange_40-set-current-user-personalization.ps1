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

function Get-WindowsPersonalizationRegistrySetting {
    $settings = @(
        [pscustomobject]@{
            Path = "Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            Name = "AppsUseLightTheme"; Value = 0; Kind = "DWord"
        }
        [pscustomobject]@{
            Path = "Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
            Name = "SystemUsesLightTheme"; Value = 0; Kind = "DWord"
        }
        [pscustomobject]@{
            Path = "Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
            Name = "RotatingLockScreenOverlayEnabled"; Value = 0; Kind = "DWord"
        }
        [pscustomobject]@{
            Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Name = "ShowTaskViewButton"; Value = 0; Kind = "DWord"
        }
        [pscustomobject]@{
            Path = "Software\Microsoft\Windows\CurrentVersion\Search"
            Name = "SearchboxTaskbarMode"; Value = 0; Kind = "DWord"
        }
        [pscustomobject]@{
            Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Name = "HideFileExt"; Value = 0; Kind = "DWord"
        }
        [pscustomobject]@{
            Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
            Name = "Hidden"; Value = 1; Kind = "DWord"
        }
        [pscustomobject]@{
            Path = "Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers"
            Name = "BackgroundType"; Value = 3; Kind = "DWord"
        }
    )

    return $settings
}

function Get-WindowsNumberFormatRegistrySetting {
    $settings = @(
        [pscustomobject]@{
            Path = "Control Panel\International"
            Name = "sDecimal"; Value = "."; Kind = "String"
        }
        [pscustomobject]@{
            Path = "Control Panel\International"
            Name = "sThousand"; Value = ","; Kind = "String"
        }
        [pscustomobject]@{
            Path = "Control Panel\International"
            Name = "sList"; Value = ","; Kind = "String"
        }
    )

    return $settings
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
