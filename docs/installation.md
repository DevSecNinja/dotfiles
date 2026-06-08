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

Prebuilt images include package release notes at
`/usr/local/share/dotfiles-devcontainer/release-notes.md` and a full package
inventory at `/usr/local/share/dotfiles-devcontainer/manifest.md`. The exported
release notes (uploaded as a workflow artifact and shown in the build job
summary) also include the compressed image storage size per platform under an
`## Image size` section.

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

### Using the prebuilt image in another project

The prebuilt image (`ghcr.io/devsecninja/dotfiles-devcontainer:latest`) can be
reused by any other repository. Point its `devcontainer.json` at the image and
add a `postCreateCommand` that trusts and installs the consuming project's own
mise tools:

```json
{
  "image": "ghcr.io/devsecninja/dotfiles-devcontainer:latest",
  // Trust this workspace's mise config (untrusted by default in a fresh
  // container) and install its pinned tools so the project's mise.toml /
  // .tool-versions take effect.
  "postCreateCommand": "mise trust --all --yes && mise install",
  "remoteUser": "vscode"
}
```

`mise trust --all --yes` trusts every `mise.toml` / `.mise.toml` /
`.tool-versions` in the workspace non-interactively — mise ignores untrusted
config files, so without this step `mise install` would skip the project's
pinned tools. The baked image already exposes `mise` on `PATH`, so the hook
works even though it runs in a bare shell before the VS Code server attaches.

### Testing the DevContainer

```bash
.github/scripts/test-devcontainer.sh
```
