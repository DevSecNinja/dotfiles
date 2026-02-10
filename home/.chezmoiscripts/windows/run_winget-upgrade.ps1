#Requires -Version 5.1
<#
.SYNOPSIS
    Runs winget package upgrades when chezmoi detects changes.

.DESCRIPTION
    This script automatically checks for and upgrades winget packages during chezmoi update.
    It runs as the final script (99-) to allow cancellation if needed.

    Features:
    - Detection phase: Only runs if updates are available
    - Execution phase: 3-second countdown before upgrading (can be cancelled)
    - Uses Microsoft.WinGet.Client PowerShell module when available
    - Falls back to winget.exe if module is not installed
    - Warns if neither is available

.NOTES
    - This is a run_onchange script, triggered when this file or its dependencies change
    - Requires Microsoft.WinGet.Client module (automatically installed via packages.yaml)
    - Run order: 99- ensures this is the last script to execute
    - Compatible with both PowerShell Core (7+) and Windows PowerShell (5.1+)

.LINK
    https://www.powershellgallery.com/packages/Microsoft.WinGet.Client
#>

$ErrorActionPreference = "Continue"  # Continue on errors to avoid blocking chezmoi

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host ">> Winget Package Upgrade (Chezmoi OnChange)" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Check if Microsoft.WinGet.Client module is available
$wingetModule = Get-Module -Name Microsoft.WinGet.Client -ListAvailable -ErrorAction SilentlyContinue

if (-not $wingetModule) {
    Write-Warning "Microsoft.WinGet.Client module not found"
    Write-Warning "This module should be installed automatically via packages.yaml"
    Write-Warning "To install manually: Install-Module -Name Microsoft.WinGet.Client"

    # Check if winget.exe is available as fallback
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Warning "Neither Microsoft.WinGet.Client nor winget.exe is available"
        Write-Warning "Skipping winget upgrade. Please install one of the following:"
        Write-Warning "  1. Microsoft.WinGet.Client module: Install-Module -Name Microsoft.WinGet.Client"
        Write-Warning "  2. App Installer from Microsoft Store (includes winget.exe)"
        exit 0
    }

    Write-Host "   Using winget.exe as fallback..." -ForegroundColor Yellow
}
else {
    Write-Host "`n[OK] Microsoft.WinGet.Client module found (v$($wingetModule.Version))" -ForegroundColor Green
}

# Check if functions are available (they should be loaded by profile.ps1 via DotfilesHelpers module)
# If not available, import the module directly (needed when running via chezmoi)
if (-not (Get-Command Invoke-WingetUpgrade -ErrorAction SilentlyContinue)) {
    $modulePath = Join-Path $HOME ".config\powershell\modules\DotfilesHelpers"
    if (Test-Path $modulePath) {
        try {
            Import-Module $modulePath -Force -DisableNameChecking
        }
        catch {
            Write-Warning "Failed to load DotfilesHelpers module from $modulePath : $_"
        }
    }

    if (-not (Get-Command Invoke-WingetUpgrade -ErrorAction SilentlyContinue)) {
        Write-Warning "DotfilesHelpers module not found at $modulePath"
        Write-Warning "Skipping winget upgrade"
        exit 0
    }
}

# Run the upgrade using the function from DotfilesHelpers module
try {
    Invoke-WingetUpgrade -CountdownSeconds 3 -UseWingetModule $true
}
catch {
    Write-Warning "Failed to run Invoke-WingetUpgrade: $_"
    Write-Warning "Continuing with chezmoi update despite winget upgrade failure"
}

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "[OK] Winget upgrade check completed" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan

exit 0
