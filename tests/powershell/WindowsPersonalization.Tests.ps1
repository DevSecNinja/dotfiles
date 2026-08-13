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
