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
yk-enroll                      # mints a fresh per-serial resident key
```

> **Safe migration:** `useYubiKey: true` only swaps your `~/.ssh/config`
> over to the FIDO2 `IdentityFile` lines once `~/.ssh/id_ed25519_sk*` (or
> `id_ecdsa_sk*`) actually exists on disk. If you flip the toggle before
> enrolling a key, chezmoi keeps the 1Password `IdentityAgent` line and
> the `Include ~/.ssh/1Password/config` block as a fallback so your
> existing SSH access survives. Run `yk-enroll` and re-run
> `chezmoi apply`.

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

## Enrolling YubiKeys (recommended workflow)

`yk-enroll` is the one-stop wizard for taking a fresh (or partially
configured) YubiKey to the point where you can `ssh` and sign Git commits
with it. It is **idempotent** — re-run it any time to verify what's
already in place.

```bash
yk-enroll              # interactive: walks through every step
yk-enroll --check      # read-only audit; never prompts or writes
yk-enroll --rotate-pin # change FIDO2 PIN even if one is already set
```

The wizard runs five steps:

1. **Preflight** — confirms `ykman` and a FIDO2-capable `ssh-keygen` are
   on your PATH (catches the macOS Apple-OpenSSH trap from the previous
   section).
2. **Detect** — refuses to proceed unless **exactly one** YubiKey is
   plugged in, so it's never ambiguous which key is being enrolled.
3. **Capability check** — fails fast if firmware is too old for the
   requested key type (suggests `--type ecdsa-sk` for fw <5.2.3).
4. **FIDO2 PIN** — sets one if missing; reports it as set otherwise.
   On **FIPS** YubiKeys it explicitly warns about the factory default
   (see below) and tells you to use `--rotate-pin`.
5. **SSH key** — generates a resident `ed25519-sk` key at
   `~/.ssh/id_ed25519_sk_<serial>`; skips if already present. After
   `ssh-keygen` returns the wizard verifies the key file actually exists
   on disk before declaring success — so cancelling the FIDO2 PIN prompt
   (Ctrl+C) is reported as an abort, never as a successful enrollment.

It then prints the exact `gh ssh-key add` and `ssh-add` commands you
should run.

### FIPS YubiKeys ship with a factory PIN

The **YubiKey 5 FIPS** series ships with a publicly known factory FIDO2
PIN of `123456` — `ykman fido info` will report "PIN is set" on a
brand-new device. The non-FIPS YubiKey 5 ships with no PIN at all.

`yk-enroll` detects FIPS devices via the device-type string and warns
you when this is likely the case. Rotate the PIN before relying on the
key:

```bash
yk-enroll --rotate-pin
```

### Why not `AddKeysToAgent yes`?

For FIDO2 (`*-sk`) keys the SSH config sets `IdentitiesOnly yes` and
**does not** set `AddKeysToAgent yes`. The reason: the private key never
leaves the YubiKey, so `ssh-agent` has nothing to cache except the
handle. With `verify-required` set on the credential, every signing
op needs a fresh PIN — but `ssh-agent` (especially on macOS) cannot
re-prompt for the FIDO2 PIN, so the second `ssh` call fails with:

```
sign_and_send_pubkey: signing failed for ED25519-SK "..." from agent: agent refused operation
```

Letting OpenSSH talk to the YubiKey directly each time keeps the touch
+ PIN dance interactive and reliable. If you ever land in the broken
state (e.g. you ran an older config that did `AddKeysToAgent yes`),
clear the agent and you're back in business:

```bash
ssh-add -D                   # drop all cached keys
ssh -T git@github.com        # works again
```

### Multiple YubiKeys

A FIDO2 resident credential lives only on the YubiKey that minted it —
there is no way to copy it to a second key. To use **all** your YubiKeys
for SSH:

1. Plug in **only the first** YubiKey, run `yk-enroll`.
2. Repeat for each additional YubiKey. Each gets its own
   `~/.ssh/id_ed25519_sk_<serial>` (private + public).
3. Add **every resulting `.pub`** to GitHub (`gh ssh-key add` for each).
4. From then on, any plugged-in YubiKey can authenticate / commit. SSH
   picks whichever is touched.

> **Don't try to "expand" an existing key onto a second YubiKey** — the
> hardware doesn't allow it. Enrolling a second key is the supported
> path, and `yk-enroll` makes it a one-command operation.

### On work machines

Some setup steps can't be automated by chezmoi (network-gated URLs,
browser-based MFA enrollment, per-user sign-ins). They live in a
separate helper, `work-checklist`, so you don't have to remember them
on a fresh machine:

```bash
work-checklist        # prints the manual post-install checklist
```

Currently includes (among others) **`https://aka.ms/CloudMFA`** for
corporate SSO MFA enrollment, plus the `gh ssh-key add` / `gh auth
login` / `az login` reminders. The wizard mentions `work-checklist` in
its own "Done." footer so you don't miss it.

## Helpers (Bash/Zsh + Fish)

| Bash/Zsh                | Fish                | Purpose                                                    |
| ----------------------- | ------------------- | ---------------------------------------------------------- |
| `yk-enroll`             | `yk_enroll`         | **Wizard**: end-to-end enrollment + health check, idempotent |
| `yk-status`             | `yk_status`         | Per-device health: firmware, FIPS, PIN status, SSH key check |
| `yk-pick`               | `yk_pick`           | Pick one serial when multiple keys are connected           |
| `yk-ssh-new`            | `yk_ssh_new`        | Low-level: generate `ed25519-sk` / `ecdsa-sk` on the key   |
| `work-checklist`        | `work_checklist`    | Print manual post-install steps for work machines          |
| `clipboard-copy`        | `clipboard_copy`    | Cross-platform clipboard helper used by `pubkey`           |
| `pubkey`                | `pubkey`            | Print + copy the highest-priority pubkey from `~/.ssh`     |
| `yk-git-sign-setup`     | `yk_git_sign_setup` | Register your SSH pubkey for git commit signing            |

`pubkey` discovers per-serial files: it picks the first match of
`id_ed25519_sk_*.pub` → `id_ed25519_sk.pub` → `id_ecdsa_sk_*.pub` →
`id_ecdsa_sk.pub` → `id_ed25519.pub` → `id_rsa.pub`, so it transparently
follows you onto a YubiKey enrolled with `yk-enroll`.

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

## Git commit signing

Once your YubiKey-backed SSH key exists, you can use it to sign git commits and
tags — no GPG required. This is gated by the same `useYubiKey` chezmoi var.

```bash
# 1) Enroll your YubiKey (mints ~/.ssh/id_ed25519_sk_<serial>)
yk-enroll

# 2) Upload the pubkey to GitHub as BOTH an authentication AND a signing key.
#    Both are required: the first lets you push/pull over SSH, the second is
#    what gets you the green "Verified" badge on signed commits.
gh ssh-key add ~/.ssh/id_ed25519_sk_<serial>.pub --type authentication --title "<title>"
gh ssh-key add ~/.ssh/id_ed25519_sk_<serial>.pub --type signing       --title "<title>"

# 3) chezmoi picks up the new key:
#      ~/.ssh/config gets per-serial IdentityFile lines (via glob)
#      ~/.config/git/config gets [gpg] format=ssh + user.signingkey
#      ~/.config/git/allowed_signers gets every per-serial pubkey
chezmoi apply

# 4) Register your pubkey(s) as trusted signers + verify
yk-git-sign-setup
yk-git-sign-setup --check

# 5) Smoke test
git commit -S --allow-empty -m "test signing"
git log --show-signature -1
```

> **Uploading a *signing* key isn't optional** — the whole point of signing is
> the verified badge. `yk-enroll`'s "Done." block lists both `gh ssh-key add`
> commands explicitly, and `work-checklist` includes them as separate
> checklist items.

### Multi-YubiKey signing

`user.signingkey` is a single path, so chezmoi picks the first per-serial
pubkey it finds (`id_ed25519_sk_*` first, then legacy un-suffixed). Whichever
YubiKey is plugged in, OpenSSH walks every `IdentityFile` until one matches
the SSH config — but git always asks the device that holds the **`user.signingkey`**
private key. If you carry multiple YubiKeys, set `user.signingkey` to the
specific pubkey you want to sign with (or override per-repo via
`git config user.signingkey ~/.ssh/id_ed25519_sk_<other-serial>.pub`).

`allowed_signers` lists **all** per-serial pubkeys so verification works
regardless of which YubiKey signed the commit.

### Add a coworker's key

```bash
yk-git-sign-setup --add /path/to/coworker.pub --principal coworker@example.com
```

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
