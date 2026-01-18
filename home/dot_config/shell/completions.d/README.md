# Shell Completions and Initializations

This directory contains shell completions and tool initializations for **Bash** and **Zsh**.

## 📂 Files

### Tool Initializations (Evals)

These files handle shell integration and environment setup:

- **homebrew.bash** / **homebrew.zsh** - Homebrew environment initialization
- **mise.bash** / **mise.zsh** - mise (rtx) shell activation and environment

### Completions

These files provide tab completion for commands:

- **chezmoi.bash** / **chezmoi.zsh** - Chezmoi command completion
- **docker.bash** / **docker.zsh** - Docker command completion
- **gh.bash** / **gh.zsh** - GitHub CLI command completion

## 🔄 How It Works

All files in this directory are automatically sourced by:

- **Bash**: `~/.config/shell/config.bash`
- **Zsh**: `~/.config/shell/config.zsh`

Files are loaded in alphabetical order. Each file checks if the tool is installed before attempting to load its completion or initialization.

## ✏️ Adding New Completions

To add a new completion or initialization:

1. Create `toolname.bash` and/or `toolname.zsh`
2. Check if the tool exists before loading:

```bash
# For Bash
if command -v toolname >/dev/null 2>&1; then
    eval "$(toolname completion bash)"
fi
```

```zsh
# For Zsh
if command -v toolname >/dev/null 2>&1; then
    eval "$(toolname completion zsh)"
fi
```

3. Save and reload your shell - the file will be automatically sourced

## 📚 Resources

- [Bash Completion Documentation](https://github.com/scop/bash-completion)
- [Zsh Completion System](https://zsh.sourceforge.io/Doc/Release/Completion-System.html)

---

**Managed by Chezmoi** - Edit via `chezmoi edit`, not directly!
