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

| Shell      | Command          | Alias                             |
| ---------- | ---------------- | --------------------------------- |
| Bash / Zsh | `chezmoi-up`     | `czu`                             |
| fish       | `chezmoi_up`     | `czu`                             |
| PowerShell | `Update-Chezmoi` | `chezmoi-up`, `chezmoi_up`, `czu` |

Before those steps it checks which branch the source repository is on, then
runs three steps and **stops at the first failure**, so a failed pull can never
be followed by an apply of half-updated source:

0. **Branch guard** — `chezmoi update` pulls whichever branch is checked out,
   so a feature branch you forgot about would be applied to the machine
   silently. When the source repo is not on its default branch you get a
   warning and an offer to switch and pull. See
   [Branch guard](#branch-guard) below.
1. `chezmoi update --apply=false` — pull the source repo only. Applying here
   would use the _old_ config, which breaks when the pull introduces a
   template variable your current config does not have yet.
2. `chezmoi init` — **only when the config template actually changed.** It
   compares the SHA256 chezmoi recorded in its `configState` bucket (the same
   data behind its _"config file template has changed"_ warning) with the
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

### Branch guard

When the source repository is on another branch, `czu` says so and offers to
put it back:

```console
$ czu
! Source repository is on 'feat/new-aliases', not 'main'.
! chezmoi update pulls whichever branch is checked out.
Switch to 'main' and pull? [y/N] y
==> Switching to 'main'
==> Pulling the source repository
```

Declining is fine — working on a branch is a legitimate way to test dotfiles
changes, so the run continues either way. The guard never switches a branch
with uncommitted changes; it tells you to commit or stash first and carries on
where you are. Pulls use `--ff-only`, so it will never create a merge commit in
your dotfiles behind your back.

Non-interactive shells answer "no" automatically, so scripts and CI are warned
but never blocked.

| Variable                         | Effect                                                            |
| -------------------------------- | ----------------------------------------------------------------- |
| `CHEZMOI_UP_BRANCH`              | Expected branch (default: the repo's default branch, else `main`) |
| `CHEZMOI_UP_SKIP_BRANCH_CHECK=1` | Skip the guard entirely                                           |
| `CHEZMOI_UP_ASSUME_YES=1`        | Switch without asking                                             |
| `CHEZMOI_UP_ASSUME_NO=1`         | Never switch, even on a TTY                                       |

## System info at shell startup

Both shells print a `fastfetch` banner when you open an interactive session:
fish via `fish_greeting`, PowerShell via the profile. fastfetch is installed by
the dotfiles (apt/brew on Unix, `Fastfetch-cli.Fastfetch` via winget on
Windows), and when it is missing the banner is simply skipped — a light install
stays quiet.

The PowerShell side runs it behind a timeout, because a fetch tool can hang on a
hardware probe (the GPU query on Snapdragon X, for instance) and would otherwise
freeze the whole profile load while ignoring Ctrl+C. If that happens you get a
notice instead of a hung shell:

```console
(fastfetch timed out after 5.0s; skipping)
```

Set `FASTFETCH_TIMEOUT_MS` to tune the limit (default 5000).

## Windows PATH

On Windows, the setup adds `%OneDrive%\Portable Programs` to the user-scope
PATH when the folder exists, so it survives reboots and is available to GUI
apps. The PowerShell profile also adds the same folder to the current session
when OneDrive is configured.

## Learn More

- [Chezmoi documentation](https://www.chezmoi.io/user-guide/command-overview/)
- [Fish shell documentation](https://fishshell.com/docs/current/)
- [Chezmoi template reference](https://www.chezmoi.io/reference/templates/)
