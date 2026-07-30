# ✍️ Git commit signing with 1Password

Commits and tags are signed with an SSH key held by 1Password. The private key
never leaves the vault: git delegates the signing operation to 1Password's own
signer binary, which prompts you to approve it.

This is the alternative to the hardware-token flow in
[yubikey.md](yubikey.md) — `useYubiKey = true` takes precedence and ignores
everything on this page.

## Setup

The repository owner's public keys ship as the defaults for `gitSigningKey`, so
signing switches itself on as soon as a 1Password signer binary is present —
nothing to configure. Which default applies depends on the machine:

| Machine | Default key |
| --- | --- |
| Entra ID tenant ending in `Microsoft` (`isWork = true`) | work key |
| Everything else | personal key ([published][keys]) |

[keys]: https://github.com/DevSecNinja.keys

`isWork` comes from `dsregcmd /status` on Windows and WSL; elsewhere it is
`false`, so the personal key applies. A `gitSigningKey` left over in your local
chezmoi config from an earlier `chezmoi init` is re-evaluated whenever it still
equals one of the shipped defaults, so a machine never gets pinned to the wrong
one — only a key of your own is treated as an override.

**Using your own key instead:**

1. In the 1Password app, open the SSH key item.
2. Choose **⋮ → Configure Commit Signing**. On Windows, tick
   **Configure for Windows Subsystem for Linux (WSL)** if you want the WSL
   variant.
3. Select **Copy Snippet** and take the public key from it.
4. Put that key in your local chezmoi config, which overrides the default:

   ```yaml
   data:
     gitSigningKey: "ssh-ed25519 AAAA… comment"
   ```

5. Run `chezmoi apply`.

That renders `user.signingkey`, points `gpg.ssh.program` at the right signer,
turns on `commit.gpgsign` / `tag.gpgsign`, and adds the key to
`~/.config/git/allowed_signers` so your own commits verify locally. A public
key is not a secret, so keeping it in the config is fine.

Git needs a `key::` prefix to read a literal public key rather than a file
path; the template adds it for you, so paste the key exactly as 1Password
gives it — with or without a trailing comment.

## The agent has to offer the key

Holding the right key is not enough: the 1Password SSH agent only offers keys
from the vaults listed in its config, so the signer can hold a perfectly good
key and still fail with *"No SSH private key found for the specified public
key"*.

On Windows that config is managed by this repo at
`%LOCALAPPDATA%\1Password\config\ssh\agent.toml`, rendered from the
`opSshVault` chezmoi variable — `Microsoft` on work machines, `Private`
elsewhere. WSL benefits too, since it reaches the same Windows agent
(see [wsl.md](wsl.md)).

Watch out for a bare `ssh-keys = []`, which 1Password writes on a fresh
install. That is an explicit *empty* list, not "the default set", so the agent
offers nothing at all and `ssh-add -l` reports no identities. Adding at least
one `[[ssh-keys]]` entry is what fixes it.

Use a differently-named vault by setting it in your local chezmoi config:

```yaml
data:
  opSshVault: "My Custom Vault"
```

## The signer is platform-specific

1Password ships a different binary per platform, and the repo auto-detects the
right one:

| Platform | Binary | Auto-detected from |
| --- | --- | --- |
| WSL | `op-ssh-sign-wsl.exe` | Current Windows user's `%LOCALAPPDATA%\Microsoft\WindowsApps\`, then the pre-8.11.18 `…\1Password\app\8\` |
| Native Windows | `op-ssh-sign.exe` | `%LOCALAPPDATA%\Microsoft\WindowsApps\`, then `%LOCALAPPDATA%\1Password\app\8\` |
| macOS | `op-ssh-sign` | `/Applications/1Password.app/Contents/MacOS/` |
| Linux | — | no standard path; set it explicitly |

Paths are emitted with forward slashes, because git config treats a backslash
as an escape character. That is also the form 1Password's own snippet uses.

Override auto-detection for a non-standard install:

```yaml
data:
  opSshSignProgram: "C:/Users/you/AppData/Local/Microsoft/WindowsApps/op-ssh-sign.exe"
```

## If no signer is found

Signing is deliberately left **off**, and the rendered `~/.config/git/config`
says why.

Enabling `commit.gpgsign` without a working `gpg.ssh.program` would make git
fall back to the local `ssh-keygen`, which cannot reach the key held by
1Password — so **every `git commit` would fail**. Leaving signing off keeps the
repo usable; install or update 1Password, or set `opSshSignProgram`, then
re-run `chezmoi apply`.

## Verify

```bash
git config --get gpg.ssh.program
git config --get user.signingkey
git commit --allow-empty -m "signing test"
git log --show-signature -1
```

A good signature shows `Good "git" signature`. In WSL the approval prompt
appears on the Windows host — see [wsl.md](wsl.md).

If signing fails with *"No SSH private key found for the specified public
key"*, check what the agent is actually offering:

```bash
ssh-add -l
```

No identities means the agent is not running, is locked, or its `agent.toml`
does not list the vault holding the key — see
[the agent has to offer the key](#the-agent-has-to-offer-the-key).
