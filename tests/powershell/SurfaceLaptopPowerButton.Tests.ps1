#Requires -Version 7.0
<#
.SYNOPSIS
    Tests the Surface Laptop power-button configuration.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:ScriptPath = Join-Path $script:RepoRoot `
        "home\.chezmoiscripts\windows\run_onchange_disable-surface-laptop-power-button.ps1"

    . $script:ScriptPath -SkipApply
}

Describe "Surface Laptop power button script" -Tag "Unit" {
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

    It "recognizes Microsoft Surface Laptop models" {
        Test-SurfaceLaptop -ComputerSystem ([pscustomobject]@{
                Manufacturer = "Microsoft Corporation"
                Model        = "Surface Laptop 7th Edition"
            }) | Should -BeTrue
    }

    It "recognizes the Surface Laptop 7 SMBIOS model" {
        Test-SurfaceLaptop -ComputerSystem ([pscustomobject]@{
                Manufacturer = "Microsoft Corporation"
                Model        = "Microsoft Surface Laptop, 7th Edition"
            }) | Should -BeTrue
    }

    It "recognizes Surface Laptop Studio models" {
        Test-SurfaceLaptop -ComputerSystem ([pscustomobject]@{
                Manufacturer = "Microsoft Corporation"
                Model        = "Surface Laptop Studio 2"
            }) | Should -BeTrue
    }

    It "does not match other Surface form factors" {
        Test-SurfaceLaptop -ComputerSystem ([pscustomobject]@{
                Manufacturer = "Microsoft Corporation"
                Model        = "Surface Pro 11th Edition"
            }) | Should -BeFalse
    }

    It "requires Microsoft as the manufacturer" {
        Test-SurfaceLaptop -ComputerSystem ([pscustomobject]@{
                Manufacturer = "Contoso"
                Model        = "Surface Laptop 7"
            }) | Should -BeFalse
    }

    It "reads the documented AC and DC policy values" {
        $expectedPath = "HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\7648EFA3-DD9C-4E3E-B566-50F929386280"
        Mock Test-Path { $true } -ParameterFilter { $LiteralPath -eq $expectedPath }
        Mock Get-ItemProperty {
            [pscustomobject]@{
                ACSettingIndex = 0
                DCSettingIndex = 0
            }
        } -ParameterFilter { $LiteralPath -eq $expectedPath }

        $result = Get-PowerButtonPolicy

        $result.Path | Should -Be $expectedPath
        $result.HasAC | Should -BeTrue
        $result.AC | Should -Be 0
        $result.HasDC | Should -BeTrue
        $result.DC | Should -Be 0
        Should -Invoke Get-ItemProperty -Times 1 -Exactly `
            -ParameterFilter { $LiteralPath -eq $expectedPath }
    }

    It "does not invoke powercfg on non-Surface hardware" {
        $script:PowerCfgCalls = @()

        $result = Disable-SurfaceLaptopPowerButton `
            -GetComputerSystem {
                [pscustomobject]@{
                    Manufacturer = "Dell Inc."
                    Model        = "XPS 13"
                }
            } `
            -InvokePowerCfg {
                param([string[]]$ArgumentList)
                $script:PowerCfgCalls += , $ArgumentList
            }

        $result.Status | Should -Be "NotSurfaceLaptop"
        $result.Changed | Should -BeFalse
        $script:PowerCfgCalls | Should -BeNullOrEmpty
    }

    It "disables the current plan power button action for AC and battery power" {
        $script:PowerCfgCalls = @()

        $result = Disable-SurfaceLaptopPowerButton `
            -GetComputerSystem {
                [pscustomobject]@{
                    Manufacturer = "Microsoft Corporation"
                    Model        = "Surface Laptop 7"
                }
            } `
            -InvokePowerCfg {
                param([string[]]$ArgumentList)
                $script:PowerCfgCalls += , $ArgumentList
            } `
            -GetPowerButtonPolicy {
                [pscustomobject]@{
                    HasAC = $false
                    AC    = $null
                    HasDC = $false
                    DC    = $null
                }
            }

        $result.Status | Should -Be "Disabled"
        $result.Changed | Should -BeTrue
        $script:PowerCfgCalls.Count | Should -Be 3
        $script:PowerCfgCalls[0] -join " " | Should -Be (
            "/SETACVALUEINDEX SCHEME_CURRENT " +
            "4f971e89-eebd-4455-a8de-9e59040e7347 " +
            "7648efa3-dd9c-4e3e-b566-50f929386280 0"
        )
        $script:PowerCfgCalls[1] -join " " | Should -Be (
            "/SETDCVALUEINDEX SCHEME_CURRENT " +
            "4f971e89-eebd-4455-a8de-9e59040e7347 " +
            "7648efa3-dd9c-4e3e-b566-50f929386280 0"
        )
        $script:PowerCfgCalls[2] -join " " | Should -Be "/SETACTIVE SCHEME_CURRENT"
    }

    It "does not invoke powercfg when the desired policy manages both power states" {
        $script:PowerCfgCalls = @()
        $policy = {
            [pscustomobject]@{
                Path  = "HKLM:\policy"
                HasAC = $true
                AC    = 0
                HasDC = $true
                DC    = 0
            }
        }
        $surface = {
            [pscustomobject]@{
                Manufacturer = "Microsoft Corporation"
                Model        = "Surface Laptop 7"
            }
        }
        $powerCfg = {
            param([string[]]$ArgumentList)
            $script:PowerCfgCalls += , $ArgumentList
        }

        $firstResult = Disable-SurfaceLaptopPowerButton `
            -GetComputerSystem $surface `
            -InvokePowerCfg $powerCfg `
            -GetPowerButtonPolicy $policy
        $secondResult = Disable-SurfaceLaptopPowerButton `
            -GetComputerSystem $surface `
            -InvokePowerCfg $powerCfg `
            -GetPowerButtonPolicy $policy

        $firstResult.Status | Should -Be "ManagedByPolicy"
        $firstResult.Changed | Should -BeFalse
        $secondResult.Status | Should -Be "ManagedByPolicy"
        $secondResult.Changed | Should -BeFalse
        $script:PowerCfgCalls | Should -BeNullOrEmpty
    }

    It "rejects conflicting policy without invoking powercfg" {
        $script:PowerCfgCalls = @()

        {
            Disable-SurfaceLaptopPowerButton `
                -GetComputerSystem {
                    [pscustomobject]@{
                        Manufacturer = "Microsoft Corporation"
                        Model        = "Surface Laptop 7"
                    }
                } `
                -InvokePowerCfg {
                    param([string[]]$ArgumentList)
                    $script:PowerCfgCalls += , $ArgumentList
                } `
                -GetPowerButtonPolicy {
                    [pscustomobject]@{
                        Path  = "HKLM:\SOFTWARE\Policies\Microsoft\Power\PowerSettings\7648EFA3-DD9C-4E3E-B566-50F929386280"
                        HasAC = $true
                        AC    = 1
                        HasDC = $true
                        DC    = 0
                    }
                }
        } | Should -Throw "*Group Policy owns*ACSettingIndex=1, DCSettingIndex=0*will not override*"

        $script:PowerCfgCalls | Should -BeNullOrEmpty
    }

    It "does not invoke powercfg under WhatIf" {
        $script:PowerCfgCalls = @()

        $result = Disable-SurfaceLaptopPowerButton `
            -GetComputerSystem {
                [pscustomobject]@{
                    Manufacturer = "Microsoft Corporation"
                    Model        = "Surface Laptop 7"
                }
            } `
            -InvokePowerCfg {
                param([string[]]$ArgumentList)
                $script:PowerCfgCalls += , $ArgumentList
            } `
            -GetPowerButtonPolicy {
                [pscustomobject]@{
                    HasAC = $false
                    AC    = $null
                    HasDC = $false
                    DC    = $null
                }
            } `
            -WhatIf

        $result.Status | Should -Be "WhatIf"
        $result.Changed | Should -BeFalse
        $script:PowerCfgCalls | Should -BeNullOrEmpty
    }

    It "propagates native-command failures on unmanaged devices" {
        {
            Disable-SurfaceLaptopPowerButton `
                -GetComputerSystem {
                    [pscustomobject]@{
                        Manufacturer = "Microsoft Corporation"
                        Model        = "Surface Laptop 7"
                    }
                } `
                -InvokePowerCfg {
                    throw "powercfg.exe failed with exit code 1"
                } `
                -GetPowerButtonPolicy {
                    [pscustomobject]@{
                        HasAC = $false
                        AC    = $null
                        HasDC = $false
                        DC    = $null
                    }
                }
        } | Should -Throw "*powercfg.exe failed with exit code 1*"
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAKyDPyGzU/rPuh
# sRJHyco0ZqjxjaIJVrq5iuU0c8KkzqCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCBByG1PiH9976UddUwkaSDPRfpb0DbDaKPYAjTuLpvpQjANBgkqhkiG
# 9w0BAQEFAASCAgAKllCkByVI3B046NqixU+YJQ/dFMjxzr2U8ZRj53xYvFmFuC0k
# P6BqwRdfF8yi+rfBXnxau2bcr+Ph2n3hDwxSn/pa1r8qf0Ue1FEFrNavhFXKzBgp
# 1d5OBrNttw9zZv3GOTqwilUkdURBRa/WbezhUu+QPOyLAk9BcvcTXcgRitASll09
# HyWXxYPGLw1qPZPpofqIGH0DvYHOVmj0PR8A+ywwGgV6xM2DD0yA7P/62kG4hzpM
# WpSA1myM6vVYdZ/Z3XNIwLzo2yUQqpHNazQrEw1TbdEJKIbxSPPOOT3sYzlP52lS
# 2va3qSaQyCZms6r8bP9adl1Va/Cthn2Qz8GeXX1S+siPCPxRGWGk59tv1+pPbglJ
# KFzL5HnE4c0bhFTHv6KFfvQUqmEwYl+32mwEA3WlCfkWfsJAHRQ0DZ5ZcgS8y3r5
# Z+tBxB18xYjr89/XOWGpNHvcM934VYj66XIpYs5jYQbYu/v2OpSf4IWNHlTIrNHP
# DBlZ9MdGq3XgB4Ep4k0IeN8+jjytZNCpwmx/at9Ab7ldFujxaiSNSpW9frdt2Fp9
# YQXdGC3CnpcwVGlamyKgM2jtr/YwjOiMGpZ9LLopgX73d/GI+sPj/Zva4ZSlH6E2
# PJlXZr1jiszZxTXr3vLe4Ziz2UVycjcwlHGK5rwrI2tuBxS0hjNqs6nkCaGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA4MTQxMDEwMTRaMC8GCSqGSIb3DQEJBDEi
# BCDiGECTA3TyHcNzdrk+lhNsTMxwTPhDKk2oxEu6rI6JrTANBgkqhkiG9w0BAQEF
# AASCAgBABjc1nmIPiRX/gj7GcZU0QUmy+JWL6nkkel+vYuKxVvvjPoEAulizt5d/
# q1Nx10nTtZUm4sVYbNNOM3EUDzp8txbfLmyAQtMHzxHaBd6aFPGJSudAeC0diNFZ
# 7W/1ydfXOPnFhYIRO00PXuxLABu6zT6nvtwdjbWWOzH4/HhtP2VNwCvoqNRa+JIb
# VAcpNntKATYAIBvEvvuWiI5jpBeLR8cDhQG9VFY7T41Gq692FH0XHatwZ/3TOarV
# WVsJUtQtG0aYQSA/Y5kSdFWd7yieqhCz52IkMT3NtDg9ptpRv4nl0rinp/OzKQym
# dDTEjv3/Ar7ggKw41TOwGfISnElI4Qne8IjjMs++E4j2jDMAGYMrAUlbPLiVIVHF
# tySEaNeVDrdtVPq8oPW+C2DZXQKipgE2+7sMrryPC9f8sg/wm9yIQf2TJy5/PGhk
# iNh0Kv5390mP/A4qtA+BBtvN/+4ZoeRnSRGwWkhkSxMfpTtJI/WA/xgtQbdWCRD9
# 5f5n6U7S0Qqb6nmcnOL6SWdm2YJNEVjUvT6dfSrZfG+Jw9TwGaVr2ryb//YWz52A
# VAfp1ZjvrOhWHYwchBXUyXsdQA5Brda4aZZxpZL5uwnprtyrVh1GVbshfuhjICsu
# evA5/tQcfckb19/SQsXiotG+LZ28Mz97cImc/OM/QQewn00eog==
# SIG # End signature block
