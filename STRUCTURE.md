# 📂 Dotfiles Structure Reference

Quick reference guide for the dotfiles repository structure and Chezmoi naming conventions.

## 🎯 Chezmoi Naming Conventions

Chezmoi uses special prefixes in filenames to determine how files are managed:

| Prefix | Target | Example |
|--------|--------|---------|
| `dot_` | `.` (hidden file) | `dot_vimrc` → `~/.vimrc` |
| `private_` | File with 0600 permissions | `private_ssh_config` |
| `executable_` | File with +x permissions | `executable_script.sh` |
| `run_once_` | Script that runs once | `run_once_install.sh` |
| `run_onchange_` | Script that runs on change | `run_onchange_update.sh` |
| `run_` | Script that runs every apply | `run_backup.sh` |
| `.tmpl` | Template file | `config.tmpl` (processes Chezmoi templates) |

## 📁 Directory Structure

```
dotfiles/
│
├── 🐠 Fish Shell Configuration (Linux/macOS/WSL)
│   └── dot_config/fish/
│       ├── config.fish              # Main Fish configuration
│       ├── conf.d/                  # Auto-loaded configuration snippets
│       │   ├── aliases.fish         # Command aliases
│       │   └── .gitkeep             # Keeps directory in git
│       ├── functions/               # Custom Fish functions
│       │   ├── fish_greeting.fish   # Custom greeting
│       │   └── .gitkeep
│       └── completions/             # Custom completions
│           └── .gitkeep
│
├── 💻 PowerShell Configuration (Windows)
│   └── dot_config/powershell/
│       ├── profile.ps1              # Main PowerShell profile
│       ├── aliases.ps1              # Command aliases and functions
│       └── README.md                # PowerShell configuration guide
│
├── 🪟 Windows Terminal Configuration
│   └── AppData/Local/Packages/
│       └── Microsoft.WindowsTerminal_8wekyb3d8bbwe/
│           └── LocalState/
│               └── settings.json    # Windows Terminal settings
│
├── 🔧 Git Configuration
│   └── dot_config/git/
│       ├── config.tmpl              # Git config (templated with user data)
│       └── ignore                   # Global gitignore patterns
│
├── 📝 Editor & Terminal Configuration
│   ├── dot_vimrc                    # Vim configuration
│   ├── dot_tmux.conf                # Tmux configuration
│   └── dot_config/shell/.gitkeep    # Future bash/zsh configs
│
├── 🚀 Setup Scripts (run on chezmoi apply)
│   ├── Unix/Linux/macOS/WSL:
│   │   ├── run_once_before_00-setup.sh.tmpl       # Initial directory creation
│   │   ├── run_once_install-fish.sh.tmpl          # Fish shell installation
│   │   ├── run_once_install-packages.sh.tmpl      # Development tools
│   │   └── run_once_install-precommit.sh.tmpl     # Pre-commit hooks
│   │
│   └── Windows:
│       ├── run_once_before_00-setup.ps1.tmpl      # Initial directory creation
│       └── run_once_install-packages.ps1.tmpl     # Development tools (winget)
│
├── 🧪 Validation & Testing Scripts
│   └── scripts/
│       ├── validate-chezmoi.sh      # Validate Chezmoi config
│       ├── validate-shell-scripts.sh # Check shell syntax
│       ├── validate-fish-config.sh  # Check Fish syntax
│       ├── test-chezmoi-apply.sh    # Dry-run test
│       ├── test-fish-config.sh      # Test Fish loads
│       ├── verify-dotfiles.sh       # Verify files applied
│       ├── setup-precommit.sh       # Install pre-commit hooks
│       ├── validate-all.sh          # Run all checks
│       └── README.md                # Scripts documentation
│
├── ⚙️ Chezmoi Configuration
│   ├── .chezmoi.yaml.tmpl           # Chezmoi config (prompts for name/email)
│   ├── .chezmoiignore               # Files to not copy to home (supports templates)
│   ├── .pre-commit-config.yaml      # Pre-commit hooks configuration
│   ├── requirements.txt             # Python dependencies (pre-commit)
│   ├── install.sh                   # Installation script (Unix)
│   └── install.ps1                  # Installation script (Windows)
│
├── 📚 Documentation
│   ├── README.md                    # Main documentation
│   ├── QUICKSTART.md                # Quick start guide
│   ├── STRUCTURE.md                 # This file
│   ├── CONTRIBUTING.md              # Development guide
│
└── 🔄 CI/CD
    └── .github/workflows/ci.yaml    # GitHub Actions validation
```

## 🎨 File Organization Tips

### Adding New Dotfiles

```bash
# Hidden file in home directory
chezmoi add ~/.bashrc              # Creates: dot_bashrc

# Config file in ~/.config/
chezmoi add ~/.config/app/config   # Creates: dot_config/app/config

# Executable script
chezmoi add --template ~/.local/bin/script.sh
```

### Script Execution Order

Scripts run in this order:
1. `run_once_before_*` - Before applying dotfiles
2. Apply dotfiles
3. `run_once_after_*` - After applying dotfiles
4. `run_onchange_*` - When script content changes
5. `run_*` - Every time

Numerical prefixes ensure order: `00-`, `01-`, `02-`, etc.

### Template Variables

Access Chezmoi data in `.tmpl` files:

```yaml
# Available variables
{{ .chezmoi.os }}              # "linux", "darwin", "windows"
{{ .chezmoi.osRelease.id }}    # "ubuntu", "debian" (Linux only)
{{ .chezmoi.hostname }}        # Hostname
{{ .chezmoi.username }}        # Current user
{{ .name }}                    # User's name (from prompts)
{{ .email }}                   # User's email (from prompts)
{{ .installType }}             # "light" or "full" (auto-detected)
```

### Conditional Configuration

```bash
{{- if eq .chezmoi.os "darwin" }}
# macOS-specific config
{{- else if eq .chezmoi.os "linux" }}
# Linux-specific config
{{- else if eq .chezmoi.os "windows" }}
# Windows-specific config
{{- end }}

# Installation mode
{{- if eq .installType "light" }}
# Light server installation
{{- else }}
# Full installation
{{- end }}
```

## 🔍 Quick Commands

```bash
# Preview structure
chezmoi managed -i files

# See what would be applied
chezmoi diff

# Apply changes
chezmoi apply -v

# Edit managed file
chezmoi edit ~/.config/fish/config.fish

# Re-run setup (change name/email)
chezmoi init --data=false
```

## 📦 What Gets Applied Where

### Unix/Linux/macOS/WSL

| Source File | Target Location |
|-------------|----------------|
| `dot_vimrc` | `~/.vimrc` |
| `dot_tmux.conf` | `~/.tmux.conf` |
| `dot_config/fish/config.fish` | `~/.config/fish/config.fish` |
| `dot_config/git/config.tmpl` | `~/.config/git/config` |
| `run_once_*.sh.tmpl` | Executed once, not copied |

### Windows

| Source File | Target Location |
|-------------|----------------|
| `dot_config/powershell/profile.ps1` | `~/.config/powershell/profile.ps1` |
| `dot_config/powershell/aliases.ps1` | `~/.config/powershell/aliases.ps1` |
| `dot_config/git/config.tmpl` | `~/.config/git/config` |
| `AppData/.../settings.json` | `%LOCALAPPDATA%/.../settings.json` |
| `run_once_*.ps1.tmpl` | Executed once, not copied |

**Note**: Platform-specific files are filtered via `.chezmoiignore` (supports templates natively).

## 🎓 Learning Resources

- **Chezmoi Docs**: <https://www.chezmoi.io/>
- **Fish Shell Docs**: <https://fishshell.com/docs/current/>
- **Chezmoi Templates**: <https://www.chezmoi.io/reference/templates/>

---

💡 **Tip**: Use `.gitkeep` files to track empty directories in Git. Chezmoi will respect the directory structure.
