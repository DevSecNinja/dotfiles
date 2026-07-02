# 🤖 GitHub Copilot CLI on headless servers

[GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli)
wants to store its token in a secure OS vault (Keychain on macOS, Secret Service
/ gnome-keyring on Linux). On **headless Linux servers** there is no desktop
session to unlock such a vault, so Copilot falls back to either storing the
token in a plaintext config file or keeping it in memory (re-login every start).

Instead, we authenticate non-interactively with the `COPILOT_GITHUB_TOKEN`
environment variable, sourced from **1Password** on your workstation and
**forwarded over SSH** to the server. No secret is ever written to the server or
committed to a repository.

> macOS and other workstations are unaffected — Copilot uses the native Keychain
> automatically. This flow only matters for the headless Linux dev servers.

## How it works

```text
workstation                                   headless server (svldev, …)
───────────                                   ───────────────────────────
1Password Environment
  COPILOT_GITHUB_TOKEN
        │  op run --environment <ID>
        ▼
  copilot-ssh svldev
        │  ssh -o SendEnv=COPILOT_GITHUB_TOKEN
        ▼  (encrypted channel)
                                      sshd AcceptEnv COPILOT_GITHUB_TOKEN
                                              │
                                              ▼
                                      session env: COPILOT_GITHUB_TOKEN
                                              │
                                              ▼
                                      copilot  ← authenticates
```

- **Token source:** a 1Password [Environment][openv] variable named exactly
  `COPILOT_GITHUB_TOKEN`. Same name end-to-end, so nothing is remapped.
- **Workstation:** the `copilot-ssh` (bash/zsh) / `copilot_ssh` (fish) helper
  reads the token via `op run` and forwards it with SSH `SendEnv`.
- **Server:** `sshd` opts in with `AcceptEnv COPILOT_GITHUB_TOKEN`. SSH's secure
  default is to drop all client-sent env vars, so this server-side allow-list is
  required — it is managed by the `system_setup` role in the `docker` repo.
- **Copilot:** reads `COPILOT_GITHUB_TOKEN` natively (it takes precedence over
  `GH_TOKEN` and does **not** collide with the `gh` CLI).

## One-time setup

1. **Create a token.** A fine-grained
   [Personal Access Token](https://github.com/settings/personal-access-tokens/new)
   with the **"Copilot Requests"** permission. Give it an expiry and rotate it
   periodically.
2. **Store it in 1Password.** In the desktop app: **Developer → View
   Environments → New environment** (e.g. "Development Machine"), then add a
   variable named `COPILOT_GITHUB_TOKEN` with the PAT as its value.
3. **Get the Environment ID.** Open the Environment → **Manage environment →
   Copy environment ID**. This ID is not a secret.
4. **Tell chezmoi.** Set the `opCopilotEnvironmentId` variable (prompted on
   `chezmoi init`, or re-enter with `chezmoi init --data=false`). It is stored in
   your local chezmoi config only and exported as `OP_COPILOT_ENVIRONMENT_ID`.
5. **1Password CLI.** Install the [1Password CLI][opcli] **beta ≥ 2.33.0-beta.02**
   and enable the **desktop-app integration** (so `op run` unlocks with
   biometrics — no service-account token needed). Environment support is beta.

The server side needs no manual steps — the `docker` repo's Ansible pull adds
`AcceptEnv COPILOT_GITHUB_TOKEN` to `sshd` automatically.

## Usage

```bash
copilot-ssh svldev        # bash / zsh
copilot_ssh svldev        # fish
```

Then run `copilot` on the server as usual — it picks up the forwarded token.
Any extra `ssh` arguments are passed through (e.g. `copilot-ssh -A svldev`).

If `op` or `OP_COPILOT_ENVIRONMENT_ID` is unavailable, the helper falls back to
a plain `ssh` (you connect, but Copilot won't receive a token).

## Security notes

- The token lives only in 1Password (at rest), transiently in the helper's
  memory, the encrypted SSH channel, and the server **session's** environment
  for that session's lifetime. Nothing is persisted on the server.
- `AcceptEnv` is scoped to the single variable `COPILOT_GITHUB_TOKEN` — never a
  wildcard, which the OpenSSH docs warn can be used to bypass restricted
  environments.
- During a live session the token is readable via `/proc/<pid>/environ` by
  same-user processes and root on that server — the same trust boundary as the
  logged-in user. Use a least-privilege, expiring PAT to limit blast radius.

[openv]: https://www.1password.dev/environments
[opcli]: https://developer.1password.com/docs/cli/
