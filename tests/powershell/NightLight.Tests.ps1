#Requires -Version 7.0
<#
.SYNOPSIS
    Tests the Night Light configuration script and its Bond CompactBinary codec.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:ScriptPath = Join-Path $script:RepoRoot `
        "home\.chezmoiscripts\windows\run_onchange_41-set-night-light.ps1"

    . $script:ScriptPath -SkipApply

    # Captured from a live Windows 11 install: sunset-to-sunrise schedule,
    # start 21:00, end 07:00, 3850 K, sunset 21:06, sunrise 06:25.
    $script:SampleSettingsBlob = [byte[]]@(
        0x43, 0x42, 0x01, 0x00, 0x0a, 0x02, 0x01, 0x00, 0x2a, 0x06, 0xcf, 0xa2,
        0x88, 0xd4, 0x06, 0x2a, 0x2b, 0x0e, 0x23, 0x43, 0x42, 0x01, 0x00, 0x02,
        0x01, 0xca, 0x14, 0x0e, 0x15, 0x00, 0xca, 0x1e, 0x0e, 0x07, 0x00, 0xcf,
        0x28, 0x94, 0x3c, 0xca, 0x32, 0x0e, 0x15, 0x2e, 0x06, 0x00, 0xca, 0x3c,
        0x0e, 0x06, 0x2e, 0x19, 0x00, 0x00, 0x00, 0x00, 0x00
    )

    # Captured from the same install: Night Light force-enabled.
    $script:SampleStateBlob = [byte[]]@(
        0x43, 0x42, 0x01, 0x00, 0x0a, 0x02, 0x01, 0x00, 0x2a, 0x06, 0xcd, 0xa1,
        0x88, 0xd4, 0x06, 0x2a, 0x2b, 0x0e, 0x15, 0x43, 0x42, 0x01, 0x00, 0x10,
        0x00, 0xd0, 0x0a, 0x02, 0xc6, 0x14, 0xef, 0x9a, 0xfa, 0xaf, 0xe4, 0xb6,
        0xcb, 0xee, 0x01, 0x00, 0x00, 0x00, 0x00
    )

    # ConvertTo-* helpers return a byte[] as a single pipeline object, so compare
    # via a hex string instead of letting Pester unroll the collection.
    function script:Format-ByteHex {
        param([byte[]]$Bytes)
        return ($Bytes | ForEach-Object { $_.ToString('x2') }) -join ' '
    }

    function script:New-FakeNightLightRegistry {
        param(
            [byte[]]$SettingsBlob = $script:SampleSettingsBlob,
            [byte[]]$StateBlob = $script:SampleStateBlob
        )

        $store = @{}
        if ($SettingsBlob) { $store[$script:NightLightSettingsPath] = $SettingsBlob }
        if ($StateBlob) { $store[$script:NightLightStatePath] = $StateBlob }

        return [pscustomobject]@{
            Store  = $store
            Writes = [System.Collections.Generic.List[string]]::new()
        }
    }
}

Describe "Night Light script" -Tag "Unit" {
    It "exists and has valid PowerShell syntax" {
        $script:ScriptPath | Should -Exist

        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ScriptPath,
            [ref]$null,
            [ref]$errors
        ) | Out-Null

        $errors | Should -BeNullOrEmpty
    }

    It "is a non-template Windows script" {
        $script:ScriptPath | Should -Match '\.ps1$'
        $script:ScriptPath | Should -Not -Match '\.tmpl$'
    }

    It "contains no non-ASCII characters" {
        $content = Get-Content -Path $script:ScriptPath -Raw
        [regex]::Matches($content, '[^\x00-\x7F]').Count | Should -Be 0
    }

    It "targets the documented CloudStore registry locations" {
        $script:NightLightSettingsPath |
            Should -Be 'Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default$windows.data.bluelightreduction.settings\windows.data.bluelightreduction.settings'
        $script:NightLightStatePath |
            Should -Be 'Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current\default$windows.data.bluelightreduction.bluelightreductionstate\windows.data.bluelightreduction.bluelightreductionstate'
    }
}

Describe "Windows host detection" -Tag "Unit" {
    It "reports true on the current Windows host" {
        Test-WindowsHost | Should -BeTrue
    }

    It "does not guard on the bare `$IsWindows variable" {
        # $IsWindows is undefined in Windows PowerShell 5.1, which is the
        # interpreter chezmoi uses for .ps1 scripts. A bare guard therefore
        # skips the script on the exact platform it targets.
        $content = Get-Content -Path $script:ScriptPath -Raw
        $content | Should -Not -Match '-not\s+\$IsWindows'
    }

    It "returns true under Windows PowerShell 5.1" -Skip:(-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $output = & powershell.exe -NoLogo -NoProfile -Command @"
. '$script:ScriptPath' -SkipApply
if (Test-WindowsHost) { 'True' } else { 'False' }
"@
        $LASTEXITCODE | Should -Be 0
        ($output | Select-Object -Last 1) | Should -Be "True"
    }

    It "runs without skipping under Windows PowerShell 5.1" -Skip:(-not (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
        $output = & powershell.exe -NoLogo -NoProfile -File $script:ScriptPath -WhatIf 2>&1
        ($output -join "`n") | Should -Not -Match 'Windows-only setting'
    }
}

Describe "Bond CompactBinary primitives" -Tag "Unit" {
    It "round-trips varints" -ForEach @(
        @{ Value = [uint64]0 }
        @{ Value = [uint64]1 }
        @{ Value = [uint64]127 }
        @{ Value = [uint64]128 }
        @{ Value = [uint64]7700 }
        @{ Value = [uint64]1742540908 }
        @{ Value = [uint64]134313824772590959 }
    ) {
        $encoded = ConvertTo-BondVarint -Value $Value
        (ConvertFrom-BondVarint -Bytes $encoded -Offset 0).Value | Should -Be $Value
    }

    It "encodes 7700 as the two-byte varint 0x94 0x3C" {
        script:Format-ByteHex (ConvertTo-BondVarint -Value ([uint64]7700)) | Should -Be "94 3c"
    }

    It "round-trips zigzag values" -ForEach @(
        @{ Value = [int64]0 }
        @{ Value = [int64]1 }
        @{ Value = [int64]-1 }
        @{ Value = [int64]2790 }
        @{ Value = [int64]-3850 }
    ) {
        ConvertFrom-BondZigZag -Value (ConvertTo-BondZigZag -Value $Value) | Should -Be $Value
    }

    It "encodes 2790 K as the documented zigzag varint" {
        script:Format-ByteHex (ConvertTo-BondVarint -Value (ConvertTo-BondZigZag -Value 2790)) |
            Should -Be "cc 2b"
    }

    It "packs small field ids into a single header byte" {
        script:Format-ByteHex (ConvertTo-BondFieldHeader -FieldId 0 -BondType 0x02) | Should -Be "02"
        script:Format-ByteHex (ConvertTo-BondFieldHeader -FieldId 1 -BondType 0x0B) | Should -Be "2b"
    }

    It "spills field ids of 6 or higher into a second header byte" {
        script:Format-ByteHex (ConvertTo-BondFieldHeader -FieldId 10 -BondType 0x02) | Should -Be "c2 0a"
        script:Format-ByteHex (ConvertTo-BondFieldHeader -FieldId 20 -BondType 0x0A) | Should -Be "ca 14"
        script:Format-ByteHex (ConvertTo-BondFieldHeader -FieldId 40 -BondType 0x0F) | Should -Be "cf 28"
    }

    It "round-trips field headers" -ForEach @(
        @{ FieldId = 0; BondType = 2 }
        @{ FieldId = 5; BondType = 14 }
        @{ FieldId = 60; BondType = 10 }
        @{ FieldId = 300; BondType = 16 }
    ) {
        $header = ConvertFrom-BondFieldHeader -Bytes (ConvertTo-BondFieldHeader -FieldId $FieldId -BondType $BondType) -Offset 0
        $header.FieldId | Should -Be $FieldId
        $header.BondType | Should -Be $BondType
    }
}

Describe "CloudStore wrapper" -Tag "Unit" {
    It "extracts the inner payload and timestamp" {
        $wrapper = ConvertFrom-CloudStoreBlob -Blob $script:SampleSettingsBlob
        $wrapper.Timestamp | Should -Be ([uint64]1786909007)
        $wrapper.Payload.Length | Should -Be 0x23
        script:Format-ByteHex $wrapper.Payload[0..3] | Should -Be "43 42 01 00"
    }

    It "round-trips a blob byte for byte" {
        $wrapper = ConvertFrom-CloudStoreBlob -Blob $script:SampleSettingsBlob
        script:Format-ByteHex (ConvertTo-CloudStoreBlob -Payload $wrapper.Payload -Timestamp $wrapper.Timestamp) |
            Should -Be (script:Format-ByteHex $script:SampleSettingsBlob)
    }

    It "stamps the current time when no timestamp is supplied" {
        $before = [uint64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $blob = ConvertTo-CloudStoreBlob -Payload ([byte[]]@(0x43, 0x42, 0x01, 0x00, 0x00))
        (ConvertFrom-CloudStoreBlob -Blob $blob).Timestamp | Should -BeGreaterOrEqual $before
    }

    It "rejects a blob without the marshaled CB v1 header" {
        { ConvertFrom-CloudStoreBlob -Blob ([byte[]]::new(32)) } | Should -Throw "*marshaled CB v1 header*"
    }

    It "rejects a truncated blob" {
        { ConvertFrom-CloudStoreBlob -Blob ([byte[]]@(0x43, 0x42, 0x01, 0x00)) } | Should -Throw "*too short*"
    }
}

Describe "Night Light settings payload" -Tag "Unit" {
    BeforeAll {
        $script:SamplePayload = (ConvertFrom-CloudStoreBlob -Blob $script:SampleSettingsBlob).Payload
        $script:SampleSettings = ConvertFrom-NightLightSettingsPayload -Payload $script:SamplePayload
    }

    It "decodes the schedule mode as sunset to sunrise" {
        $script:SampleSettings.ScheduleEnabled | Should -BeTrue
        $script:SampleSettings.SetHoursMode | Should -BeFalse
    }

    It "decodes the schedule, sunset and sunrise time blocks" {
        $script:SampleSettings.StartHour | Should -Be 21
        $script:SampleSettings.StartMinute | Should -Be 0
        $script:SampleSettings.EndHour | Should -Be 7
        $script:SampleSettings.SunsetHour | Should -Be 21
        $script:SampleSettings.SunsetMinute | Should -Be 6
        $script:SampleSettings.SunriseHour | Should -Be 6
        $script:SampleSettings.SunriseMinute | Should -Be 25
    }

    It "decodes the colour temperature" {
        $script:SampleSettings.ColorTemperature | Should -Be 3850
    }

    It "round-trips the payload byte for byte" {
        script:Format-ByteHex (ConvertTo-NightLightSettingsPayload -Settings $script:SampleSettings) |
            Should -Be (script:Format-ByteHex $script:SamplePayload)
    }

    It "emits the set-hours presence flag only in set-hours mode" {
        $settings = ConvertFrom-NightLightSettingsPayload -Payload $script:SamplePayload
        $settings.SetHoursMode = $true
        $payload = ConvertTo-NightLightSettingsPayload -Settings $settings

        # C2 0A = field 10, BT_BOOL.
        $hex = ($payload | ForEach-Object { $_.ToString('x2') }) -join ''
        $hex | Should -Match 'c20a'
        (ConvertFrom-NightLightSettingsPayload -Payload $payload).SetHoursMode | Should -BeTrue
    }

    It "omits time-block fields that hold the default value" {
        script:Format-ByteHex (Write-NightLightTimeBlock -FieldId 30 -Hour 0 -Minute 0) |
            Should -Be "ca 1e 00"
    }

    It "round-trips arbitrary time blocks" -ForEach @(
        @{ Hour = 0; Minute = 0 }
        @{ Hour = 1; Minute = 15 }
        @{ Hour = 23; Minute = 59 }
        @{ Hour = 12; Minute = 0 }
    ) {
        $block = Write-NightLightTimeBlock -FieldId 20 -Hour $Hour -Minute $Minute
        # Skip the two-byte field header to read the inner struct.
        $decoded = Read-NightLightTimeBlock -Bytes $block -Offset 2
        $decoded.Hour | Should -Be $Hour
        $decoded.Minute | Should -Be $Minute
    }
}

Describe "Night Light state payload" -Tag "Unit" {
    It "decodes the enabled flag and last transition time" {
        $state = ConvertFrom-NightLightStatePayload -Payload (ConvertFrom-CloudStoreBlob -Blob $script:SampleStateBlob).Payload
        $state.Enabled | Should -BeTrue
        $state.LastTransitionFileTime | Should -Be ([uint64]134313824772590959)
    }

    It "round-trips the payload byte for byte" {
        $payload = (ConvertFrom-CloudStoreBlob -Blob $script:SampleStateBlob).Payload
        $state = ConvertFrom-NightLightStatePayload -Payload $payload
        script:Format-ByteHex (ConvertTo-NightLightStatePayload -Enabled $state.Enabled -FileTime $state.LastTransitionFileTime) |
            Should -Be (script:Format-ByteHex $payload)
    }

    It "omits field 0 when Night Light is off" {
        $payload = ConvertTo-NightLightStatePayload -Enabled $false -FileTime ([uint64]134313824772590959)
        (ConvertFrom-NightLightStatePayload -Payload $payload).Enabled | Should -BeFalse
        $payload.Length | Should -BeLessThan (ConvertTo-NightLightStatePayload -Enabled $true -FileTime ([uint64]134313824772590959)).Length
    }
}

Describe "Strength conversion" -Tag "Unit" {
    It "maps strength to colour temperature" -ForEach @(
        @{ Strength = 0; Kelvin = 6500 }
        @{ Strength = 50; Kelvin = 3850 }
        @{ Strength = 60; Kelvin = 3320 }
        @{ Strength = 100; Kelvin = 1200 }
    ) {
        ConvertTo-NightLightColorTemperature -Strength $Strength | Should -Be $Kelvin
        ConvertFrom-NightLightColorTemperature -Kelvin $Kelvin | Should -Be $Strength
    }

    It "rejects a strength outside 0-100" {
        { ConvertTo-NightLightColorTemperature -Strength 101 } | Should -Throw
    }
}

Describe "Default settings" -Tag "Unit" {
    It "describes a sunset-to-sunrise schedule with no cached solar times" {
        $defaults = Get-NightLightDefaultSetting
        $defaults.ScheduleEnabled | Should -BeTrue
        $defaults.SetHoursMode | Should -BeFalse
        $defaults.SunsetHour | Should -Be 0
        $defaults.SunriseHour | Should -Be 0
    }

    It "round-trips through the payload codec" {
        $defaults = Get-NightLightDefaultSetting
        $payload = ConvertTo-NightLightSettingsPayload -Settings $defaults
        $decoded = ConvertFrom-NightLightSettingsPayload -Payload $payload
        $decoded.StartHour | Should -Be $defaults.StartHour
        $decoded.EndHour | Should -Be $defaults.EndHour
        $decoded.ScheduleEnabled | Should -BeTrue
    }
}

Describe "Night window detection" -Tag "Unit" {
    BeforeAll {
        $script:WindowSettings = [pscustomobject]@{
            SunsetHour = 21; SunsetMinute = 6; SunriseHour = 6; SunriseMinute = 25
        }
    }

    It "treats times inside the sunset-to-sunrise window as night" -ForEach @(
        @{ Time = "21:06" }
        @{ Time = "23:59" }
        @{ Time = "00:00" }
        @{ Time = "06:24" }
    ) {
        Test-NightLightWithinNightWindow -Settings $script:WindowSettings -Now ([DateTime]::Parse($Time)) |
            Should -BeTrue
    }

    It "treats daytime as outside the window" -ForEach @(
        @{ Time = "06:25" }
        @{ Time = "12:00" }
        @{ Time = "21:05" }
    ) {
        Test-NightLightWithinNightWindow -Settings $script:WindowSettings -Now ([DateTime]::Parse($Time)) |
            Should -BeFalse
    }

    It "returns false when sunset and sunrise are unknown" {
        $settings = [pscustomobject]@{ SunsetHour = 0; SunsetMinute = 0; SunriseHour = 0; SunriseMinute = 0 }
        Test-NightLightWithinNightWindow -Settings $settings -Now ([DateTime]::Parse("23:00")) | Should -BeFalse
    }
}

Describe "Set-NightLightConfiguration" -Tag "Unit" {
    It "reports no change when the desired configuration is already applied" {
        $fake = script:New-FakeNightLightRegistry
        $results = Set-NightLightConfiguration -Strength 50 -Now ([DateTime]::Parse("22:00")) `
            -GetRegistryValue { param([string]$Path) $fake.Store[$Path] } `
            -SetRegistryValue { param([string]$Path, [byte[]]$Value) $fake.Store[$Path] = $Value; $fake.Writes.Add($Path) }

        @($results | Where-Object { $_.Changed }).Count | Should -Be 0
        $fake.Writes.Count | Should -Be 0
    }

    It "writes the requested strength while preserving sunset and sunrise times" {
        $fake = script:New-FakeNightLightRegistry
        Set-NightLightConfiguration -Strength 80 -Now ([DateTime]::Parse("22:00")) `
            -GetRegistryValue { param([string]$Path) $fake.Store[$Path] } `
            -SetRegistryValue { param([string]$Path, [byte[]]$Value) $fake.Store[$Path] = $Value; $fake.Writes.Add($Path) } | Out-Null

        $written = ConvertFrom-NightLightSettingsPayload -Payload (ConvertFrom-CloudStoreBlob -Blob $fake.Store[$script:NightLightSettingsPath]).Payload
        $written.ColorTemperature | Should -Be 2260
        $written.ScheduleEnabled | Should -BeTrue
        $written.SetHoursMode | Should -BeFalse
        $written.SunsetHour | Should -Be 21
        $written.SunriseMinute | Should -Be 25
    }

    It "switches set-hours mode back to sunset to sunrise" {
        $settings = ConvertFrom-NightLightSettingsPayload -Payload (ConvertFrom-CloudStoreBlob -Blob $script:SampleSettingsBlob).Payload
        $settings.SetHoursMode = $true
        $blob = ConvertTo-CloudStoreBlob -Payload (ConvertTo-NightLightSettingsPayload -Settings $settings)

        $fake = script:New-FakeNightLightRegistry -SettingsBlob $blob
        Set-NightLightConfiguration -Strength 50 -Now ([DateTime]::Parse("22:00")) `
            -GetRegistryValue { param([string]$Path) $fake.Store[$Path] } `
            -SetRegistryValue { param([string]$Path, [byte[]]$Value) $fake.Store[$Path] = $Value; $fake.Writes.Add($Path) } | Out-Null

        $written = ConvertFrom-NightLightSettingsPayload -Payload (ConvertFrom-CloudStoreBlob -Blob $fake.Store[$script:NightLightSettingsPath]).Payload
        $written.SetHoursMode | Should -BeFalse
    }

    It "turns Night Light off outside the sunset-to-sunrise window" {
        $fake = script:New-FakeNightLightRegistry
        Set-NightLightConfiguration -Strength 50 -Now ([DateTime]::Parse("12:00")) `
            -GetRegistryValue { param([string]$Path) $fake.Store[$Path] } `
            -SetRegistryValue { param([string]$Path, [byte[]]$Value) $fake.Store[$Path] = $Value; $fake.Writes.Add($Path) } | Out-Null

        $state = ConvertFrom-NightLightStatePayload -Payload (ConvertFrom-CloudStoreBlob -Blob $fake.Store[$script:NightLightStatePath]).Payload
        $state.Enabled | Should -BeFalse
    }

    It "turns Night Light on inside the sunset-to-sunrise window" {
        $fake = script:New-FakeNightLightRegistry -StateBlob (ConvertTo-CloudStoreBlob -Payload (ConvertTo-NightLightStatePayload -Enabled $false))
        Set-NightLightConfiguration -Strength 50 -Now ([DateTime]::Parse("23:30")) `
            -GetRegistryValue { param([string]$Path) $fake.Store[$Path] } `
            -SetRegistryValue { param([string]$Path, [byte[]]$Value) $fake.Store[$Path] = $Value; $fake.Writes.Add($Path) } | Out-Null

        $state = ConvertFrom-NightLightStatePayload -Payload (ConvertFrom-CloudStoreBlob -Blob $fake.Store[$script:NightLightStatePath]).Payload
        $state.Enabled | Should -BeTrue
    }

    It "does not write anything when -WhatIf is supplied" {
        $fake = script:New-FakeNightLightRegistry
        $results = Set-NightLightConfiguration -Strength 90 -Now ([DateTime]::Parse("22:00")) -WhatIf `
            -GetRegistryValue { param([string]$Path) $fake.Store[$Path] } `
            -SetRegistryValue { param([string]$Path, [byte[]]$Value) $fake.Store[$Path] = $Value; $fake.Writes.Add($Path) }

        $fake.Writes.Count | Should -Be 0
        @($results | Where-Object { $_.Status -eq "WhatIf" }).Count | Should -BeGreaterThan 0
    }

    It "creates the settings from scratch when Night Light was never initialised" {
        $fake = script:New-FakeNightLightRegistry -SettingsBlob $null -StateBlob $null
        $results = Set-NightLightConfiguration -Strength 50 -Now ([DateTime]::Parse("22:00")) `
            -GetRegistryValue { param([string]$Path) $fake.Store[$Path] } `
            -SetRegistryValue { param([string]$Path, [byte[]]$Value) $fake.Store[$Path] = $Value; $fake.Writes.Add($Path) }

        @($results | Where-Object { $_.Changed }).Count | Should -BeGreaterThan 0
        $fake.Store.ContainsKey($script:NightLightSettingsPath) | Should -BeTrue

        $written = ConvertFrom-NightLightSettingsPayload -Payload (ConvertFrom-CloudStoreBlob -Blob $fake.Store[$script:NightLightSettingsPath]).Payload
        $written.ScheduleEnabled | Should -BeTrue
        $written.SetHoursMode | Should -BeFalse
        $written.ColorTemperature | Should -Be 3850
    }

    It "leaves sunset and sunrise unset when creating from scratch" {
        # Windows computes these from the machine location; seeding them would
        # only risk storing wrong times.
        $fake = script:New-FakeNightLightRegistry -SettingsBlob $null -StateBlob $null
        Set-NightLightConfiguration -Strength 50 -Now ([DateTime]::Parse("22:00")) `
            -GetRegistryValue { param([string]$Path) $fake.Store[$Path] } `
            -SetRegistryValue { param([string]$Path, [byte[]]$Value) $fake.Store[$Path] = $Value; $fake.Writes.Add($Path) } | Out-Null

        $written = ConvertFrom-NightLightSettingsPayload -Payload (ConvertFrom-CloudStoreBlob -Blob $fake.Store[$script:NightLightSettingsPath]).Payload
        $written.SunsetHour | Should -Be 0
        $written.SunriseHour | Should -Be 0

        # With no solar window known, Night Light must not be forced on.
        $state = ConvertFrom-NightLightStatePayload -Payload (ConvertFrom-CloudStoreBlob -Blob $fake.Store[$script:NightLightStatePath]).Payload
        $state.Enabled | Should -BeFalse
    }

    It "does not throw on a host where Night Light was never initialised" {
        $fake = script:New-FakeNightLightRegistry -SettingsBlob $null -StateBlob $null
        {
            Set-NightLightConfiguration -Strength 50 `
                -GetRegistryValue { param([string]$Path) $fake.Store[$Path] } `
                -SetRegistryValue { param([string]$Path, [byte[]]$Value) $fake.Store[$Path] = $Value }
        } | Should -Not -Throw
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAw23iaJQbERbI2
# bg8TiZU3+EVu1SEstGlvu6/YtdDkaqCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCCN0oo9seU9gHYM07efzYF7i87oobOU2eCpxivEEuM28TANBgkqhkiG
# 9w0BAQEFAASCAgBvugJYltHwErtMagTVL7By0aNtENPJU1rSFp1Bowfu5pOBN/at
# D9+qsHRcY7M08IUsBT98GEaOIW+cLOPVa/XUd3nnzRHdbX6qSldQU/GrDb59FTx+
# YdXa7g+ZJEBGq+fFzPmXUfuByuTNkSt+lUHcn0mpA7M6A0SE0yKG+VyDw5uiRRWo
# rHBhZlGKALMT7mY0T/h1Yi2r9ysQ7sdUWinEjMm9E4GgkrKkALnrZ/uaE0JNutpT
# jdbncpscb2w+8pokRzYEspJYpiKtxNAN9nk/7eh44qe7CoI5NVnRCn45m9Bb44oN
# F205rWw23b9CYwWr5Twwe69ss7pJSHANJcqpbTJR8uDcq11yOHi6GNAhLqRZQZ4U
# mb9dtLC+ct/sgunyu+A/Ma/MhsfhgtO70mLaMxGjzHi+hX/bLD+abI3mM41F8UVf
# UotHXB6346LemHV9JHE9ACYt+4mRh66dB0N59AKDRExrK1gFJza1vgdyYO9fJzb6
# M2wq5ZnB+MWLkPnIwj3zYFILJCSeoiyGDSUc28RYaO50BXUDxulY0995KTOqZunB
# WjAthVUJFmlyRj5Lq31QxXN+GSwFLqRD9fxCdXGiniPvLe08Sq0rnpF2IfpqiNmo
# 77jaP+pMZguM0HY9yXn1HsZDjJ3+KeLbakPx4VeYFnoErSP8lgJ8G6ibV6GCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA4MTYyMDU2NDBaMC8GCSqGSIb3DQEJBDEi
# BCChDWP6VWvvxxs3Q6UF0x7oMazoKSTJe6ZUFmYpxoCQ6jANBgkqhkiG9w0BAQEF
# AASCAgBlyJ36zGHR88QLQ9ulBC9ZMhSPFO81newMh7YL6s14UDL+cqEi8Oibh5GB
# p1BUyGMch1gxUf6+f11adG7lVwwtvYlbBpk8ZjxRjJuqyyh/Wz0TH9JI7DMpcpNi
# tmQhsm//sgOPi+fh1/QpBJYB2u7I7hTLH1T2+OQ+Xbi6o3NcT7rLGKj4zO1bRbRG
# g5qCFrzcyLUE8inBK+kfrtBLr2SuedK+XRTeItGZ9OgzeF3rnsL3TnJAKOb1gVuw
# hD46SsKQ703kK6mn5hmk6InBLxNt/FzldPmjOxah9VqAUULuzEArzqOXerDKhpAh
# jy18qkQScDIwcCQb9p1Yk7InwVk9ev/D/cnQwv84bz0CDiriQawQODM4PaieO8sp
# Y+ISGfP6h2QXuH6ypdH0plQNZmMYrZ7twITe9eKiXfuzoK0MC5+/pi6SzPnmBPl+
# kcEjUKtpYj91qflyKiR1lUEiSjmgCrT/uXitXJ1IJHUwDiytndw5lLhSwnzOyfKS
# Rxkt3NtqgEHitdomF0oJqtkGN/uyqJHxN93zhgUifAREu9/EsZZSu3CvBh3uGkc0
# +QtHAlcBIomvjEQm2pwDJ2mAJqys444dFNCTXsdD/hsA0haFxewjhNKFGTNv+iBo
# ILefDetGsb8NRgOI0socPCffudlNWyQWFiQinMQ4I4RP+yV0yA==
# SIG # End signature block
