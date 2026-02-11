# Module installation utilities

function Install-PowerShellModule {
    <#
    .SYNOPSIS
    Installs a PowerShell module using pwsh -Command for reliable installation.

    .PARAMETER ModuleName
    The name of the module to install from PowerShell Gallery.

    .EXAMPLE
    Install-PowerShellModule -ModuleName "oh-my-posh"
    #>
    param (
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    Write-Host "Installing module '$ModuleName'..." -NoNewline
    $result = pwsh -NoProfile -NonInteractive -Command "`$module = Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction SilentlyContinue -PassThru 2>&1; if (`$module) { `$module | Select-Object Name, Version | Format-Table -HideTableHeaders | Out-String } else { Write-Error 'Module installation failed' }" 2>&1

    if ($LASTEXITCODE -eq 0) {
        if ($result) {
            # Parse the output to extract module name and version
            $parsed = $result.Trim().Split(" ") | Where-Object { $_ -ne "" }
            if ($parsed.Count -ge 2) {
                $moduleInfo = [PSCustomObject]@{
                    Name    = $parsed[0]
                    Version = $parsed[1]
                }
                Write-Host " [OK] Installed $($moduleInfo.Name) $($moduleInfo.Version)" -ForegroundColor Green
                return $moduleInfo
            }
        }
    }
    else {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Module installation failed: $result"
        return $null
    }
}

function Install-GitPowerShellModule {
    <#
    .SYNOPSIS
    Installs a PowerShell module from a Git repository.

    .DESCRIPTION
    Clones a Git repository into the PowerShell modules directory and adds it to PSModulePath.
    For security reasons, only GitHub HTTPS URLs are supported.

    .PARAMETER Name
    The display name of the module for logging purposes.

    .PARAMETER Url
    The Git repository URL to clone from. Must be a GitHub HTTPS URL (e.g., https://github.com/user/repo.git).
    For security reasons, only GitHub URLs are supported.

    .PARAMETER Destination
    The destination folder name within the PowerShell modules directory.
    Must be a simple folder name without path separators or traversal characters.

    .EXAMPLE
    Install-GitPowerShellModule -Name "PowerShell-Modules" -Url "https://github.com/DevSecNinja/PowerShell-Modules.git" -Destination "DevSecNinja.PowerShell"

    .NOTES
    - Only GitHub HTTPS URLs are supported for security
    - Destination must be a simple folder name (no paths or special characters)
    - Module will be cloned to ~/Documents/PowerShell/Modules/<Destination>
    - Module path will be automatically added to PSModulePath
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    # Validate Destination to prevent path traversal attacks and UNC paths
    if ($Destination -match '(\.\.|[/\\]|^[a-zA-Z]:|^\\\\)') {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Invalid destination name. Destination must be a simple folder name without path traversal characters (e.g., 'MyModule', not '../MyModule' or 'C:\MyModule')"
        return $null
    }

    # Additional validation: ensure destination doesn't contain invalid characters
    if ($Destination -match '[<>:"|?*\x00-\x1F]') {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Invalid destination name. Contains invalid path characters."
        return $null
    }

    # Determine PowerShell modules directory
    $modulesDir = Join-Path $env:USERPROFILE "Documents\PowerShell\Modules"
    if (-not (Test-Path $modulesDir)) {
        New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null
    }

    $targetPath = Join-Path $modulesDir $Destination

    # Additional safety check: ensure target path is within modules directory
    $normalizedTarget = [System.IO.Path]::GetFullPath($targetPath)
    $normalizedModulesDir = [System.IO.Path]::GetFullPath($modulesDir)
    if (-not $normalizedTarget.StartsWith($normalizedModulesDir)) {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Security violation: Target path escapes modules directory"
        return $null
    }

    Write-Host "Installing Git module '$Name'..." -NoNewline

    # Check if module already exists
    if (Test-Path $targetPath) {
        Write-Host " [OK] Already exists at $targetPath" -ForegroundColor Yellow

        # Try to update if it's a git repository
        if (Test-Path (Join-Path $targetPath ".git")) {
            Write-Host "  Updating..." -NoNewline
            Push-Location $targetPath
            try {
                # Use git fetch and reset for a clean update (avoids merge conflicts)
                git fetch --quiet origin 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    # Get the default branch name
                    $defaultBranch = git symbolic-ref refs/remotes/origin/HEAD 2>&1 | ForEach-Object { $_ -replace 'refs/remotes/origin/', '' }
                    if (-not $defaultBranch) {
                        $defaultBranch = "main"  # Fallback to main if detection fails
                    }

                    # Reset to remote branch
                    git reset --hard "origin/$defaultBranch" --quiet 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host " [OK] Updated" -ForegroundColor Green
                    }
                    else {
                        Write-Host " [WARN] Reset failed, trying pull" -ForegroundColor Yellow
                        # Fallback to pull if reset fails
                        git pull --quiet 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Host " [OK] Updated" -ForegroundColor Green
                        }
                        else {
                            Write-Host " [WARN] Update failed" -ForegroundColor Yellow
                        }
                    }
                }
                else {
                    Write-Host " [WARN] Fetch failed" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host " [WARN] Update failed: $_" -ForegroundColor Yellow
            }
            finally {
                Pop-Location
            }
        }

        # Ensure the module path is in PSModulePath
        Add-ToPSModulePath -Path $modulesDir
        return [PSCustomObject]@{
            Name   = $Name
            Path   = $targetPath
            Status = "Exists"
        }
    }

    # Check if git is available
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Git is not installed or not in PATH. Please install Git first."
        return $null
    }

    # Validate URL format to prevent command injection
    if ($Url -notmatch '^https://github\.com/.+/.+\.git$') {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Invalid Git URL format. Only GitHub HTTPS URLs are supported (e.g., https://github.com/user/repo.git)"
        return $null
    }

    # Clone the repository using git command directly with proper escaping
    try {
        # Use git directly with proper parameter passing (not string interpolation)
        # Use -- separator to prevent argument injection
        Push-Location $modulesDir
        try {
            git clone --quiet $Url -- $Destination 2>&1 | Out-Null
            $cloneSuccess = $LASTEXITCODE -eq 0
        }
        finally {
            Pop-Location
        }

        if ($cloneSuccess -and (Test-Path $targetPath)) {
            Write-Host " [OK] Cloned to $targetPath" -ForegroundColor Green

            # Ensure the module path is in PSModulePath
            Add-ToPSModulePath -Path $modulesDir

            return [PSCustomObject]@{
                Name   = $Name
                Path   = $targetPath
                Status = "Installed"
            }
        }
        else {
            Write-Host " [FAILED]" -ForegroundColor Red
            Write-Error "Failed to clone repository from $Url"
            return $null
        }
    }
    catch {
        Write-Host " [FAILED]" -ForegroundColor Red
        Write-Error "Failed to clone repository: $_"
        return $null
    }
}

function Add-ToPSModulePath {
    <#
    .SYNOPSIS
    Adds a directory to the PSModulePath if it's not already present.

    .PARAMETER Path
    The path to add to PSModulePath.

    .EXAMPLE
    Add-ToPSModulePath -Path "C:\Users\username\Documents\PowerShell\Modules"
    #>
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        # Normalize the path with error handling
        $normalizedPath = [System.IO.Path]::GetFullPath($Path)

        # Get current PSModulePath from environment
        $currentPath = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
        if (-not $currentPath) {
            $currentPath = ""
        }

        # Split into array and check if path already exists
        $pathArray = $currentPath -split [IO.Path]::PathSeparator | Where-Object { $_ }
        $pathExists = $false

        foreach ($existingPath in $pathArray) {
            try {
                $normalizedExisting = [System.IO.Path]::GetFullPath($existingPath)
                if ($normalizedExisting -eq $normalizedPath) {
                    $pathExists = $true
                    break
                }
            }
            catch {
                # Skip invalid paths in existing PSModulePath
                Write-Verbose "Skipping invalid path in PSModulePath: $existingPath"
                continue
            }
        }

        if (-not $pathExists) {
            # Add to user's PSModulePath permanently
            if ($currentPath) {
                $newPath = $currentPath + [IO.Path]::PathSeparator + $normalizedPath
            }
            else {
                $newPath = $normalizedPath
            }
            [Environment]::SetEnvironmentVariable("PSModulePath", $newPath, "User")

            # Also update current session
            $env:PSModulePath = $env:PSModulePath + [IO.Path]::PathSeparator + $normalizedPath

            Write-Host "  Added $normalizedPath to PSModulePath" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Warning "Failed to add path to PSModulePath: $_"
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAryyE9wWACiBuV
# o4zqxMwUpJYJRa1Lv2zmQ/ZNQGmXNqCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCDFo7tix1iJXy4IZdBskyeouoMP28msAwWyAB9oJXfriDANBgkqhkiG
# 9w0BAQEFAASCAgBjlIIMW7LS2bZ+N2hUkHsn0J12/5+1Vy77AVqTCTUFWN3RGUTe
# eYztQOn8rCC84vfqGrbztRThOhlmmojCtQ2yL64bFsFWHtV/16onvknm+w4xNJ2Z
# j2PTo2HQhw4wu9qFSyEHr5phfhOLtyot5Sxpe/wzqv3R2G6Eb1RdmUkN92yOQhNJ
# zzTQCjlNa9Vi97aAHmtOJPMRUdA5wdb9d8pfFNAn1mw7JqW7CDjfvT4L0GDACg/q
# ck7tmU3IBn/EFdN4yhhVd0+wFgOMBc6nBu3HYjcQ2BPyqCeucOEbDDDrAXGJyLu3
# 2yL2xcgaz775Wh1fOT2PHCzwXZQg2/yBL+yOYxcIqtc6v20MoAYfky3pbXr5Q1qg
# s6fdiZ/R0No7CzqLv4XE8qNVef51uBKd3I3uE8xhyV9WDZUOSuvhOxaD4JFlIZih
# eBcz7ZG+OzeDwRWYVhHD5rw80/HiJo18Bs5PoQJqhZof2usE7tGLKNiB7XPRArZ6
# 9fKLxf7oOUvUi8DMPiLZBsyTujYksEWp4AUGGghrra3VnCZrkBi62tBXOenq5Oaz
# EUUPQD7qW/cMjpfhV0GS96dKGy/Tin47+8k9Ah/j8xA+0NQCKjvTBJoksnRycJf0
# CG2SBNJ186f3xcxnwHWng+VA8YVbWL0We1WlSDwlc/zPFvPaIvDRvtKj46GCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjAyMTAxNjM4NDdaMC8GCSqGSIb3DQEJBDEi
# BCAqzSjBJd3Fnw3+AIMr9kA+M420N4d8kMKBetvBu6L6xDANBgkqhkiG9w0BAQEF
# AASCAgCLGIHOAjGKXsfnByTl4SilLh/0RE9FC4uuPzacP0WcR4yDpEYHVp2jq+wZ
# f0O4GI4npLRKVeOwUyl65qCmq2Lhr9PoICxqHoVL1iNUyTSXwhM26dd2wesf9dDj
# WxdLv/h3tuhuw3+R0pX+WPHAcpX5b1xv26bW5azjVFdeUVWFhCpk3X3t1AjodMI8
# Pl7QMDK8ENMaVIid2tWxe/+bnvtEch1G0GmuEmOuxKL3gjkhp9CbRXkPV7lJwjsz
# TRmWkVKC+bjFz6wBsRZ+kEzyRJjYID+0OX8wl+cTZTJjWiNJv01pENkeCdvDbXkY
# V4jRA66TvBgYgefT9LOeoo7XJafOyUe7Sb4QiiAITTIZcFw9yTr5dbeuEPeI9kIJ
# F1o+ckBpeweN3jnk1VZvZ2A9MgzMgukjMnefUTL+cWNJrRdmJjczdOoKD72Z35Rn
# S/B7Pw7GS7UcXpE2Oj9eLlE410H9IpmpCFWKWKedsesPNNw0UsD575zewXyopUyf
# 3p9/BJ+tuZ65skqKsWZxJR6T6RWrazqfwdn+VZ8x3DC6THkR4RQhIfd3F+fw1qk6
# L8A5TKgZUtjzaOjF19gGcgQQYduiZ5HwoX0kOPMqckntVuPFgFSxyRgnpbB5ihAi
# 5GR70SQxa1ZpIn8v0kd2aX6MUqFN0cLIt+aJYNDpD5XNjW8CrQ==
# SIG # End signature block
