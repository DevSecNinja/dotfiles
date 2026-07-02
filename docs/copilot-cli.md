# 🤖 GitHub Copilot CLI on headless servers

[GitHub Copilot CLI](https://docs.github.com/copilot/concepts/agents/about-copilot-cli)
wants to store its token in a secure OS vault (Keychain on macOS, Secret Service
/ gnome-keyring on Linux). On **headless Linux servers** there is no desktop
session to unlock such a vault, so Copilot falls back to either storing the
token in a plaintext config file or keeping it in memory (re-login every start).

Instead, we authenticate non-interactively with the `COPILOT_GITHUB_TOKEN`
environment variable (and `GH_TOKEN` for the [`gh` CLI](https://cli.github.com/)),
sourced from **1Password** on your workstation and **forwarded over SSH** to the
server. No secret is ever written to the server or committed to a repository.

> macOS and other workstations are unaffected — Copilot uses the native Keychain
> automatically. This flow only matters for the headless Linux dev servers.

## How it works

```text
workstation                                   headless server (svldev, …)
───────────                                   ───────────────────────────
1Password Environment
  COPILOT_GITHUB_TOKEN
  GH_TOKEN (optional)
        │  op run --environment <ID>
        ▼
  copilot-ssh svldev
        │  ssh -o SendEnv=COPILOT_GITHUB_TOKEN -o SendEnv=GH_TOKEN
        ▼  (encrypted channel)
                              sshd AcceptEnv COPILOT_GITHUB_TOKEN GH_TOKEN
                                              │
                                              ▼
                                      session env: COPILOT_GITHUB_TOKEN, GH_TOKEN
                                              │
                                              ▼
                                      copilot ← COPILOT_GITHUB_TOKEN
                                      gh      ← GH_TOKEN
```

- **Token source:** a 1Password [Environment][openv] with a variable named
  exactly `COPILOT_GITHUB_TOKEN` (required) and, optionally, `GH_TOKEN` for the
  `gh` CLI. Same names end-to-end, so nothing is remapped. Keeping them separate
  lets each tool's token be scoped and rotated independently.
- **Workstation:** the `copilot-ssh` (bash/zsh) / `copilot_ssh` (fish) helper
  reads the token(s) via `op run` and forwards them with SSH `SendEnv`.
- **Server:** `sshd` opts in with `AcceptEnv COPILOT_GITHUB_TOKEN GH_TOKEN`.
  SSH's secure default is to drop all client-sent env vars, so this server-side
  allow-list is required — it is managed by the `system_setup` role in the
  `docker` repo.
- **Tools:** Copilot CLI reads `COPILOT_GITHUB_TOKEN` (it takes precedence over
  `GH_TOKEN`); the `gh` CLI reads `GH_TOKEN`. They do not interfere with each
  other.

## One-time setup

1. **Create the token(s).** A fine-grained
   [Personal Access Token](https://github.com/settings/personal-access-tokens/new)
   with the **"Copilot Requests"** permission for Copilot. Optionally create a
   **second** fine-grained PAT scoped to what you need `gh` to do on the servers
   (e.g. repository contents, pull requests). Give them an expiry and rotate
   periodically. Keeping them separate keeps each token least-privilege.
2. **Store them in 1Password.** In the desktop app: **Developer → View
   Environments → New environment** (e.g. "Development Machine"), then add a
   variable named `COPILOT_GITHUB_TOKEN` with the Copilot PAT as its value. To
   also authenticate `gh`, add a second variable named `GH_TOKEN` with the `gh`
   PAT (optional — omit it if you only want Copilot).
3. **Get the Environment ID.** Open the Environment → **Manage environment →
   Copy environment ID**. This ID is not a secret.
4. **Tell chezmoi (usually nothing to do).** The Environment ID is a non-secret
   identifier, so a shared default is hardcoded in `.chezmoi.yaml.tmpl` and
   exported as `OP_COPILOT_ENVIRONMENT_ID`. To use a different Environment,
   override `opCopilotEnvironmentId` in your local chezmoi config or at the
   interactive init prompt (`chezmoi init --data=false` to re-enter).
5. **1Password CLI.** Install the [1Password CLI][opcli] **beta ≥ 2.33.0-beta.02**
   and enable the **desktop-app integration** (so `op run` unlocks with
   biometrics — no service-account token needed). Environment support is beta.

The server side needs no manual steps — the `docker` repo's Ansible pull adds
`AcceptEnv COPILOT_GITHUB_TOKEN GH_TOKEN` to `sshd` automatically.

## Usage

```bash
copilot-ssh svldev        # bash / zsh
copilot_ssh svldev        # fish
```

Then run `copilot` (and `gh`, if you added `GH_TOKEN`) on the server as usual —
they pick up the forwarded tokens. Any extra `ssh` arguments are passed through
(e.g. `copilot-ssh -A svldev`).

If `op` or `OP_COPILOT_ENVIRONMENT_ID` is unavailable, the helper falls back to
a plain `ssh` (you connect, but the tools won't receive a token).

## Security notes

- The tokens live only in 1Password (at rest), transiently in the helper's
  memory, the encrypted SSH channel, and the server **session's** environment
  for that session's lifetime. Nothing is persisted on the server.
- `AcceptEnv` is scoped to the specific variables `COPILOT_GITHUB_TOKEN` and
  `GH_TOKEN` — never a wildcard, which the OpenSSH docs warn can be used to
  bypass restricted environments.
- During a live session the tokens are readable via `/proc/<pid>/environ` by
  same-user processes and root on that server — the same trust boundary as the
  logged-in user. Use least-privilege, expiring PATs (separate ones for Copilot
  and `gh`) to limit blast radius.

[openv]: https://www.1password.dev/environments
[opcli]: https://developer.1password.com/docs/cli/
