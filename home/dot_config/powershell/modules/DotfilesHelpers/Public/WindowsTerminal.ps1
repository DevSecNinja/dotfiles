# Windows Terminal settings utilities
#
# Windows Terminal owns settings.json (it rewrites the file at runtime), and the
# config differs from machine to machine. Rather than managing the whole file in
# git - which overwrites local changes and breaks per-machine setups - these
# helpers parse the existing settings.json and surgically patch only the single
# value being changed, leaving everything else untouched.

function Remove-JsonComment {
    <#
    .SYNOPSIS
    Strips // and /* */ comments from a JSONC string in a string-aware way.

    .DESCRIPTION
    Windows PowerShell 5.1's ConvertFrom-Json cannot parse JSONC (comments /
    trailing commas), which Windows Terminal allows. This helper removes
    comments while preserving content inside string literals (so URLs such as
    "https://example.com" are not mangled) and drops trailing commas before
    closing braces/brackets.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $sb = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    $i = 0
    $len = $Text.Length

    while ($i -lt $len) {
        $c = $Text[$i]
        $next = if ($i + 1 -lt $len) { $Text[$i + 1] } else { [char]0 }

        if ($inString) {
            [void]$sb.Append($c)
            if ($escaped) { $escaped = $false }
            elseif ($c -eq '\') { $escaped = $true }
            elseif ($c -eq '"') { $inString = $false }
            $i++
            continue
        }

        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }

        if ($c -eq '/' -and $next -eq '/') {
            while ($i -lt $len -and $Text[$i] -ne "`n") { $i++ }
            continue
        }

        if ($c -eq '/' -and $next -eq '*') {
            $i += 2
            while ($i + 1 -lt $len -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { $i++ }
            $i += 2
            continue
        }

        [void]$sb.Append($c)
        $i++
    }

    # Remove trailing commas (",}" / ",]") that JSONC allows but JSON rejects.
    return [regex]::Replace($sb.ToString(), ',(\s*[}\]])', '$1')
}

function Get-WindowsTerminalSettingsPath {
    <#
    .SYNOPSIS
    Returns the well-known Windows Terminal settings.json locations.

    .DESCRIPTION
    Covers the Store (stable), Store Preview, and unpackaged installs. Paths are
    returned whether or not they exist; callers are expected to skip missing
    files.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
}

function Read-WindowsTerminalSettings {
    <#
    .SYNOPSIS
    Reads and parses a Windows Terminal settings.json (JSON or JSONC).

    .DESCRIPTION
    Reads the file as raw text and parses it as JSON, retrying as JSONC
    (comments / trailing commas stripped via Remove-JsonComment) so that
    comment-annotated user configs still parse under Windows PowerShell 5.1.
    Throws on unreadable / unparseable files so callers can report an error.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop

    try {
        return $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # Retry assuming JSONC (comments / trailing commas).
        return (Remove-JsonComment -Text $raw) | ConvertFrom-Json -ErrorAction Stop
    }
}

function Save-WindowsTerminalSettings {
    <#
    .SYNOPSIS
    Serializes a settings object back to a Windows Terminal settings.json.

    .DESCRIPTION
    Writes UTF-8 without a BOM (Windows Terminal does not emit one) and uses a
    deep serialization depth so nested actions/profiles are preserved.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [psobject]$Settings
    )

    $out = $Settings | ConvertTo-Json -Depth 32
    [System.IO.File]::WriteAllText($Path, $out, (New-Object System.Text.UTF8Encoding($false)))
}

function Set-WindowsTerminalFont {
    <#
    .SYNOPSIS
    Sets the Windows Terminal default font face by surgically patching settings.json.

    .DESCRIPTION
    Updates only profiles.defaults.font.face in each existing Windows Terminal
    settings.json, leaving everything else untouched. Windows Terminal keeps
    owning the file, so this avoids the conflicts that come from managing the
    whole config in git. Files that do not exist are skipped (initial creation
    is handled by run_once_setup-windows-terminal.ps1).

    .PARAMETER FontFace
    The font face name to set, e.g. 'FiraCode Nerd Font'.

    .PARAMETER SettingsPath
    One or more settings.json paths. Defaults to the known Windows Terminal
    locations (Store, Preview, and unpackaged).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FontFace,

        [Parameter()]
        [string[]]$SettingsPath
    )

    if (-not $SettingsPath) {
        $SettingsPath = Get-WindowsTerminalSettingsPath
    }

    $results = @()

    foreach ($path in $SettingsPath) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Verbose "Windows Terminal settings not found at: $path (skipping)"
            continue
        }

        try {
            $json = Read-WindowsTerminalSettings -Path $path

            if ($null -eq $json.profiles) {
                $json | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            if ($null -eq $json.profiles.defaults) {
                $json.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            if ($null -eq $json.profiles.defaults.font) {
                $json.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) -Force
            }

            if ($json.profiles.defaults.font.face -eq $FontFace) {
                Write-Verbose "Font already set to '$FontFace' at: $path"
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'AlreadySet' }
                continue
            }

            if ($null -eq $json.profiles.defaults.font.PSObject.Properties['face']) {
                $json.profiles.defaults.font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace -Force
            }
            else {
                $json.profiles.defaults.font.face = $FontFace
            }

            if ($PSCmdlet.ShouldProcess($path, "Set default font face to '$FontFace'")) {
                Save-WindowsTerminalSettings -Path $path -Settings $json
                Write-Host "[OK] Set Windows Terminal font to '$FontFace' at: $path" -ForegroundColor Green
                $results += [pscustomobject]@{ Path = $path; Changed = $true; Status = 'Updated' }
            }
            else {
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'WhatIf' }
            }
        }
        catch {
            Write-Warning "Could not update Windows Terminal settings at '$path': $_"
            $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'Error' }
        }
    }

    return $results
}

function Set-WindowsTerminalDefaultProfile {
    <#
    .SYNOPSIS
    Points Windows Terminal's defaultProfile at a profile resolved from settings.json.

    .DESCRIPTION
    Parses each existing Windows Terminal settings.json, finds the matching
    profile in profiles.list (by source, e.g. 'Windows.Terminal.PowershellCore',
    or by display name), and surgically sets the top-level defaultProfile to that
    profile's guid. Only defaultProfile is touched; the rest of the config is
    left exactly as Windows Terminal wrote it, so this is safe to run against a
    different, hand-tuned config on every machine.

    When no matching profile exists (e.g. PowerShell Core is not installed on
    that machine) the file is left unchanged and the result is reported as
    'ProfileNotFound' rather than raising an error, so callers can skip cleanly.

    .PARAMETER Source
    The profile 'source' to match, e.g. 'Windows.Terminal.PowershellCore'
    (default). Used when -ProfileName is not supplied.

    .PARAMETER ProfileName
    Match a profile by its display 'name' instead of its 'source'.

    .PARAMETER SettingsPath
    One or more settings.json paths. Defaults to the known Windows Terminal
    locations (Store, Preview, and unpackaged).

    .EXAMPLE
    Set-WindowsTerminalDefaultProfile
    Sets the default profile to the PowerShell Core profile, if present.

    .EXAMPLE
    Set-WindowsTerminalDefaultProfile -ProfileName 'Debian'
    Sets the default profile to the profile named 'Debian', if present.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'BySource')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'BySource')]
        [ValidateNotNullOrEmpty()]
        [string]$Source = 'Windows.Terminal.PowershellCore',

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$ProfileName,

        [Parameter()]
        [string[]]$SettingsPath
    )

    if (-not $SettingsPath) {
        $SettingsPath = Get-WindowsTerminalSettingsPath
    }

    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $criteria = "name '$ProfileName'"
    }
    else {
        $criteria = "source '$Source'"
    }

    $results = @()

    foreach ($path in $SettingsPath) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Verbose "Windows Terminal settings not found at: $path (skipping)"
            continue
        }

        try {
            $json = Read-WindowsTerminalSettings -Path $path

            $list = $null
            if ($json.PSObject.Properties['profiles'] -and $json.profiles.PSObject.Properties['list']) {
                $list = @($json.profiles.list)
            }

            if (-not $list) {
                Write-Verbose "No profiles.list found in: $path (skipping)"
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'ProfileNotFound'; Guid = $null; MatchedProfile = $null }
                continue
            }

            if ($PSCmdlet.ParameterSetName -eq 'ByName') {
                $match = $list | Where-Object { $_.PSObject.Properties['name'] -and $_.name -eq $ProfileName } | Select-Object -First 1
            }
            else {
                $match = $list | Where-Object { $_.PSObject.Properties['source'] -and $_.source -eq $Source } | Select-Object -First 1
            }

            if (-not $match -or -not $match.PSObject.Properties['guid'] -or [string]::IsNullOrWhiteSpace([string]$match.guid)) {
                Write-Verbose "No profile matching $criteria (with a guid) found in: $path (skipping)"
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'ProfileNotFound'; Guid = $null; MatchedProfile = $null }
                continue
            }

            $guid = [string]$match.guid
            $name = if ($match.PSObject.Properties['name']) { [string]$match.name } else { $guid }

            $currentDefault = if ($json.PSObject.Properties['defaultProfile']) { [string]$json.defaultProfile } else { $null }
            if ($currentDefault -eq $guid) {
                Write-Verbose "defaultProfile already set to $guid ($name) at: $path"
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'AlreadySet'; Guid = $guid; MatchedProfile = $name }
                continue
            }

            if ($null -eq $json.PSObject.Properties['defaultProfile']) {
                $json | Add-Member -NotePropertyName defaultProfile -NotePropertyValue $guid -Force
            }
            else {
                $json.defaultProfile = $guid
            }

            if ($PSCmdlet.ShouldProcess($path, "Set defaultProfile to $guid ($name)")) {
                Save-WindowsTerminalSettings -Path $path -Settings $json
                Write-Host "[OK] Set Windows Terminal default profile to '$name' ($guid) at: $path" -ForegroundColor Green
                $results += [pscustomobject]@{ Path = $path; Changed = $true; Status = 'Updated'; Guid = $guid; MatchedProfile = $name }
            }
            else {
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'WhatIf'; Guid = $guid; MatchedProfile = $name }
            }
        }
        catch {
            Write-Warning "Could not update Windows Terminal default profile at '$path': $_"
            $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'Error'; Guid = $null; MatchedProfile = $null }
        }
    }

    return $results
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA3en3+oipv/GDx
# kILYp3js4vLCTRvc5GIM9In39TzTFKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCC84+D1I8bY4aD8EjBPO/sFhRPlqiOgO8Q5QKoNBG7pGDANBgkqhkiG
# 9w0BAQEFAASCAgBg3g0rW5a4NEV1PKho9k/c4O6Q2HB+HBirjiqlp6mUvjLVoQ6R
# 51bGw8nfyHJmB7lGQwfWJNR7tKWDd6DGuQ5nKo6h9kb9T8AbmM6NGqpfvHd4SwWH
# 9bb8A7RemTgYP8OhwVk302MSMduKGoQUqnbU923FK2l2q+JfPhnhSZlM8HlMJTHb
# 3xq+AVyFc8oOOwOa+a6tz8D/KmjvcIOrH81BW42IL/k71WEk2HnmWopqi9q1EdKc
# 8ILOv+QD866aNaL9F+xY5FfjMBPcY8WtCNLoOlCQoIAc8mIJj/NbOoVbzrCg4/5S
# IeeWG0uonGLNd/0tyv5II4s/ThLk5gySDG9hdQMItR5JRJ13XqZzO9wLbmB+ctKt
# Q9h9KmnhI3hOGL0Zne3mYxcNv6OiLa7M53KT3YohZSvF285pT0HSVHe7cMx7jfz/
# MHyh/1imWQbpEAf9eZ7f6ucNhP8ZMGiUk8VMD7RckxlFSsj93VvOUTGCbhypmxuk
# KQHqB84C0mUvY0nf+xznBSlt6sf5YNKrStmJ7NqynKjxDw+y5csSs3g2JvhxCrgW
# L245UmbUt9+dT9JWH/9dQ7fZjaDyPKj9Zou42NXQKbMgvkbwCSAxYWj73hPKaJCF
# 8T1Z33LDDAuGN7oGvfTk/O8wP58wc74y+Tg9lbiT0tFe98Gaz+IMRUx5iKGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MjExNzU1MzJaMC8GCSqGSIb3DQEJBDEi
# BCClCWPcC+3qQrQSTAVZjzu0/5uEcT/AsQ1oGdifpG1f3jANBgkqhkiG9w0BAQEF
# AASCAgAn+d+6zCd15FTJWEAbpoKBA99KfZH8vmksaOG+X8qxqGra5OOT3svqx5pv
# Navddfzoc1+W4LzOLaviXx9pRzLnccXZ8SYEwj113sLbTPCllVf9k8QkBgT8xa9k
# c1UsPj4vKd0KLuB1lekZIlQ9uI6bqWMoV4dt9Qq7T2DeiatUyU2yw2GyXi0RZGYx
# XYpTA3ajAdKAcxwfM0xwp47tmWtI8mA/YO6djyh5Rslls2y3dM1NKunmwnJeBoGh
# kcqXjo8/1CxyT6EzvGDvB8F2JDZ6BwaZtPbEBrVBInpyXrn0D3c5gBQEcLU2nt5/
# kD5Xy8aOku9BwznkC9jh6Y4bKV51Ji+2eS9/UpVBfynnwqjPynBBSJlFY7/fuBuK
# LmiHiILdda1OmBEHLLhKRcI16l7sdAKKB4wQS5ark2McjfM/AqPWQUQSYvEHXN63
# RKzi5IPXNAzf3lZpMjD1TDyB3JtdtvdPWXjlLhh/w9vYoc7AqbcbN2ekUZ9pY+Pc
# gMKi+1gY+JBflfrgttnNBkb/fJL5kH6Jyx0kIw1dk5vcmp0LeQ08BXhbY1ky6pej
# oBpFge0l+jzHlXU3K3ECcpcMjv7A8zfXdl/d9izBv8ctlmmXNzULzdMAJVwjLw7X
# X11Th9jcQb9km7Wwj61A50upzPpquNLhdDuCLg/G69YFdEfQ6Q==
# SIG # End signature block
