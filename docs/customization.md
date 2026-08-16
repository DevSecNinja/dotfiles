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

## Projects folder and Dev Drive

Interactive shells `cd` into your projects folder at startup (unless the shell
was launched from VS Code, or you're already somewhere under a path containing
`projects`).

On Windows the folder is resolved by `Get-ProjectsPath` in the order below, so a
[Dev Drive](https://learn.microsoft.com/en-us/windows/dev-drive/) — a ReFS
volume tuned for developer workloads — wins over the user profile:

1. `$env:PROJECTS_PATH`, when set.
2. `<Dev Drive>\projects`, when a Dev Drive has one (for example `D:\projects`).
3. `%USERPROFILE%\projects`.

`run_once_before_00-setup.ps1` creates the folder on the Dev Drive when one is
present, so a fresh machine with a Dev Drive gets `D:\projects` instead of
`%USERPROFILE%\projects`.

!!! note "How the Dev Drive is detected"
    `fsutil devdrv query` is the authoritative check, but it needs an elevated
    shell — unusable from a profile. Fixed, ready ReFS volumes are used as the
    heuristic instead. If that guesses wrong (a plain ReFS data volume, or
    several Dev Drives), pin the right one with `$env:DEV_DRIVE`, or skip
    detection entirely with `$env:PROJECTS_PATH`.

The Linux/macOS shell configs (`fish`, `bash`, `zsh`) always use
`$HOME/projects`; Dev Drive is a Windows-only feature.

## Windows PATH

On Windows, the setup adds `%OneDrive%\Portable Programs` to the user-scope
PATH when the folder exists, so it survives reboots and is available to GUI
apps. The PowerShell profile also adds the same folder to the current session
when OneDrive is configured.

## Windows personalization

On Windows, `run_onchange_40-set-current-user-personalization.ps1` applies the
opinionated settings below to the invoking user's profile without elevation:

| Preference | Applied value | Evidence/source | Normal alternative or reversal |
| ---------- | ------------- | --------------- | ------------------------------ |
| App and Windows theme | Dark (`AppsUseLightTheme=0`, `SystemUsesLightTheme=0`) | Grade 3: related [Microsoft theme guidance](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/apply-windows-themes), but the registry mappings are community-documented | Choose Light in Settings > Personalization > Colors, delete the values, or set both to `1` |
| Lock-screen Spotlight overlays | Off (`RotatingLockScreenOverlayEnabled=0`) | Grade 3: [Microsoft Community mapping](https://learn.microsoft.com/en-us/answers/questions/1326668/how-to-disable-windows-spotlight-via-registry) | Re-enable lock-screen tips, delete the value, or set it to `1` |
| Task View button | Hidden (`ShowTaskViewButton=0`) | Grade 1: [Windows 11 settings reference](https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11) | Enable Task view in taskbar settings, delete the value, or set it to `1` |
| Taskbar search | Hidden (`SearchboxTaskbarMode=0`) | Grade 2: modes correspond to the [Windows 11 settings reference](https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11), but this value is not a documented policy | Select Search box in taskbar settings, delete the value, or set it to `3` |
| File-name extensions | Shown (`HideFileExt=0`) | Grade 3: exact registry mapping is unverified | Clear File Explorer's File name extensions option, delete the value, or set it to `1` |
| Hidden files and folders | Shown (`Hidden=1`) | Grade 3: exact registry mapping is unverified | Clear File Explorer's Hidden items option, delete the value, or set it to `2` |
| Desktop background | Windows Spotlight (`BackgroundType=3`) | Grade 3: Spotlight is documented in the [settings reference](https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11), but the registry mirror is best-effort | Choose another background, delete the value, or set image mode (`1`) |
| Regional format | Dutch (Netherlands), `nl-NL` | Grade 1: [`Set-Culture`](https://learn.microsoft.com/en-us/powershell/module/international/set-culture) | Select another regional format or run `Set-Culture -CultureInfo en-US` |
| Home location | Netherlands, GeoID `176` | Grade 1: [`Set-WinHomeLocation`](https://learn.microsoft.com/en-us/powershell/module/international/set-winhomelocation) | Select another country or run `Set-WinHomeLocation -GeoId 244` for the US |
| Languages and keyboards | `en-US`, then `nl-NL`; both US-International (`00020409`) | Grade 1: [`Set-WinUserLanguageList`](https://learn.microsoft.com/en-us/powershell/module/international/set-winuserlanguagelist) | Edit Language & region settings or run `Set-WinUserLanguageList en-US -Force` |
| Number and CSV separators | Decimal `.`, thousands `,`, list `,` | Grade 2: [Windows locale constants](https://learn.microsoft.com/en-us/windows/win32/intl/locale-custom-constants) document the fields; registry behavior is vendor-observed | Restore Dutch defaults: decimal `,`, thousands `.`, list `;` |

The script checks exact desired state before every change and preserves
unrelated registry values. It intentionally replaces the input-language list
with the two entries above. Number separators are applied after `Set-Culture`,
which rewrites `HKCU\Control Panel\International` and otherwise restores the
Dutch defaults. The decimal symbol is restored first because Windows will not
allow the decimal and list separators to match. All registry writes are limited
to `HKEY_CURRENT_USER`.

The executable settings table in the script carries the same descriptions,
rationales, citations, evidence grades, and reversal guidance next to each
desired value. Tests require those fields for every applied registry setting so
this audit context cannot silently drift away from the implementation.

## Windows Night Light

On Windows, `run_onchange_41-set-night-light.ps1` enables Night Light on a
sunset-to-sunrise schedule at strength `50`. Pass `-Strength` (0-100) to the
script to use a different intensity.

Night Light has no supported configuration API. Windows persists it as two
`REG_BINARY` CloudStore values under `HKEY_CURRENT_USER`:

| Value | Contents |
| ----- | -------- |
| `...\default$windows.data.bluelightreduction.settings\windows.data.bluelightreduction.settings` | Schedule mode, colour temperature, schedule times, cached sunset/sunrise times |
| `...\default$windows.data.bluelightreduction.bluelightreductionstate\windows.data.bluelightreduction.bluelightreductionstate` | Whether Night Light is currently on |

Both are [Microsoft Bond CompactBinary v1][bond] payloads inside a CloudStore
envelope. The script implements just enough of that codec to decode the
existing blobs, change the fields it owns, and re-encode them, so unrelated
data (notably the sunset/sunrise times Windows computes from your location) is
preserved byte for byte. Evidence grade 3: the format is
[reverse-engineered and community-documented][fmt], not a Microsoft contract.

Schedule mode is encoded by field presence rather than a value: field `0`
(`schedule_enabled`) is set to `true` and field `10` (`set_hours_mode`) is
omitted, which is how Windows represents "Sunset to sunrise". Strength maps
linearly onto colour temperature, where `0` is 6500 K (no effect) and `100` is
1200 K, so strength `50` stores 3850 K.

The state value is derived rather than forced: the script turns Night Light on
only when the current time falls inside the cached sunset-to-sunrise window,
matching what Windows itself would have done. All writes stay in
`HKEY_CURRENT_USER` and the script is idempotent — a second run reports zero
changes.

On a machine where Night Light has never been used the two values do not exist
yet. Rather than failing the apply, the script seeds them. Sunset and sunrise
are deliberately left unset in that case: Windows derives them from the machine
location, and seeding them would only risk storing wrong times. Until Windows
computes them, the solar window is unknown and Night Light is left off.

Reversal: open Settings > System > Display > Night light and turn it off, or
delete the two registry values above and sign out.

[bond]: https://github.com/microsoft/bond
[fmt]: https://github.com/kvnxiao/win-nightlight-cli/blob/main/docs/nightlight-registry-format.md

## Learn More

- [Chezmoi documentation](https://www.chezmoi.io/user-guide/command-overview/)
- [Fish shell documentation](https://fishshell.com/docs/current/)
- [Chezmoi template reference](https://www.chezmoi.io/reference/templates/)
