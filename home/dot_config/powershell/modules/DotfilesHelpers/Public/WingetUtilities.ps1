# Winget utilities

function Test-WingetUpdates {
    <#
    .SYNOPSIS
    Checks for available winget package updates.

    .DESCRIPTION
    Uses Microsoft.WinGet.Client to quickly detect if any package updates are available.
    Returns true if updates are found, false otherwise.

    .PARAMETER UseWingetModule
    Use the Microsoft.WinGet.Client PowerShell module instead of winget.exe.
    Defaults to true for better performance and compatibility.

    .EXAMPLE
    Test-WingetUpdates
    Returns $true if updates are available, $false otherwise.

    .NOTES
    Requires Microsoft.WinGet.Client module or winget.exe to be installed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [bool]$UseWingetModule = $true
    )

    # Check if Microsoft.WinGet.Client is available
    $wingetModule = Get-Module -Name Microsoft.WinGet.Client -ListAvailable -ErrorAction SilentlyContinue

    if ($UseWingetModule -and $wingetModule) {
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop

            # Get updates using the PowerShell module (faster and more reliable)
            Write-Verbose "Checking for updates using Microsoft.WinGet.Client module..."
            $updates = Get-WinGetPackage -Source winget | Where-Object { $_.IsUpdateAvailable }

            if ($updates -and $updates.Count -gt 0) {
                Write-Host "[OK] Found $($updates.Count) package update(s) available" -ForegroundColor Green
                return $true
            }
            else {
                Write-Host "[OK] All packages are up to date" -ForegroundColor Green
                return $false
            }
        }
        catch {
            Write-Warning "Failed to use Microsoft.WinGet.Client module: $_"
            Write-Warning "Falling back to winget.exe..."
            $UseWingetModule = $false
        }
    }

    # Fallback to winget.exe if module not available or failed
    if (-not $UseWingetModule -or -not $wingetModule) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Warning "Neither Microsoft.WinGet.Client module nor winget.exe is available."
            Write-Warning "Please install Microsoft.WinGet.Client: Install-Module -Name Microsoft.WinGet.Client"
            return $false
        }

        Write-Verbose "Checking for updates using winget.exe..."
        $result = winget upgrade --source winget --accept-source-agreements 2>&1 | Out-String

        # Parse winget output to check for updates
        # Winget shows "No installed package found matching input criteria" when no updates
        if ($result -match "No applicable upgrade found" -or $result -match "No installed package") {
            Write-Host "[OK] All packages are up to date" -ForegroundColor Green
            return $false
        }
        elseif ($result -match "(\d+) upgrades available") {
            $count = $Matches[1]
            Write-Host "[OK] Found $count package update(s) available" -ForegroundColor Green
            return $true
        }
        else {
            # Assume updates available if we can't determine (safer to prompt)
            Write-Verbose "Unable to parse winget output, assuming updates available"
            return $true
        }
    }

    return $false
}

# Soak time: only upgrade to package versions that have been published in
# microsoft/winget-pkgs for at least N days. winget has no native minimum
# package age yet (see microsoft/winget-cli#6178), so the age is derived from
# the community repository: a version folder that already existed in the
# repository N days ago was first committed at least N days ago.

function Get-WingetManifestPath {
    # Private helper: 'Git.Git' -> 'manifests/g/Git/Git'.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PackageId
    )

    $first = $PackageId.Substring(0, 1).ToLowerInvariant()
    return "manifests/$first/$(($PackageId -split '\.') -join '/')"
}

function Invoke-WingetPkgsGh {
    # Private helper: single `gh api` call so tests can mock the process launch.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint
    )

    # Native stderr becomes an ErrorRecord; under a caller's 'Stop' preference,
    # Windows PowerShell 5.1 would turn it into a terminating error.
    $ErrorActionPreference = 'Continue'
    $output = & gh api --hostname github.com $Endpoint 2>&1
    return [PSCustomObject]@{
        ExitCode = $LASTEXITCODE
        Output   = ($output | Out-String).Trim()
    }
}

function Invoke-WingetPkgsApi {
    <#
    .SYNOPSIS
        Private helper: GET a GitHub REST endpoint for the public winget-pkgs repo.
    .DESCRIPTION
        Uses `gh api` when gh is available, which gets the authenticated rate
        limit. When gh fails (SAML enforcement on the microsoft org, a bad
        token, rate limiting), the rest of the run falls back to unauthenticated
        requests, which work because winget-pkgs is public (60 requests/hour).
        Returns $null for HTTP 404 and throws on any other failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint
    )

    if (-not $script:WingetPkgsGhDisabled -and (Get-Command gh -ErrorAction SilentlyContinue)) {
        try {
            $result = Invoke-WingetPkgsGh -Endpoint $Endpoint
        }
        catch {
            $result = [PSCustomObject]@{ ExitCode = 1; Output = "$_" }
        }
        if ($result.ExitCode -eq 0) {
            return ($result.Output | ConvertFrom-Json)
        }
        if ($result.Output -match 'HTTP 404') {
            return $null
        }
        Write-Verbose "gh api $Endpoint failed; using unauthenticated requests for the rest of this run: $($result.Output)"
        $script:WingetPkgsGhDisabled = $true
    }

    $headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'DevSecNinja-dotfiles-winget-soak' }
    try {
        return (Invoke-RestMethod -Uri "https://api.github.com/$Endpoint" -Headers $headers -ErrorAction Stop)
    }
    catch {
        $statusCode = $null
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = $null }
        if ($statusCode -eq 404) {
            return $null
        }
        if ("$_" -match 'rate limit') {
            throw "GitHub API rate limit reached (unauthenticated: 60 requests/hour)"
        }
        throw "GitHub API request for $Endpoint failed: $($_.Exception.Message)"
    }
}

function Get-WingetSoakCutoffRef {
    # Private helper: the winget-pkgs master commit as of the cutoff time.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Cutoff
    )

    $until = $Cutoff.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    $commits = @(Invoke-WingetPkgsApi -Endpoint "repos/microsoft/winget-pkgs/commits?sha=master&until=$until&per_page=1")
    if ($commits.Count -eq 0 -or -not $commits[0].sha) {
        throw "No winget-pkgs commit found before $until"
    }
    return [string]$commits[0].sha
}

function Get-WingetSoakedVersion {
    # Private helper: version folders that existed for a package at the cutoff commit.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId,

        [Parameter(Mandatory = $true)]
        [string]$Ref
    )

    $path = Get-WingetManifestPath -PackageId $PackageId
    # A 404 means the package was not in winget-pkgs yet at the cutoff.
    $entries = @(Invoke-WingetPkgsApi -Endpoint "repos/microsoft/winget-pkgs/contents/$path`?ref=$Ref")
    return @($entries | Where-Object { $_ -and $_.type -eq 'dir' } | ForEach-Object { [string]$_.name })
}

function Select-WingetSoakTarget {
    <#
    .SYNOPSIS
        Private helper: pick the newest upgrade that has soaked long enough.
    .DESCRIPTION
        Walks AvailableVersions (newest first, as winget returns them) and
        returns the first version that is newer than the installed one and
        present in SoakedVersions. Version ordering is left to winget via the
        package's CompareToVersion method, which also understands installed
        versions such as '< 8.12.46.29'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Package,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]]$SoakedVersions = @()
    )

    $soaked = @{}
    foreach ($version in $SoakedVersions) { $soaked[$version] = $true }

    foreach ($version in @($Package.AvailableVersions)) {
        if ("$($Package.CompareToVersion($version))" -ne 'Lesser') {
            continue
        }
        if ($soaked.ContainsKey($version)) {
            return $version
        }
    }
    return $null
}

function Get-WingetSoakPlan {
    <#
    .SYNOPSIS
        Private helper: decide which version to upgrade each package to.
    .DESCRIPTION
        Returns one object per package with Target set to the version to
        install, or Target $null and a Reason when the package is skipped.
        Fails closed: when the manifest dates cannot be determined, the package
        is skipped with a warning.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Packages,

        [Parameter(Mandatory = $true)]
        [int]$SoakDays,

        [Parameter(Mandatory = $true)]
        [datetime]$Cutoff
    )

    $script:WingetPkgsGhDisabled = $false
    $refError = $null
    $ref = $null
    try {
        $ref = Get-WingetSoakCutoffRef -Cutoff $Cutoff
    }
    catch {
        $refError = $_.Exception.Message
    }

    foreach ($package in $Packages) {
        $newest = @($package.AvailableVersions) | Select-Object -First 1
        $item = [PSCustomObject]@{
            Id               = $package.Id
            Name             = $package.Name
            InstalledVersion = $package.InstalledVersion
            Newest           = $newest
            Target           = $null
            Reason           = $null
        }

        $lookupError = $refError
        if (-not $lookupError) {
            try {
                $soaked = @(Get-WingetSoakedVersion -PackageId $package.Id -Ref $ref)
                $item.Target = Select-WingetSoakTarget -Package $package -SoakedVersions $soaked
                if (-not $item.Target) {
                    $item.Reason = "no update is $SoakDays+ days old yet (newest: $newest)"
                }
            }
            catch {
                $lookupError = $_.Exception.Message
            }
        }

        if ($lookupError) {
            $item.Reason = "could not determine manifest dates: $lookupError"
            Write-Warning "Skipping $($package.Id): $($item.Reason)"
        }

        $item
    }
}

function Invoke-WingetCountdown {
    # Private helper: cancellable countdown, skipped in CI/non-interactive sessions.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Seconds
    )

    if ($Seconds -le 0) { return }

    if ([bool]$env:CI -or -not [Environment]::UserInteractive) {
        Write-Host "`n[SKIP] Skipping countdown (CI/non-interactive environment)" -ForegroundColor Yellow
        return
    }

    Write-Host "`nExecution Phase: Starting upgrade in $Seconds seconds..." -ForegroundColor Yellow
    Write-Host "   Press Ctrl+C to cancel" -ForegroundColor Gray
    for ($i = $Seconds; $i -gt 0; $i--) {
        Write-Host "   $i..." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }
    Write-Host "   GO!" -ForegroundColor Green
}

function Invoke-WingetUpgrade {
    <#
    .SYNOPSIS
    Upgrades winget packages to versions that have soaked for a number of days.

    .DESCRIPTION
    Performs winget package upgrades with a 3-second countdown that can be cancelled.
    Only runs if updates are detected. Uses Microsoft.WinGet.Client module when available.

    By default each package is upgraded to the newest available version that has
    been published in microsoft/winget-pkgs for at least SoakDays days (7 by
    default), so brand-new releases get time to be pulled or fixed before they
    land on this machine. Packages without such a version are skipped and listed
    in the summary. A version's age is the time since its manifest folder was
    added to winget-pkgs, looked up through the GitHub API (gh api when signed
    in, unauthenticated requests otherwise). When the age cannot be determined,
    the package is skipped (fail closed). Soak requires the Microsoft.WinGet.Client
    module.

    winget has no native minimum package age yet; see
    https://github.com/microsoft/winget-cli/issues/6178.

    .PARAMETER CountdownSeconds
    Number of seconds to wait before starting the upgrade. Defaults to 3.
    Set to 0 to skip countdown.

    .PARAMETER Force
    Skip the update detection phase and force upgrade execution.

    .PARAMETER UseWingetModule
    Use the Microsoft.WinGet.Client PowerShell module instead of winget.exe.
    Defaults to true for better performance and compatibility.

    .PARAMETER SoakDays
    Minimum number of days a package version must have been published in
    winget-pkgs before it is installed. Defaults to 7. 0 disables the soak.

    .PARAMETER NoSoak
    Disable the soak and upgrade every package to its newest version.

    .EXAMPLE
    Invoke-WingetUpgrade
    Checks for updates, then upgrades packages to versions at least 7 days old after a 3-second countdown.

    .EXAMPLE
    Invoke-WingetUpgrade -WhatIf
    Shows which packages would be upgraded, to which version, and which are skipped.

    .EXAMPLE
    Invoke-WingetUpgrade -SoakDays 14
    Only installs versions that have been published for at least 14 days.

    .EXAMPLE
    Invoke-WingetUpgrade -NoSoak
    Upgrades all packages to their newest version, regardless of age.

    .EXAMPLE
    Invoke-WingetUpgrade -CountdownSeconds 0
    Upgrades immediately without countdown.

    .EXAMPLE
    Invoke-WingetUpgrade -Force
    Forces upgrade without checking for updates first.

    .NOTES
    Requires Microsoft.WinGet.Client module or winget.exe to be installed.
    Press Ctrl+C during countdown to cancel.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [int]$CountdownSeconds = 3,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [bool]$UseWingetModule = $true,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 365)]
        [int]$SoakDays = 7,

        [Parameter(Mandatory = $false)]
        [switch]$NoSoak
    )

    $soakEnabled = (-not $NoSoak) -and $SoakDays -gt 0
    $isWhatIf = [bool]$WhatIfPreference
    $countdown = if ($isWhatIf) { 0 } else { $CountdownSeconds }

    Write-Host "`n>> Winget Package Upgrade" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan
    if ($soakEnabled) {
        Write-Host "Soak: only versions published $SoakDays+ days ago (use -NoSoak to disable)" -ForegroundColor Gray
    }

    # Detection phase (skip if Force is specified)
    if (-not $Force) {
        Write-Host "`nDetection Phase: Checking for updates..." -ForegroundColor Yellow
        $hasUpdates = Test-WingetUpdates -UseWingetModule $UseWingetModule

        if (-not $hasUpdates) {
            Write-Host "`n[OK] No updates available. Skipping upgrade." -ForegroundColor Green
            return
        }
    }
    else {
        Write-Host "`n[WARN] Skipping detection phase (Force mode)" -ForegroundColor Yellow
    }

    # Check if Microsoft.WinGet.Client is available
    $wingetModule = Get-Module -Name Microsoft.WinGet.Client -ListAvailable -ErrorAction SilentlyContinue

    if ($UseWingetModule -and $wingetModule) {
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop

            Write-Host "`n>> Planning package upgrades..." -ForegroundColor Cyan
            Write-Host "   Using Microsoft.WinGet.Client module..." -ForegroundColor Gray

            # Get packages with updates
            $packagesToUpdate = @(Get-WinGetPackage -Source winget | Where-Object { $_.IsUpdateAvailable })

            if ($packagesToUpdate.Count -eq 0) {
                Write-Host "[OK] No packages to upgrade" -ForegroundColor Green
                return
            }

            if ($soakEnabled) {
                $cutoff = (Get-Date).ToUniversalTime().AddDays(-$SoakDays)
                Write-Host "   Checking winget-pkgs for versions published before $($cutoff.ToString('yyyy-MM-dd HH:mm')) UTC..." -ForegroundColor Gray
                $plan = @(Get-WingetSoakPlan -Packages $packagesToUpdate -SoakDays $SoakDays -Cutoff $cutoff)
            }
            else {
                $plan = @($packagesToUpdate | ForEach-Object {
                        [PSCustomObject]@{
                            Id               = $_.Id
                            Name             = $_.Name
                            InstalledVersion = $_.InstalledVersion
                            Newest           = @($_.AvailableVersions) | Select-Object -First 1
                            Target           = $null
                            Reason           = $null
                        }
                    })
            }

            $toUpgrade = @($plan | Where-Object { -not $_.Reason })
            $skipped = @($plan | Where-Object { $_.Reason })

            Write-Host "`nUpgrade plan:" -ForegroundColor Cyan
            foreach ($item in $toUpgrade) {
                $version = if ($item.Target) { $item.Target } else { $item.Newest }
                $note = if ($item.Target -and $item.Target -ne $item.Newest) { "  (newest $($item.Newest) is under $SoakDays days old)" } else { '' }
                Write-Host ("   {0,-40} {1} -> {2}{3}" -f $item.Id, $item.InstalledVersion, $version, $note)
            }
            if ($toUpgrade.Count -eq 0) {
                Write-Host "   (nothing to upgrade)" -ForegroundColor Gray
            }
            if ($skipped.Count -gt 0) {
                Write-Host "Skipped:" -ForegroundColor Yellow
                foreach ($item in $skipped) {
                    Write-Host ("   {0,-40} {1}" -f $item.Id, $item.Reason) -ForegroundColor Yellow
                }
            }

            if ($toUpgrade.Count -eq 0) {
                Write-Host "`n[OK] Nothing to upgrade yet" -ForegroundColor Green
                return
            }

            Invoke-WingetCountdown -Seconds $countdown
            if (-not $isWhatIf) {
                Write-Host "`n>> Starting package upgrades..." -ForegroundColor Cyan
            }

            # Upgrade each package
            $successCount = 0
            $failCount = 0

            foreach ($item in $toUpgrade) {
                $action = if ($item.Target) { "Upgrade to $($item.Target)" } else { 'Upgrade to latest' }
                if (-not $PSCmdlet.ShouldProcess($item.Id, $action)) {
                    continue
                }

                Write-Host "   Upgrading $($item.Name)..." -NoNewline

                $updateParams = @{
                    Id          = $item.Id
                    Source      = 'winget'
                    Mode        = 'Silent'
                    Force       = $true
                    ErrorAction = 'Stop'
                }
                if ($item.Target) {
                    $updateParams['Version'] = $item.Target
                    $updateParams['MatchOption'] = 'Equals'
                }

                try {
                    Update-WinGetPackage @updateParams | Out-Null
                    Write-Host " OK" -ForegroundColor Green
                    $successCount++
                }
                catch {
                    Write-Host " FAIL" -ForegroundColor Red
                    Write-Warning "Failed to upgrade $($item.Name): $_"
                    $failCount++
                }
            }

            if ($isWhatIf) {
                return
            }

            Write-Host "`nUpgrade Summary:" -ForegroundColor Cyan
            Write-Host "   Successful: $successCount" -ForegroundColor Green
            Write-Host "   Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Gray' })
            Write-Host "   Skipped: $($skipped.Count)" -ForegroundColor $(if ($skipped.Count -gt 0) { 'Yellow' } else { 'Gray' })
        }
        catch {
            Write-Warning "Failed to use Microsoft.WinGet.Client module: $_"
            Write-Warning "Falling back to winget.exe..."
            $UseWingetModule = $false
        }
    }

    # Fallback to winget.exe if module not available or failed
    if (-not $UseWingetModule -or -not $wingetModule) {
        if ($soakEnabled) {
            Write-Warning "Soak requires the Microsoft.WinGet.Client module (Install-Module -Name Microsoft.WinGet.Client). Rerun with -NoSoak to upgrade everything with winget.exe."
            return
        }

        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Error "Neither Microsoft.WinGet.Client module nor winget.exe is available."
            Write-Error "Please install Microsoft.WinGet.Client: Install-Module -Name Microsoft.WinGet.Client"
            return
        }

        if (-not $PSCmdlet.ShouldProcess('all winget packages', 'winget upgrade --all')) {
            return
        }

        Invoke-WingetCountdown -Seconds $countdown
        Write-Host "`n>> Starting package upgrades..." -ForegroundColor Cyan
        Write-Host "   Using winget.exe..." -ForegroundColor Gray
        winget upgrade --all --source winget --silent --accept-package-agreements --accept-source-agreements

        if ($LASTEXITCODE -eq 0) {
            Write-Host "`nUpgrade completed successfully" -ForegroundColor Green
        }
        else {
            Write-Host "`nUpgrade completed with errors (exit code: $LASTEXITCODE)" -ForegroundColor Red
        }
    }

    Write-Host "`n================================" -ForegroundColor Cyan
    Write-Host "Winget upgrade process completed" -ForegroundColor Green
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCwgCwMLbcB8N8m
# KY19Ko3JoG2Fp4XcmVx6Y+HtTcY+86CCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCBcZL0P6M/qCVz0oXXU0kSvoYdBHtmTVsJyAeJK/KR9RDANBgkqhkiG
# 9w0BAQEFAASCAgAN2ngzu+cfL14s+Zd0eTTBg64s2okRZwMrjqPAHqIEt2/0/hny
# U9OglfWsiV752MPMxhUjbPXkF2geOYw8np/Wz8Jvk8Jw3J06uDezejDNT3hT8yq7
# sK5j852C7zlo+XvNDINrEet2akZTIiide5zWx+HtYh+84FpTo5vP/uco2w7C0pCd
# zA3dquwNkK9sm0/AVxgCyBP7R+/2uP1o8D/TCZe1KlACoCOBfyVtkCwkFDeOFmtm
# UH2NYV+0y/54MGBnV2RePqdIMYkbqzA8KxKeMO5w00sY5CbfbrfwgtQt653Epeic
# OrbED3Pq7iGaJ8nZlsTUKxWHLo7Efmb4RjBneFHCx3nodzct4uA+ls36WK/hc2Gd
# jg45SAtsUYrb0ii0+cIpISy7W021IItohJR0VgvGIBCfaa01lXf20FWbgJFfAqwJ
# EGIsQd48RmAVvfYC69ItggiYHdq1H/1BX3RZJSk4OUjJXEgbDqANoFte6r/hcwU4
# Z46vEtKntf0/LWrO8siRnCl+UK59mLG0Y+Xo3HbAKTEQCh8mF5tvxpy4DCkKbK5w
# hP+cxDq+Gw7WRoiAw1Ch72U8/NMDcldYIpsaKaWw+YjGTOLZ3R21Vf2Yy0ISMcrJ
# Sz1DlbfFHDU3LMh9IAmUOepUSn5GByFC3y0QPTRxpYuFHV8gfYV6wbNxYaGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjAyMTAxNjM4NDdaMC8GCSqGSIb3DQEJBDEi
# BCCVjkDUd6csyme5+KEnOYm/bC6iwDdxxIcaO1j0xk1kiTANBgkqhkiG9w0BAQEF
# AASCAgBgwIoRFsPfM27EyCu9IpnQwvjS7ouKo8Ihk3s/rnmFPIQpWeGs3Xq0plvZ
# 32Xd3O1j+Qrae+lE4NAnSN1l4yUSrnYdZ5TD+aqEkKLj64GeDvIsSnvaD16GaUk0
# EG/eOwpgPeOG6pms+X7cyt2R/PV5RMZubtJB9NAQ1ShM6TBBTXPYR1LsBjZu3vXZ
# 8cXCKB7/iMdprY0ctIPyw/UTORWauu7X1imp0X6trzo9rHJtTvVFckNu12Gi92kN
# Eyu8Rnm7s21ai7DCiGO7DFJpK4IIvxx1RUhqQaOvcV9qhJzwopMtx8iol2Mv7Umy
# kMurlJBI0oYStWP1tY4ATqdoR2/5ngdxLiJQsgTZ4Kgv8TGrNo9c3boy+JI/z6sj
# +6eQxKLji3y1Xd9+gYvFJJrKSbuCZjJAzlBbDK2qGpI3wFljmHTJo7Ag3Pc4k3gY
# WbrWYLoccnW7UvcAu/Bem0Hd1pYjSTWaDI5peVqrD1BKX1ZDrJHHmbLcvjtz4Fho
# 8lNwePcOfwHmSF0n+CGr2ppHFV+jbdoVwNR7A+GEMe8pWLMWtO3HWFXaSOfVDRBr
# EpF83RKo1jkEQRVmNvtRJkt4vktW9ym7g/my1YvG/EwlM7+SUG1crz1Q36xwz5ED
# omS3QFdKO+ER8fqvyK7U5MDlGXE0GPOF+koF6COn3Uv6YYqb0w==
# SIG # End signature block
