#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for adding OneDrive Portable Programs to PATH.

.DESCRIPTION
    Tests the user-scope PATH helper without writing to the registry and checks
    that the PowerShell profile keeps the current session update cheap.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $script:PortableProgramsScriptPath = Join-Path $script:RepoRoot "home\.chezmoiscripts\windows\run_onchange_add-portable-programs-path.ps1"
    $script:ProfilePath = Join-Path $script:RepoRoot "home\dot_config\powershell\profile.ps1"

    . $script:PortableProgramsScriptPath -SkipApply
}

AfterAll {
    Pop-Location
}

Describe "Portable Programs PATH Script" -Tag "Unit" {
    It "script file should exist" {
        $script:PortableProgramsScriptPath | Should -Exist
    }

    It "script should have valid PowerShell syntax" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:PortableProgramsScriptPath,
            [ref]$null,
            [ref]$errors
        ) | Out-Null

        $errors | Should -BeNullOrEmpty
    }

    It "should read the raw user PATH without expanding percent variables" {
        $content = Get-Content -LiteralPath $script:PortableProgramsScriptPath -Raw
        $content | Should -Match "DoNotExpandEnvironmentNames"
        $content | Should -Not -Match "GetEnvironmentVariable\(.+User"
    }

    It "should write only the user-scope PATH variable" {
        $content = Get-Content -LiteralPath $script:PortableProgramsScriptPath -Raw
        $content | Should -Match "OpenSubKey\(`"Environment`",\s*\`$true\)"
        $content | Should -Match "SetValue\(\`$writeInfo\.ValueName,\s*\`$Path,\s*\`$writeInfo\.Kind\)"
        $content | Should -Not -Match "SetEnvironmentVariable"
        $content | Should -Not -Match "`"Machine`""
    }

    It "should preserve an existing ExpandString registry value kind" {
        $info = Resolve-UserPathRegistryWriteInfo `
            -ValueName "PATH" `
            -Kind ([Microsoft.Win32.RegistryValueKind]::ExpandString) `
            -Value "C:\Tools;C:\Users\Demo\OneDrive\Portable Programs"

        $info.ValueName | Should -Be "PATH"
        $info.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    }

    It "should choose ExpandString for a new value containing percent variables" {
        $info = Resolve-UserPathRegistryWriteInfo `
            -ValueName $null `
            -Kind $null `
            -Value "%USERPROFILE%\bin;C:\Users\Demo\OneDrive\Portable Programs"

        $info.ValueName | Should -Be "Path"
        $info.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    }

    It "should choose String for a new plain value" {
        $info = Resolve-UserPathRegistryWriteInfo `
            -ValueName $null `
            -Kind $null `
            -Value "C:\Tools;C:\Users\Demo\OneDrive\Portable Programs"

        $info.ValueName | Should -Be "Path"
        $info.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
    }

    It "should detect existing entries case-insensitively and ignore trailing backslashes" {
        $pathList = "C:\Tools;c:\users\demo\onedrive\portable programs\"

        Test-PathListContainsEntry -PathList $pathList -Entry "C:\Users\Demo\OneDrive\Portable Programs" |
            Should -Be $true
    }

    It "should append the Portable Programs path without expanding existing variables" {
        $userPath = "%USERPROFILE%\bin;C:\Tools"
        $entry = "C:\Users\Demo\OneDrive\Portable Programs"

        Add-PathListEntry -PathList $userPath -Entry $entry |
            Should -Be "%USERPROFILE%\bin;C:\Tools;C:\Users\Demo\OneDrive\Portable Programs"
    }

    It "should not add a duplicate entry" {
        $userPath = "%USERPROFILE%\bin;C:\Users\Demo\OneDrive\Portable Programs\"
        $entry = "c:\users\demo\onedrive\portable programs"

        Add-PathListEntry -PathList $userPath -Entry $entry |
            Should -Be $userPath
    }

    It "should do nothing when OneDrive is not configured" {
        $script:PathExistsCalled = $false
        $script:SetUserPathCalled = $false

        $result = Add-PortableProgramsToUserPath `
            -OneDrivePath $null `
            -PathExists { $script:PathExistsCalled = $true; $true } `
            -SetUserPath { $script:SetUserPathCalled = $true }

        $result.Status | Should -Be "OneDriveMissing"
        $result.Changed | Should -Be $false
        $script:PathExistsCalled | Should -Be $false
        $script:SetUserPathCalled | Should -Be $false
    }

    It "should skip persistence when Portable Programs does not exist" {
        $script:SetUserPathCalled = $false

        $result = Add-PortableProgramsToUserPath `
            -OneDrivePath "C:\Users\Demo\OneDrive" `
            -PathExists { $false } `
            -GetUserPath { "%USERPROFILE%\bin" } `
            -SetUserPath { $script:SetUserPathCalled = $true }

        $result.Status | Should -Be "PortableProgramsMissing"
        $result.Changed | Should -Be $false
        $script:SetUserPathCalled | Should -Be $false
    }

    It "should append and persist the user PATH when the folder exists" {
        $script:WrittenUserPath = $null
        $script:WrittenValueName = $null
        $script:WrittenValueKind = $null

        $result = Add-PortableProgramsToUserPath `
            -OneDrivePath "C:\Users\Demo\OneDrive" `
            -PathExists { $true } `
            -GetUserPath {
                [pscustomobject]@{
                    Value     = "%USERPROFILE%\bin;C:\Tools"
                    ValueName = "PATH"
                    Kind      = [Microsoft.Win32.RegistryValueKind]::ExpandString
                }
            } `
            -SetUserPath {
                param(
                    [string]$Path,
                    [string]$ValueName,
                    [object]$Kind
                )
                $script:WrittenUserPath = $Path
                $script:WrittenValueName = $ValueName
                $script:WrittenValueKind = $Kind
            }

        $result.Status | Should -Be "Updated"
        $result.Changed | Should -Be $true
        $script:WrittenUserPath | Should -Be "%USERPROFILE%\bin;C:\Tools;C:\Users\Demo\OneDrive\Portable Programs"
        $script:WrittenValueName | Should -Be "PATH"
        $script:WrittenValueKind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    }

    It "should not write under WhatIf" {
        $script:SetUserPathCalled = $false

        $result = Add-PortableProgramsToUserPath `
            -OneDrivePath "C:\Users\Demo\OneDrive" `
            -PathExists { $true } `
            -GetUserPath { "C:\Tools" } `
            -SetUserPath { $script:SetUserPathCalled = $true } `
            -WhatIf

        $result.Status | Should -Be "Updated"
        $result.Changed | Should -Be $true
        $script:SetUserPathCalled | Should -Be $false
    }
}

Describe "PowerShell profile Portable Programs PATH" -Tag "Unit" {
    BeforeAll {
        $script:ProfileContent = Get-Content -LiteralPath $script:ProfilePath -Raw
    }

    It "should use OneDrive and Portable Programs for the session PATH update" {
        $script:ProfileContent | Should -Match "env:OneDrive"
        $script:ProfileContent | Should -Match "Portable Programs"
        $script:ProfileContent | Should -Match "env:Path"
    }

    It "should use a simple string check instead of reading the registry" {
        $script:ProfileContent | Should -Match "-split ';'"
        $script:ProfileContent | Should -Match "TrimEnd\('\\'\)"
        $script:ProfileContent | Should -Match "ToUpperInvariant"
        $script:ProfileContent | Should -Not -Match "GetEnvironmentVariable\(.+User"
        $script:ProfileContent | Should -Not -Match "Microsoft\.Win32\.Registry|RegistryValueOptions|Get-ItemProperty.*HKCU"
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBgq8AXGJe44vOt
# +l+CBkn+tzwXV1s3TxADNjCSbZrfsaCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCCJMF2XiB+Q5tDzeoUgR7ng2tPcQJF7LzOCvOfIqkp5azANBgkqhkiG
# 9w0BAQEFAASCAgB8RwPhjnk3Uoy0pAsG2Nhv2wtuOnJ557uQxucM67MWmxvwmLnZ
# eEZS/mQ9Nf6lzYLAbuK1FqI+qBKxtdw4/qu3VrKEWFMUYEwBWPcBxVpHYnVBKvAH
# odiLl/sr8WoJAEKN6mqvV1ESPaGQ90EntKwXDDHilZLtKdO3XAwsuoFw1lcmW4Yb
# gNMzOXNZbBT58W1w7BhHIp2PJrNf7eKba8ivH2Lffc6EBKTxHpWYC3ZMxvou4+59
# rTbJadvX0gjg5KpAuzbPMC1rFrvegnL1g7RTmxWzYUIayRvwLA3bZ+1U6WZWcud4
# YS8aGYGD6/vSrHFbPEYW/ZkNRYhxYcbt7KPtJIAM/WtE+CD2E1ITQm3mNqnbEoeD
# M/xDB/6AdZVkgj8991Q79dU3bbsAp2yKldvfuiW+RAz/giZd33H3ta85cSb0/YTk
# HHbicjAUoA1aK9HqloxdvJabvsPTMCu9kkYlhx3Rb6jTn/AUBJHTVn0BkTGBOGRj
# 3m0OLSnO0I/n7o9NXxSnuCRxV2Y8sAHe3ygU/gL1LsoyshobkKDeU+xwqZBxAbu5
# fScRU8RSZy3iB09EDwMvqePOvEe8kZKjFY6FBVeyu2ird6R054y1A9HYrhOVyBkl
# LIjbqWM8kpDn379JJaiBp/IBewxhCW12tzfK3eD68Fw6OAAQFFz0guFx66GCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MjgwNzQ5MzRaMC8GCSqGSIb3DQEJBDEi
# BCAXQn/KTJOUTSOQ0fbp/xp4VO4EGISd5dAlpfqavAmNWTANBgkqhkiG9w0BAQEF
# AASCAgAol9HhBZF8AE8Q+/e2NOZFT2tbMxlgPvb60rYU+b9acwaWLdJL3rl/fpsS
# Izp9RAnMPIE67P/8bhn/nnsSRccvQ4tSQ61m75iDQaO6RLf16FoCFVEDgDRB2xfh
# RD3l1gAlhR+SSJnN+w5LQoeczStvf17h6L2SozM7kxyt5qGA5ukgCOynp7UWzlBm
# toZxaP00ELbkDRmbd87iS9vIUQ29bKqGW2oSpkUCj0SzJ5KjrENc6IUt6ifzYmyv
# blfMO1bNWaYa5Lhn3ED5tQR7MzT+6Xtq8V5fFdDDEFScXnMx2k3v7WlTCULuWDkl
# OGTB4EWMLfFPQQT8wy77Z8l1ZZD4E7m8I7HeVxpzCY+aPqkJH57e6QxmMUSo+kEe
# /GN44FuPtTxVDAnYFyFr52g8mie148x8eYZ486PXJQjYlEZwMEnC+RHp3/cKiRrf
# RaEt/BfB8mJjibs/j+abZIczHK83yaKIts+m4gU93BbNKIANlhMc53iTNHeQc5Gc
# 0riyM7zNy+V9MPMLfoxzkzNOsmLadBnijrO7kdYvpgwbAaWuCvZK/Nt2cu4vm3lM
# 6vlhDlZPy1y2xq5zOUYZp9lgb/KeNlgyQtyLe+OvX057ajQDTUCyU3l2aNjhMYOv
# l72cnb9qRPf0Yxc+il08gHRPILT0TuqDSyyndFxLWOToU6SxjQ==
# SIG # End signature block
