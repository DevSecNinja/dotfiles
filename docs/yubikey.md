# 🔐 YubiKey

This repo ships shell helpers for using a YubiKey as your SSH (and later
Git-signing and TOTP) hardware token. The flow is designed to work with
**any firmware ≥ 5.2.3** — the brand-new 5.7 FIPS keys and older 5.4.x keys
can be used side-by-side, and multi-key setups are first-class.

It's also designed to **survive the migration off 1Password**: the
1Password SSH agent integration is gated behind the `useYubiKey` chezmoi
variable and stays the default until you flip it.

## What gets installed

When `useYubiKey: true`, `chezmoi apply` also installs `ykman` (yubikey-manager)
and the smart-card daemon needed for OATH:

| OS        | Package(s)                                  |
| --------- | ------------------------------------------- |
| macOS     | `ykman`, `openssh` (Homebrew — Apple's bundled OpenSSH lacks FIDO2) |
| Debian/Ubuntu | `yubikey-manager`, `pcscd`, `scdaemon`  |
| Fedora    | `yubikey-manager`, `pcsc-lite`              |
| Windows   | `Yubico.YubikeyManagerCLI` (winget)         |

Set `useYubiKey: false` (the default) and none of these are touched.

## Quick start

```bash
# 1) See what's plugged in
yk-status

# 2) Generate a hardware-backed SSH key (resident, PIN+touch required)
yk-ssh-new

# 3) Tell chezmoi to wire it into ~/.ssh/config
chezmoi edit-config-template   # set useYubiKey to true, or pass --promptBool
chezmoi apply

# 4) On a *new* machine, after `chezmoi apply`:
yk-ssh-load                    # ssh-add -K — pulls keys back from the YubiKey
```

> **Safe migration:** `useYubiKey: true` only swaps your `~/.ssh/config`
> over to the FIDO2 `IdentityFile` lines once `~/.ssh/id_ed25519_sk` (or
> `id_ecdsa_sk`) actually exists on disk. If you flip the toggle before
> generating / loading a resident key, chezmoi keeps the 1Password
> `IdentityAgent` line and the `Include ~/.ssh/1Password/config` block as
> a fallback so your existing SSH access survives. Run `yk-ssh-new` (new
> machine: provisioning a key) or `yk-ssh-load` (new machine: pulling
> resident keys back from the YubiKey) and re-run `chezmoi apply`.

### Locked yourself out?

If `git@github.com: Permission denied (publickey)` appears after enabling
the toggle on a machine where the keys aren't there yet:

```bash
chezmoi init --data=false --apply   # the --apply is the key bit
# or pull source over HTTPS and re-apply:
cd "$(chezmoi source-path)" \
  && git remote set-url origin https://github.com/DevSecNinja/dotfiles.git \
  && git pull
chezmoi apply
```

### macOS: "No FIDO SecurityKeyProvider specified"

If `yk-ssh-new` fails with:

```
No FIDO SecurityKeyProvider specified
Key enrollment failed: invalid format
```

…you're running Apple's bundled `/usr/bin/ssh-keygen`, which is built
without libfido2. Install Homebrew's OpenSSH (it's added to the YubiKey
package set, so a re-apply does it for you) and put it ahead of `/usr/bin`
on your PATH:

```bash
brew install openssh
# Apple Silicon
export PATH="/opt/homebrew/bin:$PATH"
# Intel
export PATH="/usr/local/bin:$PATH"

ssh -V       # expect OpenSSH_9.x — *not* OpenSSH_9.x p1, LibreSSL …
yk-ssh-new
```

`yk-ssh-new` now detects this case and prints the same instructions before
attempting key generation.

## Helpers (Bash/Zsh + Fish)

| Bash/Zsh                | Fish                | Purpose                                                    |
| ----------------------- | ------------------- | ---------------------------------------------------------- |
| `yk-status`             | `yk_status`         | Firmware / form-factor / FIPS info per device              |
| `yk-pick`               | `yk_pick`           | Pick one serial when multiple keys are connected           |
| `yk-ssh-new`            | `yk_ssh_new`        | Generate `ed25519-sk` (or `ecdsa-sk`) on the YubiKey       |
| `yk-ssh-load`           | `yk_ssh_load`       | `ssh-add -K`: load resident keys from the YubiKey          |
| `clipboard-copy`        | `clipboard_copy`    | Cross-platform clipboard helper used by `pubkey`           |
| `pubkey`                | `pubkey`            | Print + copy the highest-priority pubkey from `~/.ssh`     |

`pubkey` now picks the first available of:
`id_ed25519_sk.pub` → `id_ecdsa_sk.pub` → `id_ed25519.pub` → `id_rsa.pub`,
so it transparently follows you onto a YubiKey.

## Firmware compatibility

| Feature                        | Min fw   | Notes                                |
| ------------------------------ | -------- | ------------------------------------ |
| `ed25519-sk` SSH keys          | 5.2.3    | Both 5.4.3 and 5.7.4 supported       |
| Resident credentials + `-K`    | 5.2.3    | Both 5.4.3 and 5.7.4 supported       |
| PIV `ed25519`                  | 5.7      | Not used by these helpers (yet)      |
| FIPS-approved algorithms only  | FIPS sku | `yk-status` flags FIPS devices       |

`yk-status` warns when a device is below 5.7 so you remember which
features are available on which key.

## Multiple keys

When more than one YubiKey is connected, every helper either:

- accepts `--serial <SN>` to target a specific device, or
- delegates to `yk-pick`, which uses `fzf` if available.

Run `yk-status` to see all serials at a glance.

## Migrating off 1Password

The current flow is preserved as-is until you flip the switch:

1. Generate keys on the YubiKey: `yk-ssh-new`.
2. Add the public key to GitHub (or wherever): `gh ssh-key add ~/.ssh/id_ed25519_sk.pub`.
3. Set `useYubiKey: true` in your chezmoi data.
4. `chezmoi apply` — the 1Password `Include ~/.ssh/1Password/config` line
   and the macOS `IdentityAgent` line are removed; `IdentityFile` lines
   for `id_ed25519_sk` / `id_ecdsa_sk` are added under `Host *`.
5. Apple Passwords does not provide an SSH agent; on macOS the OS keychain
   + ssh-agent handle the FIDO2 key directly. Bitwarden CLI (`bw`) can
   stand in for `op` when scripts need secrets.
