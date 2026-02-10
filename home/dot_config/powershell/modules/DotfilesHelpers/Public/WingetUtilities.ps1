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

function Invoke-WingetUpgrade {
    <#
    .SYNOPSIS
    Upgrades all winget packages after a countdown timer.

    .DESCRIPTION
    Performs winget package upgrades with a 3-second countdown that can be cancelled.
    Only runs if updates are detected. Uses Microsoft.WinGet.Client module when available.

    .PARAMETER CountdownSeconds
    Number of seconds to wait before starting the upgrade. Defaults to 3.
    Set to 0 to skip countdown.

    .PARAMETER Force
    Skip the update detection phase and force upgrade execution.

    .PARAMETER UseWingetModule
    Use the Microsoft.WinGet.Client PowerShell module instead of winget.exe.
    Defaults to true for better performance and compatibility.

    .EXAMPLE
    Invoke-WingetUpgrade
    Checks for updates, then upgrades all packages after 3-second countdown.

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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$CountdownSeconds = 3,

        [Parameter(Mandatory = $false)]
        [switch]$Force,

        [Parameter(Mandatory = $false)]
        [bool]$UseWingetModule = $true
    )

    Write-Host "`n>> Winget Package Upgrade" -ForegroundColor Cyan
    Write-Host "================================" -ForegroundColor Cyan

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

    # Countdown phase
    if ($CountdownSeconds -gt 0) {
        # Skip countdown in CI or non-interactive environments
        $isCI = [bool]$env:CI
        $isNonInteractive = -not [Environment]::UserInteractive

        if ($isCI -or $isNonInteractive) {
            Write-Host "`n[SKIP] Skipping countdown (CI/non-interactive environment)" -ForegroundColor Yellow
        }
        else {
            Write-Host "`nExecution Phase: Starting upgrade in $CountdownSeconds seconds..." -ForegroundColor Yellow
            Write-Host "   Press Ctrl+C to cancel" -ForegroundColor Gray

            for ($i = $CountdownSeconds; $i -gt 0; $i--) {
                Write-Host "   $i..." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
            Write-Host "   GO!" -ForegroundColor Green
        }
    }

    # Execution phase
    Write-Host "`n>> Starting package upgrades..." -ForegroundColor Cyan

    # Check if Microsoft.WinGet.Client is available
    $wingetModule = Get-Module -Name Microsoft.WinGet.Client -ListAvailable -ErrorAction SilentlyContinue

    if ($UseWingetModule -and $wingetModule) {
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop

            Write-Host "   Using Microsoft.WinGet.Client module..." -ForegroundColor Gray

            # Get packages with updates
            $packagesToUpdate = Get-WinGetPackage -Source winget | Where-Object { $_.IsUpdateAvailable }

            if (-not $packagesToUpdate -or $packagesToUpdate.Count -eq 0) {
                Write-Host "[OK] No packages to upgrade" -ForegroundColor Green
                return
            }

            Write-Host "   Found $($packagesToUpdate.Count) package(s) to upgrade`n" -ForegroundColor Gray

            # Upgrade each package
            $successCount = 0
            $failCount = 0

            foreach ($package in $packagesToUpdate) {
                Write-Host "   Upgrading $($package.Name)..." -NoNewline

                try {
                    Update-WinGetPackage -Id $package.Id -Source winget -Mode Silent -Force -ErrorAction Stop | Out-Null
                    Write-Host " OK" -ForegroundColor Green
                    $successCount++
                }
                catch {
                    Write-Host " FAIL" -ForegroundColor Red
                    Write-Warning "Failed to upgrade $($package.Name): $_"
                    $failCount++
                }
            }

            Write-Host "`nUpgrade Summary:" -ForegroundColor Cyan
            Write-Host "   Successful: $successCount" -ForegroundColor Green
            Write-Host "   Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } else { 'Gray' })
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
            Write-Error "Neither Microsoft.WinGet.Client module nor winget.exe is available."
            Write-Error "Please install Microsoft.WinGet.Client: Install-Module -Name Microsoft.WinGet.Client"
            return
        }

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
