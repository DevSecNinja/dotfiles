#!/usr/bin/env pwsh
# Disable the hardware power button on Microsoft Surface Laptop models.
# Runs on Windows and is idempotent.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    "PSAvoidUsingWriteHost",
    "",
    Justification = "Matches existing chezmoi setup script progress output."
)]
param(
    [switch]$SkipApply
)

$ErrorActionPreference = "Stop"

function Test-SurfaceLaptop {
    param(
        [AllowNull()]
        [object]$ComputerSystem
    )

    if ($null -eq $ComputerSystem) {
        return $false
    }

    $manufacturer = [string]$ComputerSystem.Manufacturer
    $model = [string]$ComputerSystem.Model

    return $manufacturer.Trim() -eq "Microsoft Corporation" -and
        $model.Trim() -match "^(?:Microsoft )?Surface Laptop(?:[\s,]|$)"
}

function Invoke-PowerCfg {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    $powerCfgPath = Join-Path $env:SystemRoot "System32\powercfg.exe"
    if (-not (Test-Path -LiteralPath $powerCfgPath -PathType Leaf)) {
        throw "powercfg.exe was not found at '$powerCfgPath'."
    }

    $output = & $powerCfgPath @ArgumentList 2>&1
    if ($LASTEXITCODE -ne 0) {
        $details = ($output | Out-String).Trim()
        throw "powercfg.exe failed with exit code $LASTEXITCODE for '$($ArgumentList -join ' ')': $details"
    }
}

function Disable-SurfaceLaptopPowerButton {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [scriptblock]$GetComputerSystem = {
            Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        },

        [scriptblock]$InvokePowerCfg = {
            param([string[]]$ArgumentList)
            Invoke-PowerCfg -ArgumentList $ArgumentList
        }
    )

    $computerSystem = & $GetComputerSystem
    if (-not (Test-SurfaceLaptop -ComputerSystem $computerSystem)) {
        Write-Host "[SKIP] Power button unchanged: this device is not a Microsoft Surface Laptop." -ForegroundColor Yellow
        return [pscustomobject]@{
            Status  = "NotSurfaceLaptop"
            Changed = $false
            Model   = [string]$computerSystem.Model
        }
    }

    $powerButtonSetting = "7648efa3-dd9c-4e3e-b566-50f929386280"
    $buttonSubgroup = "4f971e89-eebd-4455-a8de-9e59040e7347"
    $commands = @(
        [pscustomobject]@{
            ArgumentList = @("/SETACVALUEINDEX", "SCHEME_CURRENT", $buttonSubgroup, $powerButtonSetting, "0")
        }
        [pscustomobject]@{
            ArgumentList = @("/SETDCVALUEINDEX", "SCHEME_CURRENT", $buttonSubgroup, $powerButtonSetting, "0")
        }
        [pscustomobject]@{
            ArgumentList = @("/SETACTIVE", "SCHEME_CURRENT")
        }
    )

    $model = [string]$computerSystem.Model
    if (-not $PSCmdlet.ShouldProcess($model, "Set the AC and battery power button action to Do nothing")) {
        return [pscustomobject]@{
            Status  = "WhatIf"
            Changed = $false
            Model   = $model
        }
    }

    foreach ($command in $commands) {
        & $InvokePowerCfg -ArgumentList $command.ArgumentList
    }

    Write-Host "[OK] Disabled the power button on $model for AC and battery power." -ForegroundColor Green
    return [pscustomobject]@{
        Status  = "Disabled"
        Changed = $true
        Model   = $model
    }
}

if (-not $SkipApply) {
    Disable-SurfaceLaptopPowerButton | Out-Null
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCASqu2itbjs5puZ
# 2BByk9ALH25PpnOKRV9YJ1mL5OlZgKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCAYRcaN1tCc6cMRzR8ufiv5NntUfHzksp8XnPkuJzq3HTANBgkqhkiG
# 9w0BAQEFAASCAgC2ZtoB3s//JFCH/ICF42XsjNbvb7nZN96A7k5LWSnIUj8uvSrq
# /nly4OMd/3gIinNNCpBgBzMUNbMsnoL8DVq8eidKTGf3PABhqyPHVRAkQR8bYLVo
# LcEMaa2em53ko25Dwa2cXhjHS8AdxmfIy1BX1v06XCkZsEppsfXTjaASvGSjaMG6
# 6pkbt5czyYUNzItnX92bNpHLniyU29F/S+YhYsOfFKySvg0IY+b/lCY7xE3FBxPB
# uL+IkVtlDtfCoOUxSmtj1sE3rbLaxbSA8CfDsLLZZEDKP9kKJPv+EbIvZk8BmDlX
# r5U3U1+DTONi9OISN0stA8ZlqwqELLCsBhRalS+03ipMcKpy4v67Ae2wtXWf4r4p
# AxOHUQoMt/pCShoIad2Dk7D1X/Ds8t7AQOEGi3KC6YjgWUL/lPw225inU4Olrf78
# WUyptssLHNRH//evFdh64FTZrPX9vUB267ZpIPpf7HhC4sQJg2KiExmAsrKx2iyb
# VW42gNSBxDHUSL/O5u5pgLsxLM8cERGS5srDENLywKD0+qYFH5ez95mk3q7hAAF/
# 7eM/Iv09+Bqr9KMsBqeY92zuK6iHe9iRs09ahV9d7+Aon+iich6b/sjh6au7IU/G
# SKywnUF/MZ+U9eQXJwgslFeEih7BLr7pthRWz10w4h1lGPEKm32bArsm+KGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA4MTEwOTU3MDZaMC8GCSqGSIb3DQEJBDEi
# BCBwyN/0ceyum7fZWCJ6rto017bpRIr1eLoumAG1FyMDIDANBgkqhkiG9w0BAQEF
# AASCAgBWScqV/foKMGM3ryJc8BfSNM1/4tRuLOo4O2+Ap2rPkTejJuUvRuV0JXyy
# L3pA9QgO78eMItdP91lulELoXKoKWN09zkwvyMhSC9VEd4Ugdk6lhuYwglZywZur
# ZzkBUH/+DBnUJROlrGzgycs+dmUFBQxmN+vkxcDBdGGbfG7hevtveCNOnj53XpJs
# S/qFeMyieS3pfDlkJE1A8HpoNBs2W6MDJN0yB1ig48caBE+iokT4rsjMai/anD4P
# lo4qoUE+1crrcT4zWMPVF4+Kz3rWkZ8t4/ByLq6Ohr2WywCjuhow6IzrF+lVqqt7
# l8E1sounrMRylL7yCdKoeF28I/7qOPeLZPWAGJNFINyNkrfQlrhf0ZA/MshGxTC/
# RVxoAtJncOkM+p5CGo7lUyE6ye9JD0KRcm01V08F/xbMhwT+tOzysQd8EFFxAQt6
# edWxj5vDvx8bTrKyyixOt9LGAlpeQ7vfQaP6ZMorPcNen/0LBHfbUZ9FfPMqfPMI
# SnAhcCQfegKBJeGdlVEWAtFNnEF/sTmDI6FEuCD4hEKD6SootAErva4dASE7f/KE
# 8jtYezFQ5Ir8wzxN0zgioGeRjqVA5LLjCjxPl3fPjcFStxD2b0NziMj0+WxlBEeT
# FOEcHPx6Sl8diJa9Wj1GfrvPdTVU2FZQ4mXRmlLHIhm0XVBZkw==
# SIG # End signature block
