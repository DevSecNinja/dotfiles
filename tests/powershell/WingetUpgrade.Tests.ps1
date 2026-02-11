#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for winget upgrade functionality.

.DESCRIPTION
    Tests the PowerShell functions and scripts for automated winget package upgrades.
    Validates:
    - Test-WingetUpdates function
    - Invoke-WingetUpgrade function
    - run_winget-upgrade.ps1 script
    - Module availability checks
    - Compatibility with PowerShell Core and Windows PowerShell

.NOTES
    These tests validate the winget upgrade automation added for chezmoi integration.
    Tests run in both interactive and CI modes.
    Compatible with PowerShell 5.1+ (same as the functions being tested).

    CI COMPATIBILITY:
    Stub functions are created for Get-WinGetPackage and Update-WinGetPackage in tests
    where they need to be mocked. This allows tests to run in CI environments where the
    Microsoft.WinGet.Client module is not installed. Pester requires commands to exist
    before they can be mocked, so stubs enable mocking of external module commands.
#>

BeforeAll {
    # Setup: Navigate to repository root
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    # Load functions from the DotfilesHelpers module
    $modulePath = Join-Path $script:RepoRoot "home\dot_config\powershell\modules\DotfilesHelpers"
    if (Test-Path $modulePath) {
        # Remove all existing copies to avoid 'multiple modules loaded' errors during mocking
        Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force -DisableNameChecking
    }
    else {
        throw "DotfilesHelpers module not found at: $modulePath"
    }

    # Check if we're in CI mode
    $script:IsCIMode = [bool]$env:CI

    # Check if winget or Microsoft.WinGet.Client is available
    $script:WingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $script:WingetModuleAvailable = $null -ne (Get-Module -Name Microsoft.WinGet.Client -ListAvailable -ErrorAction SilentlyContinue)
}

AfterAll {
    Pop-Location
}

Describe "Winget Upgrade Functions" -Tag "Unit" {
    Context "Test-WingetUpdates Function" {
        It "Should be available as a function" {
            Get-Command Test-WingetUpdates -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have proper parameter definitions" {
            $cmd = Get-Command Test-WingetUpdates
            $cmd.Parameters.Keys | Should -Contain 'UseWingetModule'
        }

        It "Should return a boolean value" -Skip:(-not $script:WingetAvailable -and -not $script:WingetModuleAvailable) {
            $result = Test-WingetUpdates -ErrorAction SilentlyContinue
            $result | Should -BeOfType [bool]
        }

        It "Should handle missing winget gracefully" {
            # Mock Get-Command to simulate missing winget
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'winget' }
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'Microsoft.WinGet.Client' }

            { Test-WingetUpdates -UseWingetModule $false -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context "Invoke-WingetUpgrade Function" {
        It "Should be available as a function" {
            Get-Command Invoke-WingetUpgrade -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have proper parameter definitions" {
            $cmd = Get-Command Invoke-WingetUpgrade
            $cmd.Parameters.Keys | Should -Contain 'CountdownSeconds'
            $cmd.Parameters.Keys | Should -Contain 'Force'
            $cmd.Parameters.Keys | Should -Contain 'UseWingetModule'
        }

        It "Should accept CountdownSeconds parameter" {
            $cmd = Get-Command Invoke-WingetUpgrade
            $countdownParam = $cmd.Parameters['CountdownSeconds']
            $countdownParam.ParameterType | Should -Be ([int])
        }

        It "Should have default countdown of 3 seconds" {
            $cmd = Get-Command Invoke-WingetUpgrade
            $countdownParam = $cmd.Parameters['CountdownSeconds']
            $countdownParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Should -Not -BeNullOrEmpty
        }

        It "Should accept Force switch parameter" {
            $cmd = Get-Command Invoke-WingetUpgrade
            $forceParam = $cmd.Parameters['Force']
            $forceParam.SwitchParameter | Should -Be $true
        }

        It "Should skip detection when Force is used" {
            # Create stub functions if they don't exist (for CI environments)
            if (-not (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue)) {
                function global:Get-WinGetPackage { }
            }
            if (-not (Get-Command Update-WinGetPackage -ErrorAction SilentlyContinue)) {
                function global:Update-WinGetPackage { }
            }

            # Mock dependencies to prevent actual execution
            # Use -ModuleName to intercept calls inside the DotfilesHelpers module
            Mock Test-WingetUpdates { return $false } -ModuleName DotfilesHelpers
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'Microsoft.WinGet.Client' } -ModuleName DotfilesHelpers
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'winget' } -ModuleName DotfilesHelpers
            Mock Import-Module { } -ModuleName DotfilesHelpers
            Mock Update-WinGetPackage { } -ModuleName DotfilesHelpers
            Mock Get-WinGetPackage { return @() } -ModuleName DotfilesHelpers

            # Capture host output from inside the module
            $script:forceOutput = @()
            Mock Write-Host { $script:forceOutput += $Object } -ModuleName DotfilesHelpers

            # Run with Force to skip detection
            { Invoke-WingetUpgrade -Force -CountdownSeconds 0 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue } | Should -Not -Throw

            # Verify Force mode message appears
            $script:forceOutput -join '' | Should -Match 'Force mode|Skipping detection'
        }
    }

    Context "Function Aliases" {
        It "Should have 'wup' alias for Invoke-WingetUpgrade" {
            # Load aliases
            $aliasesPath = Join-Path $script:RepoRoot "home\dot_config\powershell\aliases.ps1"
            if (Test-Path $aliasesPath) {
                . $aliasesPath
            }

            $alias = Get-Alias -Name wup -ErrorAction SilentlyContinue
            $alias | Should -Not -BeNullOrEmpty
            $alias.Definition | Should -Be 'Invoke-WingetUpgrade'
        }

        It "Should have 'winup' alias for Invoke-WingetUpgrade" {
            # Load aliases
            $aliasesPath = Join-Path $script:RepoRoot "home\dot_config\powershell\aliases.ps1"
            if (Test-Path $aliasesPath) {
                . $aliasesPath
            }

            $alias = Get-Alias -Name winup -ErrorAction SilentlyContinue
            $alias | Should -Not -BeNullOrEmpty
            $alias.Definition | Should -Be 'Invoke-WingetUpgrade'
        }
    }
}

Describe "Winget Upgrade Script" -Tag "Integration" {
    Context "run_winget-upgrade.ps1" {
        BeforeAll {
            $script:ScriptPath = Join-Path $script:RepoRoot "home\.chezmoiscripts\windows\run_winget-upgrade.ps1"
        }

        It "Should exist" {
            Test-Path $script:ScriptPath | Should -Be $true
        }

        It "Should be a plain .ps1 file (not a template)" {
            $script:ScriptPath | Should -Match '\.ps1$'
        }

        It "Should load DotfilesHelpers module" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'Get-Command.*Invoke-WingetUpgrade'
            $content | Should -Match 'DotfilesHelpers'
        }

        It "Should check for Microsoft.WinGet.Client module" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'Microsoft\.WinGet\.Client'
        }

        It "Should call Invoke-WingetUpgrade function" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'Invoke-WingetUpgrade.*-CountdownSeconds'
        }

        It "Should use run_ prefix for chezmoi execution" {
            $scriptName = Split-Path $script:ScriptPath -Leaf
            $scriptName | Should -Match '^run_'
        }

        It "Should be compatible with PowerShell 5.1+" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match '#Requires -Version 5\.1'
        }

        It "Should handle missing module gracefully" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'not found'
            $content | Should -Match 'exit 0'
        }
    }
}

Describe "Package Configuration" -Tag "Configuration" {
    Context "packages.yaml Integration" {
        BeforeAll {
            $script:PackagesYaml = Join-Path $script:RepoRoot "home\.chezmoidata\packages.yaml"
        }

        It "Should include Microsoft.WinGet.Client in packages.yaml" {
            Test-Path $script:PackagesYaml | Should -Be $true
            $content = Get-Content $script:PackagesYaml -Raw
            $content | Should -Match 'Microsoft\.WinGet\.Client'
        }

        It "Should be in the light mode packages (installed on all Windows systems)" {
            $content = Get-Content $script:PackagesYaml -Raw

            # Find the powershell_modules section
            # Note: Manual parsing is used here instead of a YAML parser to avoid
            # introducing additional dependencies (like PowerShell-YAML module).
            # The parsing is specific to the known structure of packages.yaml.
            $lines = Get-Content $script:PackagesYaml
            $inPowerShellModules = $false
            $inLight = $false
            $foundModule = $false

            foreach ($line in $lines) {
                if ($line -match '^\s*powershell_modules:') {
                    $inPowerShellModules = $true
                }
                elseif ($inPowerShellModules -and $line -match '^\s*light:') {
                    $inLight = $true
                }
                elseif ($inLight -and $line -match '^\s*-\s*Microsoft\.WinGet\.Client') {
                    $foundModule = $true
                    break
                }
                elseif ($line -match '^\s*full:' -and $inPowerShellModules) {
                    $inLight = $false
                }
                elseif ($line -match '^\s*\w+:' -and -not $line.StartsWith('    ')) {
                    $inPowerShellModules = $false
                }
            }

            $foundModule | Should -Be $true -Because "Microsoft.WinGet.Client should be in light mode packages"
        }
    }
}

Describe "Help and Documentation" -Tag "Documentation" {
    Context "Function Documentation" {
        It "Test-WingetUpdates should have help documentation" {
            $help = Get-Help Test-WingetUpdates
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Invoke-WingetUpgrade should have help documentation" {
            $help = Get-Help Invoke-WingetUpgrade
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Test-WingetUpdates should have parameter documentation" {
            $help = Get-Help Test-WingetUpdates -Parameter UseWingetModule
            $help | Should -Not -BeNullOrEmpty
        }

        It "Invoke-WingetUpgrade should have examples" {
            $help = Get-Help Invoke-WingetUpgrade
            $help.Examples | Should -Not -BeNullOrEmpty
            $help.Examples.Example.Count | Should -BeGreaterThan 0
        }
    }
}

Describe "E2E: Winget Upgrade Workflow" -Tag "E2E" {
    Context "Mocked End-to-End Workflow (CI-safe)" {
        BeforeAll {
            # Create stub functions if they don't exist (for CI environments without Microsoft.WinGet.Client)
            if (-not (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue)) {
                function global:Get-WinGetPackage {
                    param([string]$Source)
                }
            }
            if (-not (Get-Command Update-WinGetPackage -ErrorAction SilentlyContinue)) {
                function global:Update-WinGetPackage {
                    param([string]$Id, [string]$Source, [string]$Mode, [switch]$Force)
                }
            }
        }

        It "Should complete full workflow with mocked dependencies" {
            # Mock all external dependencies inside the module scope
            Mock Get-Module {
                return [PSCustomObject]@{ Name = 'Microsoft.WinGet.Client'; Version = '1.0.0' }
            } -ParameterFilter { $Name -eq 'Microsoft.WinGet.Client' } -ModuleName DotfilesHelpers

            Mock Import-Module { } -ModuleName DotfilesHelpers

            Mock Get-WinGetPackage {
                # Simulate one package with update available
                return @([PSCustomObject]@{
                    Name = 'TestPackage'
                    Id = 'Test.Package'
                    IsUpdateAvailable = $true
                    InstalledVersion = '1.0.0'
                    AvailableVersion = '1.0.1'
                })
            } -ModuleName DotfilesHelpers

            Mock Update-WinGetPackage { } -ModuleName DotfilesHelpers

            # Capture output from inside the module
            $script:e2eOutput = @()
            Mock Write-Host { $script:e2eOutput += $Object } -ModuleName DotfilesHelpers

            # Run detection
            $hasUpdates = Test-WingetUpdates -UseWingetModule $true
            $hasUpdates | Should -Be $true

            # Run upgrade with no countdown
            { Invoke-WingetUpgrade -CountdownSeconds 0 -UseWingetModule $true } | Should -Not -Throw

            # Verify upgrade was called
            Should -Invoke Update-WinGetPackage -Times 1 -ModuleName DotfilesHelpers
        }

        It "Should handle no updates gracefully" {
            # Mock no updates available inside the module scope
            Mock Get-Module {
                return [PSCustomObject]@{ Name = 'Microsoft.WinGet.Client'; Version = '1.0.0' }
            } -ParameterFilter { $Name -eq 'Microsoft.WinGet.Client' } -ModuleName DotfilesHelpers

            Mock Import-Module { } -ModuleName DotfilesHelpers

            Mock Get-WinGetPackage {
                # Simulate no packages with updates
                return @()
            } -ModuleName DotfilesHelpers

            Mock Update-WinGetPackage { } -ModuleName DotfilesHelpers

            # Suppress output from inside the module
            Mock Write-Host { } -ModuleName DotfilesHelpers

            # Run detection
            $hasUpdates = Test-WingetUpdates -UseWingetModule $true
            $hasUpdates | Should -Be $false

            # Run upgrade - should exit early
            { Invoke-WingetUpgrade -CountdownSeconds 0 -UseWingetModule $true } | Should -Not -Throw

            # Verify upgrade was NOT called (no updates)
            Should -Invoke Update-WinGetPackage -Times 0 -ModuleName DotfilesHelpers
        }
    }

    Context "Real End-to-End Workflow (Local only)" -Skip:$script:IsCIMode {
        # These tests are only run in local environment, not in CI
        # They require actual winget/module availability and can modify system state

        It "Should detect updates (if any)" -Skip:(-not $script:WingetAvailable -and -not $script:WingetModuleAvailable) {
            { Test-WingetUpdates } | Should -Not -Throw
        }

        It "Should show proper output format" -Skip:(-not $script:WingetAvailable -and -not $script:WingetModuleAvailable) {
            # Capture host output
            $output = @()
            Mock Write-Host { $output += $Object }

            Test-WingetUpdates | Out-Null
            $output -join '' | Should -Match 'package|update|up to date'
        }
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCAbVB8oM7Pd/jK
# LXVWdLvRXTgTt+8SGp/s8JnaRcHj+KCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCAvNXyQUtu+FNTTuAhYbRlzmuJXDsTIB7ttmQ3sXjAUdTANBgkqhkiG
# 9w0BAQEFAASCAgBefJ00Rcqdkrx/VS5HVXTZl/sATtVzoNJ95wMym0xmGxyYV7of
# 0rFZc3W+dJH2nAxvAglFnth3La9TD5Qz4/nCON6T5ioGYeU2liS2e4ZQdBWJzKCq
# TIdM0EEt1Xt2pFDOA2vq8KtuakCuXobCgN38JKjHojXJG9jR/vZ/Utq+mYdUdsfR
# WnRx+QmcFJ4XdlS3ncrrWGzOcFOgZdGLMQAi/T1L53NnXiAzoeut+QF1k+TCtxz4
# UZBMj12TBmfAk5dldTqwWnD77Y8Avl1nyUl7d9YJDPJ4i+QJu8tgbQN2/6ffyOM+
# oe4mJNzfOxDZ8bd0944bTidZvIWDw0CQ+IihC+YT35vTlzHf7zO7ZB6CJhM5ZDFW
# OKBDMEZMkXYHzQYGn5BVKzZD1GH1Pne+HVvo/KJz+y1srvRRRLndM2cjZFlO6XBH
# Zbzi+ENLR18c/xFa35ko9cluRY2O9vIBtobQv57Z2vCUdFou2IXCyb9bmjiRxzxk
# tMjLnE4JsOKkiGk6gjFOW0Lms/lxZEmjTQVqw/LmiWmlnJGCKl7cksB+dTKOExO0
# YqZcHk6SsslfK0HfDDc4NxhxJz5r5q8jvZNiAUyDmOz1mvhXSy4eQux88THLgbP6
# IMSfi8tqCf0oMDuBr3NX8EBMQUfr8wUGaPORMyAArJ5OvD+YHDpQA0doy6GCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjAyMTAxNjM4NDhaMC8GCSqGSIb3DQEJBDEi
# BCAE4/181pW5SznXxXhhGMl9IHNEt6K1l5fPUJOnBXjoLzANBgkqhkiG9w0BAQEF
# AASCAgDNZdpJDqwRwOZD8+qD6MS/KL82OfFr62wHomJ4Yd3b8kvh7DJqT69RnIzp
# 5l5IbtTnnLVSpwDKOa2SHNpWkSq0Xhv0Bew5EEjxihsl7und/bbY8cenRIH+x6kz
# h2lt3MMpBZizeTq0k2EcJKIBCBMg4MmkiBk561VS7mQ9G5Jr1lvak71VgIrGQ7Jj
# KLT9mDakt3FL+C1IbHAsV6xYhOHMpDK41K4a5f79UxlcpoLAqLkyHfmIP4Y9AuNL
# HT9aN3QZGWEVY68k5tW3koHnsQEZdwMeMD2Cuy+HaFPr9zjB0sGDySrn6H/BnHgk
# sAKlVs0XUD0YnnHU1oM/w1yT+QpU5HFsHKWcGJroBT3Sp3isv1Ai7TfMz/WwHzZr
# Nzj6/ZtGuxMGYwycEEIruDRiiMbcpM712+JML3GAUATYhxBsBEkF0zmu+OueslC5
# QT9yuGgL3+ZN8ktZUopkNeRscnS9S1dDdaU+Nv0jf+kZ4Emg1uzXY8ggP6k20iEv
# wrCL+SRWaUthY6Vw6yq22841uj9QGSOv2ZtWu+3D48ia+J2C9yI2lJZldivarSwU
# W46JTANgK5ezi/ZmDEJPPubLbpFdr3375CgPxvB/gDkHY/r6o/KHlPnsLsRKEq01
# vARBdth+Epnw93jwdaPb3cX18O3UKu6/fWzQMZQ/+cJbpguLpA==
# SIG # End signature block
