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

On Windows, Microsoft Surface Laptop models always have the hardware power
button set to **Do nothing** for both AC and battery power, preventing an
accidental press next to Delete from suspending or shutting down the computer.

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

The module list lives in `~/.config/fastfetch/config.jsonc`. One deviation from
the defaults is worth knowing about: the `Host` line is formatted as `{name}`
only, because fastfetch otherwise appends the product version — on OEM hardware
that is a long firmware/SKU string such as `124I:00108T:000M:...` that pushes the
useful part off the line.

### Extra status lines

The banner carries a few extra lines that only appear when they have something
to say — fastfetch hides a module entirely when it prints nothing, so a healthy
machine stays clean:

```console
Updates: 📦 6 update(s) available (winget) · checked 5m ago
Reboot: 🔄 Reboot required — linux-image-generic
Ansible: ✅ ansible-pull OK · ran 5m ago · next in 25m
```

`Updates` works everywhere: apt/dnf/pacman/zypper/apk on Linux, brew on macOS,
winget on Windows. `Reboot` and `Ansible` are Linux-only.

Counting updates is far too slow to do while you wait for a prompt (a winget
query takes tens of seconds), so nothing is ever computed on the login path.
Instead the numbers come from a small cache that is refreshed in the background:
the banner shows the previous result instantly while a fresh one is computed for
the next login.

| Platform    | Cache                                  | Filled by                                                                |
| ----------- | -------------------------------------- | ------------------------------------------------------------------------ |
| Linux/macOS | `~/.cache/fastfetch-status/`           | `~/.config/fastfetch/status.sh`, which self-spawns its own refresh        |
| Windows     | `%LOCALAPPDATA%\fastfetch-status\`     | `~/.config/fastfetch/status.ps1`, spawned detached by the PowerShell profile |

On Windows fastfetch reads the cache with `cmd /c type` rather than starting
PowerShell, which keeps the line free (a few milliseconds).

The `checked 5m ago` part is deliberately not stored in the cache — that would
freeze it until the next hourly refresh. Each section is kept twice: a source
file holding the moment as an absolute timestamp, and the rendered line the
banner shows. Expanding one into the other is pure arithmetic and happens on
every shell start, so the age is always correct when you read it.

Refresh by hand — useful right after installing updates:

```bash
~/.config/fastfetch/status.sh refresh        # Linux/macOS
```

```powershell
~/.config/fastfetch/status.ps1 refresh       # Windows
```

| Variable                     | Effect                                                       |
| ---------------------------- | ------------------------------------------------------------ |
| `FASTFETCH_STATUS_TTL`       | Cache lifetime in seconds (default 3600)                     |
| `FASTFETCH_STATUS_DISABLE=1` | Print no status lines at all                                 |
| `FASTFETCH_STATUS_CACHE_DIR` | Override the cache directory (Windows; testing)              |
| `ANSIBLE_PULL_WORKDIR`       | ansible-pull checkout (default `/var/lib/ansible/local`)      |

### A quiet PowerShell startup

fastfetch already reports the shell version and everything else worth knowing,
so the noise around it is turned off rather than printed twice:

- `PowerShell 7.6.4` and `Loading personal and system profiles took 1513ms.` are
  printed by pwsh itself, before and after the profile runs. They cannot be
  suppressed from `profile.ps1`, so the Windows Terminal PowerShell profile is
  launched as `pwsh.exe -NoLogo -NoProfileLoadTime` instead (set by
  `run_onchange_set-windows-terminal-powershell-args.ps1`).
- The dotfiles' own `[OK] PowerShell Profile Loaded` and `Type 'aliases'` lines
  are skipped whenever the fastfetch banner rendered. On a light install without
  fastfetch they stay, so an interactive shell still confirms the profile loaded.

## Windows PATH

On Windows, the setup adds `%OneDrive%\Portable Programs` to the user-scope
PATH when the folder exists, so it survives reboots and is available to GUI
apps. The PowerShell profile also adds the same folder to the current session
when OneDrive is configured.

## Windows personalization

On Windows, `run_onchange_40-set-current-user-personalization.ps1` applies the
opinionated settings below to the invoking user's profile without elevation:

- dark app and system themes, a hidden taskbar search box and Task View button,
  visible file extensions and hidden items, reduced lock-screen Spotlight
  overlays, and Windows Spotlight for the desktop background;
- Dutch (Netherlands) regional formatting and home location while retaining
  English (`en-US`) as the first input language;
- `en-US` followed by `nl-NL`, both using the United States-International
  keyboard layout; and
- US decimal, thousands, and list separators (`.`, `,`, `,`) so comma-delimited
  CSV files work as expected.

The script checks exact desired state before every change and preserves
unrelated registry values. It intentionally replaces the input-language list
with the two entries above. Number separators are applied after `Set-Culture`,
which otherwise restores the Dutch defaults. All registry writes are limited to
`HKEY_CURRENT_USER`.

## Learn More

- [Chezmoi documentation](https://www.chezmoi.io/user-guide/command-overview/)
- [Fish shell documentation](https://fishshell.com/docs/current/)
- [Chezmoi template reference](https://www.chezmoi.io/reference/templates/)
