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

### Prerequisites & manual bootstrap steps

A brand-new Windows install needs a few one-time manual steps before (and
around) the automated installer. These are unavoidable bootstrapping steps —
the dotfiles can't configure the machine until the machine can fetch and run
the dotfiles.

1. **Install Git and chezmoi, then open a _new_ terminal.**

    ```powershell
    winget install Git.Git twpayne.chezmoi
    ```

    winget updates the `PATH` environment variable, but the change only applies
    to **newly started** shells. Close the current PowerShell window and open a
    fresh one before continuing, otherwise `git` and `chezmoi` are reported as
    "not recognized".

2. **Allow local scripts to run.** Windows PowerShell blocks scripts by
    default (`running scripts is disabled on this system`). Set a policy that
    permits local scripts:

    ```powershell
    Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
    ```

    !!! warning "Don't use `AllSigned`"
        `AllSigned` refuses to run `install.ps1` with *"a certificate chain
        processed, but terminated in a root certificate which is not trusted"*
        because these scripts are signed with a personal code-signing
        certificate whose root isn't in your trust store. Use `RemoteSigned`,
        or import the signing certificate first (see
        [`Import-SigningCert.ps1`](https://github.com/DevSecNinja/dotfiles/blob/main/home/dot_config/powershell/scripts/Import-SigningCert.ps1)).

3. **Clone over HTTPS the first time.** SSH access to GitHub depends on your
    SSH config and agent — both of which are provided *by* these dotfiles, so
    they don't exist yet on a fresh machine. Clone over HTTPS to break the
    chicken-and-egg:

    ```powershell
    mkdir ~\projects; cd ~\projects
    git clone https://github.com/DevSecNinja/dotfiles.git
    cd dotfiles
    ```

    To use SSH afterwards (e.g. with the 1Password SSH agent), install
    1Password and enable the agent, then switch the remote to SSH:

    ```powershell
    winget install AgileBits.1Password AgileBits.1Password.CLI
    # In the 1Password app: Settings -> Developer -> "Use the SSH agent"
    # and make sure your public key is added to https://github.com/settings/keys
    git remote set-url origin git@github.com:DevSecNinja/dotfiles.git
    ```

4. **Run the installer.**

    ```powershell
    .\install.ps1
    ```

!!! note "PowerShell 7 (`pwsh`) is installed for you"
    Several steps (PowerShell modules, Nerd Fonts) require PowerShell 7. The
    package-install step installs it via winget **before** the module step, and
    the module script refreshes `PATH` so the freshly installed `pwsh` is
    found within the same run. If you ever run the pieces by hand, install it
    first with `winget install Microsoft.PowerShell` and open a new shell.

!!! tip "WSL may need elevation and a reboot"
    The WSL step runs `wsl --install -d Debian`, which requires administrator
    privileges. On some machines the first run reports *"WSL installation
    appears to be corrupted"* and only updates the WSL engine instead of
    installing the distro — this needs a reboot to finish:

    ```powershell
    wsl --update       # ensure the WSL engine is current
    # reboot Windows
    wsl --install -d Debian   # now installs Debian and prompts for a UNIX user
    ```

    The installer detects this case: if Debian isn't registered after the
    attempt it prints reboot guidance and exits non-zero, so re-running
    `.\install.ps1` (or `chezmoi apply`) after the reboot retries automatically.

### Quick install

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
