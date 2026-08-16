#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Configures Windows Night Light for the invoking user.

.DESCRIPTION
    Night Light has no supported API. Windows persists it as two REG_BINARY
    CloudStore blobs encoded with Microsoft Bond CompactBinary v1:

      HKCU\...\CloudStore\Store\DefaultAccount\Current\
        default$windows.data.bluelightreduction.settings\...        (schedule + strength)
        default$windows.data.bluelightreduction.bluelightreductionstate\...  (on/off)

    This script decodes the existing blobs, applies the desired schedule mode
    and strength, and writes them back. Sunset/sunrise times computed by
    Windows are preserved so the shell does not have to recompute them.

    Format reference (reverse-engineered, community-documented):
    https://github.com/kvnxiao/win-nightlight-cli/blob/main/docs/nightlight-registry-format.md

.PARAMETER Strength
    Night Light strength as shown in Settings (0-100). Maps linearly onto the
    stored colour temperature: 0 => 6500 K (no effect), 100 => 1200 K.

.PARAMETER SkipApply
    Dot-source the functions without applying anything (used by tests).
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    "PSAvoidUsingWriteHost",
    "",
    Justification = "Matches existing chezmoi setup script progress output."
)]
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateRange(0, 100)]
    [int]$Strength = 50,

    [switch]$SkipApply
)

$ErrorActionPreference = "Stop"

$script:NightLightStoreRoot = "Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\DefaultAccount\Current"
$script:NightLightSettingsPath = "$script:NightLightStoreRoot\default`$windows.data.bluelightreduction.settings\windows.data.bluelightreduction.settings"
$script:NightLightStatePath = "$script:NightLightStoreRoot\default`$windows.data.bluelightreduction.bluelightreductionstate\windows.data.bluelightreduction.bluelightreductionstate"

# Colour temperature bounds of the Settings strength slider.
$script:NightLightMaxKelvin = 6500
$script:NightLightMinKelvin = 1200

#region Bond CompactBinary v1 primitives

function ConvertTo-BondVarint {
    [OutputType([byte[]])]
    param([Parameter(Mandatory)][uint64]$Value)

    $bytes = [System.Collections.Generic.List[byte]]::new()
    do {
        $chunk = [byte]($Value -band 0x7F)
        $Value = $Value -shr 7
        if ($Value -ne 0) {
            $chunk = [byte]($chunk -bor 0x80)
        }
        $bytes.Add($chunk)
    } while ($Value -ne 0)

    return , $bytes.ToArray()
}

function ConvertFrom-BondVarint {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][int]$Offset
    )

    [uint64]$value = 0
    $shift = 0
    $index = $Offset

    while ($true) {
        if ($index -ge $Bytes.Length) {
            throw "Truncated varint at offset $Offset."
        }

        $current = $Bytes[$index]
        $index++
        $value = $value -bor ([uint64]($current -band 0x7F) -shl $shift)
        if (($current -band 0x80) -eq 0) {
            break
        }

        $shift += 7
        if ($shift -gt 63) {
            throw "Varint at offset $Offset exceeds 64 bits."
        }
    }

    return [pscustomobject]@{ Value = $value; NextOffset = $index }
}

function ConvertTo-BondZigZag {
    [OutputType([uint64])]
    param([Parameter(Mandatory)][int64]$Value)

    $encoded = ($Value -shl 1) -bxor ($Value -shr 63)
    return [BitConverter]::ToUInt64([BitConverter]::GetBytes($encoded), 0)
}

function ConvertFrom-BondZigZag {
    [OutputType([int64])]
    param([Parameter(Mandatory)][uint64]$Value)

    $half = [int64]($Value -shr 1)
    if (($Value -band 1) -eq 1) {
        return -($half + 1)
    }

    return $half
}

<#
    Field headers pack the Bond type into the low 5 bits and the field id into
    the high 3 bits. Ids >= 6 spill into one (id <= 255) or two extra bytes.
#>
function ConvertTo-BondFieldHeader {
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)][int]$FieldId,
        [Parameter(Mandatory)][int]$BondType
    )

    if ($FieldId -lt 6) {
        return , [byte[]]@([byte](($FieldId -shl 5) -bor $BondType))
    }

    if ($FieldId -le 255) {
        return , [byte[]]@([byte](0xC0 -bor $BondType), [byte]$FieldId)
    }

    return , [byte[]]@(
        [byte](0xE0 -bor $BondType),
        [byte]($FieldId -band 0xFF),
        [byte](($FieldId -shr 8) -band 0xFF)
    )
}

function ConvertFrom-BondFieldHeader {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][int]$Offset
    )

    $raw = $Bytes[$Offset]
    $bondType = $raw -band 0x1F
    $idBits = ($raw -shr 5) -band 0x07

    switch ($idBits) {
        6 {
            return [pscustomobject]@{ FieldId = [int]$Bytes[$Offset + 1]; BondType = $bondType; NextOffset = $Offset + 2 }
        }
        7 {
            $id = [int]$Bytes[$Offset + 1] -bor ([int]$Bytes[$Offset + 2] -shl 8)
            return [pscustomobject]@{ FieldId = $id; BondType = $bondType; NextOffset = $Offset + 3 }
        }
        default {
            return [pscustomobject]@{ FieldId = $idBits; BondType = $bondType; NextOffset = $Offset + 1 }
        }
    }
}

#endregion

#region CloudStore wrapper

function ConvertFrom-CloudStoreBlob {
    <#
        .SYNOPSIS
            Extracts the inner Bond payload from a CloudStore wrapper blob.
    #>
    param([Parameter(Mandatory)][byte[]]$Blob)

    if ($Blob.Length -lt 20) {
        throw "CloudStore blob is too short ($($Blob.Length) bytes)."
    }

    # 43 42 01 00 = marshaled CB v1 header; 0A 02 01 00 = metadata struct;
    # 2A 06 <varint timestamp> = payload container with Unix timestamp.
    if ($Blob[0] -ne 0x43 -or $Blob[1] -ne 0x42 -or $Blob[2] -ne 0x01 -or $Blob[3] -ne 0x00) {
        throw "CloudStore blob does not start with the marshaled CB v1 header."
    }

    $offset = 4
    if ($Blob[$offset] -ne 0x0A -or $Blob[$offset + 1] -ne 0x02 -or $Blob[$offset + 3] -ne 0x00) {
        throw "Unexpected CloudStore metadata struct."
    }
    $offset += 4

    if ($Blob[$offset] -ne 0x2A -or $Blob[$offset + 1] -ne 0x06) {
        throw "Unexpected CloudStore payload container."
    }
    $offset += 2

    $timestamp = ConvertFrom-BondVarint -Bytes $Blob -Offset $offset
    $offset = $timestamp.NextOffset

    if ($Blob[$offset] -ne 0x2A -or $Blob[$offset + 1] -ne 0x2B -or $Blob[$offset + 2] -ne 0x0E) {
        throw "Unexpected CloudStore data wrapper."
    }
    $offset += 3

    $count = ConvertFrom-BondVarint -Bytes $Blob -Offset $offset
    $offset = $count.NextOffset
    $length = [int]$count.Value

    if (($offset + $length) -gt $Blob.Length) {
        throw "CloudStore payload length ($length) exceeds blob size."
    }

    $payload = [byte[]]::new($length)
    [Array]::Copy($Blob, $offset, $payload, 0, $length)

    return [pscustomobject]@{
        Timestamp = $timestamp.Value
        Payload   = $payload
    }
}

function ConvertTo-CloudStoreBlob {
    <#
        .SYNOPSIS
            Wraps an inner Bond payload in the CloudStore envelope.
    #>
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)][byte[]]$Payload,
        [uint64]$Timestamp = [uint64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    )

    $bytes = [System.Collections.Generic.List[byte]]::new()
    $bytes.AddRange([byte[]]@(0x43, 0x42, 0x01, 0x00))
    $bytes.AddRange([byte[]]@(0x0A, 0x02, 0x01, 0x00))
    $bytes.AddRange([byte[]]@(0x2A, 0x06))
    $bytes.AddRange((ConvertTo-BondVarint -Value $Timestamp))
    $bytes.AddRange([byte[]]@(0x2A, 0x2B, 0x0E))
    $bytes.AddRange((ConvertTo-BondVarint -Value ([uint64]$Payload.Length)))
    $bytes.AddRange($Payload)
    $bytes.AddRange([byte[]]@(0x00, 0x00, 0x00))

    return , $bytes.ToArray()
}

#endregion

#region Night Light schema

function ConvertTo-NightLightColorTemperature {
    <#
        .SYNOPSIS
            Converts a 0-100 Settings strength value to Kelvin.
    #>
    [OutputType([int])]
    param([Parameter(Mandatory)][ValidateRange(0, 100)][int]$Strength)

    $span = $script:NightLightMaxKelvin - $script:NightLightMinKelvin
    return [int]($script:NightLightMaxKelvin - [Math]::Round($span * $Strength / 100.0))
}

function ConvertFrom-NightLightColorTemperature {
    [OutputType([int])]
    param([Parameter(Mandatory)][int]$Kelvin)

    $span = $script:NightLightMaxKelvin - $script:NightLightMinKelvin
    return [int][Math]::Round(($script:NightLightMaxKelvin - $Kelvin) * 100.0 / $span)
}

function Read-NightLightTimeBlock {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][int]$Offset
    )

    $hour = 0
    $minute = 0
    $index = $Offset

    while ($index -lt $Bytes.Length -and $Bytes[$index] -ne 0x00) {
        $header = ConvertFrom-BondFieldHeader -Bytes $Bytes -Offset $index
        $index = $header.NextOffset

        # BT_INT8 is stored as a single raw byte, not as a zigzag varint.
        $decoded = [int][sbyte]$Bytes[$index]
        $index++

        switch ($header.FieldId) {
            0 { $hour = $decoded }
            1 { $minute = $decoded }
        }
    }

    return [pscustomobject]@{
        Hour       = $hour
        Minute     = $minute
        NextOffset = $index + 1
    }
}

function Write-NightLightTimeBlock {
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)][int]$FieldId,
        [Parameter(Mandatory)][int]$Hour,
        [Parameter(Mandatory)][int]$Minute
    )

    $bytes = [System.Collections.Generic.List[byte]]::new()
    $bytes.AddRange((ConvertTo-BondFieldHeader -FieldId $FieldId -BondType 0x0A))

    # Bond omits fields that hold the default value (0).
    if ($Hour -ne 0) {
        $bytes.AddRange((ConvertTo-BondFieldHeader -FieldId 0 -BondType 0x0E))
        $bytes.Add([byte]$Hour)
    }
    if ($Minute -ne 0) {
        $bytes.AddRange((ConvertTo-BondFieldHeader -FieldId 1 -BondType 0x0E))
        $bytes.Add([byte]$Minute)
    }

    $bytes.Add(0x00)
    return , $bytes.ToArray()
}

function ConvertFrom-NightLightSettingsPayload {
    param([Parameter(Mandatory)][byte[]]$Payload)

    $settings = [pscustomobject]@{
        ScheduleEnabled  = $false
        SetHoursMode     = $false
        StartHour        = 0
        StartMinute      = 0
        EndHour          = 0
        EndMinute        = 0
        ColorTemperature = $script:NightLightMaxKelvin
        SunsetHour       = 0
        SunsetMinute     = 0
        SunriseHour      = 0
        SunriseMinute    = 0
    }

    $offset = 4
    while ($offset -lt $Payload.Length -and $Payload[$offset] -ne 0x00) {
        $header = ConvertFrom-BondFieldHeader -Bytes $Payload -Offset $offset
        $offset = $header.NextOffset

        switch ($header.FieldId) {
            0 {
                $settings.ScheduleEnabled = $Payload[$offset] -ne 0x00
                $offset++
            }
            10 {
                $settings.SetHoursMode = $true
                $offset++
            }
            20 {
                $block = Read-NightLightTimeBlock -Bytes $Payload -Offset $offset
                $settings.StartHour = $block.Hour
                $settings.StartMinute = $block.Minute
                $offset = $block.NextOffset
            }
            30 {
                $block = Read-NightLightTimeBlock -Bytes $Payload -Offset $offset
                $settings.EndHour = $block.Hour
                $settings.EndMinute = $block.Minute
                $offset = $block.NextOffset
            }
            40 {
                $value = ConvertFrom-BondVarint -Bytes $Payload -Offset $offset
                $settings.ColorTemperature = [int](ConvertFrom-BondZigZag -Value $value.Value)
                $offset = $value.NextOffset
            }
            50 {
                $block = Read-NightLightTimeBlock -Bytes $Payload -Offset $offset
                $settings.SunsetHour = $block.Hour
                $settings.SunsetMinute = $block.Minute
                $offset = $block.NextOffset
            }
            60 {
                $block = Read-NightLightTimeBlock -Bytes $Payload -Offset $offset
                $settings.SunriseHour = $block.Hour
                $settings.SunriseMinute = $block.Minute
                $offset = $block.NextOffset
            }
            default {
                throw "Unknown Night Light settings field id $($header.FieldId)."
            }
        }
    }

    return $settings
}

function ConvertTo-NightLightSettingsPayload {
    [OutputType([byte[]])]
    param([Parameter(Mandatory)][psobject]$Settings)

    $bytes = [System.Collections.Generic.List[byte]]::new()
    $bytes.AddRange([byte[]]@(0x43, 0x42, 0x01, 0x00))

    if ($Settings.ScheduleEnabled) {
        $bytes.AddRange([byte[]]@(0x02, 0x01))
    }

    # Field 10 is a presence flag: present => "Set hours", absent => solar.
    if ($Settings.SetHoursMode) {
        $bytes.AddRange((ConvertTo-BondFieldHeader -FieldId 10 -BondType 0x02))
        $bytes.Add(0x00)
    }

    $bytes.AddRange((Write-NightLightTimeBlock -FieldId 20 -Hour $Settings.StartHour -Minute $Settings.StartMinute))
    $bytes.AddRange((Write-NightLightTimeBlock -FieldId 30 -Hour $Settings.EndHour -Minute $Settings.EndMinute))

    $bytes.AddRange((ConvertTo-BondFieldHeader -FieldId 40 -BondType 0x0F))
    $bytes.AddRange((ConvertTo-BondVarint -Value (ConvertTo-BondZigZag -Value $Settings.ColorTemperature)))

    $bytes.AddRange((Write-NightLightTimeBlock -FieldId 50 -Hour $Settings.SunsetHour -Minute $Settings.SunsetMinute))
    $bytes.AddRange((Write-NightLightTimeBlock -FieldId 60 -Hour $Settings.SunriseHour -Minute $Settings.SunriseMinute))

    $bytes.Add(0x00)
    return , $bytes.ToArray()
}

function ConvertFrom-NightLightStatePayload {
    param([Parameter(Mandatory)][byte[]]$Payload)

    $state = [pscustomobject]@{
        Enabled              = $false
        LastTransitionFileTime = [uint64]0
    }

    $offset = 4
    while ($offset -lt $Payload.Length -and $Payload[$offset] -ne 0x00) {
        $header = ConvertFrom-BondFieldHeader -Bytes $Payload -Offset $offset
        $offset = $header.NextOffset
        $value = ConvertFrom-BondVarint -Bytes $Payload -Offset $offset
        $offset = $value.NextOffset

        switch ($header.FieldId) {
            0 { $state.Enabled = $true }
            10 { }
            20 { $state.LastTransitionFileTime = $value.Value }
            default { throw "Unknown Night Light state field id $($header.FieldId)." }
        }
    }

    return $state
}

function ConvertTo-NightLightStatePayload {
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory)][bool]$Enabled,
        [uint64]$FileTime = 0
    )

    if ($FileTime -eq 0) {
        $FileTime = [uint64][DateTime]::UtcNow.ToFileTimeUtc()
    }

    $bytes = [System.Collections.Generic.List[byte]]::new()
    $bytes.AddRange([byte[]]@(0x43, 0x42, 0x01, 0x00))

    # Field 0 is a presence flag: present => forced on, absent => follow schedule.
    if ($Enabled) {
        $bytes.AddRange((ConvertTo-BondFieldHeader -FieldId 0 -BondType 0x10))
        $bytes.Add(0x00)
    }

    $bytes.AddRange((ConvertTo-BondFieldHeader -FieldId 10 -BondType 0x10))
    $bytes.AddRange((ConvertTo-BondVarint -Value (ConvertTo-BondZigZag -Value 1)))

    $bytes.AddRange((ConvertTo-BondFieldHeader -FieldId 20 -BondType 0x06))
    $bytes.AddRange((ConvertTo-BondVarint -Value $FileTime))

    $bytes.Add(0x00)
    return , $bytes.ToArray()
}

function Test-NightLightWithinNightWindow {
    <#
        .SYNOPSIS
            True when the reference time falls in the sunset..sunrise window.
    #>
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][psobject]$Settings,
        [DateTime]$Now = (Get-Date)
    )

    $current = $Now.Hour * 60 + $Now.Minute
    $sunset = $Settings.SunsetHour * 60 + $Settings.SunsetMinute
    $sunrise = $Settings.SunriseHour * 60 + $Settings.SunriseMinute

    if ($sunset -eq $sunrise) {
        return $false
    }

    if ($sunset -gt $sunrise) {
        # Window crosses midnight, which is the normal case.
        return ($current -ge $sunset) -or ($current -lt $sunrise)
    }

    return ($current -ge $sunset) -and ($current -lt $sunrise)
}

#endregion

function Set-NightLightConfiguration {
    <#
        .SYNOPSIS
            Applies the desired Night Light schedule and strength.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateRange(0, 100)]
        [int]$Strength = 50,

        [DateTime]$Now = (Get-Date),

        [scriptblock]$GetRegistryValue = {
            param([string]$Path)

            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path, $false)
            try {
                if (-not $key) {
                    return $null
                }
                return $key.GetValue("Data", $null)
            }
            finally {
                if ($key) { $key.Dispose() }
            }
        },

        [scriptblock]$SetRegistryValue = {
            param([string]$Path, [byte[]]$Value)

            $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($Path)
            try {
                if (-not $key) {
                    throw "Unable to open or create HKCU\$Path."
                }
                $key.SetValue("Data", $Value, [Microsoft.Win32.RegistryValueKind]::Binary)
            }
            finally {
                if ($key) { $key.Dispose() }
            }
        }
    )

    $results = @()
    $desiredKelvin = ConvertTo-NightLightColorTemperature -Strength $Strength

    $settingsBlob = & $GetRegistryValue -Path $script:NightLightSettingsPath
    if (-not $settingsBlob) {
        throw "Night Light settings are not initialised. Open Settings > System > Display > Night light once, then re-run."
    }

    $settings = ConvertFrom-NightLightSettingsPayload -Payload (ConvertFrom-CloudStoreBlob -Blob ([byte[]]$settingsBlob)).Payload
    $settingsCorrect = $settings.ScheduleEnabled -and -not $settings.SetHoursMode -and $settings.ColorTemperature -eq $desiredKelvin

    if ($settingsCorrect) {
        $results += [pscustomobject]@{ Setting = "Schedule and strength"; Status = "AlreadySet"; Changed = $false }
    }
    elseif ($PSCmdlet.ShouldProcess("HKCU\$script:NightLightSettingsPath", "Set sunset-to-sunrise schedule at strength $Strength ($desiredKelvin K)")) {
        $settings.ScheduleEnabled = $true
        $settings.SetHoursMode = $false
        $settings.ColorTemperature = $desiredKelvin

        & $SetRegistryValue -Path $script:NightLightSettingsPath -Value (ConvertTo-CloudStoreBlob -Payload (ConvertTo-NightLightSettingsPayload -Settings $settings))
        $results += [pscustomobject]@{ Setting = "Schedule and strength"; Status = "Updated"; Changed = $true }
    }
    else {
        $results += [pscustomobject]@{ Setting = "Schedule and strength"; Status = "WhatIf"; Changed = $false }
    }

    $desiredState = Test-NightLightWithinNightWindow -Settings $settings -Now $Now
    $stateBlob = & $GetRegistryValue -Path $script:NightLightStatePath
    $currentState = $false
    if ($stateBlob) {
        $currentState = (ConvertFrom-NightLightStatePayload -Payload (ConvertFrom-CloudStoreBlob -Blob ([byte[]]$stateBlob)).Payload).Enabled
    }

    if ($stateBlob -and $currentState -eq $desiredState) {
        $results += [pscustomobject]@{ Setting = "Current state"; Status = "AlreadySet"; Changed = $false }
    }
    elseif ($PSCmdlet.ShouldProcess("HKCU\$script:NightLightStatePath", "Set Night Light to $(if ($desiredState) { 'on' } else { 'off' })")) {
        & $SetRegistryValue -Path $script:NightLightStatePath -Value (ConvertTo-CloudStoreBlob -Payload (ConvertTo-NightLightStatePayload -Enabled $desiredState))
        $results += [pscustomobject]@{ Setting = "Current state"; Status = "Updated"; Changed = $true }
    }
    else {
        $results += [pscustomobject]@{ Setting = "Current state"; Status = "WhatIf"; Changed = $false }
    }

    return $results
}

if (-not $SkipApply) {
    if (-not $IsWindows) {
        Write-Host "[SKIP] Night Light is a Windows-only setting." -ForegroundColor Yellow
        return
    }

    Write-Host "Applying Night Light configuration (sunset to sunrise, strength $Strength)..." -ForegroundColor Cyan
    $results = @(Set-NightLightConfiguration -Strength $Strength -WhatIf:$WhatIfPreference)
    $updatedCount = @($results | Where-Object { $_.Changed }).Count
    Write-Host "[OK] Night Light configured ($updatedCount setting(s) changed)." -ForegroundColor Green
}
