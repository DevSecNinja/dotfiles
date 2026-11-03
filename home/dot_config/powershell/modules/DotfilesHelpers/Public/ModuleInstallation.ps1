# Module installation utilities

function Install-PowerShellModule {
    <#
    .SYNOPSIS
    Installs a PowerShell module using pwsh -Command for reliable installation.

    .PARAMETER ModuleName
    The name of the module to install from PowerShell Gallery.

    .EXAMPLE
    Install-PowerShellModule -ModuleName "Pester"
    #>
    param (
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    Write-Host "Installing module '$ModuleName'..." -NoNewline
    $result = pwsh -ExecutionPolicy Bypass -NoProfile -NonInteractive -Command "`$module = Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction SilentlyContinue -PassThru 2>&1; if (`$module) { `$module | Select-Object Name, Version | Format-Table -HideTableHeaders | Out-String } else { Write-Error 'Module installation failed' }" 2>&1

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

                # The pwsh call above installs the module into the PowerShell 7
                # user modules directory (~\Documents\PowerShell\Modules). When
                # chezmoi runs .ps1 scripts under Windows PowerShell 5.1, those
                # scripts look in ~\Documents\WindowsPowerShell\Modules and
                # cannot see PS7-only modules. If we are currently running in
                # Windows PowerShell 5.1 and the module is not already
                # available here, install it for the current host too so
                # interactive PowerShell sessions and any future chezmoi
                # scripts can load it.
                if ($PSVersionTable.PSVersion.Major -lt 7) {
                    # Get-Module -ListAvailable checks the current host's module
                    # paths (PSModulePath), so under Windows PowerShell 5.1 this
                    # only reflects the 5.1 user/system paths — not PowerShell 7's
                    # ~\Documents\PowerShell\Modules where the pwsh subprocess
                    # above installed the module. That's exactly what we want
                    # here: only re-install if 5.1 cannot see it.
                    $alreadyAvailable = Get-Module -Name $ModuleName -ListAvailable -ErrorAction SilentlyContinue
                    if (-not $alreadyAvailable) {
                        try {
                            Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
                            Write-Host "  [OK] Also installed $ModuleName for Windows PowerShell 5.1" -ForegroundColor Green
                        }
                        catch {
                            Write-Warning "  Could not install $ModuleName for Windows PowerShell 5.1: $_"
                        }
                    }
                }

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

function Uninstall-PowerShellModule {
    <#
    .SYNOPSIS
    Removes all installed versions of a PowerShellGet module.

    .DESCRIPTION
    Checks the current host and, on Windows, the other installed PowerShell
    host so both Windows PowerShell and PowerShell 7 module paths are covered.
    Missing modules are skipped. Uninstall failures stop provisioning.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.-]*$')]
        [string]$ModuleName
    )

    if (-not $PSCmdlet.ShouldProcess($ModuleName, "Uninstall all module versions from each PowerShell host")) {
        return
    }

    $uninstallScript = {
        param([string]$Name)

        $ErrorActionPreference = "Stop"
        if (-not (Get-Module -Name $Name -ListAvailable -ErrorAction Stop)) {
            Write-Host "[SKIP] Module '$Name' is not installed in PowerShell $($PSVersionTable.PSVersion.Major)"
            return
        }

        Get-Module -Name $Name -ErrorAction Stop | Remove-Module -Force -ErrorAction Stop
        Uninstall-Module -Name $Name -AllVersions -Force -ErrorAction Stop

        if (Get-Module -Name $Name -ListAvailable -ErrorAction Stop) {
            throw "Module '$Name' is still available after uninstalling. Check its installation path and permissions."
        }
        Write-Host "[OK] Uninstalled module '$Name' from PowerShell $($PSVersionTable.PSVersion.Major)" -ForegroundColor Green
    }

    & $uninstallScript $ModuleName

    # Each host has its own CurrentUser module directory. Use a clean process
    # for the other host rather than guessing paths or deleting module folders.
    if ($env:OS -eq 'Windows_NT') {
        $otherHost = if ($PSVersionTable.PSVersion.Major -lt 7) { 'pwsh.exe' } else { 'powershell.exe' }
        $hostCommand = Get-Command -Name $otherHost -CommandType Application -ErrorAction SilentlyContinue
        if ($hostCommand) {
            $command = "& { $uninstallScript } '$ModuleName'"
            $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
            & $hostCommand.Source -NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand $encodedCommand
            if ($LASTEXITCODE -ne 0) {
                throw "Could not uninstall module '$ModuleName' using $otherHost (exit code $LASTEXITCODE)."
            }
        }
        else {
            Write-Host "[SKIP] $otherHost is not installed"
        }
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
    Install-GitPowerShellModule -Name "Office 365 Mail Alias" -Url "https://github.com/DevSecNinja/Office365AliasModule.git" -Destination "DevSecNinja.Office365AliasModule"

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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBWYSoin791Z3TB
# nyEE/Tog0eBq7UoAjLWHzBhKLbztwaCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCCFwipsdOAGOaXZbajyi+TRvx3gXlKkglP+g65EDNmzvzANBgkqhkiG
# 9w0BAQEFAASCAgC6JlizdPGlLPBsbkPgt5MrQFSq1izGfpiEXeJywSu2tbQoX66d
# kHywUwILKs8tDa0MhzA/LboPAe5hnsgK4PtMhAv2LVEHXQ/fRnHGtRR3KCRIlZ/o
# b5AENTBHfaC9cUQJY0JYLsQGuo6hSV6eeeqiJ8bTbcuWS4TiN64tfnGL8ogt15WG
# S/jZqCqsVN+BLc6J6OZumauiI0nf3jsgJjHs5+heDEeSNe+3oRhzK3BkGLdsAPh5
# M4LNC9ce7XncrYWgQDI00wuFH/Oziu04nQLcW4zdh49VN4nZzpIAEyTOR0luMDk3
# XobUkIlNkOvlmhpe+bbVDGgh2IfmHkYSfF6P/meM0kpr3kBVpss4SBzfvH/UQbd6
# 8T0nZmtCIZLPq4cFjePNVtw8705rPQhXlAHr5RK2xld1O8vSl8+jwZv9g7JnzSGW
# 6pzQ4T9/wAltRO1jQSfdLB5lG2u4maqqrCgbi092HQymtmWObzJyCYtDHkyesKVa
# amLYBkwBNRUx+KDbkFSdmLZ+0OmFogAZScDMBYxhbaIlLCkrbegULYI2uIewSLDa
# HdlGnwSDxQpBzOnkC2sulUfD02imVKaURKg5yW5tGNSve1wtF+Vh+39w6BscFG6b
# /X8WdymGdaL5/7o1PihAth2SNlfboJa8un3Qqp5EhHq/LxQc5nH/hHqS9aGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO
# 28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjExMDMxODQ1NDNaMC8GCSqGSIb3DQEJBDEi
# BCD1bHnDtY+Qfvkr5MTW34+zhQqY19IFGz//G2rIeCvx+DANBgkqhkiG9w0BAQEF
# AASCAgBMjgWlmyKagxuk0RojTOjxA+SE+5niOWC3ERvrS49iENumEvuO0l3izyW6
# YiDtHlii6adnGpNPd5gYJTLqua7iDVubo9vUkhh88r/3xh0gvCLupj7NUhcyHiRO
# VAYMtaqiZEMD2N3O9xNvVjoBWf/Sam1JKc+luQ96KpkjLIoUWh+fOZpPq3cuVNOw
# ATI+ywS/9r7lVAsdb14LewyqS/ILunDvrFNm/qj5QRiEp2SRvFWYtzfRKDxpBjU8
# xVdC3Sx7JY7nEKBqVwiyuP5bd4xrkAdc5qyvmDnEtfoxXS5KaQudTvAzBOFLsCs1
# ZSnP2mdnw3Du9Z9R2fIJjpbTI4BwlfLQZMqHATLBCCsOqrz1KVgDzZS1SO5v0fK5
# wC9xK1IPrNxeorpD3f1061P3S8eeBitdKm70WAR2xDzdNoJudPUGuEFfH9FLp7+2
# /6z2KpVkCc/HzklS8WS9T7qF5mRaKWisS9WO/9Il1VBgOzIv0TtyYGYyioNapDMJ
# iArUajGacgy8JV5WXMfyXKwUFwHSGEl80luZOSAC6m/LfBQO7bt3mrTFyRaZnrpL
# sl+EmfI3qE/N+V66XuD9bG+5ARwJ4N5Dc4bzK4IlT6e3LaVV+hUR0JllUTRhUa1E
# AyvIr1wIK4Pt2g31UP4sXwcfPysMO/oQNsZRGb3vuz7z7FHT0w==
# SIG # End signature block
