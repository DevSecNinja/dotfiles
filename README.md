# 🐠 Dotfiles

Modern dotfiles repository managed with [Chezmoi](https://chezmoi.io/), featuring [Fish shell](https://fishshell.com/) configuration and automated setup scripts.

## ✨ Features

- **Fish Shell**: Modern shell with sensible defaults and useful aliases
- **Git Configuration**: Pre-configured with templates for user info
- **Vim & Tmux**: Basic but functional configurations
- **Automated Setup**: Scripts to install tools and create directories
- **Cross-Platform**: Works on Linux (Ubuntu/Debian) and macOS

## 📁 Structure

```
dotfiles-new/
├── dot_config/                    # XDG config directory (~/.config/)
│   ├── fish/                      # Fish shell configuration
│   │   ├── config.fish           # Main Fish config
│   │   ├── conf.d/               # Configuration snippets (auto-loaded)
│   │   │   └── aliases.fish      # Command aliases
│   │   ├── functions/            # Custom Fish functions
│   │   │   └── fish_greeting.fish
│   │   └── completions/          # Custom completions
│   ├── git/                       # Git configuration
│   │   ├── config.tmpl           # Git config with templating
│   │   └── ignore                # Global gitignore
│   └── shell/                     # Other shell configs (bash, zsh)
├── dot_vimrc                      # Vim configuration
├── dot_tmux.conf                  # Tmux configuration
├── run_once_before_00-setup.sh.tmpl      # Initial directory setup
├── run_once_install-fish.sh.tmpl         # Fish shell installation
├── run_once_install-packages.sh.tmpl     # Development tools
├── .chezmoi.yaml.tmpl            # Chezmoi configuration
├── .chezmoiignore                # Files to exclude
└── install.sh                     # Installation script
```

## 🚀 Quick Start

### Install on a new machine

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply DevSecNinja/dotfiles-new
```

Or clone and install locally:

```bash
git clone https://github.com/DevSecNinja/dotfiles-new.git
cd dotfiles-new
./install.sh
```

### What happens during installation

1. Installs Chezmoi (if not present)
2. Prompts for your name and email (for Git config)
3. Runs initial setup scripts:
   - Creates necessary directories (~/.vim/undo, ~/bin, ~/projects)
   - Installs Fish shell (if not present)
   - Installs common development tools
4. Applies all dotfiles to your home directory

## 🔧 Customization

### Personal Information

On first run, Chezmoi will prompt for:
- **Name**: Used in Git commits
- **Email**: Used in Git commits

To re-enter this information:
```bash
chezmoi init --data=false
```

### Adding Your Own Dotfiles

1. **Add an existing file**:
   ```bash
   chezmoi add ~/.bashrc
   ```

2. **Edit a managed file**:
   ```bash
   chezmoi edit ~/.config/fish/config.fish
   ```

3. **Apply changes**:
   ```bash
   chezmoi apply
   ```

### Fish Shell Customization

- **Aliases**: Edit [dot_config/fish/conf.d/aliases.fish](dot_config/fish/conf.d/aliases.fish)
- **Functions**: Add files to [dot_config/fish/functions/](dot_config/fish/functions/)
- **Config snippets**: Add files to [dot_config/fish/conf.d/](dot_config/fish/conf.d/)

### Adding Scripts

Create scripts in the root directory:
- `run_once_*.sh`: Runs once after installation
- `run_onchange_*.sh`: Runs when file content changes
- `run_*.sh`: Runs on every apply

Use `.tmpl` extension to use Chezmoi templating.

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

- **Set Fish as default shell**: `chsh -s $(which fish)`
- **Preview changes**: Always run `chezmoi diff` before `chezmoi apply`
- **Templates**: Use `.tmpl` extension to access Chezmoi variables like `{{ .name }}`
- **Platform-specific config**: Use Chezmoi's conditional templating:
  ```
  {{- if eq .chezmoi.os "darwin" }}
  # macOS-specific config
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
