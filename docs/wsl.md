# 🪟 WSL

A WSL distro is a Linux userland without the pieces a desktop Linux takes for
granted: no local SSH agent holding your keys, and no graphical browser. This
repo wires up both, guarded so nothing leaks into a native Linux or macOS
session.

## SSH keys live in 1Password

In WSL your SSH private keys are not on the Linux side at all — they live in
1Password on the Windows host. Rather than forwarding an _agent socket_, the
[1Password WSL integration][opwsl] forwards the whole SSH request to the
Windows OpenSSH client (`ssh.exe`), which talks to the 1Password SSH agent and
raises the approval prompt on Windows.

### What is configured automatically

| Concern                       | How                                     | Where                                                                          |
| ----------------------------- | --------------------------------------- | ------------------------------------------------------------------------------ |
| Git over SSH                  | `core.sshCommand = ssh.exe`             | `dot_config/git/config.tmpl`                                                   |
| Interactive `ssh` / `ssh-add` | aliased to `ssh.exe` / `ssh-add.exe`    | `dot_config/shell/functions/wsl-ssh.sh`, `dot_config/fish/conf.d/wsl-ssh.fish` |
| Commit signing                | `gpg.ssh.program = op-ssh-sign-wsl.exe` | `dot_config/git/config.tmpl` (see [git-signing.md](git-signing.md))            |

The aliases are guarded on `WSL_DISTRO_NAME` **and** on `ssh.exe` being
reachable, so they never leak into a native Linux or macOS session and stay
inert if [WSL interop][interop] is disabled.

## Prerequisites

1. 1Password for Windows installed and signed in **on the Windows host**.
2. The [1Password SSH agent enabled][opagent] there.
3. Your SSH key stored in 1Password.

Verify the agent is reachable from inside WSL:

```bash
ssh-add.exe -l
```

You should see the same keys as on Windows. If you get `command not found`,
either use the full path `/mnt/c/Windows/System32/OpenSSH/ssh-add.exe` or check
that `[interop] enabled = true` in your WSL config.

## Commit signing

Signing in WSL runs through `op-ssh-sign-wsl.exe` on the Windows host, driven
by the `gitSigningKey` chezmoi variable. The setup is shared with the other
platforms, so it lives in [git-signing.md](git-signing.md) — use the
**Configure for Windows Subsystem for Linux (WSL)** option when copying the
snippet out of the 1Password app.

!!! note

    `useYubiKey = true` takes precedence: that flow signs with a FIDO2 key from
    `~/.ssh/id_*_sk*.pub` and ignores `gitSigningKey`. See
    [yubikey.md](yubikey.md).

## SSH config lives on Windows

Because the request is executed by `ssh.exe`, host aliases and options must be
in the **Windows** `%USERPROFILE%\.ssh\config`, not the WSL one.

## Authorization model

Approving a key authorizes the current WSL session only. A new session or tab
prompts again — the same [authorization model][opauth] 1Password uses
everywhere else.

## Opening links in a browser

A WSL distro has no browser of its own, and no `xdg-open`. Anything that opens
one — `gh auth login`, OAuth flows, `npm docs` — looks for `xdg-open` or
`$BROWSER`, and when neither points anywhere useful it falls back to whatever
terminal browser happens to be installed. Completing an OAuth flow in `lynx` is
not a good time.

`~/.local/bin/wsl-browser` hands the URL to Windows via `powershell.exe
Start-Process`, which opens it in the real default browser. `BROWSER` is
pointed at it, which fixes every tool at once instead of configuring them one
at a time.

| Concern       | How                             | Where                                                                                  |
| ------------- | ------------------------------- | -------------------------------------------------------------------------------------- |
| Opening a URL | `powershell.exe Start-Process`  | `dot_local/bin/executable_wsl-browser`                                                 |
| `$BROWSER`    | exported when running under WSL | `dot_config/shell/functions/wsl-browser.sh`, `dot_config/fish/conf.d/wsl-browser.fish` |

Guarded on `WSL_DISTRO_NAME` **and** on `powershell.exe` being reachable, so it
stays inert on a native Linux session or when [interop][interop] is disabled.

Two deliberate choices in that script:

- **It only accepts `http(s)` URLs or files that exist.** `Start-Process` is
  Windows' general "run this" verb, not a browser — handed `calc.exe` or a path
  to an executable, it would _run_ it. Since `$BROWSER` is invoked by other
  programs, anything else is refused rather than quietly launched.
- **The URL is passed through `WSLENV`, not interpolated** into the PowerShell
  command string, so a URL containing quotes or semicolons is always data and
  never code.

### Why not wslu?

[wslu][wslu] provides `wslview`, which does the same job and would be the
obvious dependency. It was [archived upstream][wsluarchive] in 2025 — last
release 4.1.3, April 2024 — and it is not packaged for Debian 13. Installing an
unmaintained `.deb` outside `apt` is worse than shipping the few lines above.
If it ever returns to the archives, `wslview` is a drop-in replacement: point
`BROWSER` at it and delete the script.

### Check it

```bash
echo "$BROWSER"          # ~/.local/bin/wsl-browser
wsl-browser https://github.com
```

If a tool still opens a terminal browser it is probably remembering its own
setting — `gh`, for example, has `gh config set browser`. Clear it with
`gh config set browser ""` and let `$BROWSER` win.

## What does _not_ work in WSL

1Password **shell plugins** (`op plugin run`) are unsupported under WSL, so the
`gh` / `copilot` wrappers are not applied there. See
[1password-shell-plugins.md](1password-shell-plugins.md#wsl-is-not-supported).

[opwsl]: https://www.1password.dev/ssh/integrations/wsl
[opagent]: https://www.1password.dev/ssh/get-started/
[opauth]: https://www.1password.dev/ssh/agent/security#authorization-model
[interop]: https://learn.microsoft.com/windows/wsl/wsl-config#interop-settings
[wslu]: https://wslutiliti.es/wslu/
[wsluarchive]: https://github.com/wslutilities/wslu
