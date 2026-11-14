#Requires -Version 5.1

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:SetupScriptPath = Join-Path $script:RepoRoot "home/.chezmoiscripts/windows/run_onchange_20-install-modules.ps1.tmpl"
    $script:SetupScriptContent = Get-Content -Path $script:SetupScriptPath -Raw
}

Describe "PowerShell module setup script" -Tag "Unit" {
    It "Tracks package configuration changes" {
        $script:SetupScriptContent | Should -Match 'include "\.chezmoidata/packages.yaml" \| sha256sum'
    }

    It "Should create the PSResourceGet repository directory before configuring PSGallery" {
        $directoryCreation = 'New-Item -ItemType Directory -Path $repositoryStorePath -Force'
        $setRepository = 'Set-PSResourceRepository -Name "PSGallery"'

        $script:SetupScriptContent | Should -Match '\[Environment\]::GetFolderPath\(\[Environment\+SpecialFolder\]::LocalApplicationData\)'
        $script:SetupScriptContent | Should -Match 'Join-Path.+["'']PSResourceGet["'']'
        $script:SetupScriptContent.IndexOf($directoryCreation) | Should -BeGreaterThan -1
        $script:SetupScriptContent.IndexOf($directoryCreation) |
            Should -BeLessThan $script:SetupScriptContent.IndexOf($setRepository)
    }
}

Describe "PowerShell module setup rendering" -Tag "Integration" {
    BeforeAll {
        $script:TestConfig = Join-Path $TestDrive 'chezmoi.json'
        Set-Content -LiteralPath $script:TestConfig -Value '{}' -Encoding ASCII
        $script:OverrideFile = Join-Path $TestDrive 'override.json'
        $script:PackageData = chezmoi execute-template --source $script:RepoRoot --config $script:TestConfig '{{ .packages.windows | toJson }}' |
            ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw 'Could not load package data' }
    }

    It "Keeps Oh My Posh as an executable, not an installed module" {
        $script:PackageData.winget.full | Should -Contain 'JanDeDobbeleer.OhMyPosh'
        $script:PackageData.powershell_modules.uninstall | Should -Contain 'oh-my-posh'
        $script:PackageData.powershell_modules.light | Should -Not -Contain 'oh-my-posh'
        $script:PackageData.powershell_modules.full | Should -Not -Contain 'oh-my-posh'
    }

    It "Does not both install and uninstall any module" {
        $modules = $script:PackageData.powershell_modules
        foreach ($name in $modules.uninstall) {
            $name | Should -Match '^[A-Za-z0-9][A-Za-z0-9.-]*$'
            @($modules.light) + @($modules.full) | Should -Not -Contain $name
        }
    }

    It "Renders removal before installations in <Mode> mode" -TestCases @(
        @{ Mode = 'light' }
        @{ Mode = 'full' }
    ) {
        param($Mode)

        $override = @{ chezmoi = @{ os = 'windows' }; installType = $Mode } | ConvertTo-Json -Compress
        Set-Content -LiteralPath $script:OverrideFile -Value $override -Encoding ASCII
        $rendered = (chezmoi execute-template --source $script:RepoRoot --config $script:TestConfig --override-data-file $script:OverrideFile --file $script:SetupScriptPath) -join "`n"
        $LASTEXITCODE | Should -Be 0
        $rendered | Should -Match 'Uninstall-PowerShellModule -ModuleName "oh-my-posh"'
        $rendered | Should -Not -Match '(?m)^Install-PowerShellModule -ModuleName "oh-my-posh"'
        $rendered.IndexOf('Uninstall-PowerShellModule') | Should -BeLessThan $rendered.IndexOf('Install-PowerShellModule')
        $rendered | Should -Match 'Install-PowerShellModule -ModuleName "Microsoft.WinGet.Client"'
        if ($Mode -eq 'full') {
            $rendered | Should -Match 'Install-PowerShellModule -ModuleName "Pester"'
        }
        else {
            $rendered | Should -Not -Match 'Install-PowerShellModule -ModuleName "Pester"'
        }
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($rendered, [ref]$null, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty

        $destination = Join-Path $TestDrive "home-$Mode"
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        $state = Join-Path $TestDrive "state-$Mode.boltdb"
        $preview = (chezmoi apply --dry-run --verbose --no-tty --include scripts --refresh-externals=never --source $script:RepoRoot --config $script:TestConfig --override-data-file $script:OverrideFile --destination $destination --persistent-state $state --source-path $script:SetupScriptPath 2>&1) -join "`n"
        $LASTEXITCODE | Should -Be 0 -Because $preview
        $preview | Should -Match 'Uninstall-PowerShellModule -ModuleName "oh-my-posh"'
    }

    It "Renders an empty uninstall list without removal calls" {
        $override = @{
            chezmoi = @{ os = 'windows' }
            installType = 'full'
            packages = @{ windows = @{ powershell_modules = @{ uninstall = @() } } }
        } | ConvertTo-Json -Depth 6 -Compress
        Set-Content -LiteralPath $script:OverrideFile -Value $override -Encoding ASCII
        $rendered = (chezmoi execute-template --source $script:RepoRoot --config $script:TestConfig --override-data-file $script:OverrideFile --file $script:SetupScriptPath) -join "`n"

        $LASTEXITCODE | Should -Be 0
        $rendered | Should -Not -Match '(?m)^Uninstall-PowerShellModule'
    }

    It "Does not render Windows module actions on <OS>" -TestCases @(
        @{ OS = 'linux' }
        @{ OS = 'darwin' }
    ) {
        param($OS)

        $override = @{ chezmoi = @{ os = $OS }; installType = 'full' } | ConvertTo-Json -Compress
        Set-Content -LiteralPath $script:OverrideFile -Value $override -Encoding ASCII
        $rendered = (chezmoi execute-template --source $script:RepoRoot --config $script:TestConfig --override-data-file $script:OverrideFile --file $script:SetupScriptPath) -join "`n"

        $LASTEXITCODE | Should -Be 0
        $rendered | Should -Not -Match '(?m)^(Uninstall|Install)-PowerShellModule'
    }
}

Describe "PowerShell repository setup with <Manager>" -Tag "Unit" -ForEach @(
    @{ Manager = 'PSResourceGet'; UsePSResourceGet = $true }
    @{ Manager = 'PowerShellGet'; UsePSResourceGet = $false }
) {
    BeforeAll {
        $start = $script:SetupScriptContent.IndexOf('# Set-PSResourceRepository ships')
        $end = $script:SetupScriptContent.IndexOf('Write-Host "`nInstalling PowerShell Fonts..."')
        $script:RepositorySetup = [scriptblock]::Create($script:SetupScriptContent.Substring($start, $end - $start))

        function Get-PSResourceRepository { [CmdletBinding()] param() }
        function Get-PSRepository { [CmdletBinding()] param() }
        function Set-PSResourceRepository {
            [CmdletBinding()]
            param([string]$Name, [int]$Priority, [switch]$Trusted)
        }
        function Set-PSRepository {
            [CmdletBinding()]
            param([string]$Name, [string]$InstallationPolicy)
        }
    }

    BeforeEach {
        $script:UsePSResourceGet = $UsePSResourceGet
        $script:Repositories = @([pscustomobject]@{ Name = 'PSGallery' })
        Mock Get-Command {
            if ($script:UsePSResourceGet) { [pscustomobject]@{ Name = 'Set-PSResourceRepository' } }
        } -ParameterFilter { $Name -eq 'Set-PSResourceRepository' }
        Mock Get-Command { [pscustomobject]@{ Name = 'Set-PSRepository' } } -ParameterFilter { $Name -eq 'Set-PSRepository' }
        Mock Get-PSResourceRepository { $script:Repositories }
        Mock Get-PSRepository { $script:Repositories }
        Mock Set-PSResourceRepository {}
        Mock Set-PSRepository {}
        Mock New-Item {}
        Mock Write-Host {}
    }

    It "Trusts PSGallery when it is registered" {
        & $script:RepositorySetup

        if ($UsePSResourceGet) {
            Should -Invoke Set-PSResourceRepository -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'PSGallery' -and $Priority -eq 25 -and $Trusted -and $ErrorAction -eq 'Stop'
            }
            Should -Invoke Set-PSRepository -Times 0 -Exactly
            Should -Invoke New-Item -Times 1 -Exactly -ParameterFilter { $ItemType -eq 'Directory' -and $Force }
        }
        else {
            Should -Invoke Set-PSRepository -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'PSGallery' -and $InstallationPolicy -eq 'Trusted' -and $ErrorAction -eq 'Stop'
            }
            Should -Invoke Set-PSResourceRepository -Times 0 -Exactly
        }
    }

    It "Preserves replacement repositories without changing trust or adding PSGallery" {
        $script:Repositories = @([pscustomobject]@{ Name = 'CompanyGallery' })

        & $script:RepositorySetup

        Should -Invoke Set-PSResourceRepository -Times 0 -Exactly
        Should -Invoke Set-PSRepository -Times 0 -Exactly
        Should -Invoke New-Item -Times 0 -Exactly
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { "$Object" -like '*preserving configured repositories*' }
    }

    It "Fails explicitly when no repositories are registered" {
        $script:Repositories = @()

        { & $script:RepositorySetup } | Should -Throw '*No PowerShell repositories are registered*'
        Should -Invoke Set-PSResourceRepository -Times 0 -Exactly
        Should -Invoke Set-PSRepository -Times 0 -Exactly
    }

    It "Propagates repository inventory failures" {
        Mock Get-PSResourceRepository { throw 'Cannot read repositories' }
        Mock Get-PSRepository { throw 'Cannot read repositories' }

        { & $script:RepositorySetup } | Should -Throw '*Cannot read repositories*'
    }

    It "Propagates repository configuration failures" {
        Mock Set-PSResourceRepository { throw 'Cannot update repository' }
        Mock Set-PSRepository { throw 'Cannot update repository' }

        { & $script:RepositorySetup } | Should -Throw '*Cannot update repository*'
    }

    It "Fails explicitly when repository management is unavailable" {
        Mock Get-Command { $null } -ParameterFilter { $Name -in 'Set-PSResourceRepository', 'Set-PSRepository' }

        { & $script:RepositorySetup } | Should -Throw '*repository management is available*'
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD2ZBMfSurv6Dr6
# AlxhSdu4esy/gCC9B/hlYBXsjKbF/6CCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# oW2jNrbM1pD2T7m3XDCCBu0wggTVoAMCAQICEAhP3DNPfkVO28MPj/mSGDUwDQYJ
# KoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBS
# U0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNjA4MDUwMDAwMDBaFw0zNzExMDQy
# MzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7
# MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3Bv
# bmRlciAyMDI2IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2e6by
# yf7NSvjUm0xls/04xjD4fAkOkbnGQi7+Wpx81iYxfzViaxSIctuH3KSl5YEYpMuF
# gGsA31N2D9ATMbfZdw5uaAhuWevQKhDdZIB4NnqcfpfpWQXJiQnDdAElETC+bhSE
# vNLGbA8DtwUpFMQ4yyYQSPqomT92osQAv6hBi47ATZS6JfVWe6XxhF4jJZ3iSAuf
# 2Cros1czRSmWRHqMv9AfGZvp8ygYElhudpQjtcPpwoOl6QrZJUyV3iINvN4cO05p
# rGV0fkjG426xDr2d3z9lcSIHkdvGPdGUrXdxfVbgOUVcp2/8ISEzwKPW++Wa+E2u
# jI91EZtukGWDJ/xZ27k3oHKEXBRGfRTqjOU+jE3ba/5++JSE/7oNHnjs5mekExYN
# 96LV/mxUbCKJb8pBNY4r3uD7hEmk/M81XhVgwDA7aMzYC3LZBg9WY5BMmbSay5ec
# mtJuXaB/0nKWmQmVZeqTVDgsmzHP5MQuhAJkiWNuC9MmCg9TZHXbJ2/yLVSov9p1
# 6UDTLtT0+aa1vN71fHeu1qMLlLNB3WOB/ADCxr3S/1hxI92Z6jKgEED/btwIvbfu
# XkNNhg8MtDg43c4tMZae9FvqMOt/9PvmAxF9TNIsIFB8G6yb36ZJZGUL8N/pL971
# DyLXcK6HM5PYnH5X+eVtczhCgHCVQCF6XDAlPQIDAQABo4IBlTCCAZEwDAYDVR0T
# AQH/BAIwADAdBgNVHQ4EFgQUFMljijAu1Er7bpTz5uNAfvXszeIwHwYDVR0jBBgw
# FoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB
# /wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdS
# U0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
# L2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAjcU6YR6dUgrfmawJgH59KECx
# a9Ji8sEi2g10CBDaMiqsaxWyW5cwlT/6ZF5sFznazqVsoC85U9dqLOYqQwst+UQQ
# oNlDHgKRLa3xoc+OReFreFhnTXSG0Vrd2E2CZqUfm+5a+He1MJ/h+tNLuA+0Zzhn
# /Fo+FDYAHWZHx4R79ZsfRFYe9UiXpXBDf6DkUo183Y38NYmR/XfDYf7YZ+oR9t3f
# lbDwK+hgGMs0gNNp1w9Z2CyOyI5or/sSwomAuNQ0hWC9xoU4stD8aWsD7RkcmgVR
# s6vlIk3zPKQ+ylcheWkMlj+CoVRlFE55pv0ZWCaFt04lwP/rdGHE9qEVQZtyRE42
# ox7oNgC/r+Y4bSlZ3dw9K2x1xLtu6PkPKeLBFjzKigwfqm3Hm+k/+lnME8F5kPZT
# giy2HLEHklpryqs6QHnPXrRNeIzkAMyylnRN8P0wmirS0WkU+ywpEWFZ4QNg+9xS
# 43tTuW9x0eXh7NDc1P/sV+zWxHXKH8tFt1ncHdVzqrZaYPyYMLSn2TOXajveJW1L
# 3joiQSPsWRGxkbDDW15jERFE4LvjnGu2O9zD1nLJSMdlYZEikl4w2w+q4IN/R+TI
# e0H4ngCI1moJCTbevGH4punIxM1Uoi0nmX3ZK+XbRT01uowE5ViXWHng0RgsmrX/
# EdYUo80r3TfMlkD0/YMxggYTMIIGDwIBATA3MCMxITAfBgNVBAMMGEplYW4tUGF1
# bCB2YW4gUmF2ZW5zYmVyZwIQELbg9grCcadOf9RJU4Fg9DANBglghkgBZQMEAgEF
# AKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgor
# BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3
# DQEJBDEiBCBMvDTLHAuDFKMqAC+IdAO9lGahQDvZPPXsQQCUTJvGIjANBgkqhkiG
# 9w0BAQEFAASCAgCpf4r+k5aRP9mJf61Kknz8MWfJewtrXySngkdjxihlZpaubXSX
# FrYA9Nl+U0NDCxQf4PI43PgCkZgd4ilSvQssNRt3yFRnkv7qD81GDjMkUG62gCgU
# wSxcif0nt21AosufALR7QOLSrRksQ2LH0VlZ/VuwjsBmeZgxobqTIO2roKdPXS0F
# /uxMyn/2B+L/DDPmbpHnpoNox3Dmws5nnQbRMIm3fXhn++E2VJFYUFc7z8504IDE
# Z0Lzyp+FMVbmw4RY0dzLSkCjoyL/UB5rr+WhxJv/bC+o0E1kKB+V3+kE/lIZ0wzg
# iGT7v8IwYtqV3R9xx0BcM9N+LkbZcEaHeEUiJ73TgLPkRsnJy3KmIfwr6jieT0xA
# VS0iYt/bHholTsYATGSNMeIsLi7ynn7wMCa6TxuBEUCvCCNkYY6tENh/xsjWLh1O
# FYmYRH4k4rPFZ48uHxunWije6ZYFsxIkoh2hHW4X8+js2GGqbzyxWVLokDXkvVle
# Mq+w/trIunaewAVdyItcT2vujPttDJgbpoZW/eTVKF8NMME+TBLH5dGJ0LtmMBR2
# XbULevrWjxmTIejqev45rqZZsHM7q+JUNg3VEHYNyvVA8yZI6XQiMlx6JurnSYxv
# FjDr+fCXrotmGzBbPers0lqW17J63Aavc1wxam0TAxtcj7gxlfgH+AvWv6GCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO
# 28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjExMTQxMTU0MjVaMC8GCSqGSIb3DQEJBDEi
# BCBxMFW9eZ958g8e7HnVoiNvGwPr1DxAcoSbdcoqkWPlozANBgkqhkiG9w0BAQEF
# AASCAgBookTXLIZOejhPBW9Aab1x1MsiETAg74S3dpJ1ovMPfuOV+UgPzmYTKEU9
# jHejIxhR4LVVaC/GKEuQa4TMqfjzhyQzjyQKVK076De9Sf2ukc/7JKG3Um0CFOc7
# 7YGop1Yei8+hX8qMeIXVPDVEt7rgALF1wmVAfvq+ROUA9kiyqd4uAVQm3myEJskg
# Mvej8ttuBM/NsDyYQ6opjCZHtJJfXhDEf9eWdVPbiE+qyxRMOnW/ZD/AmSnmyfCj
# 0yT4RP+LlDNeqiKxLQQtKmS88XO9nURu6iEooOmsJc0Ko0LKiQND05/+HT1bTvFX
# zfe7AJv+AcYW5s+QmNuVbeuNFBnEbSrYsLWY3kkC2r+XT8DdAYvPg2FJ7hh6W3OA
# K4bcvaA8xWVm1P6XV7IiyPNe6ELe+C6g1nfFIXD1+xorDjHy3Egq15Wtg7qnO7yL
# BULLUqYDfSkg9mzZ7s8DKK/VDI4fg8+IuuyayWuwQhx6gK5qahU0pCoRQhsq9zIJ
# mlTmK17AKeufclkV3vRHpnaFtCyAiV0i5ECAnsNxVkkCZSy/ruI/33EEjycuaxB3
# IcKc1wb1XbqJ8KfjnaAHyvpom2fgnBpko8PYq4pncnBf4OlmdY4skLvCvtlKPna4
# RtMkXitzkSDM3yBMgtiAA2+qTj3YDB2jZjxJb71mSQDHUnwxyw==
# SIG # End signature block
