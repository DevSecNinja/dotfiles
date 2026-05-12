# PowerShell installation script for Windows
# Downloads and installs chezmoi, then applies dotfiles

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ChezmoiVersion = "latest"
)

$ErrorActionPreference = "Stop"

# Function to check if running interactively
function Test-Interactive {
    # Return false (non-interactive) if:
    # - CI environment variable is set
    # - Running in automation (e.g., Azure DevOps, GitHub Actions)
    # - Host doesn't support user interaction
    if ($env:CI -eq "true" -or
        $env:TF_BUILD -eq "true" -or
        $env:GITHUB_ACTIONS -eq "true" -or
        -not [Environment]::UserInteractive) {
        return $false
    }
    return $true
}

function Get-RequiredChezmoiVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir
    )

    $versionFile = Join-Path $SourceDir ".chezmoiversion"
    if (Test-Path $versionFile) {
        return (Get-Content $versionFile -Raw).Trim()
    }

    return $null
}

function Get-ChezmoiVersion {
    param(
        [Parameter(Mandatory = $true)]
        $CommandInfo
    )

    try {
        $versionOutput = & $CommandInfo.Source --version 2>$null | Select-Object -First 1
    }
    catch {
        return $null
    }

    if ($versionOutput -match '(\d+\.\d+\.\d+(?:[-+][^\s]+)?)') {
        return $Matches[1]
    }

    return $null
}

function Test-VersionAtLeast {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter(Mandatory = $true)]
        [string]$MinimumVersion
    )

    try {
        $normalizedVersion = $Version -replace '[-+].*$', ''
        $normalizedMinimum = $MinimumVersion -replace '[-+].*$', ''
        return ([version]$normalizedVersion) -ge ([version]$normalizedMinimum)
    }
    catch {
        return $false
    }
}

function Update-PathFromMachineAndUser {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")

    if ($machinePath -and $userPath) {
        $env:Path = $machinePath + ";" + $userPath
    }
    elseif ($machinePath) {
        $env:Path = $machinePath
    }
}

function Format-CommandOutput {
    param(
        [Parameter()]
        [object[]]$Output
    )

    return ($Output | ForEach-Object { "$_" }) -join [Environment]::NewLine
}

function Update-WingetSource {
    Write-Host "Updating winget sources..." -ForegroundColor Cyan
    $sourceUpdateOutput = winget source update 2>&1
    if ($LASTEXITCODE -eq 0) {
        return
    }

    Write-Warning "winget source update failed; resetting winget sources. Captured stdout/stderr: $(Format-CommandOutput -Output $sourceUpdateOutput)"
    $sourceResetOutput = winget source reset --force 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "winget source reset failed with exit code $LASTEXITCODE. Captured stdout/stderr: $(Format-CommandOutput -Output $sourceResetOutput)"
    }

    $sourceUpdateOutput = winget source update 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "winget source update failed with exit code $LASTEXITCODE. Captured stdout/stderr: $(Format-CommandOutput -Output $sourceUpdateOutput)"
    }
}

function Get-WingetChezmoiVersion {
    $searchOutput = winget search --id twpayne.chezmoi --exact --source winget --accept-source-agreements 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "winget search chezmoi failed with exit code $LASTEXITCODE. Captured stdout/stderr: $(Format-CommandOutput -Output $searchOutput)"
        return $null
    }

    foreach ($line in $searchOutput) {
        if ($line -match '^\s*\S+\s+twpayne\.chezmoi\s+(\d+\.\d+\.\d+(?:[-+][^\s]+)?)\b') {
            return $Matches[1]
        }
    }

    Write-Warning "winget search did not return a parseable chezmoi version. Captured stdout/stderr: $(Format-CommandOutput -Output $searchOutput)"
    return $null
}

function Install-ChezmoiWithWinget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [Parameter()]
        [switch]$Upgrade
    )

    $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetPath) {
        Write-Error "winget is not available. Please install Windows Package Manager (winget) first."
        exit 1
    }

    Update-WingetSource

    # Keep the discovered package version so fresh installs can pin a version
    # that winget actually provides while still satisfying .chezmoiversion.
    $wingetVersion = $null
    if ($Version -ne "latest") {
        $wingetVersion = Get-WingetChezmoiVersion
        if (-not $wingetVersion -or -not (Test-VersionAtLeast -Version $wingetVersion -MinimumVersion $Version)) {
            $displayVersion = if ($wingetVersion) { $wingetVersion } else { "unknown" }
            Write-Error "winget provides chezmoi $displayVersion, but this source requires $Version or later. No manual installer fallback is used; run 'winget source update' manually or check winget community source status before retrying."
            exit 1
        }
    }

    $action = if ($Upgrade) { "upgrade" } else { "install" }
    $wingetArgs = @(
        $action,
        "--id", "twpayne.chezmoi",
        "--source", "winget",
        "--silent",
        "--accept-source-agreements",
        "--accept-package-agreements"
    )

    # Let winget upgrades move to its latest available package; pin fresh installs
    # to the discovered package version that satisfies .chezmoiversion.
    if ($wingetVersion -and -not $Upgrade) {
        $wingetArgs += @("--version", $wingetVersion)
    }

    Write-Host "Running: winget $($wingetArgs -join ' ')" -ForegroundColor Cyan
    winget @wingetArgs

    if ($LASTEXITCODE -ne 0) {
        throw "winget $action failed with exit code $LASTEXITCODE"
    }

    Write-Host "Chezmoi installed successfully with winget" -ForegroundColor Green
    Write-Host "Refreshing path environment variable..." -ForegroundColor Cyan
    Update-PathFromMachineAndUser
}

function Assert-RequiredChezmoiVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RequiredVersion
    )

    $chezmoiCommand = Get-Command chezmoi -ErrorAction SilentlyContinue
    if (-not $chezmoiCommand) {
        Write-Error "chezmoi was not found after package-manager installation."
        exit 1
    }

    $installedVersion = Get-ChezmoiVersion -CommandInfo $chezmoiCommand
    if (-not $installedVersion -or -not (Test-VersionAtLeast -Version $installedVersion -MinimumVersion $RequiredVersion)) {
        $displayVersion = if ($installedVersion) { $installedVersion } else { "unknown" }
        $remediation = "Run 'winget source update' and check availability with 'winget search --id twpayne.chezmoi --exact --source winget --accept-source-agreements', then rerun this installer when the required version is available."
        Write-Error "chezmoi $displayVersion was installed, but this source requires $RequiredVersion or later. $remediation"
        exit 1
    }
}

$isInteractive = Test-Interactive

# Get the source directory (script's directory)
$sourceDir = $PSScriptRoot
$requiredChezmoiVersion = if ($ChezmoiVersion -eq "latest") {
    Get-RequiredChezmoiVersion -SourceDir $sourceDir
} else {
    $ChezmoiVersion
}

# Check if chezmoi is already installed
$chezmoiExists = Get-Command chezmoi -ErrorAction SilentlyContinue

if ($chezmoiExists -and $requiredChezmoiVersion) {
    $installedChezmoiVersion = Get-ChezmoiVersion -CommandInfo $chezmoiExists
    if (-not $installedChezmoiVersion -or -not (Test-VersionAtLeast -Version $installedChezmoiVersion -MinimumVersion $requiredChezmoiVersion)) {
        $displayChezmoiVersion = if ($installedChezmoiVersion) { $installedChezmoiVersion } else { "unknown" }
        Write-Warning "chezmoi $displayChezmoiVersion is older than required $requiredChezmoiVersion"
        Install-ChezmoiWithWinget -Version $requiredChezmoiVersion -Upgrade
        Assert-RequiredChezmoiVersion -RequiredVersion $requiredChezmoiVersion
        $chezmoiExists = Get-Command chezmoi -ErrorAction SilentlyContinue
    }
}

if (-not $chezmoiExists) {
    if ($requiredChezmoiVersion) {
        Install-ChezmoiWithWinget -Version $requiredChezmoiVersion
        Assert-RequiredChezmoiVersion -RequiredVersion $requiredChezmoiVersion
        $chezmoiExists = Get-Command chezmoi -ErrorAction SilentlyContinue
    }
    else {
        try {
            Install-ChezmoiWithWinget -Version "latest"
        }
        catch {
            Write-Error "Failed to install chezmoi: $_"
            exit 1
        }
    }
}
else {
    Write-Host "Chezmoi already installed" -ForegroundColor Green
}

# Build chezmoi arguments
$chezmoiArgs = @("init", "--apply")

if (-not $isInteractive) {
    $chezmoiArgs += "--no-tty"
}

if ($sourceDir) {
    $chezmoiArgs += "--source=$sourceDir"
}

# Run chezmoi
Write-Host "`nRunning: chezmoi $($chezmoiArgs -join ' ')" -ForegroundColor Cyan
chezmoi $chezmoiArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "Chezmoi init failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "`n✅ Dotfiles installation complete!" -ForegroundColor Green
Write-Host "💡 Run 'chezmoi update' to pull and apply the latest changes" -ForegroundColor Yellow

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDXSZjzrCH0LL7y
# L4364IqyFxEacOIxL/Jqi9kku2lzMKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCB32bnEUIquycMIli+EcFZXo5HphRvuN1MbdqmIMYl6dTANBgkqhkiG
# 9w0BAQEFAASCAgBGtJXeCW4L36tZmj0pTTlPqdMHqaPvwE65xdRZqzJMZ9cCPoQN
# 3SC+3/pe/KV5XC7UhTfqgO5cmysiehVjsiO89rattK3XceqEI4S9wev2LfVaBsl8
# S/4l9L1csKxBKjGYiwWmnRKUEq030zaUgBzFUKXqiNJ2wSEc10dXcEwdJv9yoIU3
# aPwE9yP0mz9KWqVMA5JxxTcRyq2PPUFlzApUZ7sWWbLiZud7pERakoGhunzdxDAQ
# vOyrgTjNa0EkR71Vva4GbzclMoVe9oKuTqiD/kdDwk0zTdBw9609RtMUwoiUkI81
# bBogJS/GHwUaaXfIRC1v1fHu1AG3CFk7sEwKNEkC7Ab+1cRGVG4+ZVeK7X8oUHJo
# Id7punSzLkGbljFy2RsMyphdKDgSb/NaJ7U6Kf3grYqDGPHoBsuVj0wyl4E27Q/F
# Nh2TuprctoUnKzFdeo+PKp5Sf1PFtnvQZIgygdPV/G9Rc4guy0eiBaB4clwpEaDf
# x3Yxo16wWHFvSAQMdLnWHWCZ2etkFvZ2tiL8FbxWfA8s2+wZFJPdW3w9Bbm4AZ91
# dJ77OuCHFgIqSs0mCCplHzMBn3pxDLgRIkrP+2C5HCGMaB23B6aA1sj/fbMqVPDw
# MCtrHMJV0x2uf80fsyZ+vSll6MVJidzi9Gf2nz2hP0uy8lKKxVg3d8snWaGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA1MTIwOTEyMjNaMC8GCSqGSIb3DQEJBDEi
# BCAnhOaIEOpbl2L0oSSsApM12RwY/KgjUmFhBibm/Z/ywzANBgkqhkiG9w0BAQEF
# AASCAgCRYmdnoFvwWnHMKH0gTX924CNEcozp7pywlHIZPMXTXX+VsnUXFTHZZvTa
# +LTXrq2azLK1W6TfY9wgogmWunVMnTBWKogED7kWiUQo7j9CM6LND6zTOEGVNmWg
# 0wa3vYC6d10x4WnePygw+8B7vH5L04OMgyhasMjj5BuGqFiypDyYPaTZNjXw5SjX
# hDY0zQstcNdIcy6ASefu8HTx+tBB+dnfNU2RzZQjS7/xxtmDAUfYF1t3vMmKvs4K
# v+AVRNuG7giNOuhJBU5hFX6cDTPQHAKbTgvSOugpyUf6vlr7+/SYopjdrozwO1Zb
# MVO2h2IVhTaGerSbYh6sHrdLAOhVloE5dDjstCteBArIfTXswPVJMk9VZgmCxXMr
# e2PRq7EOcE1C7ZYFcPHd+8QyfVaZy6onKEyfWoc9JKEDWPsIAXGQU2iOpXVbcmiu
# i2Ix2QAvi/b6QXDzQ9M1EykhiXtHjMseaWYFZwSGht7qm/mNeWOVr5aKqxO8u7kv
# KezRg9PzuqYQAuSJcVpEWYyONFD78GjneADqu7RSMoShJ5aC7ZYZx5UADP0rE3Fu
# Jt+/4EMNCgDR+s64Y3ry9XCzWZBsfG7EKbZm37Y/XyOf3Ts7kTk6vUhwBqU1nIgk
# bpvJMQ2gD6bvfTQWEQKTg9D+7eTtlOL28pHhJtNg3xJxJPOLFA==
# SIG # End signature block
