# PowerShell Profile Configuration - README

This directory contains PowerShell profile configuration managed by chezmoi.

## Files

- `profile.ps1` - Main PowerShell profile with settings and module imports
- `aliases.ps1` - Command aliases and helper functions

## Installation

The profile is automatically installed by chezmoi. A loader file is placed at `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` (the default `$PROFILE` location) which sources the actual configuration from `~/.config/powershell/profile.ps1`.

This approach works seamlessly across different PowerShell versions and doesn't require symbolic links or manual setup.

## Features

- **PSReadLine** - Enhanced command-line editing with history search
- **Custom aliases** - Unix-like shortcuts (ll, gs, gp, etc.)
- **Git-aware prompt** - Shows current branch

## Usage

After installation, start a new PowerShell session. Type `aliases` to see all available commands.

## Customization

Edit the files in this directory and run `chezmoi apply` to update your profile.
