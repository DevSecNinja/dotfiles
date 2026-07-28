# 🪟 WSL and 1Password

In WSL your SSH private keys are not on the Linux side at all — they live in
1Password on the Windows host. Rather than forwarding an *agent socket*, the
[1Password WSL integration][opwsl] forwards the whole SSH request to the
Windows OpenSSH client (`ssh.exe`), which talks to the 1Password SSH agent and
raises the approval prompt on Windows.

This repo wires that up for you.

## What is configured automatically

| Concern | How | Where |
| --- | --- | --- |
| Git over SSH | `core.sshCommand = ssh.exe` | `dot_config/git/config.tmpl` |
| Interactive `ssh` / `ssh-add` | aliased to `ssh.exe` / `ssh-add.exe` | `dot_config/shell/functions/wsl-ssh.sh`, `dot_config/fish/conf.d/wsl-ssh.fish` |
| Commit signing | `gpg.ssh.program = op-ssh-sign-wsl.exe` | `dot_config/git/config.tmpl` |

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

## Enabling commit signing

Signing needs your **public** key, which this repo reads from the
`gitSigningKey` chezmoi variable:

1. In the 1Password Windows app, open the SSH key item.
2. Choose **⋮ → Configure Commit Signing**.
3. Tick **Configure for Windows Subsystem for Linux (WSL)** and select
   **Copy Snippet**.
4. Put the public key from that snippet into your local chezmoi config:

   ```yaml
   data:
     gitSigningKey: "ssh-ed25519 AAAA… comment"
   ```

5. Run `chezmoi apply`.

That renders `user.signingkey`, turns on `commit.gpgsign` / `tag.gpgsign`, and
adds the key to `~/.config/git/allowed_signers` so your own commits verify
locally. A public key is not a secret, so keeping it in the config is fine.

Git needs the `key::` prefix to read a literal public key rather than a file
path; the template adds it for you, so paste the key exactly as 1Password
gives it.

The signer binary is located automatically, preferring the current MSIX path
and falling back to the pre-8.11.18 one:

```text
/mnt/c/Users/<you>/AppData/Local/Microsoft/WindowsApps/op-ssh-sign-wsl.exe
/mnt/c/Users/<you>/AppData/Local/1Password/app/8/op-ssh-sign-wsl
```

If neither exists, signing is left **off** and the rendered config explains
why. Turning `commit.gpgsign` on without a signer would make git fall back to
the local `ssh-keygen`, which cannot reach the key held by 1Password on
Windows — every `git commit` would fail. Install or update 1Password for
Windows, then re-run `chezmoi apply`.

For a non-standard install you can point at the signer explicitly instead of
relying on auto-detection:

```yaml
data:
  opSshSignProgram: "/mnt/c/path/to/op-ssh-sign-wsl.exe"
```

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

## What does *not* work in WSL

1Password **shell plugins** (`op plugin run`) are unsupported under WSL, so the
`gh` / `copilot` wrappers are not applied there. See
[1password-shell-plugins.md](1password-shell-plugins.md#wsl-is-not-supported).

[opwsl]: https://www.1password.dev/ssh/integrations/wsl
[opagent]: https://www.1password.dev/ssh/get-started/
[opauth]: https://www.1password.dev/ssh/agent/security#authorization-model
[interop]: https://learn.microsoft.com/windows/wsl/wsl-config#interop-settings
