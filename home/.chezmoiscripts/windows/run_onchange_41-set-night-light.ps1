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

function Test-WindowsHost {
    <#
        .SYNOPSIS
            True when running on Windows, under either PowerShell edition.

        .DESCRIPTION
            $IsWindows only exists in PowerShell Core. Chezmoi runs .ps1 scripts
            with `powershell` (Windows PowerShell 5.1, PSEdition "Desktop"),
            where the variable is undefined, so a guard that negates it directly
            is always true and skips the script on the very platform it targets.
            Desktop edition only ships on Windows, so treat it as a match.
    #>
    [OutputType([bool])]
    param()

    if ($PSVersionTable.PSEdition -eq "Desktop") {
        return $true
    }

    return [bool](Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue)
}

function Get-NightLightDefaultSetting {
    <#
        .SYNOPSIS
            Baseline settings for a machine where Night Light was never used.

        .DESCRIPTION
            Sunset and sunrise are left at their defaults (00:00). Windows
            recomputes them from the machine location and writes them back, so
            seeding them here would only risk storing wrong times.
    #>
    [OutputType([psobject])]
    param()

    return [pscustomobject]@{
        ScheduleEnabled  = $true
        SetHoursMode     = $false
        StartHour        = 21
        StartMinute      = 0
        EndHour          = 7
        EndMinute        = 0
        ColorTemperature = $script:NightLightMaxKelvin
        SunsetHour       = 0
        SunsetMinute     = 0
        SunriseHour      = 0
        SunriseMinute    = 0
    }
}

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
    if ($settingsBlob) {
        $settings = ConvertFrom-NightLightSettingsPayload -Payload (ConvertFrom-CloudStoreBlob -Blob ([byte[]]$settingsBlob)).Payload
    }
    else {
        # Night Light has never been used on this machine (fresh install, or a
        # host without the feature). Seed a baseline rather than failing the
        # whole chezmoi apply.
        Write-Verbose "Night Light settings not present; creating them from scratch."
        $settings = Get-NightLightDefaultSetting
    }

    $settingsCorrect = $settingsBlob -and $settings.ScheduleEnabled -and -not $settings.SetHoursMode -and $settings.ColorTemperature -eq $desiredKelvin

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
    if (-not (Test-WindowsHost)) {
        Write-Host "[SKIP] Night Light is a Windows-only setting." -ForegroundColor Yellow
        return
    }

    Write-Host "Applying Night Light configuration (sunset to sunrise, strength $Strength)..." -ForegroundColor Cyan
    $results = @(Set-NightLightConfiguration -Strength $Strength -WhatIf:$WhatIfPreference)
    $updatedCount = @($results | Where-Object { $_.Changed }).Count
    Write-Host "[OK] Night Light configured ($updatedCount setting(s) changed)." -ForegroundColor Green
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCGQWV3wRXRT2aI
# s/myY7v3HqWK3Ax0OquyjodKqnjoraCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCCLmfAQJuwEfZC2L7Rceg/HThKvP51mghKt5RD7sUfCGzANBgkqhkiG
# 9w0BAQEFAASCAgBhIjaZd24iOTtv0s+rQGCMb81czDIK9kIoSfXiKd0ifUhYDlrI
# be8uelVZqmYfkBidOgMm2tbdW950zZ8WFUU3cV5WQLwGfYeI99oUBgDNzoPzSKK2
# fU6NA+eqrQjvi1LahZpuO+lYau+MGgGgzyKplD5cm5nnqW4SSKd1SRk4fNRpKl6J
# rWgPoMU4DpvevYHsJWFl/pWLat9B6QeW7FPFCAER9yrBgn0PSN1r9DUoYfWYFaZu
# snqP+9hHAU5POsMTdEs23oVH5O/6WjzOAR1Yom9rke2Zop03RU0yl+iZ3zmGQr8c
# 29cOvcM16acvNQxQKgnl9uSagFiVRqy2jIJRrSCgj91EC87ni3Va+6k47d9o3q12
# VRkAQQGLSzpiJ5ncjwizUEQFZkwnPn1rrB28zz7chT64OkqX1u66p5EmNZVvWd1Z
# UfeNfsgGNfkDHrgV7bjQbUCBrH7C1ckaTe5nw6YD/QpBPbdiFx8PpqHJvsjUslf3
# oShsLf43s0QgahUlL+nwVGaPRsz8XOtB1CxHZnY+lu13FFeQZ6CAjLx6r72WUs39
# /HtXxBNNycw4TbmWJNXQLBc6xTBZSgacdFVTOkGhiFm2cd6SQzc+xY+FT9FdIYxe
# dmpfBVFM56pDnqX5IAPEsP1074iP9wq5UucM9Xo1VjIIHNZfrWr0rytt4aGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA4MTYyMDU2MzlaMC8GCSqGSIb3DQEJBDEi
# BCBSl8e56U8CUZYb0hCqRD/q4x9WkWrNm/px4j4t5MH0IjANBgkqhkiG9w0BAQEF
# AASCAgCvMNNTafqRtsBawShogDPf+MdgJyYKzqesnEpiK2wA9eJf2K4ia9v6e+0g
# HprzHJ1Ft8b3vcNY91SFeRJijF1lTv4NFzLe0L6ec9AK5e4UGc2vz2kXBfir2Vsq
# RV3t5mAl14/knSxMz4cx/ElrgeoJ98r2NzFp27Phh1eJ31GJaBz9ACx4YaLkDAeE
# 68VWi+rGNFsoRswO91fXXDd+/9gTWtqaYt0HrabiIV38jyOzCfLH3sHUQzkjvOLY
# pk/7TRxD5MPjkdb+q2xfjiLXmwH2O7QJIs8asgTUkn5a+Y3ntG3LK+hmXwf+z3p4
# KP7QNi6t5UuVPt1osHOWP8EynCJF5AxuP6k3U/1SpYitaDn0iTx8Odj/AvF1sX8X
# SlGqyk3SBrFT17e7VIRp55vHa77h8c9SQ34w0TwHGU42FtPLOyo4c66IWvnbbZaJ
# cvUtPtIZSAvKX98FQBVN+SXqWoZqSkfqPAF6rGTm6z4N4hmqc3tKv2ZgdTuDYskK
# F0s8yWMt96CHjGD5d5h+mAzZHHwIqHk6+/e3ARyLSgI5I30vegP2DnM/jxuo4Wsq
# LGKhhCdTM3b+lCZvV2BoW4cepeRi3bbGXoISfS30lkUSefJkJuMCHQapKqD5yvdp
# frYxzpV/1XXRVosHAKTLO8rpAO7PXtSpBvERLzqeitYyLMxoOw==
# SIG # End signature block
