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

$isInteractive = Test-Interactive

# Check if winget is available
$wingetPath = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wingetPath) {
    Write-Error "winget is not available. Please install Windows Package Manager (winget) first."
    exit 1
}

# Check if chezmoi is already installed
$chezmoiExists = Get-Command chezmoi -ErrorAction SilentlyContinue

if (-not $chezmoiExists) {
    Write-Host "Installing chezmoi using winget..." -ForegroundColor Cyan

    try {
        if ($ChezmoiVersion -eq "latest") {
            winget install --id twpayne.chezmoi --silent --accept-source-agreements --accept-package-agreements
        } else {
            winget install --id twpayne.chezmoi --version $ChezmoiVersion --silent --accept-source-agreements --accept-package-agreements
        }

        if ($LASTEXITCODE -ne 0) {
            throw "winget install failed with exit code $LASTEXITCODE"
        }

        Write-Host "✅ Chezmoi installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install chezmoi: $_"
        exit 1
    }
}
else {
    Write-Host "Chezmoi already installed" -ForegroundColor Green
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
chezmoi $chezmoiArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "Chezmoi init failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "`n✅ Dotfiles installation complete!" -ForegroundColor Green
Write-Host "💡 Run 'chezmoi update' to pull and apply the latest changes" -ForegroundColor Yellow
