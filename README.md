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
│   │   │   └── fish-greeting.fish
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

### What happens during installation

1. Installs Chezmoi (if not present)
2. Detects the system type based on hostname and OS:
   - **Light Server Mode** (hostname starts with `SVL` but not `SVLDEV`):
     - **Linux/macOS**: Installs only essential tools: git, vim, tmux, curl, wget, fish
     - **Windows**: Installs only essential tools: git, vim, curl, wget
     - Skips pre-commit hooks and dev-only tools
     - Excludes development configuration files
   - **Full Mode** (hostname starts with `SVLDEV` or any other name):
     - **Linux/macOS**: Installs all development tools: tree, htop, python3-venv, etc.
     - **Windows**: Installs all development tools: 7zip, python3, nodejs, vscode, PowerShell 7
     - Installs pre-commit hooks (in devcontainer environments)
     - Includes all configuration files
3. Prompts for your name and email (for Git config)
4. Runs initial setup scripts:
   - **Linux/macOS**: Creates directories (~/.vim/undo, ~/bin, ~/projects)
   - **Windows**: Creates directories (%USERPROFILE%\bin, %USERPROFILE%\projects)
   - Installs Fish shell (Linux/macOS) or PowerShell modules (Windows)
   - Installs packages based on installation mode
5. Applies all dotfiles to your home directory

### Installation Modes

The dotfiles automatically detect the system type:

- **🔧 Light Server** (`SVL*`): Minimal installation for production servers
  - Example hostnames: `SVLPROD01`, `SVLWEB02`, `SVLDB03`
  - Only essential tools installed
  - No dev-only tools like pre-commit, tree, htop

- **🖥️ Dev Server** (`SVLDEV*`): Full installation for development servers
  - Example hostnames: `SVLDEV01`, `SVLDEV-STAGING`
  - All development tools installed
  - Includes pre-commit hooks and dev tools

- **💻 Workstation** (any other hostname): Full installation
  - Your local machine, laptop, or desktop
  - All tools and features enabled

## 🔧 Customization

### Personal Information

On first run, Chezmoi will prompt for:
- **Name**: Used in Git commits
- **Email**: Used in Git commits

To re-enter this information:
```bash
# Linux/macOS/WSL
chezmoi init --data=false

# Windows PowerShell
chezmoi init --data=false
```

### Adding Your Own Dotfiles

1. **Add an existing file**:
   ```bash
   # Linux/macOS/WSL
   chezmoi add ~/.bashrc

   # Windows PowerShell
   chezmoi add $PROFILE
   ```

2. **Edit a managed file**:
   ```bash
   # Linux/macOS/WSL
   chezmoi edit ~/.config/fish/config.fish

   # Windows PowerShell
   chezmoi edit ~/.config/powershell/profile.ps1
   ```

3. **Apply changes**:
   ```bash
   chezmoi apply
   ```

### Shell Customization

#### Fish Shell (Linux/macOS/WSL)

- **Aliases**: Edit [dot_config/fish/conf.d/aliases.fish](dot_config/fish/conf.d/aliases.fish)
- **Functions**: Add files to [dot_config/fish/functions/](dot_config/fish/functions/)
- **Config snippets**: Add files to [dot_config/fish/conf.d/](dot_config/fish/conf.d/)

#### PowerShell (Windows)

- **Profile**: Edit [dot_config/powershell/profile.ps1](dot_config/powershell/profile.ps1)
- **Aliases**: Edit [dot_config/powershell/aliases.ps1](dot_config/powershell/aliases.ps1)
- **View all aliases**: Type `aliases` in PowerShell

### Windows Terminal Configuration

Windows Terminal settings are managed at:
- [AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json](AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json)

Features:
- PowerShell 7 as default profile
- WSL integration
- Useful keyboard shortcuts

### Adding Scripts

Create scripts in the root directory with platform-specific extensions:

**Unix (Linux/macOS/WSL)**:
- `run_once_*.sh`: Runs once after installation
- `run_onchange_*.sh`: Runs when file content changes
- `run_*.sh`: Runs on every apply

**Windows**:
- `run_once_*.ps1`: Runs once after installation
- `run_onchange_*.ps1`: Runs when file content changes
- `run_*.ps1`: Runs on every apply

Use `.tmpl` extension to use Chezmoi templating (e.g., `run_once_setup.sh.tmpl`).

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

## 🎯 Tips

### Unix (Linux/macOS/WSL)
- **Set Fish as default shell**: `chsh -s $(which fish)`
- **Preview changes**: Always run `chezmoi diff` before `chezmoi apply`

### Windows
- **Set PowerShell 7 as default**: Open Windows Terminal settings and set PowerShell 7 as default profile
- **PowerShell modules**: Type `aliases` to see all available shortcuts

### Cross-Platform
- **Preview changes**: Always run `chezmoi diff` before `chezmoi apply`
- **Templates**: Use `.tmpl` extension to access Chezmoi variables like `{{ .name }}`
- **Platform-specific config**: Use Chezmoi's conditional templating:
  ```
  {{- if eq .chezmoi.os "darwin" }}
  # macOS-specific config
  {{- else if eq .chezmoi.os "linux" }}
  # Linux-specific config
  {{- else if eq .chezmoi.os "windows" }}
  # Windows-specific config
  {{- end }}
  ```

## 🧪 Testing

The repository includes validation and testing scripts in the [scripts/](scripts/) directory:

```bash
# Validate everything at once
./scripts/validate-all.sh

# Or run individual checks
./scripts/validate-chezmoi.sh       # Check Chezmoi config
./scripts/validate-shell-scripts.sh # Validate shell syntax
./scripts/validate-fish-config.sh   # Validate Fish config
./scripts/test-chezmoi-apply.sh     # Dry-run apply
```

### CI Testing

The CI pipeline automatically tests both installation scenarios:
- **Light server** (hostname `SVLPROD01`): Minimal toolset
- **Dev server** (hostname `SVLDEV01`): Full toolset

These tests run only in GitHub Actions with specific container hostname configuration.

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

These scripts and hooks are also used in the GitHub Actions CI pipeline to ensure quality. See [scripts/README.md](scripts/README.md) for detailed documentation.

## 📚 Learn More

- [Chezmoi Documentation](https://www.chezmoi.io/user-guide/command-overview/)
- [Fish Shell Documentation](https://fishshell.com/docs/current/)
- [Chezmoi Template Reference](https://www.chezmoi.io/reference/templates/)

## 🤝 Contributing

Feel free to fork and customize this repository for your own needs!

## 📄 License

MIT
