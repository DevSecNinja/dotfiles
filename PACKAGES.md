# Cross-Platform Package Management

This repository uses Chezmoi's data feature to manage packages across Windows, Linux, and macOS from a centralized YAML file.

## Overview

All packages are defined in [.chezmoidata/packages.yaml](.chezmoidata/packages.yaml), which is automatically loaded by Chezmoi and made available to all templates.

**Key Design**: The `full` mode installs `light` packages + additional packages. No duplication!

## Structure

```yaml
packages:
  windows:
    winget:
      light: [...]         # Essential packages (always installed)
      full: [...]          # Additional packages (only in full mode)
    powershell_modules:
      light: [...]         # Essential modules
      full: [...]          # Additional modules
  linux:
    apt:
      light: [...]         # Essential packages
      full: [...]          # Additional packages
    dnf:
      light: [...]
      full: [...]
  darwin:
    brew:
      light: [...]
      full: [...]
extensions:
  common: [...]            # VS Code extensions for all platforms
  windows: [...]           # Windows-specific extensions
```

## Installation Scripts

Packages are automatically installed by Chezmoi `run_once` scripts:

- **Windows**: [run_once_install-packages.ps1.tmpl](run_once_install-packages.ps1.tmpl)
- **Linux/macOS**: [run_once_install-packages.sh.tmpl](run_once_install-packages.sh.tmpl)

These scripts:
1. Always install `light` packages
2. If `installType == "full"`, also install `full` packages

## Installation Modes

### Light Mode
Minimal installation for production servers (hostname pattern: `SVL*` but not `SVLDEV*`).

**Windows packages** (3):
- Git.Git
- Microsoft.PowerShell  
- twpayne.chezmoi

**PowerShell modules** (2):
- PSReadLine
- Posh-Git

### Full Mode
Complete development environment (hostname: `SVLDEV*` or other).

Installs **light + full** packages.

**Windows packages** (6 total = 3 light + 3 additional):
- All light mode packages
- **Plus**: Microsoft.VisualStudioCode, Microsoft.WindowsTerminal, JanDeDobbeleer.OhMyPosh

**PowerShell modules** (5 total = 2 light + 3 additional):
- All light mode modules
- **Plus**: Terminal-Icons, PSFzf, z

## Adding New Packages

1. Edit [.chezmoidata/packages.yaml](.chezmoidata/packages.yaml)
2. Add package to the appropriate section:
   - For essential tools (servers): add to `light` list
   - For development tools: add to `full` list
   - Example for Windows:
     ```yaml
     windows:
       winget:
         light:
           - Git.Git
         full:
           - Microsoft.VisualStudioCode  # Add new package here
     ```
3. Test with: `.\scripts\test-packages-windows.ps1`
4. Validate with: `chezmoi apply --dry-run --source=.`

## Testing on Windows

Test if packages.yaml is valid:

```powershell
.\scripts\test-packages-windows.ps1
```

Test template rendering:

```powershell
# Test light mode packages
chezmoi execute-template --source=. '{{ range .packages.windows.winget.light }}{{ . }}{{ "\n" }}{{ end }}'

# Test full mode extra packages  
chezmoi execute-template --source=. '{{ range .packages.windows.winget.full }}{{ . }}{{ "\n" }}{{ end }}'

# Test PowerShell modules
chezmoi execute-template --source=. '{{ range .packages.windows.powershell_modules.light }}{{ . }}{{ "\n" }}{{ end }}'
```

## How It Works

Chezmoi automatically loads `.chezmoidata/packages.yaml` and makes it available in templates via `.packages`.

The installation scripts always install `light` packages, and conditionally install `full` packages based on `installType`.

Example from [run_once_install-packages.ps1.tmpl](run_once_install-packages.ps1.tmpl):

```powershell
# Install light mode packages (always)
{{- range .packages.windows.winget.light }}
winget install --id {{ . | quote }} --exact --silent
{{- end }}

{{- if eq .installType "full" }}
# Install full mode packages (additional)
{{- range .packages.windows.winget.full }}
winget install --id {{ . | quote }} --exact --silent
{{- end }}
{{- end }}
```

This generates:
- **Light mode**: Installs only `.light` packages
- **Full mode**: Installs both `.light` and `.full` packages

## Package Managers

| Platform | Package Manager | Command | Section |
|----------|----------------|---------|---------|
| Windows | WinGet | `winget install` | `packages.windows.winget` |
| Windows | PowerShellGet | `Install-Module` | `packages.windows.powershell_modules` |
| Linux (Debian/Ubuntu) | APT | `apt-get install` | `packages.linux.apt` |
| Linux (Fedora/RHEL) | DNF | `dnf install` | `packages.linux.dnf` |
| macOS | Homebrew | `brew install` | `packages.darwin.brew` |

## VS Code Extensions

VS Code extensions are defined separately in the `extensions` section but are not automatically installed yet. To implement auto-installation:

```powershell
# Windows example
{{- range .extensions.common }}
code --install-extension {{ . | quote }}
{{- end }}
{{- range .extensions.windows }}
code --install-extension {{ . | quote }}
{{- end }}
```

## Validation

Validate the YAML structure:

```bash
# Linux/macOS/WSL
./scripts/validate-packages.sh

# Check all validations
./scripts/validate-all.sh
```

## Related Files

- [.chezmoidata/packages.yaml](.chezmoidata/packages.yaml) - Package definitions
- [run_once_install-packages.ps1.tmpl](run_once_install-packages.ps1.tmpl) - Windows installer
- [run_once_install-packages.sh.tmpl](run_once_install-packages.sh.tmpl) - Linux/macOS installer  
- [scripts/test-packages-windows.ps1](scripts/test-packages-windows.ps1) - Windows validation
- [scripts/validate-packages.sh](scripts/validate-packages.sh) - YAML validation

## Troubleshooting

### "map has no entry for key" error
Make sure `.chezmoidata` contains only YAML or JSON files (no `.md` files).

### Packages not installing
1. Verify YAML syntax: `.\scripts\test-packages-windows.ps1`
2. Test template rendering with `chezmoi execute-template`
3. Check Chezmoi data: `chezmoi data --source=. --format=json`

### WinGet not found
Install "App Installer" from Microsoft Store, which includes winget.
