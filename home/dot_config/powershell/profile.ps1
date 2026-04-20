# PowerShell Profile Configuration
# This file is loaded when PowerShell starts
# Location: $PROFILE (typically ~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1)
# But managed by chezmoi in ~/.config/powershell/

# TODO: Investigate why Windows PowerShell doesn't show emojis properly
# Set UTF-8 encoding (force code page 65001 for Windows PowerShell 5.1)
if ($PSVersionTable.PSVersion.Major -lt 7) {
    chcp 65001 | Out-Null
}
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Load chezmoi configuration variables
$chezmoiConfig = Join-Path $PSScriptRoot "chezmoi.ps1"
if (Test-Path $chezmoiConfig) {
    . $chezmoiConfig
}

# Set working directory to projects folder if not already there
# Skip this if running in VS Code to preserve the opened folder location
if ($ENV:TERM_PROGRAM -ne "vscode") {
    $currentPath = (Get-Location).Path
    $projectsPath = Join-Path $env:USERPROFILE "projects"

    # Check if current path contains 'projects' (case-insensitive)
    if ($currentPath -notlike "*projects*") {
        # Not in projects directory, change to it if it exists
        if (Test-Path $projectsPath) {
            Set-Location $projectsPath
        }
    }
}

# Load DotfilesHelpers module (lazy-loadable via PSModulePath, explicit import for profile)
$dotfilesModulePath = Join-Path $PSScriptRoot "modules\DotfilesHelpers"
if (Test-Path $dotfilesModulePath) {
    Import-Module $dotfilesModulePath -Force -DisableNameChecking
}

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

# Load completions
$completionsPath = Join-Path $PSScriptRoot "completions"
if (Test-Path $completionsPath) {
    Get-ChildItem -Path $completionsPath -Filter "*.ps1" | ForEach-Object {
        . $_.FullName
    }
}

# Show horizonfetch only in interactive sessions (not when scripts import modules)
# Guarded with a timeout because horizonfetch occasionally hangs on some
# hardware probes (e.g. GPU query on Snapdragon X), which would otherwise
# freeze the entire profile load and ignore Ctrl+C. See issue: pwsh session
# hangs on profile load.
if ([Environment]::UserInteractive -and -not $env:CHEZMOI_SOURCE_DIR) {
    $horizonfetchCmd = Get-Command horizonfetch -ErrorAction SilentlyContinue
    if ($horizonfetchCmd) {
        # Allow users to tune the timeout (milliseconds) via an env var.
        $horizonfetchTimeoutMs = 5000
        $parsedTimeout = 0
        if ($env:HORIZONFETCH_TIMEOUT_MS -and
            [int]::TryParse($env:HORIZONFETCH_TIMEOUT_MS, [ref]$parsedTimeout) -and
            $parsedTimeout -gt 0) {
            $horizonfetchTimeoutMs = $parsedTimeout
        }

        if ($horizonfetchCmd.CommandType -in @([System.Management.Automation.CommandTypes]::Application,
                                               [System.Management.Automation.CommandTypes]::ExternalScript)) {
            # External executable/script: launch it attached to the current
            # console so colors/unicode render normally, and kill it if it
            # doesn't finish within the timeout.
            try {
                $horizonfetchProc = Start-Process -FilePath $horizonfetchCmd.Source `
                    -NoNewWindow -PassThru -ErrorAction Stop
                if (-not $horizonfetchProc.WaitForExit($horizonfetchTimeoutMs)) {
                    try { $horizonfetchProc.Kill() } catch { }
                    Write-Host "`n(horizonfetch timed out after $([math]::Round($horizonfetchTimeoutMs / 1000, 1))s; skipping)" -ForegroundColor DarkYellow
                }
            } catch {
                Write-Host "(horizonfetch failed to start: $($_.Exception.Message))" -ForegroundColor DarkYellow
            }
        } else {
            # Function/alias/cmdlet: no reliable way to cancel cooperatively,
            # so just invoke it directly.
            horizonfetch
        }
    }
}

# Welcome message (only in interactive sessions)
if ([Environment]::UserInteractive -and -not $env:CHEZMOI_SOURCE_DIR) {
    Write-Host "🐚 PowerShell Profile Loaded" -ForegroundColor Green
    Write-Host "💡 Type 'aliases' to see available aliases" -ForegroundColor Yellow
}
