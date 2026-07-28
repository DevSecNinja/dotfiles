# 🔧 Customization

## Personal Information

On first run, Chezmoi will prompt for:

- **Name** — Used in Git commits.
- **Email** — Used in Git commits.

To re-enter this information:

```bash
chezmoi init --data=false
```

## Installation Modes

The repository supports two installation modes:

- **Light mode** (servers, CI, codespaces) — Essential tools only.
- **Full mode** (dev servers, workstations) — Full development tooling
  including Task and mise.

The mode is auto-detected based on:

- Hostname patterns (`SVL*DEV*` = full, `SVL*` = light).
- Environment (Codespaces, devcontainer, CI = light).
- Default = full mode.

To change modes:

```bash
chezmoi init --data=false
```

## Common Commands

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

## Windows PATH

On Windows, the setup adds `%OneDrive%\Portable Programs` to the user-scope
PATH when the folder exists, so it survives reboots and is available to GUI
apps. The PowerShell profile also adds the same folder to the current session
when OneDrive is configured.

## Learn More

- [Chezmoi documentation](https://www.chezmoi.io/user-guide/command-overview/)
- [Fish shell documentation](https://fishshell.com/docs/current/)
- [Chezmoi template reference](https://www.chezmoi.io/reference/templates/)
