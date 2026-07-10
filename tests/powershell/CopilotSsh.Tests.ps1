#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for the Connect-CopilotSsh function in the DotfilesHelpers module.

.DESCRIPTION
    Tests the PowerShell port of the copilot-ssh / copilot_ssh helper: reading
    GitHub tokens from a 1Password Environment via `op run` and forwarding them
    to a remote host with SSH SendEnv. External `op` and `ssh` are replaced with
    PATH stubs (Windows .cmd) so the behaviour is validated without 1Password or
    a real SSH connection. Behavioural tests are Windows-only (they rely on .cmd
    stubs); static/body tests run everywhere.
#>

BeforeDiscovery {
    $script:IsWindowsHost = $IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')
}

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking

    $tmpRoot = if ($env:TEMP) { $env:TEMP } else { '/tmp' }
    $script:StubDir = (New-Item -ItemType Directory -Path (Join-Path $tmpRoot "copilot-ssh-tests-$(Get-Random)") -Force).FullName
    $script:OrigPath = $env:PATH
    $script:OrigEnvId = $env:OP_COPILOT_ENVIRONMENT_ID
    $script:Tab = [char]9

    # Writes a stub `ssh.cmd` that reports its args and the forwarded tokens.
    function script:New-SshStub {
        $sshPath = Join-Path $script:StubDir 'ssh.cmd'
        @"
@echo off
echo SSH_ARGS: %*
echo FWD_COPILOT=%COPILOT_GITHUB_TOKEN%
echo FWD_GH=%GH_TOKEN%
"@ | Set-Content -Path $sshPath -Encoding ASCII
    }

    # Writes a stub `op.cmd`. -Stdout is emitted verbatim; -ExitCode controls the
    # exit status. The stub ignores its arguments (the real child command is an
    # implementation detail); it only reproduces op's stdout/exit contract.
    function script:New-OpStub {
        param([string]$Stdout = '', [int]$ExitCode = 0)
        $opPath = Join-Path $script:StubDir 'op.cmd'
        $lines = @('@echo off')
        if ($ExitCode -ne 0) {
            $lines += "exit /b $ExitCode"
        }
        elseif ($Stdout -eq '') {
            $lines += 'echo.'
        }
        else {
            $lines += "echo $Stdout"
        }
        ($lines -join "`r`n") | Set-Content -Path $opPath -Encoding ASCII
    }

    function script:Remove-OpStub {
        Remove-Item (Join-Path $script:StubDir 'op.cmd') -Force -ErrorAction SilentlyContinue
    }
}

AfterAll {
    Pop-Location
    $env:PATH = $script:OrigPath
    if ($null -eq $script:OrigEnvId) { Remove-Item Env:OP_COPILOT_ENVIRONMENT_ID -ErrorAction SilentlyContinue }
    else { $env:OP_COPILOT_ENVIRONMENT_ID = $script:OrigEnvId }
    if (Test-Path $script:StubDir) {
        Remove-Item -Recurse -Force $script:StubDir -ErrorAction SilentlyContinue
    }
}

Describe "Connect-CopilotSsh availability" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Connect-CopilotSsh -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should be exported by the module manifest" {
        $manifestPath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/DotfilesHelpers.psd1"
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $manifest.FunctionsToExport | Should -Contain 'Connect-CopilotSsh'
    }

    It "Should be aliased as copilot-ssh and copilot_ssh in aliases.ps1" {
        $aliasesPath = Join-Path $script:RepoRoot "home/dot_config/powershell/aliases.ps1"
        $content = Get-Content $aliasesPath -Raw
        $content | Should -Match 'Set-Alias\s+-Name\s+copilot-ssh\s+-Value\s+Connect-CopilotSsh'
        $content | Should -Match 'Set-Alias\s+-Name\s+copilot_ssh\s+-Value\s+Connect-CopilotSsh'
    }
}

Describe "Connect-CopilotSsh body" -Tag "Unit" {
    BeforeAll {
        $script:Body = (Get-Command Connect-CopilotSsh).ScriptBlock.ToString()
    }

    It "Should read tokens via 'op run --no-masking'" {
        $script:Body | Should -Match 'op\s+run'
        $script:Body | Should -Match '--no-masking'
    }

    It "Should forward COPILOT_GITHUB_TOKEN via SendEnv" {
        $script:Body | Should -Match 'SendEnv=COPILOT_GITHUB_TOKEN'
    }

    It "Should conditionally forward GH_TOKEN via SendEnv" {
        $script:Body | Should -Match 'SendEnv=GH_TOKEN'
    }

    It "Should point users to install op and enable Developer settings when op is missing" {
        $script:Body | Should -Match 'Install it'
        $script:Body | Should -Match 'Settings\s*->\s*Developer'
    }

    It "Should perform fatal pre-flight checks (abort, not fall back to plain ssh)" {
        $script:Body | Should -Match "'ssh' \(OpenSSH client\) was not found"
        # A bare '& ssh' fallback in the op/env-missing branches would defeat the
        # purpose; ensure those branches Write-Error instead.
        $script:Body | Should -Match 'aborting \(tokens cannot be forwarded\)'
    }

    It "HostName parameter should have an argument completer" {
        $cmd = Get-Command Connect-CopilotSsh
        $attrs = $cmd.Parameters['HostName'].Attributes
        ($attrs | Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }) |
            Should -Not -BeNullOrEmpty
    }

    It "Should collect extra ssh options via ValueFromRemainingArguments" {
        $cmd = Get-Command Connect-CopilotSsh
        $paramAttr = $cmd.Parameters['SshArgument'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -First 1
        $paramAttr.ValueFromRemainingArguments | Should -Be $true
    }
}

Describe "Connect-CopilotSsh help" -Tag "Unit" {
    It "Should display usage for --help" {
        $out = (Connect-CopilotSsh --help *>&1) | Out-String
        $out | Should -Match 'Usage: copilot-ssh'
        $out | Should -Match 'tab-completes'
    }

    It "Should display usage for -h" {
        $out = (Connect-CopilotSsh -h *>&1) | Out-String
        $out | Should -Match 'Usage: copilot-ssh'
    }

    It "Should provide comment-based help with a synopsis" {
        (Get-Help Connect-CopilotSsh).Synopsis | Should -Match '1Password'
    }
}

Describe "Connect-CopilotSsh behaviour" -Tag "Unit" -Skip:(-not $script:IsWindowsHost) {
    BeforeEach {
        script:New-SshStub
        $env:PATH = $script:StubDir
        $env:OP_COPILOT_ENVIRONMENT_ID = 'ENV-TEST'
    }

    AfterEach {
        $env:PATH = $script:OrigPath
        Remove-Item Env:COPILOT_GITHUB_TOKEN -ErrorAction SilentlyContinue
        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
    }

    It "Aborts without invoking ssh when the OpenSSH client is missing" {
        # Point PATH at an empty dir so neither ssh nor op resolve; the ssh
        # pre-flight check must fire first and abort.
        $emptyDir = (New-Item -ItemType Directory -Path (Join-Path $script:StubDir "nopath-$(Get-Random)")).FullName
        $env:PATH = $emptyDir
        $err = @()
        $out = (Connect-CopilotSsh myhost -ErrorAction SilentlyContinue -ErrorVariable +err 2>$null) | Out-String
        ($err | Out-String) | Should -Match "'ssh' \(OpenSSH client\) was not found"
        $out | Should -Not -Match 'SSH_ARGS:'
    }

    It "Aborts without invoking ssh when op is not installed" {
        script:Remove-OpStub
        $err = @()
        $out = (Connect-CopilotSsh myhost -ErrorAction SilentlyContinue -ErrorVariable +err 2>$null) | Out-String
        $errText = $err | Out-String
        $errText | Should -Match "'1Password CLI' \(op\) was not found"
        $errText | Should -Match 'Install it'
        $errText | Should -Match 'Settings -> Developer'
        $out | Should -Not -Match 'SSH_ARGS:'
        $out | Should -Not -Match 'SendEnv'
    }

    It "Aborts without invoking ssh when the Environment ID is unset" {
        script:New-OpStub -Stdout "ctok$($script:Tab)gtok"
        Remove-Item Env:OP_COPILOT_ENVIRONMENT_ID -ErrorAction SilentlyContinue
        $err = @()
        $out = (Connect-CopilotSsh myhost -ErrorAction SilentlyContinue -ErrorVariable +err 2>$null) | Out-String
        ($err | Out-String) | Should -Match 'OP_COPILOT_ENVIRONMENT_ID is not set'
        $out | Should -Not -Match 'SSH_ARGS:'
        $out | Should -Not -Match 'SendEnv'
    }

    It "Forwards both tokens when present" {
        script:New-OpStub -Stdout "ctok$($script:Tab)gtok"
        $out = (Connect-CopilotSsh myhost *>&1) | Out-String
        $out | Should -Match 'SendEnv=COPILOT_GITHUB_TOKEN'
        $out | Should -Match 'SendEnv=GH_TOKEN'
        $out | Should -Match 'FWD_COPILOT=ctok'
        $out | Should -Match 'FWD_GH=gtok'
    }

    It "Forwards only COPILOT_GITHUB_TOKEN when GH_TOKEN is empty" {
        script:New-OpStub -Stdout 'ctok'
        $out = (Connect-CopilotSsh myhost *>&1) | Out-String
        $out | Should -Match 'SendEnv=COPILOT_GITHUB_TOKEN'
        $out | Should -Not -Match 'SendEnv=GH_TOKEN'
        $out | Should -Match 'FWD_COPILOT=ctok'
    }

    It "Passes through extra ssh arguments after a -- separator" {
        script:New-OpStub -Stdout "ctok$($script:Tab)gtok"
        $out = (Connect-CopilotSsh myhost -- -A -p 2222 *>&1) | Out-String
        $out | Should -Match '-A -p 2222 myhost'
    }

    It "Errors when COPILOT_GITHUB_TOKEN is missing from the Environment" {
        script:New-OpStub -Stdout ''
        $err = @()
        $out = (Connect-CopilotSsh myhost -ErrorAction SilentlyContinue -ErrorVariable +err 2>$null) | Out-String
        ($err | Out-String) | Should -Match 'COPILOT_GITHUB_TOKEN not found'
        $out | Should -Not -Match 'SSH_ARGS:'
    }

    It "Errors with a dedicated message when op run fails" {
        script:New-OpStub -ExitCode 3
        $err = @()
        $out = (Connect-CopilotSsh myhost -ErrorAction SilentlyContinue -ErrorVariable +err 2>$null) | Out-String
        ($err | Out-String) | Should -Match 'failed to read tokens'
        $out | Should -Not -Match 'SSH_ARGS:'
    }
}

Describe "Get-DotfilesSshHost (tab-completion source)" -Tag "Unit" {
    BeforeAll {
        # Build a fake ssh directory with a config, an Include, patterns and the
        # inline "Host=name" form so the parser is exercised end to end. The
        # helper is private, so we invoke it inside the module scope and point
        # it at the fixture via -SshDirectory.
        $script:FakeSshDir = (New-Item -ItemType Directory -Path (Join-Path $script:StubDir "sshconf-$(Get-Random)")).FullName
        New-Item -ItemType Directory -Path (Join-Path $script:FakeSshDir 'conf.d') -Force | Out-Null
        @(
            '# a comment'
            'Host svldev svldev-alt'
            '    HostName 10.0.0.1'
            'Host svlprod'
            '    User root'
            'Host *.internal'
            '    User admin'
            'Host bastion-*'
            '    User jump'
            'Include conf.d/*.conf'
        ) -join "`n" | Set-Content -Path (Join-Path $script:FakeSshDir 'config') -Encoding ASCII
        @(
            'Host extrahost'
            'Host=inlinehost'
        ) -join "`n" | Set-Content -Path (Join-Path $script:FakeSshDir 'conf.d/more.conf') -Encoding ASCII

        $script:Module = Get-Module DotfilesHelpers
    }

    It "Should be a private helper (not exported by the manifest)" {
        $manifestPath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/DotfilesHelpers.psd1"
        (Import-PowerShellDataFile -Path $manifestPath).FunctionsToExport | Should -Not -Contain 'Get-DotfilesSshHost'
    }

    It "Should return concrete host aliases including multi-name and Include entries" {
        $hosts = & $script:Module { param($d) Get-DotfilesSshHost -SshDirectory $d } $script:FakeSshDir
        $hosts | Should -Contain 'svldev'
        $hosts | Should -Contain 'svldev-alt'
        $hosts | Should -Contain 'svlprod'
        $hosts | Should -Contain 'extrahost'
        $hosts | Should -Contain 'inlinehost'
    }

    It "Should exclude pattern entries (wildcards)" {
        $hosts = & $script:Module { param($d) Get-DotfilesSshHost -SshDirectory $d } $script:FakeSshDir
        $hosts | Should -Not -Contain '*.internal'
        $hosts | Should -Not -Contain 'bastion-*'
    }

    It "Should filter by prefix" {
        $hosts = & $script:Module { param($d, $f) Get-DotfilesSshHost -SshDirectory $d -Filter $f } $script:FakeSshDir 'svl'
        $hosts | Should -Contain 'svldev'
        $hosts | Should -Contain 'svlprod'
        $hosts | Should -Not -Contain 'extrahost'
    }

    It "Should return an empty result when no config exists" {
        $empty = (New-Item -ItemType Directory -Path (Join-Path $script:StubDir "nossh-$(Get-Random)")).FullName
        $hosts = & $script:Module { param($d) Get-DotfilesSshHost -SshDirectory $d } $empty
        @($hosts).Count | Should -Be 0
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD4EOnSGdgzoNuf
# 4SGOKd3edEjowhBicRzvtsra/5x5VKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCBKRWuRUQRgC5TmZrjemaPvjVjUgpxO0yj98QM5RV8NdTANBgkqhkiG
# 9w0BAQEFAASCAgClg2JXETfS7gqq45EHaNMokP3Mcvop5Gg0e/II0J1DY3Xfh6MD
# k3tjpxPSOsgdLU/Zx+eX3QzI1VJ7yXGOQ8jQcl9klouoH/FoTg1whmnwKoZX0bpq
# pRIe548S46/8e1doTsMXUZw5R6NDclgvZaUoxWWWAJGz+DGwctvi943rTPlwX4IJ
# FhnPOxUO7X+JDOahsT3cOCe/FBpibCE7TRGVPrqoT+ZT3WK1+fBvFbxhV4unae+9
# m+twqhMVCTpHbbNgXXbtWaDFhCwpcpAc4haxGVH3LwXlWqGT6g6xTATBr2AH421e
# BRT3QzyCAd62WcFRqgZNn9sF5RnUX2ppPPUMH2ah4HQkbVs7KhKfjJRe3NKAmeWv
# xiOemAWdqwlb7PZ0bR04oaoEv/YtzLtq/bp8LoF7OfLZBQ1YGpgn+bCRTRHA4qDX
# aRYezJK6J+nr7DtB8YjnQHSC5n2Viw86DZcWs0q+yhpRzACSprCpxM16O2afapG3
# NMpvktupYYCmCiVk85Mg0gt0sFr6fhDwpVaE6ezqrNo4TrSKrHGBFNsWggRwuwoc
# 1CIoC4tz+ptA1HEVjFXPjhGnHOqg/ZvU2Ww0NtbQWRk/e+QCWJkMSmaglIMqrBvK
# 1UGqk2HA8iyXh+gamc4iRxNwU8l1ST2CFFOMDNsKySDkfGaiZU/mtd+f/aGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MTAwNzM5NDRaMC8GCSqGSIb3DQEJBDEi
# BCBuuv4zBZG5gE2ycF/mKFDAlCzTH1A+euzgs+uoGgD1aTANBgkqhkiG9w0BAQEF
# AASCAgA+LkQg1ICIHWU6FWOzwEgsiOXhVKwBZHoRWFhX475SA3yNpwxIkbqK7ZWO
# dNvTHIlCP4t+32w/ZKQXpCUSg2AS5AIRhJoNRQM216WF5AmSQ1aPk/+uwiCCs/ok
# B6VrNpvvuicedUd0THN+q7DM+p0aR81mK2/D+iCJpNEGxInyRZKfkLNawMT0lfFB
# wn7Zn3lCpirXr83tmWSw+4YmmG5PdvXZyWfLDm9F/+ZmetfiDQYY5OWqyrNqlcDF
# E8lH9itn+t7lIhcRLzJge6x+2VEhX8TQvzpZVTVj6oT0QWObZGCKnkQvDXLbqGs3
# yvPFScA9ahT2wYTofILHgv8rTrv7M/RbyazBwXI01AjZjLhf1//jz7y8e+PThonW
# 4N1OvGta+oanpSUc5YeIxAuZeFzRNSzZT7LypfRKdn7nca/yksvyIplV87qnqVYy
# +wap6kCnQDFXByN0GrT4hTXDVdEqZbZ4oWhmh1bgKveG3eNq5X99n4xMxfJI7dFu
# 9G009M6ApkPwfx6L6GRGgeJc0tNQ224Qjac8KlVqfLkqK32qZKKG/E8nInowvASd
# WQ20ObC28MKmOVeVnCYDjT07xMLbdDfveLyRg4ZBlluhEwk2R6vvh7wsUibwYF5E
# 2krTUTVKBk4+zbdM+5wXQfDBFmNOa6a5cb4BDQAf+kWT9ARfVw==
# SIG # End signature block
