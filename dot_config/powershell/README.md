# PowerShell Profile Configuration - README

This directory contains PowerShell profile configuration managed by chezmoi.

## Files

- `profile.ps1` - Main PowerShell profile with settings and module imports
- `aliases.ps1` - Command aliases and helper functions

## Installation

The profile is automatically linked by the `run_once_install-packages.ps1.tmpl` script, or you can manually create a symbolic link:

### PowerShell 7+ (pwsh)
```powershell
New-Item -ItemType SymbolicLink -Path $PROFILE -Target "$HOME\.config\powershell\profile.ps1" -Force
```

### Windows PowerShell 5.1
```powershell
New-Item -ItemType SymbolicLink -Path $PROFILE -Target "$HOME\.config\powershell\profile.ps1" -Force
```

## Features

- **PSReadLine** - Enhanced command-line editing with history search
- **Custom aliases** - Unix-like shortcuts (ll, gs, gp, etc.)
- **Git-aware prompt** - Shows current branch

## Usage

After installation, start a new PowerShell session. Type `aliases` to see all available commands.

## Customization

Edit the files in this directory and run `chezmoi apply` to update your profile.
