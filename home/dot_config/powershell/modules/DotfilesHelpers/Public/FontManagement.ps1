# Font management utilities
#
# Functions for installing Nerd Fonts and for pointing Windows Terminal at an
# installed font without managing (and fighting git-sync on) the whole
# settings.json file.

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

function Test-NerdFontInstalled {
    <#
    .SYNOPSIS
    Returns $true if a Nerd Font matching the given name is registered.

    .PARAMETER Name
    The Nerd Font family name (as passed to Install-NerdFont), e.g. 'FiraCode'.
    Matching ignores spaces, so 'FiraCode' matches the registered
    'FiraCodeNerdFont-Regular (TrueType)' value.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9._ -]+$')]
        [string]$Name = 'FiraCode'
    )

    $needle = ($Name -replace '\s', '')
    $keys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )

    foreach ($key in $keys) {
        if (-not (Test-Path -Path $key)) { continue }
        $props = (Get-ItemProperty -Path $key).PSObject.Properties
        foreach ($prop in $props) {
            if ($prop.Name -like 'PS*') { continue }
            $normalized = ($prop.Name -replace '\s', '')
            if ($normalized -like "*${needle}NerdFont*") { return $true }
        }
    }

    return $false
}

function Invoke-NerdFontInstaller {
    <#
    .SYNOPSIS
    Performs the actual Nerd Font install via the (PowerShell 7) NerdFonts module.

    .DESCRIPTION
    chezmoi runs scripts under Windows PowerShell 5.1, but the NerdFonts module
    is PowerShell 7 only, so the install is delegated to pwsh. Kept private so
    Install-DotfilesNerdFont can be unit-tested by mocking this function.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope
    )

    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd) {
        Write-Warning "pwsh (PowerShell 7) not found; cannot install Nerd Font '$Name'. Install PowerShell 7 first."
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'Install Nerd Font')) { return $false }

    # $Name and $Scope are constrained by ValidatePattern/ValidateSet above, so
    # interpolating them into the command string is safe from injection.
    $inner = "Install-PSResource -Name NerdFonts -Scope CurrentUser -TrustRepository -Quiet -ErrorAction Stop; " +
    "Install-NerdFont -Name $Name -Scope $Scope -Confirm:`$false -ErrorAction Stop"

    & $pwshCmd.Source -ExecutionPolicy Bypass -NoProfile -NonInteractive -Command $inner 2>&1 |
        ForEach-Object { Write-Verbose ([string]$_) }

    return ($LASTEXITCODE -eq 0)
}

function Install-DotfilesNerdFont {
    <#
    .SYNOPSIS
    Idempotently installs a Nerd Font and verifies it registered.

    .PARAMETER Name
    Nerd Font family name (default 'FiraCode').

    .PARAMETER Scope
    Install scope: CurrentUser (default) or AllUsers.

    .PARAMETER Force
    Reinstall even if the font already appears to be installed.

    .EXAMPLE
    Install-DotfilesNerdFont -Name FiraCode -Scope CurrentUser
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [string]$Name = 'FiraCode',

        [Parameter()]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'CurrentUser',

        [switch]$Force
    )

    if ((Test-NerdFontInstalled -Name $Name) -and -not $Force) {
        Write-Host "[OK] $Name Nerd Font already installed" -ForegroundColor Green
        return [pscustomobject]@{ Name = $Name; Installed = $true; Action = 'AlreadyInstalled' }
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'Install Nerd Font')) {
        return [pscustomobject]@{ Name = $Name; Installed = (Test-NerdFontInstalled -Name $Name); Action = 'Skipped' }
    }

    Write-Host "Installing $Name Nerd Font..." -ForegroundColor Cyan
    $ok = Invoke-NerdFontInstaller -Name $Name -Scope $Scope
    $installed = Test-NerdFontInstalled -Name $Name

    if ($ok -and $installed) {
        Write-Host "[OK] $Name Nerd Font installed" -ForegroundColor Green
        return [pscustomobject]@{ Name = $Name; Installed = $true; Action = 'Installed' }
    }

    Write-Warning "Failed to install $Name Nerd Font. Install manually with: pwsh -Command 'Install-NerdFont -Name $Name -Scope $Scope'"
    return [pscustomobject]@{ Name = $Name; Installed = $false; Action = 'Failed' }
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
        $SettingsPath = @(
            (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
            (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
        )
    }

    $results = @()

    foreach ($path in $SettingsPath) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Verbose "Windows Terminal settings not found at: $path (skipping)"
            continue
        }

        try {
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop

            $json = $null
            try {
                $json = $raw | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                # Retry assuming JSONC (comments / trailing commas).
                $json = (Remove-JsonComment -Text $raw) | ConvertFrom-Json -ErrorAction Stop
            }

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
                $out = $json | ConvertTo-Json -Depth 32
                [System.IO.File]::WriteAllText($path, $out, (New-Object System.Text.UTF8Encoding($false)))
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

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB4Gjrw1xBh47XB
# lppVcas427vYLiAmDiNBkmSwsUsgkKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCAC6X47XYc64703W/FHME6d3k5TLdyHT4DMxvB/liwzRzANBgkqhkiG
# 9w0BAQEFAASCAgBnrnS3PH+4bFix2xKjvYlU8lyLmriopX3k/+tA/qsdVWZRVHay
# lfEQl1rwbw0jaTaVhT1HCpF7F2BAWZGPahliWGt4fz7PEmfKmyIajQ8CjqklldYP
# XwHTUi8dKDVMcLqiBUs7ABSmxP3py2OjwkF0OVA8iUtePuCmRzD9jEZkkgq9EAvA
# 4nMdqvS88a0W4GBAGL4/RXTRPGjMX/wDrdYLi5PkfRzJ0sLtG9OZZbLYnNPnRrCv
# VSi/8usAs2Tt19me9yzMBif+9wewVxDfarAObuVHcBoe0BT/tefGZZxdCSxOi/3z
# xQv1AGggroV7ak2MJbYaQPLE6ErcUwKmc/ocLccUtzPKWzl+X3NngK3aL1BKyaiD
# /AAbxlGZfPU6Jye8uL9pGPs9H1KWR5Lqf6t2RGLnqwXPYdPxZ5VJqQtW+4Wgzm/d
# fXM5ATHkDrAF98huXak/1Yu0jUmC7aoAocs1L01K5tBfq30xCZJRxJC1iQ2RDoPt
# h9yjk7IBhwoxak3tL3D0VJy6+j3AjLjH7d0fds/2tIjDUkNo60ACRbZpTXJ488kp
# Uo6+VQPpsr3vB6jVunlnAJBebbm1xHNCeaCSIzqVCqUpopz27IvLMq51R09AbddZ
# perljat9ZoPLo3ikK51gd1DQy2a6jzvvGCDBF9I/l5qA9gXMsGNkxQgGtaGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA2MDQxMjI0MDJaMC8GCSqGSIb3DQEJBDEi
# BCCa/Gp9kGO/9YGTub0shYsiv/89xsESHz7dqibc1NTq4jANBgkqhkiG9w0BAQEF
# AASCAgBziHAlLhIzbSD49Y2V+sTbzmA4Jqo70Ev0Orx+cKKt+P+2BvWKOlVfR3zy
# IRl1DBlVE4JTCZGa691+QdS2aZDCkc6dZmzIgGdUdXlLjYFQU5bW2vqvBIhcHk9Q
# t6kTCM0BLuycXkslZ5p05UWDrDPb48wGkdoNdslFJpjgmqSHbQdOGqJj8M1aRB51
# zHD5bFSa+aAbw96ZCMOrYcQc7KlAd9AYAoajgY1j9ewGOBHIZJT/ExClmbybICwI
# DECbfzTEq5CLiXuDTsuTmBORcWdolGlwRftiqaAkzicqjCFBeWO3NV0KVb19PMik
# O8LM/F/dbNn3BKn4/c4o9XGecJxfNW1u1MvShinig5Kgd7rZBfMZ6xRMyLClbfwW
# uyp0uwFPT5SwPa3ndB5Ds3l6wAlIxKwWNh3IpOfAOHXDoSpiEAWJPOo8FVyo8t1C
# Kh3elzu4py3He5zvXj2nBeNxLK2SYueRzPaAZNMH6YV7++BQTayW1IQcfPTG+mE5
# ZwKwtlw55Af5KA3E6pKo7WFs5M6dkI0YJN5fYotAxR00FSkYUlsBNc5LZ0QfMNqq
# oyUU5nIilXj/MNpqwxRBSV2RKqN9b4Oq6wq7MEBTF9kGzo3dRsgR6W7zLSt3amcO
# 6mrqbsjTRCYAaluRF2rXp+1R7QCCIxPEwxRr7OMAnb6wyoXgKQ==
# SIG # End signature block
