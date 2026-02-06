# PowerShell Profile Configuration - README

This directory contains PowerShell profile configuration managed by chezmoi.

## Files

- `profile.ps1` - Main PowerShell profile with settings and module imports
- `aliases.ps1` - Command aliases and helper functions
- `functions.ps1` - PowerShell utility functions for system management
- `completions/` - Command-line completions for various tools

## Installation

The profile is automatically installed by chezmoi. A loader file is placed at `~/Documents/PowerShell/profile.ps1` (the default `$PROFILE` location) which sources the actual configuration from `~/.config/powershell/profile.ps1`.

This approach works seamlessly across different PowerShell versions and doesn't require symbolic links or manual setup.

## Features

- **PSReadLine** - Enhanced command-line editing with history search
- **Custom aliases** - Unix-like shortcuts (ll, gs, gp, etc.)
- **Git-aware prompt** - Shows current branch
- **Winget Upgrade Automation** - Automated package upgrades with `wup` or `winup` commands
  - Detection phase: Only runs if updates are available
  - Execution phase: 3-second countdown before upgrading (can be cancelled)
  - Automatically runs during `chezmoi update`
  - Uses Microsoft.WinGet.Client PowerShell module when available

## Usage

After installation, start a new PowerShell session. Type `aliases` to see all available commands.

### Winget Upgrade Commands

- `wup` or `winup` - Check for and upgrade all winget packages with a 3-second countdown
- `Test-WingetUpdates` - Check if any package updates are available (returns true/false)
- `Invoke-WingetUpgrade` - Full upgrade function with customizable options

**Examples:**
```powershell
# Check for updates
Test-WingetUpdates

# Upgrade all packages (3-second countdown)
wup

# Upgrade immediately without countdown
Invoke-WingetUpgrade -CountdownSeconds 0

# Force upgrade without checking for updates first
Invoke-WingetUpgrade -Force
```

**Automatic Upgrades:**
The winget upgrade check runs automatically during `chezmoi update` (when the script or dependencies change). You can cancel the upgrade by pressing Ctrl+C during the 3-second countdown.

## Customization

Edit the files in this directory and run `chezmoi apply` to update your profile.
