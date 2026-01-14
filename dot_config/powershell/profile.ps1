# PowerShell Profile Configuration
# This file is loaded when PowerShell starts
# Location: $PROFILE (typically ~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1)
# But managed by chezmoi in ~/.config/powershell/

# Set UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8


# Load aliases
. $PSScriptRoot\aliases.ps1

# Custom prompt (simple and clean)
function prompt {
    $loc = Get-Location
    $gitBranch = ""

    # Get git branch if in a git repo
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $gitBranch = & git rev-parse --abbrev-ref HEAD 2>$null
        if ($gitBranch) {
            $gitBranch = " ($gitBranch)"
        }
    }

    Write-Host "$loc" -NoNewline -ForegroundColor Cyan
    Write-Host "$gitBranch" -NoNewline -ForegroundColor Yellow
    return "> "
}

# Welcome message
Write-Host "🐚 PowerShell Profile Loaded" -ForegroundColor Green
Write-Host "💡 Type 'aliases' to see available aliases" -ForegroundColor Yellow
