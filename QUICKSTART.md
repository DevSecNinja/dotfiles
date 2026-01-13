# 🚀 Quick Start Guide

Get up and running with your dotfiles in minutes!

## One-Line Install

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply DevSecNinja/dotfiles-new
```

This will:
1. ✅ Install Chezmoi
2. ✅ Download your dotfiles
3. ✅ Prompt for your name and email
4. ✅ Install Fish shell (if needed)
5. ✅ Install common dev tools
6. ✅ Apply all configurations

## What You Get

- 🐠 **Fish Shell** with useful aliases and functions
- 📝 **Git config** with your name and email
- ✏️ **Vim** with sensible defaults
- 🖥️ **Tmux** configuration
- 🔧 **Auto-setup scripts** for tools

## First Steps After Install

### 1. Switch to Fish Shell

```bash
chsh -s $(which fish)
```

Log out and back in for the change to take effect.

### 2. Explore Your New Shell

```bash
# Try some aliases
l          # List files (ls -lah)
gs         # Git status
cz         # Chezmoi shortcut

# See all available aliases
alias
```

### 3. Customize Your Config

```bash
# Edit Fish configuration
chezmoi edit ~/.config/fish/config.fish

# Add a new alias
chezmoi edit ~/.config/fish/conf.d/aliases.fish

# Preview changes before applying
chezmoi diff

# Apply your changes
chezmoi apply
```

## Common Tasks

### Update Your Dotfiles

```bash
cd ~/.local/share/chezmoi
git pull
chezmoi apply
```

### Add a New Dotfile

```bash
# Add an existing file
chezmoi add ~/.bashrc

# Or create a new one
chezmoi edit ~/.newconfig
```

### Change Your Git Info

```bash
chezmoi init --data=false
```

## Troubleshooting

### Fish Not Installed?
```bash
# Run the install script manually
~/.local/bin/chezmoi execute-template < ~/.local/share/chezmoi/run_once_install-fish.sh.tmpl | bash
```

### Config Not Applied?
```bash
# Re-apply all files
chezmoi apply -v
```

### See What's Managed
```bash
chezmoi managed
```

## Next Steps

- 📖 Read the full [README.md](README.md)
- 📁 Understand the [STRUCTURE.md](STRUCTURE.md)
- 🤝 Check [CONTRIBUTING.md](CONTRIBUTING.md) to customize

## Getting Help

```bash
# Chezmoi help
chezmoi help

# Fish help
fish --help
man fish

# Specific command help
chezmoi help apply
```

---

**Happy hacking! 🚀**
