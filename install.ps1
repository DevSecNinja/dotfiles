# PowerShell installation script for Windows
# Downloads and installs chezmoi, then applies dotfiles

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ChezmoiVersion = "latest",

    [Parameter()]
    [string]$BinDir = "$env:LOCALAPPDATA\bin"
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

$isInteractive = Test-Interactive

# Create bin directory if it doesn't exist
if (-not (Test-Path $BinDir)) {
    Write-Host "Creating bin directory: $BinDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

# Check if chezmoi is already installed
$chezmoiPath = "$BinDir\chezmoi.exe"
$chezmoiExists = Test-Path $chezmoiPath

if (-not $chezmoiExists) {
    Write-Host "Installing chezmoi to '$chezmoiPath'..." -ForegroundColor Cyan

    # Determine architecture
    $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "i386" }

    # Download chezmoi
    $downloadUrl = if ($ChezmoiVersion -eq "latest") {
        "https://github.com/twpayne/chezmoi/releases/latest/download/chezmoi_windows_$arch.zip"
    } else {
        "https://github.com/twpayne/chezmoi/releases/download/v$ChezmoiVersion/chezmoi_windows_$arch.zip"
    }

    $tempZip = Join-Path $env:TEMP "chezmoi.zip"
    $tempExtract = Join-Path $env:TEMP "chezmoi_extract"

    try {
        Write-Host "Downloading from $downloadUrl..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempZip -UseBasicParsing

        # Extract chezmoi
        if (Test-Path $tempExtract) {
            Remove-Item -Path $tempExtract -Recurse -Force
        }
        New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
        Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

        # Move chezmoi.exe to bin directory
        Move-Item -Path "$tempExtract\chezmoi.exe" -Destination $chezmoiPath -Force

        Write-Host "✅ Chezmoi installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install chezmoi: $_"
        exit 1
    }
    finally {
        # Clean up temporary files
        if (Test-Path $tempZip) {
            Remove-Item -Path $tempZip -Force
        }
        if (Test-Path $tempExtract) {
            Remove-Item -Path $tempExtract -Recurse -Force
        }
    }

    # Add to PATH if not already there
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$BinDir*") {
        Write-Host "Adding $BinDir to user PATH..." -ForegroundColor Yellow
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$BinDir", "User")
        $env:Path = "$env:Path;$BinDir"
        Write-Host "✅ Added to PATH (restart shell for persistence)" -ForegroundColor Green
    }
}
else {
    Write-Host "Chezmoi already installed at '$chezmoiPath'" -ForegroundColor Green
}

# Get the source directory (script's directory)
$sourceDir = $PSScriptRoot

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
& $chezmoiPath $chezmoiArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "Chezmoi init failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "`n✅ Dotfiles installation complete!" -ForegroundColor Green
Write-Host "💡 Run 'chezmoi update' to pull and apply the latest changes" -ForegroundColor Yellow
