# 🐠 Dotfiles

[![Docs](https://img.shields.io/badge/docs-dotfiles.ravensberg.org-blue?logo=materialformkdocs)](https://dotfiles.ravensberg.org)

Modern dotfiles repository managed with [Chezmoi](https://chezmoi.io/), featuring [Fish shell](https://fishshell.com/) configuration and automated setup scripts.

📖 **Full documentation:** <https://dotfiles.ravensberg.org>

## ✨ Features

- **Multi-Shell Support**: Configurations for Fish, Bash, Zsh (Linux/macOS) and PowerShell (Windows) with unified aliases and custom functions
- **Git Configuration**: Pre-configured with templates for user info and global ignore patterns
- **Editor Configurations**: Vim and Tmux with sensible defaults
- **Cross-Platform**: Works seamlessly on Linux, macOS, Windows (PowerShell), and WSL
- **Custom Functions Library**: Reusable shell functions for common tasks (git operations, brew updates, file management)
- **Automated Validation**: Pre-commit hooks and validation scripts ensure configuration quality
- **Windows Enterprise Detection**: Automatic detection of Entra ID (Azure AD) and Intune enrollment status
- **Task Automation**: Integrated [Task](https://taskfile.dev/) runner for common operations (validation, testing, installation)
- **Tool Version Management**: [mise](https://mise.jdx.dev/) for managing development tool versions

## 🔧 Chezmoi Variables

The dotfiles repository provides several variables that can be used in templates and scripts:

### User Information
- `firstname` / `lastname` / `name` - Your name (prompted on first run)
- `username` - System username (prompted on first run)
- `email` - Your email address (prompted on first run)
- `githubUsername` - Your GitHub username (auto-detected from email or git remote)

### Environment Detection
- `codespaces` - Running in GitHub Codespaces (`true`/`false`)
- `devcontainer` - Running in a dev container (`true`/`false`)
- `wsl` - Running in Windows Subsystem for Linux (`true`/`false`)
- `ci` - Running in CI environment (`true`/`false`)
- `installType` - Installation mode (`light` or `full`)

### Windows Enterprise (Windows and WSL)
- `isEntraIDJoined` - Device is Entra ID (Azure AD) joined (`true`/`false`)
- `isIntuneJoined` - Device is Intune (MDM) enrolled (`true`/`false`)
- `isEntraRegistered` - Device is Entra ID registered/workplace joined (`true`/`false`)
- `isADDomainJoined` - Device is Active Directory domain joined (`true`/`false`)
- `entraIDTenantName` - Entra ID tenant name (e.g., `Microsoft`)
- `entraIDTenantId` - Entra ID tenant ID (GUID)
- `isWork` - Device is joined to a `*Microsoft` tenant (`true`/`false`)

These variables are automatically exposed as environment variables in your shell:
- **PowerShell**: `$env:CHEZMOI_*` (e.g., `$env:CHEZMOI_IS_ENTRA_ID_JOINED`, `$env:CHEZMOI_ENTRA_ID_TENANT_NAME`)
- **Bash/Zsh**: `$CHEZMOI_*` (e.g., `$CHEZMOI_IS_ENTRA_ID_JOINED`, `$CHEZMOI_ENTRA_ID_TENANT_NAME`)
- **Fish**: `$CHEZMOI_*` (e.g., `$CHEZMOI_IS_ENTRA_ID_JOINED`, `$CHEZMOI_ENTRA_ID_TENANT_NAME`)

## 📁 Structure

```
dotfiles/
├── .devcontainer/               # DevContainer configuration
│   └── devcontainer.json        # Container features and settings
├── .github/
│   ├── workflows/
│   │   └── ci.yaml              # CI/CD pipeline with devcontainer tests
│   └── scripts/
│       ├── test-devcontainer.sh # DevContainer deployment test
│       ├── test-light-server.sh # Light installation test
│       └── test-dev-server.sh   # Full installation test
├── install.sh                   # Wrapper script for Coder support (Unix)
├── install.ps1                  # Wrapper script for Coder support (Windows)
├── home/                        # Chezmoi source directory
│   ├── dot_config/              # XDG config directory (~/.config/)
│   │   ├── fish/                # Fish shell configuration (Linux/macOS)
│   │   │   ├── config.fish      # Main Fish config
│   │   │   ├── conf.d/          # Configuration snippets (auto-loaded)
│   │   │   │   └── aliases.fish # Command aliases
│   │   │   ├── functions/       # Custom Fish functions
│   │   │   │   ├── fish_greeting.fish
│   │   │   │   └── git_undo_commit.fish
│   │   │   └── completions/     # Custom completions
│   │   ├── powershell/          # PowerShell configuration (Windows)
│   │   │   ├── profile.ps1      # Main PowerShell profile
│   │   │   ├── aliases.ps1      # Command aliases
│   │   │   ├── modules/         # PowerShell modules
│   │   │   │   └── DotfilesHelpers/  # Custom functions module
│   │   │   └── scripts/         # PowerShell utility scripts
│   │   │       ├── New-SigningCert.ps1.tmpl      # Create code signing certificate
│   │   │       ├── Import-SigningCert.ps1        # Import certificate
│   │   │       └── Sign-PowerShellScripts.ps1    # Sign PowerShell scripts
│   │   ├── git/                 # Git configuration
│   │   │   ├── config.tmpl      # Git config with templating
│   │   │   └── ignore           # Global gitignore
│   │   └── shell/               # Other shell configs (bash, zsh)
│   │       ├── config.bash
│   │       ├── config.zsh
│   │       └── functions/       # Shared shell functions
│   ├── AppData/                 # Windows-specific application data
│   │   └── Local/Packages/
│   │       └── Microsoft.WindowsTerminal_.../
│   │           └── LocalState/
│   │               └── settings.json  # Windows Terminal settings
│   ├── Documents/               # Windows PowerShell profiles
│   │   ├── PowerShell/
│   │   │   └── profile.ps1
│   │   └── WindowsPowerShell/
│   │       └── profile.ps1
│   ├── dot_bashrc               # Bash configuration
│   ├── dot_zshrc                # Zsh configuration
│   ├── dot_vimrc                # Vim configuration
│   ├── dot_tmux.conf            # Tmux configuration
│   ├── install.sh               # Main installation script (Unix)
│   └── install.ps1              # Main installation script (Windows)
├── tests/                       # Test files (Bats/Pester)
│   ├── bash/                    # Bats tests for validation
│   │   ├── validate-chezmoi.bats
│   │   ├── validate-shell-scripts.bats
│   │   ├── validate-fish-config.bats
│   │   ├── test-chezmoi-apply.bats
│   │   ├── test-fish-config.bats
│   │   ├── verify-dotfiles.bats
│   │   └── run-tests.sh         # Bats test runner
│   └── powershell/              # Pester tests
│       ├── Validate-Packages.Tests.ps1
│       └── Invoke-PesterTests.ps1 # Pester test runner
├── README.md
├── CONTRIBUTING.md
├── STRUCTURE.md
└── .lefthook.toml
```

## 🚀 Quick Start

### Install on Linux/macOS

```bash
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply DevSecNinja
```

Or clone and install locally:

```bash
git clone https://github.com/DevSecNinja/dotfiles.git
cd dotfiles
./install.sh
```

### Install on Windows (PowerShell)

**Option 1: Direct from GitHub (PowerShell 5.1+ or PowerShell 7+)**

```powershell
# Using the official chezmoi installer (recommended)
(irm -useb https://get.chezmoi.io/ps1) | powershell -c -; chezmoi init --apply DevSecNinja
```

**Option 2: Clone and install locally**

```powershell
git clone https://github.com/DevSecNinja/dotfiles.git
cd dotfiles
.\install.ps1
```

### Install on WSL (Windows Subsystem for Linux)

Use the Linux installation method inside your WSL distribution:

```bash
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply DevSecNinja
```

The dotfiles will automatically detect WSL and apply appropriate configurations.

### Install in Coder Workspaces

This repository supports [Coder](https://coder.com/) workspaces out of the box. The `install.sh` and `install.ps1` scripts in the repository root will be automatically discovered and executed by Coder when setting up a new workspace with dotfiles enabled.

To use this dotfiles repository in Coder:

1. Navigate to your Coder workspace settings
2. Enable dotfiles support
3. Set the dotfiles repository URL to: `https://github.com/DevSecNinja/dotfiles`
4. Coder will automatically run `install.sh` (Linux/macOS) or `install.ps1` (Windows) during workspace setup

For more information, see the [Coder Dotfiles Documentation](https://coder.com/docs/user-guides/workspace-dotfiles).

### Development Container (DevContainer)

This repository includes a complete [DevContainer](https://containers.dev/) configuration for Visual Studio Code and GitHub Codespaces. The devcontainer provides a fully configured development environment with:

**Pre-installed Features:**
- 🍺 Homebrew package manager
- 📦 Git LFS (Large File Storage)
- 💻 PowerShell with Pester testing framework
- 🐍 Python (latest version)
- 🐙 GitHub CLI

**Automatic Setup:**
- ✅ Dotfiles automatically installed via `postCreateCommand`
- ✅ Fish shell configured as default terminal
- ✅ All configurations applied and verified
- ✅ VSCode extensions pre-installed (GitHub Copilot, Pester)

**Prebuilt Images:**
- 🚀 Prebuilt devcontainer images are automatically built and published to GitHub Container Registry
- 🏗️ Images are rebuilt weekly and on every devcontainer configuration change
- ⚡ CI workflows use prebuilt images for faster test execution
- 📦 Available at: `ghcr.io/devsecninja/dotfiles-devcontainer:latest`

**Using the DevContainer:**

1. **In VSCode:**
   - Open this repository in VSCode
   - Install the "Dev Containers" extension
   - Click "Reopen in Container" when prompted
   - Or use Command Palette: `Dev Containers: Reopen in Container`

2. **In GitHub Codespaces:**
   - Navigate to this repository on GitHub
   - Click "Code" → "Codespaces" → "Create codespace on main"
   - The devcontainer will automatically build and configure
   - **Optional:** Enable Codespaces prebuilds in repository settings for even faster startup

3. **Testing the DevContainer:**
   ```bash
   # Run the devcontainer test script
   .github/scripts/test-devcontainer.sh
   ```

The CI pipeline automatically tests the complete devcontainer deployment, including feature installation, dotfiles setup, and postCreateCommand execution.

## 🔧 Customization

### Personal Information

On first run, Chezmoi will prompt for:
- **Name**: Used in Git commits
- **Email**: Used in Git commits

To re-enter this information:
```bash
chezmoi init --data=false
```

## 📝 Common Commands

```bash
# Check what changes would be applied
chezmoi diff

# Apply changes
chezmoi apply

# Edit a file
chezmoi edit ~/.vimrc

# Add a new file
chezmoi add ~/.config/myapp/config.yaml

# Update from repository
chezmoi update

# View Chezmoi data (name, email, OS info)
chezmoi data

# Verify all managed files
chezmoi verify
```

### Pre-commit Hooks (Lefthook)

This repository uses [lefthook](https://github.com/evilmartians/lefthook) for code quality checks:

```bash
# Install development tools (lefthook, shellcheck, shfmt, ...) via mise
mise install

# Setup lefthook git hooks (from repository root)
home/.chezmoiscripts/linux/run_once_setup-lefthook.sh

# Run manually on all files
lefthook run pre-commit --all-files
```

Hooks will automatically run on `git commit`. The checks include:
- 🐚 Shell script linting (shellcheck)
- 🎨 Shell script formatting (shfmt)
- 🔧 Executable bit enforcement on shell scripts

These scripts and hooks are also used in the GitHub Actions CI pipeline to ensure quality.

## 🛠️ Development Tools

This repository includes [Task](https://taskfile.dev/) and [mise](https://mise.jdx.dev/) for streamlined development:

### Task Runner

Task provides convenient commands for common operations:

```bash
# List all available tasks
task --list

# Install all dependencies (mise, go-task, Python packages)
task install:all

# Run all validation checks (required before commit)
task validate:all

# Run specific validations
task validate:chezmoi      # Validate Chezmoi config
task validate:shell        # Validate shell scripts
task validate:fish         # Validate Fish config

# Run tests
task test:all              # All tests
task test:chezmoi-apply    # Test Chezmoi apply

# Chezmoi operations
task chezmoi:init          # Preview changes (dry-run)
task chezmoi:diff          # Show differences
task chezmoi:verify        # Verify applied files

# Development setup
task dev:setup             # Complete dev environment setup

# CI tasks
task ci:validate           # Run CI validation pipeline
```

### Mise (Tool Version Manager)

Mise manages tool versions defined in [.mise.toml](.mise.toml):

```bash
# Install mise-managed tools
mise install

# Show installed tools
mise list

# Upgrade all tools
mise upgrade

# Check mise configuration
mise doctor
```

**Full mode installations** automatically install both Task and mise. **Light mode** installs only mise.

### Installation Modes

The repository supports two installation modes:

- **Light mode** (servers, CI, codespaces): Essential tools only
- **Full mode** (dev servers, workstations): Full development tooling including Task and mise

The mode is auto-detected based on:
- Hostname patterns (SVLDEV* = full, SVL* = light)
- Environment (codespaces, devcontainer, CI = light)
- Default = full mode

To change modes:
```bash
chezmoi init --data=false
```

## 📚 Learn More

- [Chezmoi Documentation](https://www.chezmoi.io/user-guide/command-overview/)
- [Fish Shell Documentation](https://fishshell.com/docs/current/)
- [Chezmoi Template Reference](https://www.chezmoi.io/reference/templates/)

## 🤝 Contributing

Feel free to fork and customize this repository for your own needs!

## 📄 License

MIT
