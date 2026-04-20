# 📁 Structure

Quick reference for the dotfiles repository structure and Chezmoi naming
conventions. See also the canonical
[`STRUCTURE.md`](https://github.com/DevSecNinja/dotfiles/blob/main/STRUCTURE.md)
in the repository.

## Chezmoi Naming Conventions

Chezmoi uses special prefixes in filenames to determine how files are
managed:

| Prefix | Target | Example |
| --- | --- | --- |
| `dot_` | `.` (hidden file) | `dot_vimrc` → `~/.vimrc` |
| `private_` | File with `0600` permissions | `private_ssh_config` |
| `executable_` | File with `+x` permissions | `executable_script.sh` |
| `run_once_` | Script that runs once | `run_once_install.sh` |
| `run_onchange_` | Script that runs on change | `run_onchange_update.sh` |
| `run_` | Script that runs every apply | `run_backup.sh` |
| `.tmpl` | Template file | `config.tmpl` (Chezmoi templates) |

## Repository Layout

```
dotfiles/
├── .devcontainer/               # DevContainer configuration
├── .github/
│   ├── workflows/               # CI/CD pipelines
│   └── scripts/                 # Helper scripts for CI
├── docs/                        # MkDocs documentation source
├── home/                        # Chezmoi source directory
│   ├── dot_config/              # XDG config directory (~/.config/)
│   │   ├── fish/                # Fish shell (Linux/macOS)
│   │   ├── powershell/          # PowerShell (Windows)
│   │   ├── git/                 # Git configuration
│   │   └── shell/               # Other shell configs (bash, zsh)
│   ├── AppData/                 # Windows-specific application data
│   ├── Documents/               # Windows PowerShell profiles
│   ├── dot_bashrc               # Bash configuration
│   ├── dot_zshrc                # Zsh configuration
│   ├── dot_vimrc                # Vim configuration
│   └── dot_tmux.conf            # Tmux configuration
├── tests/                       # Bats and Pester tests
│   ├── bash/                    # Bats validation tests
│   └── powershell/              # Pester tests
├── install.sh                   # Unix installation wrapper
├── install.ps1                  # Windows installation wrapper
├── mkdocs.yml                   # MkDocs configuration
└── requirements.txt             # Python dependencies
```

## Chezmoi Source Directory

The repository uses a `.chezmoiroot` file that points Chezmoi at the
`home/` subdirectory, so only files inside `home/` are treated as
dotfiles source files. Everything at the repo root (this documentation,
workflows, tests, etc.) is purely project tooling and is not applied to
the user's home directory.
