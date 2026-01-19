# Shell Completions and Initializations

This directory contains shell completions and tool initializations for **Bash** and **Zsh**.

## 📂 Files

### Homebrew Integration (Priority)

- **00-homebrew.bash** / **00-homebrew.zsh** - Homebrew environment and completion setup (loaded first)
  - **Bash**: Sources completions from `$(brew --prefix)/etc/bash_completion.d/`
  - **Zsh**: Adds `$(brew --prefix)/share/zsh/site-functions` to `FPATH`
  - See [Homebrew Shell Completion docs](https://docs.brew.sh/Shell-Completion) for details

### Tool Initializations

These files handle shell integration and environment setup:

- **mise.bash** / **mise.zsh** - mise (rtx) shell activation (includes its own completions)

### Manual Completions

These files provide completions for tools not installed via Homebrew or when Homebrew doesn't provide them:

- **chezmoi.bash** / **chezmoi.zsh** - Fallback for non-Homebrew chezmoi installations
- **docker.bash** / **docker.zsh** - Docker completions (not provided by Homebrew)
- **gh.bash** / **gh.zsh** - Fallback for non-Homebrew gh installations

**Note**: When tools are installed via Homebrew (gh, chezmoi, git, etc.), their completions are automatically provided by Homebrew and don't need dynamic generation.

## 🔄 How It Works

All files in this directory are automatically sourced by:

- **Bash**: `~/.config/shell/config.bash`
- **Zsh**: `~/.config/shell/config.zsh`

Files are loaded in alphabetical order. Homebrew is loaded first (prefix `00-`) to ensure:

1. PATH is properly set up
2. Homebrew-provided completions are available before fallback completions load

## ✏️ Adding New Completions

### For Homebrew-installed tools

**No action needed!** Homebrew automatically provides completions for most formulae.

Check if completions exist:

```bash
# Bash
ls $(brew --prefix)/etc/bash_completion.d/

# Zsh
ls $(brew --prefix)/share/zsh/site-functions/
```

### For non-Homebrew tools or tools without Homebrew completions

To add a completion for a tool not provided by Homebrew:

1. Create `toolname.bash` and/or `toolname.zsh`
2. Check if the tool exists and if Homebrew completion isn't already loaded:

```bash
# For Bash
if command -v toolname >/dev/null 2>&1 && ! type _toolname_completion >/dev/null 2>&1; then
    eval "$(toolname completion bash)"
fi
```

```zsh
# For Zsh
if command -v toolname >/dev/null 2>&1 && [[ ! -f "$(brew --prefix 2>/dev/null)/share/zsh/site-functions/_toolname" ]]; then
    eval "$(toolname completion zsh)"
fi
```

Save and reload your shell - the file will be automatically sourced.

## 🔍 Troubleshooting

**Completions not working?**

1. Verify Homebrew is initialized: `echo $HOMEBREW_PREFIX`
2. Check if tool provides Homebrew completions (see above)
3. For bash, ensure completion files are being sourced
4. For zsh, verify `compinit` is called after FPATH is set (see `~/.zshrc`)

## 📚 Resources

- [Homebrew Shell Completion Documentation](https://docs.brew.sh/Shell-Completion)
- [Bash Completion Documentation](https://github.com/scop/bash-completion)
- [Zsh Completion System](https://zsh.sourceforge.io/Doc/Release/Completion-System.html)

---

**Managed by Chezmoi** - Edit via `chezmoi edit`, not directly!
