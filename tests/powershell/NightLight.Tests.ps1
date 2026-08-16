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

    It "fails with actionable guidance when Night Light was never initialised" {
        $fake = script:New-FakeNightLightRegistry -SettingsBlob $null
        {
            Set-NightLightConfiguration -Strength 50 `
                -GetRegistryValue { param([string]$Path) $fake.Store[$Path] } `
                -SetRegistryValue { param([string]$Path, [byte[]]$Value) $fake.Store[$Path] = $Value }
        } | Should -Throw "*not initialised*"
    }
}
