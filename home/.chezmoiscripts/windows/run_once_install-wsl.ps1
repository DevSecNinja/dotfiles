# PowerShell script to check and install WSL 2 with Debian
# This script is run once during dotfiles setup

$ErrorActionPreference = "Stop"

Write-Host "🐧 Checking WSL installation..." -ForegroundColor Cyan

# Check if WSL is already installed
$wslInstalled = $false
try {
    $wslCommand = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wslCommand) {
        $wslInstalled = $true
        Write-Host "✅ WSL is already installed" -ForegroundColor Green
    }
}
catch {
    $wslInstalled = $false
}

if (-not $wslInstalled) {
    Write-Host "WSL is not installed. Installing..." -ForegroundColor Yellow

    # Check if running with admin privileges
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "⚠️  WSL installation requires administrator privileges." -ForegroundColor Yellow
        Write-Host "Please run the following command in an elevated PowerShell:" -ForegroundColor Yellow
        Write-Host "  wsl --install -d Debian" -ForegroundColor Cyan
        exit 0
    }

    # Install WSL with Debian
    Write-Host "Running: wsl --install -d Debian" -ForegroundColor Cyan
    wsl.exe --install -d Debian

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ WSL installed successfully" -ForegroundColor Green
        Write-Host "⚠️  You may need to restart your computer for WSL to work properly." -ForegroundColor Yellow
    }
    else {
        Write-Host "❌ WSL installation failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }
}
else {
    # WSL is installed, check version and provide info
    try {
        $wslStatus = wsl.exe --status 2>$null
        if ($wslStatus -match "Default Version:\s*(\d+)") {
            $wslVersion = [int]$matches[1]
            Write-Host "WSL version: $wslVersion" -ForegroundColor Cyan

            if ($wslVersion -eq 1) {
                Write-Host "⚠️  WARNING: WSL version 1 detected!" -ForegroundColor Yellow
                Write-Host "WSL 2 is recommended for better performance and compatibility." -ForegroundColor Yellow
                Write-Host "To upgrade to WSL 2:" -ForegroundColor Yellow
                Write-Host "  1. Run: wsl --set-default-version 2" -ForegroundColor Cyan
                Write-Host "  2. Convert existing distros: wsl --set-version <distro> 2" -ForegroundColor Cyan
            }
        }
    }
    catch {
        # Ignore errors in version check
    }

    # Check if Debian is installed
    $debianInstalled = $false
    try {
        $distros = wsl.exe --list --quiet 2>$null
        # Convert from UTF-16 if needed and clean up
        $distroList = $distros | ForEach-Object {
            $_.Trim() -replace '\x00', '' -replace '\r', ''
        } | Where-Object { $_ -match '\S' }
        $debianInstalled = $distroList -match "^Debian"
    }
    catch {
        # Ignore errors
    }

    if (-not $debianInstalled) {
        # Check Chezmoi variables and interactive status
        $installType = try { (chezmoi execute-template "{{ .installType }}") 2>$null } catch { "full" }
        $isCI = try { (chezmoi execute-template "{{ .ci }}") 2>$null } catch {
            if ([bool]$env:CI -or [bool]$env:GITHUB_ACTIONS -or [bool]$env:TF_BUILD) { "true" } else { "false" }
        }
        $isInteractive = [Environment]::UserInteractive -and ($Host.UI -ne $null) -and ($Host.UI.RawUI -ne $null)

        # Skip installation if light mode, CI, or non-interactive
        if ($installType -eq "light" -or $isCI -eq "true" -or -not $isInteractive) {
            $skipReason = if ($installType -eq "light") { "light installation mode" }
                          elseif ($isCI -eq "true") { "CI environment" }
                          else { "non-interactive environment" }
            Write-Host "⏭️  Skipping Debian installation ($skipReason)" -ForegroundColor Yellow
            Write-Host "💡 To install manually, run: wsl --install -d Debian" -ForegroundColor Cyan
            exit 0
        }

        # In interactive mode, run the installer
        Write-Host "Debian distribution not found. Installing..." -ForegroundColor Yellow
        Write-Host "Running: wsl --install -d Debian" -ForegroundColor Cyan
        Write-Host "💡 You may be prompted for administrator privileges..." -ForegroundColor Yellow

        wsl.exe --install -d Debian

        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Debian installed successfully" -ForegroundColor Green
            Write-Host "💡 You can launch Debian by running: wsl" -ForegroundColor Yellow
        }
        else {
            Write-Host "❌ Debian installation failed with exit code $LASTEXITCODE" -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "✅ Debian distribution is installed" -ForegroundColor Green
    }
}

Write-Host "`n💡 To launch WSL, run: wsl" -ForegroundColor Yellow
