# PowerShell Profile Configuration
# This file is loaded when PowerShell starts
# Location: $PROFILE (typically ~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1)
# But managed by chezmoi in ~/.config/powershell/

# Measure profile load time for performance diagnostics
$script:_profileLoadStart = [System.Diagnostics.Stopwatch]::StartNew()

# Set when the fastfetch banner rendered, so the welcome lines below can stay
# out of the way.
$script:_fastfetchShown = $false

# Set UTF-8 encoding (force code page 65001 for Windows PowerShell 5.1)
if ($PSVersionTable.PSVersion.Major -lt 7) {
    chcp 65001 | Out-Null
}
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Environment variables
$env:SOPS_EDITOR = "code --wait"

# Load chezmoi configuration variables
$chezmoiConfig = Join-Path $PSScriptRoot "chezmoi.ps1"
if (Test-Path $chezmoiConfig) {
    . $chezmoiConfig
}

# Add OneDrive Portable Programs to this PowerShell session without reading
# the registry on every startup. Persistence is handled by a chezmoi script.
if ($env:OneDrive) {
    $portableProgramsPath = Join-Path $env:OneDrive "Portable Programs"
    $portableProgramsKey = $portableProgramsPath.Trim().Trim('"').TrimEnd('\').ToUpperInvariant()
    $portableProgramsInPath = $false
    $currentSessionPath = if ($null -eq $env:Path) { "" } else { $env:Path }

    foreach ($pathEntry in ($currentSessionPath -split ';')) {
        if ($pathEntry.Trim().Trim('"').TrimEnd('\').ToUpperInvariant() -eq $portableProgramsKey) {
            $portableProgramsInPath = $true
            break
        }
    }

    if (-not $portableProgramsInPath) {
        $env:Path = if ([string]::IsNullOrWhiteSpace($currentSessionPath)) {
            $portableProgramsPath
        }
        elseif ($currentSessionPath.EndsWith(';')) {
            "$currentSessionPath$portableProgramsPath"
        }
        else {
            "$currentSessionPath;$portableProgramsPath"
        }
    }
}

# Load DotfilesHelpers module (lazy-loadable via PSModulePath, explicit import for profile)
$dotfilesModulePath = Join-Path $PSScriptRoot "modules\DotfilesHelpers"
if (Test-Path $dotfilesModulePath) {
    Import-Module $dotfilesModulePath -DisableNameChecking
}

# Set working directory to projects folder if not already there
# Get-ProjectsPath prefers a Dev Drive over $env:USERPROFILE when one exists
# Skip this if running in VS Code to preserve the opened folder location
if ($ENV:TERM_PROGRAM -ne "vscode") {
    $currentPath = (Get-Location).Path
    $projectsPath = if (Get-Command Get-ProjectsPath -ErrorAction SilentlyContinue) {
        Get-ProjectsPath
    }
    else {
        Join-Path $env:USERPROFILE "projects"
    }

    # Check if current path contains 'projects' (case-insensitive)
    if ($currentPath -notlike "*projects*") {
        # Not in projects directory, change to it if it exists
        if (Test-Path $projectsPath) {
            Set-Location $projectsPath
        }
    }
}

# Load aliases
. $PSScriptRoot\aliases.ps1

# Cache git command availability once at startup (avoids a full PATH scan on every prompt render)
$script:_gitCmd = Get-Command git -ErrorAction SilentlyContinue

# Custom prompt (simple and clean)
function prompt {
    $loc = Get-Location
    $gitBranch = ""

    # Get git branch if in a git repo (availability cached at profile startup)
    if ($script:_gitCmd) {
        $gitBranch = & git rev-parse --abbrev-ref HEAD 2>$null
        if ($gitBranch) {
            $gitBranch = " ($gitBranch)"
        }
    }

    Write-Host "$loc" -NoNewline -ForegroundColor Cyan
    Write-Host "$gitBranch" -NoNewline -ForegroundColor Yellow
    return "> "
}

# Load completions
$completionsPath = Join-Path $PSScriptRoot "completions"
if (Test-Path $completionsPath) {
    Get-ChildItem -Path $completionsPath -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}

# Show fastfetch only in interactive sessions (not when scripts import modules),
# mirroring the fish_greeting behaviour on Linux/macOS. fastfetch is installed on
# Windows via winget (Fastfetch-cli.Fastfetch) and simply does not run when it is
# absent, so a light install stays quiet.
#
# Guarded with a timeout because a fetch tool occasionally hangs on a hardware
# probe (e.g. the GPU query on Snapdragon X), which would otherwise freeze the
# entire profile load and ignore Ctrl+C. See issue: pwsh session hangs on
# profile load.
if ([Environment]::UserInteractive -and -not $env:CHEZMOI_SOURCE_DIR) {
    $fastfetchCmd = Get-Command fastfetch -ErrorAction SilentlyContinue
    if ($fastfetchCmd) {
        # Render the extra status lines (winget updates) and, when the cache has
        # aged out, kick off a detached refresh for the next shell. Both are
        # cheap; the expensive winget query never runs on this path. See
        # DotfilesHelpers/Public/FastfetchStatus.ps1.
        if (Get-Command Update-FastfetchStatusCache -ErrorAction SilentlyContinue) {
            try {
                Update-FastfetchStatusCache
            } catch {
                # A missing status line is never a reason to break the shell.
                Write-Verbose "fastfetch status cache update failed: $($_.Exception.Message)"
            }
        }

        # Allow users to tune the timeout (milliseconds) via an env var.
        $fastfetchTimeoutMs = 5000
        $parsedTimeout = 0
        if ($env:FASTFETCH_TIMEOUT_MS -and
            [int]::TryParse($env:FASTFETCH_TIMEOUT_MS, [ref]$parsedTimeout) -and
            $parsedTimeout -gt 0) {
            $fastfetchTimeoutMs = $parsedTimeout
        }

        if ($fastfetchCmd.CommandType -in @([System.Management.Automation.CommandTypes]::Application,
                                            [System.Management.Automation.CommandTypes]::ExternalScript)) {
            # External executable/script: launch it attached to the current
            # console so colors/unicode render normally, and kill it if it
            # doesn't finish within the timeout.
            try {
                $fastfetchProc = Start-Process -FilePath $fastfetchCmd.Source `
                    -NoNewWindow -PassThru -ErrorAction Stop
                if (-not $fastfetchProc.WaitForExit($fastfetchTimeoutMs)) {
                    try { $fastfetchProc.Kill() } catch { }
                    Write-Host "`n(fastfetch timed out after $([math]::Round($fastfetchTimeoutMs / 1000, 1))s; skipping)" -ForegroundColor DarkYellow
                } elseif ($fastfetchProc.ExitCode -eq 0) {
                    # Only a clean run actually painted a banner. A non-zero exit
                    # (bad config, for instance) leaves the screen empty, so the
                    # welcome lines below stay as the one sign of life.
                    $script:_fastfetchShown = $true
                }
            } catch {
                Write-Host "(fastfetch failed to start: $($_.Exception.Message))" -ForegroundColor DarkYellow
            }
        } else {
            # Function/alias/cmdlet: no reliable way to cancel cooperatively,
            # so just invoke it directly.
            fastfetch
            $script:_fastfetchShown = $true
        }
    }
}

# Welcome message (only in interactive sessions). fastfetch already reports the
# shell and everything else worth knowing, so when its banner rendered these two
# lines are pure noise and are skipped. A light install without fastfetch keeps
# them, so an interactive shell still confirms the profile loaded.
if ([Environment]::UserInteractive -and -not $env:CHEZMOI_SOURCE_DIR -and -not $script:_fastfetchShown) {
    $script:_profileLoadStart.Stop()
    $loadTimeMs = $script:_profileLoadStart.ElapsedMilliseconds
    Write-Host "[OK] PowerShell Profile Loaded ($loadTimeMs ms)" -ForegroundColor Green
    Write-Host ">> Type 'aliases' to see available aliases" -ForegroundColor Yellow
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCCFpofwpoC8EyI
# eMnI04dlqIlfQa6YwTxfdhOWsZpmiaCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCDlPjZqJ9Bj3qdMfdeYJWAuqvyL4t+EulppEXmz35YY4DANBgkqhkiG
# 9w0BAQEFAASCAgCeZbJ76ZX6PtvuH5Q4IbpylV/GCQFJBim6DUNDcLTg5e9OzK5P
# p32krm4gcdh3+bOcabU4wfazWVOtB2ARyLnRye/6yQdvw5cbW6AJH1F9oEfiDjJu
# Oz1rtSlw8tV4Os0ClVpxsz+KKMJgv/ZsJmXQbYfXHxWiHL07cmVTK1aYE78Z/PSG
# g1koNzrLE4UK4o5bcyDepbRxkijuKyi2Za8Q6UQySGrLbW5twAgkdCV1ylT2SDTd
# vXiZCu98tDSmKWgTBCNb26bm+9faEl2huFHtCsCNB7xC09d/hObgwDAPgQbMY4Ov
# Co4N+O5Wn8kxhj+WAmaUWMtOOi4i8FsJ6Yfb/pr5aXXEf9R5bjbJThR/sUocmsYu
# XU+H7ppBA1A2N/YbU+2FFabV99AvCaUBZGixEXcya/TNYskeF+OyWZhvZhEtD9hA
# q1KN44HPsRAjCSTy9MpRnuZy0Cc5Sbb4BNrquudaTFqJScDBYGYCU4Uje6mEct03
# U8GuzynNZia5hiobKoRXEKtmPTon0BNAGFKk+tvP+iXbjXNZsp/56B65wEFvnXSj
# M1bjI/fK/BkF/qn45Tt3IMYfLgQifCdgBiiqgTlUBKGZ1PoT7tH/it0lK0u/LEoD
# E1zk5JFfZXD/KLRpQGstA1jloxNpiE5fT2T0NZJN+94Yc9965KPEgRZxJaGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO
# 28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA5MDcxOTE0NTlaMC8GCSqGSIb3DQEJBDEi
# BCDvrUDr04Wj/L1A3TE6eJMUKZlSPunyyJv6sEE4Z1P9+DANBgkqhkiG9w0BAQEF
# AASCAgAm9EatQ+yFTmFsQgRPLBKt7JRnXScx9rCXZRezSfzMLFhcdC//CIwZRwsj
# hhQ4lxsZSqViXB8CwLQjJ0fmFmVctpwBP9Fvx4zWgSLb6YuSzsxfBimy9KC0aeMl
# YrsKoEMAsV1iMdP+/1eAruIKbE2JqZvAsh1ztb+CqdCfhzW8InoEXxkxmFvP+qQB
# 7f0nFbMeb3KG7maR9yXqF82cNpgPtbYqVGaQ/6yVkSgpkeNsXiD0yo0WD/IxWtMt
# s+u3iFXJN2zmr/7SWSkuTla3/WpP0K91eGCEZGZGT0B03+FoX0R92U01NLI5M6+k
# Jy+o3mLZFke7NAsRpjiZjBAPEbKSnzU0Uip1VX4UTD4OAjLe9eFIzg6WYJymzOem
# p/cU6InUwyCx62Sn0xhLlZdlXOqbZ2YkVY1Lu59PeQVKvVkoCuWOgSRlZdB9/flR
# KJYssJ6fG6Wd35A16OJ+nB7P1knoa6uL3xTwZtvEfP0zRV2oRONUlhzyYBKLXoiV
# REpg14sdLby4xuKPKz67p1FBJsn2f7IZeWrzWhm003FNZ/zpy3SHvDLjDQ0xevIH
# JH/ab3O7E1hxtpCAilf9LeTUKWXhu/FkmkAwTpT1NcCaxoHA0pSP2FD0Ih5VrDK5
# AQbet/1ksWflyfvEcxvi4OlrwKDZ2AJ0MOMDj+GcqnAe/tItsQ==
# SIG # End signature block
