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

## Updating everything at once

`chezmoi update && chezmoi init && chezmoi apply` is the usual dance after a
change lands. The `chezmoi-up` helper does it for you, in every shell:

| Shell | Command | Alias |
| --- | --- | --- |
| Bash / Zsh | `chezmoi-up` | `czu` |
| fish | `chezmoi_up` | `czu` |
| PowerShell | `Update-Chezmoi` | `chezmoi-up`, `chezmoi_up`, `czu` |

It runs three steps and **stops at the first failure**, so a failed pull can
never be followed by an apply of half-updated source:

1. `chezmoi update --apply=false` — pull the source repo only. Applying here
   would use the *old* config, which breaks when the pull introduces a
   template variable your current config does not have yet.
2. `chezmoi init` — **only when the config template actually changed.** It
   compares the SHA256 chezmoi recorded in its `configState` bucket (the same
   data behind its *"config file template has changed"* warning) with the
   template on disk. When it skips, it says so; when the state cannot be read
   it re-inits anyway, since a redundant init is harmless and a skipped one is
   not.
3. `chezmoi apply` — apply with the freshly generated config.

Pass `--force-init` (`-ForceInit` in PowerShell) to regenerate the config even
when the template is unchanged.

```console
$ czu
==> Pulling the source repository
==> Config template unchanged, skipping chezmoi init
==> Applying
✓ Dotfiles are up to date
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
