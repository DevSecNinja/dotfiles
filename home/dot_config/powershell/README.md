# PowerShell Profile Configuration - README

This directory contains PowerShell profile configuration managed by chezmoi.

## Files

- `profile.ps1` - Main PowerShell profile with settings and module imports
- `aliases.ps1` - Command aliases and helper functions
- `modules/DotfilesHelpers/` - PowerShell module containing all utility functions
  - `DotfilesHelpers.psd1` - Module manifest with exported function declarations (enables lazy loading)
  - `DotfilesHelpers.psm1` - Module loader that dot-sources public function files
  - `Public/` - Individual function files grouped by category:
    - `Navigation.ps1` - Directory navigation helpers
    - `SystemUtilities.ps1` - System utility functions (which, touch, mkcd)
    - `ChezmoiUtilities.ps1` - Chezmoi management functions
    - `WingetUtilities.ps1` - Winget upgrade automation
    - `ProfileManagement.ps1` - Profile editing and alias display
    - `ModuleInstallation.ps1` - PowerShell module installation utilities
- `completions/` - Command-line completions for various tools

## Installation

The profile is automatically installed by chezmoi. A loader file is placed at `~/Documents/PowerShell/profile.ps1` (the default `$PROFILE` location) which sources the actual configuration from `~/.config/powershell/profile.ps1`.

This approach works seamlessly across different PowerShell versions and doesn't require symbolic links or manual setup.

## Features

- **PSReadLine** - Enhanced command-line editing with history search
- **Custom aliases** - Unix-like shortcuts (ll, gs, gp, etc.)
- **Git-aware prompt** - Shows current branch
- **Winget Upgrade Automation** - On-demand package upgrades with `wup` or `winup` commands (the Windows counterpart of `brewup` on Linux/macOS)
  - Detection phase: Only runs if updates are available
  - Execution phase: 3-second countdown before upgrading (can be cancelled)
  - Invoked explicitly by the user (no longer wired into `chezmoi update`)
  - Uses Microsoft.WinGet.Client PowerShell module when available

## Usage

After installation, start a new PowerShell session. Type `aliases` to see all available commands.

### Winget Upgrade Commands

- `wup` or `winup` - Check for and upgrade winget packages with a 3-second countdown
- `Test-WingetUpdates` - Check if any package updates are available (returns true/false)
- `Invoke-WingetUpgrade` - Full upgrade function with customizable options

**Soak time:** by default, `Invoke-WingetUpgrade` only installs package versions
that have been published in [winget-pkgs](https://github.com/microsoft/winget-pkgs)
for at least 7 days. Each package is pinned to the newest version that is old
enough; packages without one are skipped and listed in the summary. A version's
age is when its manifest folder was added to winget-pkgs, looked up through the
GitHub API (`gh api` when signed in, otherwise unauthenticated requests, which
also covers a gh token blocked by SAML enforcement). When the age can't be
determined, the package is skipped. Soak needs the Microsoft.WinGet.Client
module. winget has no native minimum package age yet; once
[microsoft/winget-cli#6178](https://github.com/microsoft/winget-cli/issues/6178)
lands, this can move to winget's own setting.

**Examples:**

```powershell
# Check for updates
Test-WingetUpdates

# Upgrade packages to versions at least 7 days old (3-second countdown)
wup

# Preview what would be upgraded, to which version, and what is skipped
Invoke-WingetUpgrade -WhatIf

# Require versions to be at least 14 days old
Invoke-WingetUpgrade -SoakDays 14

# Upgrade everything to the newest version, regardless of age
Invoke-WingetUpgrade -NoSoak

# Upgrade immediately without countdown
Invoke-WingetUpgrade -CountdownSeconds 0

# Force upgrade without checking for updates first
Invoke-WingetUpgrade -Force
```

**Note:** Winget upgrades are intentionally decoupled from `chezmoi update`. Run `wup` / `winup` whenever you want to upgrade installed packages, similar to how `brewup` works on Linux/macOS. You can cancel the upgrade by pressing Ctrl+C during the 3-second countdown.

## Customization

Edit the files in this directory and run `chezmoi apply` to update your profile.
