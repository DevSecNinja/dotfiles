# 🐠 Dotfiles

Modern dotfiles repository managed with [Chezmoi](https://chezmoi.io/), featuring [Fish shell](https://fishshell.com/) configuration and automated setup scripts.

## ✨ Features

- **Multi-Shell Support**: Configurations for Fish, Bash, Zsh (Linux/macOS) and PowerShell (Windows) with unified aliases and custom functions
- **Git Configuration**: Pre-configured with templates for user info and global ignore patterns
- **Editor Configurations**: Vim and Tmux with sensible defaults
- **Cross-Platform**: Works seamlessly on Linux, macOS, Windows (PowerShell), and WSL
- **Custom Functions Library**: Reusable shell functions for common tasks (git operations, brew updates, file management)
- **Automated Validation**: Pre-commit hooks and validation scripts ensure configuration quality

## 📁 Structure

```
dotfiles/
├── install.sh                     # Wrapper script for Coder support (Unix)
├── install.ps1                    # Wrapper script for Coder support (Windows)
├── home/                          # Chezmoi source directory
│   ├── dot_config/                # XDG config directory (~/.config/)
│   │   ├── fish/                  # Fish shell configuration (Linux/macOS)
│   │   │   ├── config.fish        # Main Fish config
│   │   │   ├── conf.d/            # Configuration snippets (auto-loaded)
│   │   │   │   └── aliases.fish   # Command aliases
│   │   │   ├── functions/         # Custom Fish functions
│   │   │   │   ├── fish_greeting.fish
│   │   │   │   └── git_undo_commit.fish
│   │   │   └── completions/       # Custom completions
│   │   ├── powershell/            # PowerShell configuration (Windows)
│   │   │   ├── profile.ps1        # Main PowerShell profile
│   │   │   ├── aliases.ps1        # Command aliases
│   │   │   ├── functions.ps1      # Custom functions
│   │   │   └── scripts/           # PowerShell utility scripts
│   │   │       ├── New-SigningCert.ps1.tmpl      # Create code signing certificate
│   │   │       ├── Import-SigningCert.ps1        # Import certificate
│   │   │       └── Sign-PowerShellScripts.ps1    # Sign PowerShell scripts
│   │   ├── git/                   # Git configuration
│   │   │   ├── config.tmpl        # Git config with templating
│   │   │   └── ignore             # Global gitignore
│   │   └── shell/                 # Other shell configs (bash, zsh)
│   │       ├── config.bash
│   │       ├── config.zsh
│   │       └── functions/         # Shared shell functions
│   ├── AppData/                   # Windows-specific application data
│   │   └── Local/Packages/
│   │       └── Microsoft.WindowsTerminal_.../
│   │           └── LocalState/
│   │               └── settings.json  # Windows Terminal settings
│   ├── Documents/                 # Windows PowerShell profiles
│   │   ├── PowerShell/
│   │   │   └── profile.ps1
│   │   └── WindowsPowerShell/
│   │       └── profile.ps1
│   ├── dot_bashrc                 # Bash configuration
│   ├── dot_zshrc                  # Zsh configuration
│   ├── dot_vimrc                  # Vim configuration
│   ├── dot_tmux.conf              # Tmux configuration
│   ├── install.sh                 # Main installation script (Unix)
│   └── install.ps1                # Main installation script (Windows)
├── tests/                         # Test files (Bats/Pester)
│   ├── bash/                      # Bats tests for validation
│   │   ├── validate-chezmoi.bats
│   │   ├── validate-shell-scripts.bats
│   │   ├── validate-fish-config.bats
│   │   ├── test-chezmoi-apply.bats
│   │   ├── test-fish-config.bats
│   │   ├── verify-dotfiles.bats
│   │   └── run-tests.sh           # Bats test runner
│   └── powershell/                # Pester tests
│       ├── Validate-Packages.Tests.ps1
│       └── Invoke-PesterTests.ps1 # Pester test runner
├── README.md
├── CONTRIBUTING.md
├── STRUCTURE.md
└── requirements.txt
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

### Pre-commit Hooks

This repository uses [pre-commit](https://pre-commit.com/) for code quality checks:

```bash
# Install dependencies
pip3 install -r requirements.txt

# Setup pre-commit hooks (from repository root)
home/.chezmoiscripts/linux/run_once_setup-precommit.sh

# Run manually on all files
pre-commit run --all-files
```

Hooks will automatically run on `git commit`. The checks include:
- ✂️ Trailing whitespace removal
- 📄 End-of-file fixes
- 🔍 YAML validation
- 🎨 Shell script formatting (shfmt)

These scripts and hooks are also used in the GitHub Actions CI pipeline to ensure quality.

## 📚 Learn More

- [Chezmoi Documentation](https://www.chezmoi.io/user-guide/command-overview/)
- [Fish Shell Documentation](https://fishshell.com/docs/current/)
- [Chezmoi Template Reference](https://www.chezmoi.io/reference/templates/)

## 🤝 Contributing

Feel free to fork and customize this repository for your own needs!

## 📄 License

MIT
