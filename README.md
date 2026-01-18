# 🐠 Dotfiles

Modern dotfiles repository managed with [Chezmoi](https://chezmoi.io/), featuring [Fish shell](https://fishshell.com/) configuration and automated setup scripts.

## ✨ Features

- **Fish Shell** (Linux/macOS) & **PowerShell** (Windows): Modern shell configurations with sensible defaults and useful aliases
- **Git Configuration**: Pre-configured with templates for user info
- **Vim & Tmux**: Basic but functional configurations
- **Automated Setup**: Scripts to install tools and create directories
- **Cross-Platform**: Works on Linux (Ubuntu/Debian), macOS, and Windows (PowerShell/WSL)
- **Smart Installation**: Automatically detects server type and installs appropriate version
  - **Light mode** for servers (SVL*): Essential tools only
  - **Full mode** for dev servers (SVLDEV*) and workstations: All development tools

## 📁 Structure

```
dotfiles/
├── dot_config/                    # XDG config directory (~/.config/)
│   ├── fish/                      # Fish shell configuration (Linux/macOS)
│   │   ├── config.fish           # Main Fish config
│   │   ├── conf.d/               # Configuration snippets (auto-loaded)
│   │   │   └── aliases.fish      # Command aliases
│   │   ├── functions/            # Custom Fish functions
│   │   │   └── fish_greeting.fish
│   │   └── completions/          # Custom completions
│   ├── powershell/                # PowerShell configuration (Windows)
│   │   ├── profile.ps1           # Main PowerShell profile
│   │   └── aliases.ps1           # Command aliases
│   ├── git/                       # Git configuration
│   │   ├── config.tmpl           # Git config with templating
│   │   └── ignore                # Global gitignore
│   └── shell/                     # Other shell configs (bash, zsh)
├── AppData/                       # Windows-specific application data
│   └── Local/Packages/
│       └── Microsoft.WindowsTerminal_.../
│           └── LocalState/
│               └── settings.json  # Windows Terminal settings
├── dot_vimrc                      # Vim configuration
├── dot_tmux.conf                  # Tmux configuration
├── run_once_before_00-setup.sh.tmpl      # Initial directory setup (Unix)
├── run_once_before_00-setup.ps1.tmpl     # Initial directory setup (Windows)
├── run_once_install-packages.sh.tmpl     # Development tools (Unix)
├── run_once_install-packages.ps1.tmpl    # Development tools (Windows)
├── .chezmoi.yaml.tmpl            # Chezmoi configuration
├── .chezmoiignore                # Files to exclude (with templates)
├── install.sh                     # Installation script (Unix)
└── install.ps1                    # Installation script (Windows)
```

## 🚀 Quick Start

### Install on Linux/macOS

```bash
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply DevSecNinja/dotfiles
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
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply DevSecNinja/dotfiles
```

The dotfiles will automatically detect WSL and apply appropriate configurations.

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

# Setup pre-commit hooks
./scripts/setup-precommit.sh

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
