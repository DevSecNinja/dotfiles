# 🔐 YubiKey

This repo ships shell helpers for using a YubiKey as your SSH (and later
Git-signing and TOTP) hardware token. The flow is designed to work with
**any firmware ≥ 5.2.3** — the brand-new 5.7 FIPS keys and older 5.4.x keys
can be used side-by-side, and multi-key setups are first-class.

It's also designed to **survive the migration off 1Password**: the
1Password SSH agent integration is gated behind the `useYubiKey` chezmoi
variable and stays the default until you flip it.

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

## Helpers (Bash/Zsh + Fish)

| Bash/Zsh                | Fish                | Purpose                                                    |
| ----------------------- | ------------------- | ---------------------------------------------------------- |
| `yk-status`             | `yk_status`         | Firmware / form-factor / FIPS info per device              |
| `yk-pick`               | `yk_pick`           | Pick one serial when multiple keys are connected           |
| `yk-ssh-new`            | `yk_ssh_new`        | Generate `ed25519-sk` (or `ecdsa-sk`) on the YubiKey       |
| `yk-ssh-load`           | `yk_ssh_load`       | `ssh-add -K`: load resident keys from the YubiKey          |
| `clipboard-copy`        | `clipboard_copy`    | Cross-platform clipboard helper used by `pubkey`           |
| `pubkey`                | `pubkey`            | Print + copy the highest-priority pubkey from `~/.ssh`     |
| `yk-otp`                | `yk_otp`            | TOTP code from the OATH applet (fzf + clipboard)           |
| `yk-touch-watch`        | `yk_touch_watch`    | Notify when a YubiKey is waiting for a touch               |

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

## TOTP (OATH)

Use the YubiKey's OATH applet to generate 6/8-digit TOTP codes from the CLI,
no phone needed:

```bash
yk-otp                  # picks the only match, or fzf when multiple
yk-otp github           # filter by substring
yk-otp --list           # just list account names
yk-otp --no-copy aws    # print but don't touch the clipboard
```

The selected code is also copied to the clipboard via `clipboard-copy`. If
the account is configured as "requires touch", `yk-otp` prints a hint and
waits for the tap.

`yk-touch-watch` runs in the background and notifies (desktop notification +
terminal bell) when a YubiKey operation is blocking on a touch — useful when
SSH/git seem to "hang" silently. Run with `--once` to fire once and exit.

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
