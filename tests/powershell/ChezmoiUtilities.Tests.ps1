#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for ChezmoiUtilities functions in DotfilesHelpers module.

.DESCRIPTION
    Tests Reset-ChezmoiScripts, Reset-ChezmoiEntries, and Invoke-ChezmoiSigning.
    Mocks the external 'chezmoi' command to validate function behaviour without
    requiring chezmoi to be installed.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking
}

AfterAll {
    Pop-Location
}

Describe "Reset-ChezmoiScripts" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Reset-ChezmoiScripts -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Function body should call 'chezmoi state delete-bucket --bucket=scriptState'" {
        $body = (Get-Command Reset-ChezmoiScripts).ScriptBlock.ToString()
        $body | Should -Match 'chezmoi\s+state\s+delete-bucket'
        $body | Should -Match 'scriptState'
    }
}

Describe "Reset-ChezmoiEntries" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Reset-ChezmoiEntries -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Function body should call 'chezmoi state delete-bucket --bucket=entryState'" {
        $body = (Get-Command Reset-ChezmoiEntries).ScriptBlock.ToString()
        $body | Should -Match 'chezmoi\s+state\s+delete-bucket'
        $body | Should -Match 'entryState'
    }

    It "Function body should warn user about reprocessing all files" {
        $body = (Get-Command Reset-ChezmoiEntries).ScriptBlock.ToString()
        $body | Should -Match 'Warning'
        $body | Should -Match 'dry-run'
    }
}

Describe "Invoke-ChezmoiSigning" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Invoke-ChezmoiSigning -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should accept CertificateThumbprint parameter with a default value" {
        $cmd = Get-Command Invoke-ChezmoiSigning
        $cmd.Parameters.ContainsKey('CertificateThumbprint') | Should -Be $true
    }

    It "Should call 'chezmoi source-path' to determine source directory" {
        $body = (Get-Command Invoke-ChezmoiSigning).ScriptBlock.ToString()
        $body | Should -Match 'chezmoi\s+source-path'
    }

    It "Should reference Sign-PowerShellScripts.ps1 signing helper" {
        $body = (Get-Command Invoke-ChezmoiSigning).ScriptBlock.ToString()
        $body | Should -Match 'Sign-PowerShellScripts\.ps1'
    }
}


Describe "Update-Chezmoi" -Tag "Unit" {
    BeforeAll {
        $script:Module = Get-Module DotfilesHelpers
        $script:Body = (Get-Command Update-Chezmoi).ScriptBlock.ToString()
    }

    It "Should be available as a function" {
        Get-Command Update-Chezmoi -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should be exported by the module manifest" {
        $manifestPath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/DotfilesHelpers.psd1"
        (Import-PowerShellDataFile -Path $manifestPath).FunctionsToExport | Should -Contain 'Update-Chezmoi'
    }

    It "Should be aliased as chezmoi-up, chezmoi_up and czu in aliases.ps1" {
        $aliases = Get-Content (Join-Path $script:RepoRoot "home/dot_config/powershell/aliases.ps1") -Raw
        $aliases | Should -Match 'Set-Alias\s+-Name\s+chezmoi-up\s+-Value\s+Update-Chezmoi'
        $aliases | Should -Match 'Set-Alias\s+-Name\s+chezmoi_up\s+-Value\s+Update-Chezmoi'
        $aliases | Should -Match 'Set-Alias\s+-Name\s+czu\s+-Value\s+Update-Chezmoi'
    }

    It "Should pull without applying, so the old config is never used to apply" {
        $script:Body | Should -Match 'chezmoi update --apply=false'
    }

    It "Should stop after a failed step instead of continuing" {
        # Every external call is followed by a $LASTEXITCODE gate that returns.
        ([regex]::Matches($script:Body, '\$LASTEXITCODE -ne 0')).Count | Should -BeGreaterOrEqual 3
        $script:Body | Should -Match 'not continuing to init/apply'
        $script:Body | Should -Match 'not continuing to apply'
    }

    It "Should log when it skips the init step" {
        $script:Body | Should -Match 'skipping chezmoi init'
    }

    It "Should expose a ForceInit switch" {
        (Get-Command Update-Chezmoi).Parameters.ContainsKey('ForceInit') | Should -Be $true
    }

    It "Should keep its helpers private (not exported by the manifest)" {
        $manifestPath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/DotfilesHelpers.psd1"
        $exported = (Import-PowerShellDataFile -Path $manifestPath).FunctionsToExport
        $exported | Should -Not -Contain 'Get-ChezmoiConfigTemplate'
        $exported | Should -Not -Contain 'Test-ChezmoiConfigChanged'
    }
}

Describe "Test-ChezmoiConfigChanged" -Tag "Unit" {
    BeforeAll {
        $script:Module = Get-Module DotfilesHelpers
        $script:Body = & $script:Module { (Get-Command Test-ChezmoiConfigChanged).ScriptBlock.ToString() }
    }

    It "Should compare the recorded SHA256 with the template on disk" {
        $script:Body | Should -Match 'configState'
        $script:Body | Should -Match 'configTemplateContentsSHA256'
        $script:Body | Should -Match 'Get-FileHash'
    }

    It "Should default to running init when the state cannot be determined" {
        # Every early exit returns $true: a redundant init is harmless, a
        # skipped one leaves a stale config behind.
        ([regex]::Matches($script:Body, 'return \$true')).Count | Should -BeGreaterOrEqual 4
    }

    It "Should return a boolean when chezmoi is unavailable" {
        # Deterministically hide chezmoi rather than relying on the runner not
        # having it. With $ErrorActionPreference = 'Stop' (GitHub Actions'
        # `shell: pwsh`) an unguarded call would throw instead of returning.
        $originalPath = $env:PATH
        try {
            $env:PATH = Join-Path ([System.IO.Path]::GetTempPath()) "no-chezmoi-$(Get-Random)"
            $result = & $script:Module {
                $ErrorActionPreference = 'Stop'
                Test-ChezmoiConfigChanged
            }
            $result | Should -BeOfType [bool]
            $result | Should -BeTrue
        }
        finally {
            $env:PATH = $originalPath
        }
    }
}

Describe "Get-ChezmoiConfigTemplate" -Tag "Unit" {
    It "Should look for the known chezmoi config template extensions" {
        $module = Get-Module DotfilesHelpers
        $body = & $module { (Get-Command Get-ChezmoiConfigTemplate).ScriptBlock.ToString() }
        $body | Should -Match "'yaml'"
        $body | Should -Match '\.chezmoi\.\$ext\.tmpl'
    }
}


Describe "Get-ChezmoiExpectedBranch" -Tag "Unit" {
    AfterEach {
        Remove-Item Env:CHEZMOI_UP_BRANCH -ErrorAction SilentlyContinue
    }

    It "Prefers CHEZMOI_UP_BRANCH when it is set" {
        $env:CHEZMOI_UP_BRANCH = 'develop'
        InModuleScope DotfilesHelpers {
            Get-ChezmoiExpectedBranch -SourceDir '/tmp' | Should -Be 'develop'
        }
    }

    It "Falls back to main when git cannot resolve origin/HEAD" {
        InModuleScope DotfilesHelpers {
            # A directory that is not a git repo: git writes to stderr and the
            # helper must not surface that as a branch name.
            $tmp = [System.IO.Path]::GetTempPath()
            Get-ChezmoiExpectedBranch -SourceDir $tmp | Should -Be 'main'
        }
    }
}

Describe "Get-ChezmoiBranchConfirmation" -Tag "Unit" {
    AfterEach {
        Remove-Item Env:CHEZMOI_UP_ASSUME_YES -ErrorAction SilentlyContinue
        Remove-Item Env:CHEZMOI_UP_ASSUME_NO -ErrorAction SilentlyContinue
    }

    It "Answers yes when CHEZMOI_UP_ASSUME_YES is 1" {
        $env:CHEZMOI_UP_ASSUME_YES = '1'
        InModuleScope DotfilesHelpers {
            Get-ChezmoiBranchConfirmation -Message 'Switch?' | Should -BeTrue
        }
    }

    It "Answers no when CHEZMOI_UP_ASSUME_NO is 1" {
        $env:CHEZMOI_UP_ASSUME_NO = '1'
        InModuleScope DotfilesHelpers {
            Get-ChezmoiBranchConfirmation -Message 'Switch?' | Should -BeFalse
        }
    }

    It "Prefers an explicit yes over an explicit no" {
        $env:CHEZMOI_UP_ASSUME_YES = '1'
        $env:CHEZMOI_UP_ASSUME_NO = '1'
        InModuleScope DotfilesHelpers {
            Get-ChezmoiBranchConfirmation -Message 'Switch?' | Should -BeTrue
        }
    }
}

Describe "Test-ChezmoiSourceBranch" -Tag "Unit" {
    AfterEach {
        Remove-Item Env:CHEZMOI_UP_SKIP_BRANCH_CHECK -ErrorAction SilentlyContinue
    }

    It "Should be available as a function" {
        InModuleScope DotfilesHelpers {
            Get-Command Test-ChezmoiSourceBranch -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }

    It "Returns immediately when CHEZMOI_UP_SKIP_BRANCH_CHECK is 1" {
        $env:CHEZMOI_UP_SKIP_BRANCH_CHECK = '1'
        InModuleScope DotfilesHelpers {
            Mock Get-Command { throw 'the guard ran past its skip check' }
            { Test-ChezmoiSourceBranch } | Should -Not -Throw
        }
    }

    It "Does not throw when the source path cannot be determined" {
        InModuleScope DotfilesHelpers {
            { Test-ChezmoiSourceBranch } | Should -Not -Throw
        }
    }

    It "Uses --ff-only so it never creates a merge commit unattended" {
        InModuleScope DotfilesHelpers {
            (Get-Command Test-ChezmoiSourceBranch).Definition | Should -Match '--ff-only'
        }
    }

    It "Checks for uncommitted changes before switching branches" {
        InModuleScope DotfilesHelpers {
            $body = (Get-Command Test-ChezmoiSourceBranch).Definition
            $body | Should -Match 'status --porcelain'
            $body | Should -Match 'uncommitted changes'
            $body.IndexOf('status --porcelain') | Should -BeLessThan $body.IndexOf('checkout $expected')
        }
    }
}

Describe "Update-Chezmoi branch guard wiring" -Tag "Unit" {
    It "Runs the branch guard before pulling" {
        # Normalise line endings before matching. .gitattributes pins *.ps1 to
        # eol=crlf, so the working tree is CRLF on every OS while
        # [Environment]::NewLine is LF on Linux/macOS - matching against it
        # would only ever succeed on Windows.
        #
        # Match the invocations, not the comment-based help above them, which
        # also names `chezmoi update --apply=false`.
        $body = (Get-Command Update-Chezmoi).Definition -replace "`r`n", "`n"
        $guard = $body.IndexOf("Test-ChezmoiSourceBranch`n")
        $pull = $body.IndexOf('& chezmoi update --apply=false')
        $guard | Should -BeGreaterThan -1
        $pull | Should -BeGreaterThan -1
        $guard | Should -BeLessThan $pull
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC8sEcrheX+rUgk
# RS4b6lDDuLDgGqNFH7b2c3AkhuMoiqCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCBZKtG0bnArjbBXxZT258uAeFkc9EvO01ry46AgP86XhTANBgkqhkiG
# 9w0BAQEFAASCAgDABjmzYeLKgNP3pioDZc8uGUr2+Cz3DY4oEJDZniZE3Jz0Mz9Y
# U+Ms6H1yG6G/8nsX98CD7loZQoKbrofNGZ6YoZwhm60CY2ZMtZ6eNFJgaaJ0pOOX
# a3cIEGoKKVNGEYlwBqL4w+RQDpHJBIsBM+p7arP3HPvkPLpuv4iKUaRsnvKkiMeo
# m/+teSLzxA6oPdvizyrB3lreERy8prRKNO1OXyNSw4Opg5DlKnw836An3k0syqcr
# 2HyDixQpC6iJ0n3duyI/RGSynn94MOvC19lbMsjLtikiysItX/CJxICFAaBncuGg
# /JGDvIE1zQcRyqPv6+HJ4dzwfDBIja/puUyfqvgebgj8cpbXiFJbjLgZGuq17+nD
# aGloM9HnA+A4AJksSGRDEeDdSQBGU0XfHlW+erbAUFuN+UeH8yfJZJ9Gqg/FNjLo
# JxULHCMVXS3FEVFtGFwN6DYTtv3R5J2Svx4Ojvs5IQGNAHeQLO2hoszghb7BboC5
# yb2KPuqDNjZKPiv6bycWNu6I6YpMF7RJaS9DgdCd0vCE+NPBPa51kYI0a2QgjoFo
# 66yAl12orG1PPV62z5M7ggoz1UmnoVxJhB1eEPkp3VjT9RrDXz9BzaX1KG0kzfoT
# 4lDexTQvsbdyh7j+9tojzt3JHwyjAN72TILphOF8sv0nO+YwNoprCySKFqGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MjkwNDU2MjBaMC8GCSqGSIb3DQEJBDEi
# BCAAFWKUlcu4l5fqxC2dFG1ELl9Je6Fc4lcdCWM/hJuARTANBgkqhkiG9w0BAQEF
# AASCAgAJuGrBf1BkDPJkLycKFLyLrBIiGuqZtTDCoYR7MU5oMUkf5G+o6cWU1B77
# NB44YLXKGJqwLH8+8rVBVYu9B3quVTl8sOjZJF2IiBUBTXEeUNQx0mB9PXywzt5c
# TN8NOc1udMis4uj0r3FlhyjM3xzfDPBjVSYc4tmdoQ5Oi/RIdNXA3lBMQ5ffP+5l
# v+6CjPghIQvSwB6jBe1muss4cIZsrFVOqpFh5DZq0y3mVU6uttmGvUayBNlzZzWB
# UwsuOjlamIEyTsrVUZJVIFnYjQoeJu/GJftBKlkYxAnsLrkIsZ9OaqdXX8GdGBZh
# l8S+gCJGXrw9h6386WXJF6OfKxWBsXhTpnfwgvnes38DbiZQ5YrfE18+IpU3bQNR
# PtNT8zkIxSTZM3NSO7AIj0REsWRQ1PdwtDKSH0UK+c0vnpKIwO/iDxy3577AlvG2
# O145VhH+1UNhgpQHPmLAZRhPUnvn19DN1Tzw+WUZS9Mz+qRqhPIHPBlALMHMgdc+
# LThCvPp/S/hGO6YC2bDUsZf4+qiaLtdAy5dvF0xbdNLnFqF6bW/ggH1jU+ZTNgIF
# YQ8VSe8C2O2v0c1Q1pMSq9jdKcnAaC08r5R6jMfc1qrKZS4CbYkM6TvTC93jmvnJ
# HvJ542yvA8BaNl93joAySDb7HIoU9DBTsUIkdbiYwrr3NmoiRA==
# SIG # End signature block
