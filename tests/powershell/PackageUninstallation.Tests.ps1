#Requires -Version 5.1

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $script:RepoRoot 'home\.chezmoihelpers\package-uninstall.ps1')

    function winget { }
}

Describe "Uninstall-WinGetPackage" -Tag "Unit" {
    BeforeEach {
        $script:OriginalExitCode = $global:LASTEXITCODE
        $script:Calls = @()
        Mock Write-Host {}
        Mock winget {
            $script:Calls += ,$args
            $global:LASTEXITCODE = if ($args[0] -eq 'uninstall') { 0 } else { -1978335212 }
        }
    }

    AfterEach {
        $global:LASTEXITCODE = $script:OriginalExitCode
    }

    It "Uninstalls all versions of the exact ID without interactive prompts" {
        Uninstall-WinGetPackage -Id 'Vendor.Legacy'

        $script:Calls.Count | Should -Be 2
        $script:Calls[0] -join ' ' | Should -Be 'uninstall --id Vendor.Legacy --exact --all-versions --silent --accept-source-agreements --disable-interactivity'
        $script:Calls[1] -join ' ' | Should -Be 'list --id Vendor.Legacy --exact --accept-source-agreements --disable-interactivity'
    }

    It "Skips only the explicit package-not-installed exit code" {
        Mock winget { $global:LASTEXITCODE = -1978335212 }

        Uninstall-WinGetPackage -Id 'Vendor.Legacy'

        Should -Invoke winget -Times 1 -Exactly
        Should -Invoke Write-Host -Times 1 -ParameterFilter { "$Object" -like '[[]SKIP[]]*' }
    }

    It "Reports uninstall failures including native diagnostics" {
        Mock winget { $global:LASTEXITCODE = 5; 'Access denied' }

        { Uninstall-WinGetPackage -Id 'Vendor.Legacy' } | Should -Throw '*exit code 5*Access denied*'
    }

    It "Rejects a successful uninstaller that leaves the package installed" {
        Mock winget { $global:LASTEXITCODE = 0 }

        { Uninstall-WinGetPackage -Id 'Vendor.Legacy' } | Should -Throw '*still installed*'
    }

    It "Reports verification errors rather than treating them as absence" {
        Mock winget { $global:LASTEXITCODE = if ($args[0] -eq 'uninstall') { 0 } else { 5 } }

        { Uninstall-WinGetPackage -Id 'Vendor.Legacy' } | Should -Throw '*Could not verify*exit code 5*'
    }

    It "Does not run WinGet with WhatIf" {
        Uninstall-WinGetPackage -Id 'Vendor.Legacy' -WhatIf

        Should -Invoke winget -Times 0 -Exactly
    }

    It "Rejects unsafe selectors" {
        foreach ($id in '*', '--all', 'Vendor.*', 'Vendor.Legacy;throw') {
            { Uninstall-WinGetPackage -Id $id } | Should -Throw
        }
        Should -Invoke winget -Times 0 -Exactly
    }
}

Describe "Package uninstall template wiring" -Tag "Integration" {
    BeforeAll {
        $script:Config = Join-Path $TestDrive 'chezmoi.json'
        $script:Overrides = Join-Path $TestDrive 'overrides.json'
        Set-Content -LiteralPath $script:Config -Value '{}' -Encoding ASCII
        $script:UnixScript = Join-Path $script:RepoRoot 'home\.chezmoiscripts\linux\run_onchange_10-install-packages.sh.tmpl'
        $script:WindowsScript = Join-Path $script:RepoRoot 'home\.chezmoiscripts\windows\run_onchange_10-install-packages.ps1.tmpl'
        $script:Data = chezmoi execute-template --source $script:RepoRoot --config $script:Config '{{ .packages | toJson }}' | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw 'Could not load package data' }

        function Render-PackageScript {
            param([string]$Path, [hashtable]$Overrides)
            $Overrides | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:Overrides -Encoding ASCII
            $output = chezmoi execute-template --source $script:RepoRoot --config $script:Config --override-data-file $script:Overrides --file $Path 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
            $output -join "`n"
        }

        function New-PackageOverrides {
            param([string]$OS, [string]$Mode)
            @{
                chezmoi = @{ os = $OS; osRelease = @{ id = 'ubuntu' } }
                installType = $Mode
                useYubiKey = $false
                codespaces = $false
                devcontainer = $false
                packages = @{
                    linux = @{
                        apt = @{ uninstall = @('retired-apt') }
                        dnf = @{ uninstall = @('retired-dnf') }
                        brew = @{ uninstall = @('retired-formula') }
                    }
                    darwin = @{ brew = @{
                        formulas = @{ uninstall = @('retired-formula') }
                        cask = @{ uninstall = @('retired-cask') }
                        'app-store' = @{ uninstall = @(@{ name = 'Retired App'; id = 123456 }) }
                    } }
                    windows = @{ winget = @{ uninstall = @('Vendor.Retired') } }
                }
            }

        }

        function Test-ShellSyntax {
            param([string]$Content)
            $path = Join-Path $TestDrive 'packages.sh'
            [IO.File]::WriteAllText($path, $Content.Replace("`r", '') + "`n", [Text.UTF8Encoding]::new($false))
            $output = bash -n $path 2>&1
            $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        }

        function Test-PackageDryRun {
            param([string]$Path, [string]$Expected)
            $destination = Join-Path $TestDrive 'preview-home'
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            $state = Join-Path $TestDrive 'preview.boltdb'
            $preview = (chezmoi apply --dry-run --verbose --no-tty --include scripts --refresh-externals=never --source $script:RepoRoot --config $script:Config --override-data-file $script:Overrides --destination $destination --persistent-state $state --source-path $Path 2>&1) -join "`n"
            $LASTEXITCODE | Should -Be 0 -Because $preview
            $preview | Should -Match ([regex]::Escape($Expected))
        }
    }

    It "Provides an uninstall list for every native package manager" {
        $managers = @(
            $script:Data.linux.apt, $script:Data.linux.dnf, $script:Data.linux.brew,
            $script:Data.darwin.brew.formulas, $script:Data.darwin.brew.cask,
            $script:Data.darwin.brew.'app-store', $script:Data.windows.winget
        )
        foreach ($manager in $managers) {
            $manager.PSObject.Properties.Name | Should -Contain 'uninstall'
            ($manager.uninstall -is [array]) | Should -BeTrue
        }
    }

    It "Renders WinGet removal before installs in <Mode> mode" -TestCases @(
        @{ Mode = 'light' }
        @{ Mode = 'full' }
    ) {
        param($Mode)
        $rendered = Render-PackageScript $script:WindowsScript (New-PackageOverrides windows $Mode)

        $rendered | Should -Match 'Uninstall-WinGetPackage -Id "Vendor.Retired"'
        $rendered.IndexOf('Uninstall-WinGetPackage -Id') | Should -BeLessThan $rendered.IndexOf('winget install')
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($rendered, [ref]$null, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        Test-PackageDryRun $script:WindowsScript 'Uninstall-WinGetPackage -Id "Vendor.Retired"'
    }

    It "Renders Linux removals for <Distro> in <Mode> mode" -TestCases @(
        @{ Distro = 'ubuntu'; Manager = 'apt'; Mode = 'light' }
        @{ Distro = 'ubuntu'; Manager = 'apt'; Mode = 'full' }
        @{ Distro = 'fedora'; Manager = 'dnf'; Mode = 'light' }
        @{ Distro = 'fedora'; Manager = 'dnf'; Mode = 'full' }
    ) {
        param($Distro, $Manager, $Mode)
        $overrides = New-PackageOverrides linux $Mode
        $overrides.chezmoi.osRelease.id = $Distro
        $rendered = Render-PackageScript $script:UnixScript $overrides

        $rendered | Should -Match "uninstall_package $Manager `"retired-$Manager`" \|\| exit 1"
        $rendered | Should -Match 'uninstall_package brew-formula "retired-formula" \|\| exit 1'
        $rendered | Should -Not -Match 'uninstall_package (mas|brew-cask)'
        if ($Manager -eq 'apt') {
            $rendered.IndexOf('uninstall_package apt') | Should -BeLessThan $rendered.IndexOf('apt-get install')
            $rendered | Should -Not -Match 'uninstall_package dnf'
        }
        else {
            $rendered | Should -Not -Match 'uninstall_package apt'
        }
        Test-ShellSyntax $rendered
        Test-PackageDryRun $script:UnixScript "uninstall_package $Manager"
    }

    It "Renders all macOS removals before formulas in <Mode> mode" -TestCases @(
        @{ Mode = 'light' }
        @{ Mode = 'full' }
    ) {
        param($Mode)
        $rendered = Render-PackageScript $script:UnixScript (New-PackageOverrides darwin $Mode)

        foreach ($action in 'uninstall_package mas "123456"', 'uninstall_package brew-cask "retired-cask"', 'uninstall_package brew-formula "retired-formula"') {
            $rendered | Should -Match ([regex]::Escape($action))
            $rendered.IndexOf($action) | Should -BeLessThan $rendered.IndexOf('brew_install_quiet "fastfetch"')
        }
        $rendered.IndexOf('uninstall_package mas') | Should -BeLessThan $rendered.IndexOf('uninstall_package brew-formula')
        $rendered | Should -Not -Match 'uninstall_package (apt|dnf)'
        Test-ShellSyntax $rendered
        Test-PackageDryRun $script:UnixScript 'uninstall_package mas "123456"'
    }

    It "Processes an uninstall-only Linux Homebrew configuration" {
        $overrides = New-PackageOverrides linux light
        $overrides.packages.linux.brew.light = @()
        $overrides.packages.linux.brew.full = @()
        $rendered = Render-PackageScript $script:UnixScript $overrides

        $rendered | Should -Match 'uninstall_package brew-formula "retired-formula"'
        $rendered | Should -Match 'Homebrew is required to process its uninstall list'
    }

    It "Rejects install/uninstall conflicts for every native manager" {
        foreach ($os in 'windows', 'linux', 'darwin') {
            $managers = switch ($os) {
                windows { @('winget') }
                linux { @('apt', 'dnf', 'brew') }
                darwin { @('formulas', 'cask', 'app-store') }
            }
            foreach ($manager in $managers) {
                $overrides = New-PackageOverrides $os full
                $group = if ($os -eq 'darwin') { $overrides.packages.darwin.brew[$manager] } else { $overrides.packages[$os][$manager] }
                $group.full = $group.uninstall
                $path = if ($os -eq 'windows') { $script:WindowsScript } else { $script:UnixScript }

                { Render-PackageScript $path $overrides } | Should -Throw '*listed for both installation and uninstall*'
            }
        }

    }

    It "Rejects official Homebrew aliases in <OS> <Manager> install/uninstall lists" -TestCases @(
        @{ OS = 'linux'; Manager = 'brew'; Prefix = 'homebrew/core' }
        @{ OS = 'darwin'; Manager = 'formulas'; Prefix = 'homebrew/core' }
        @{ OS = 'darwin'; Manager = 'cask'; Prefix = 'homebrew/cask' }
    ) {
        param($OS, $Manager, $Prefix)

        foreach ($list in 'light', 'full', 'yubikey') {
            foreach ($names in @(
                @{ Install = 'legacy'; Uninstall = "$Prefix/legacy" }
                @{ Install = "$Prefix/legacy"; Uninstall = 'legacy' }
                @{ Install = "$Prefix/LEGACY"; Uninstall = 'legacy' }
            )) {
                $overrides = New-PackageOverrides $OS light
                $group = if ($OS -eq 'darwin') { $overrides.packages.darwin.brew[$Manager] } else { $overrides.packages.linux.brew }
                $group[$list] = @($names.Install)
                $group.uninstall = @($names.Uninstall)

                { Render-PackageScript $script:UnixScript $overrides } | Should -Throw '*listed for both installation and uninstall*'
            }
        }
    }

    It "Keeps third-party Homebrew taps distinct in <OS> <Manager> conflicts" -TestCases @(
        @{ OS = 'linux'; Manager = 'brew'; Prefix = 'homebrew/core'; OtherPrefix = 'homebrew/cask' }
        @{ OS = 'darwin'; Manager = 'formulas'; Prefix = 'homebrew/core'; OtherPrefix = 'homebrew/cask' }
        @{ OS = 'darwin'; Manager = 'cask'; Prefix = 'homebrew/cask'; OtherPrefix = 'homebrew/core' }
    ) {
        param($OS, $Manager, $Prefix, $OtherPrefix)

        foreach ($names in @(
            @{ Install = 'vendor/tap/legacy'; Uninstall = "$Prefix/legacy" }
            @{ Install = "$Prefix/legacy"; Uninstall = 'vendor/tap/legacy' }
            @{ Install = 'vendor/one/legacy'; Uninstall = 'vendor/two/legacy' }
            @{ Install = "$OtherPrefix/legacy"; Uninstall = 'legacy' }
        )) {
            $overrides = New-PackageOverrides $OS full
            $group = if ($OS -eq 'darwin') { $overrides.packages.darwin.brew[$Manager] } else { $overrides.packages.linux.brew }
            $group.light = @($names.Install)
            $group.uninstall = @($names.Uninstall)

            { Render-PackageScript $script:UnixScript $overrides } | Should -Not -Throw
        }
    }

    It "Rejects invalid uninstall selectors before rendering executable code" {
        foreach ($os in 'windows', 'linux', 'darwin') {
            $managers = switch ($os) {
                windows { @('winget') }
                linux { @('apt', 'dnf', 'brew') }
                darwin { @('formulas', 'cask', 'app-store') }
            }
            foreach ($manager in $managers) {
                $overrides = New-PackageOverrides $os full
                $group = if ($os -eq 'darwin') { $overrides.packages.darwin.brew[$manager] } else { $overrides.packages[$os][$manager] }
                if ($manager -eq 'app-store') {
                    $group.uninstall = @(@{ name = 'Invalid'; id = '$(exit 99)' })
                }
                else {
                    $group.uninstall = @('$(exit 99)')
                }
                $path = if ($os -eq 'windows') { $script:WindowsScript } else { $script:UnixScript }

                { Render-PackageScript $path $overrides } | Should -Throw '*invalid uninstall entry*'
            }
        }
    }

    It "Does not render native removals when uninstall lists are empty" {
        foreach ($os in 'windows', 'linux', 'darwin') {
            $overrides = New-PackageOverrides $os full
            foreach ($manager in $overrides.packages.linux.Values) { $manager.uninstall = @() }
            foreach ($manager in $overrides.packages.darwin.brew.Values) { $manager.uninstall = @() }
            $overrides.packages.windows.winget.uninstall = @()
            $path = if ($os -eq 'windows') { $script:WindowsScript } else { $script:UnixScript }
            $rendered = Render-PackageScript $path $overrides

            $rendered | Should -Not -Match '(?m)^\s*(Uninstall-WinGetPackage|uninstall_package) '
        }
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD2bBpAqXSS//6c
# toxiBH4HzrUzeMJby/Ecd1A3t5RNVqCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCCxzzy8IyAxmsypmcw8sPQeVhgs3ZKcGHn071YcbAlbzzANBgkqhkiG
# 9w0BAQEFAASCAgCndeoJPzCp5i6c3PF3/GfELq4p51xxFnElLitDH/Mp1y8hjjfH
# 6jx8nWTqnT9x+p8Oa0hQ+m8sOIeooql1Gc6cG3hVGiPWVcSMlgbCnpb1laF1AoiW
# 9o+KdZlPIFbfgg1l5mIjRxxRGxHZKK47pdn0INaLjt3GZur8Z3hzo8fDMPM4gJUl
# hxlq8KbXObhNI4VgesEjZGAhKrI8qp714zeaAO8kLhznuFiynEp0YMxDBfRP7ev9
# VfWTlw9TAoovFqFr1VnsOBo+p2AqzRxQ2mH9pz+ZdfaqOP8hLREsejda31nEi/Ze
# WJzMRjGBA/Uaxt25m8T7KhWZuYIAY6cB26dLwKLrIeiFjxa3a42f19QHGiNjGejy
# 2yiXXKLFvuIpaozddDZ5eOSjN+COsXMNgOn2dJWlC3nZ3WnP5nsZKVXiWmiBdkWf
# vrIzoKHZcyg8ibHMFaIrAN5lxNUuARSrpFGTU3Mm98vCqxDswSekxnGhRXprL0jz
# VgOD56+ruBXSNt35PmLb59JdVkl1OR9hELMA94HO22TOZ1RD7NVFRxutLORJTRVO
# EL8KpaqlGiWGySK5jdQBPii1rHyR4lfgOwxGX2a6SiOKzPFFneZl2VI0caKr0xO4
# Rv9vm012rWmnDE52nE7AKQhemV6+ITUGxXi9jh3JZTe7iCHdpenyjs6kQqGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO
# 28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjExMTQxMTU0MjVaMC8GCSqGSIb3DQEJBDEi
# BCATYvw7S0unjEmjIbFA8icGo2I0Q8pBesmrBNYenoQVJTANBgkqhkiG9w0BAQEF
# AASCAgA9wY6Zuh8wHy2YVvfgW1Lrc+vwmtCDVOVB9BJTjvZTpMECI8iFIH8HcFDn
# LgszjAtFkEQ3RDS/YNghQpRY0Q8nu6AoScfJQQYXizlR2hm4zJX9afKr2kDoW90D
# OVCg4pVft9QcAuD6xm2AlnSptqJVoCO5/Y2fblYAmyoKdy8i6ZLpgi6ErE5QIZJ6
# x2KMq+onr9VrmEhYO3Sy3isHXf1HujQc1U08GqnaF4Ig77RBvQw1r0MwVyzNPk95
# pT9DzwDZYYFzisGY5e0lmgl5ea+25mmnscvlKSkhph67JPoJajwWpp5UcJ5//Cen
# um6prqQ3T0+RAzgAx0B4xuUQ9Ogkas7gPa7VgH7o2++xA6gnfrMGCedR6iJ2Rl8C
# bEJnx3OXFJYBPsspDDFge6CQocKPPvp5woF3k6SM2XPGSmKaQzL0Jzpm8aa0/sAF
# d6qfnJgoZqlhjqXnT64JYnlHdsU9hllOnQJGZVFQnOAQR1BGwaj7Umjw4zyVWwX7
# kwL9prKWBKaELM3sjKIK1/n7mJIBtx+JTA+ZSpcwEJ6XyWnK6Di4FWAj2JSldfjs
# ksDH8mH8DNYqgKJnLRFODvT0uk7Th8sQHGqSO8yQKLXKvNst6kU/9h1QpfVE2h7o
# cqh1Pt/gtOMyZlRmvmNrq7XtxpnluwCVNmyaBsGymkOOo9I2fQ==
# SIG # End signature block
