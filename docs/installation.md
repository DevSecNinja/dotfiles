# 🚀 Installation

## Linux / macOS

```bash
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply DevSecNinja
```

Or clone and install locally:

```bash
git clone https://github.com/DevSecNinja/dotfiles.git
cd dotfiles
./install.sh
```

## Windows (PowerShell)

**Option 1 — Directly from GitHub (PowerShell 5.1+ or PowerShell 7+):**

```powershell
# Using the official chezmoi installer (recommended)
(irm -useb https://get.chezmoi.io/ps1) | powershell -c -; chezmoi init --apply DevSecNinja
```

**Option 2 — Clone and install locally:**

```powershell
git clone https://github.com/DevSecNinja/dotfiles.git
cd dotfiles
.\install.ps1
```

## WSL (Windows Subsystem for Linux)

Use the Linux installation method inside your WSL distribution:

```bash
sh -c "$(curl -fsLS https://get.chezmoi.io)" -- init --apply DevSecNinja
```

The dotfiles automatically detect WSL and apply appropriate configurations.

## Development Container

This repository includes a complete [DevContainer](https://containers.dev/)
configuration for Visual Studio Code and GitHub Codespaces, providing a
fully configured development environment with:

- 🍺 Homebrew package manager
- 📦 Git LFS
- 💻 PowerShell with Pester
- 🐍 Python (latest)
- 🐙 GitHub CLI

Dotfiles are installed automatically via `postCreateCommand`, Fish is set
as the default shell, and VS Code extensions (GitHub Copilot, Pester) are
pre-installed. Prebuilt images are published at
`ghcr.io/devsecninja/dotfiles-devcontainer:latest`.

### Using the DevContainer

=== "VS Code"

    - Open this repository in VS Code.
    - Install the *Dev Containers* extension.
    - Click **Reopen in Container** when prompted, or run
      `Dev Containers: Reopen in Container` from the Command Palette.

=== "GitHub Codespaces"

    - Navigate to the repository on GitHub.
    - Click **Code → Codespaces → Create codespace on main**.
    - The devcontainer will build and configure automatically.

### Testing the DevContainer

```bash
.github/scripts/test-devcontainer.sh
```
