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
- **Workstation:** the `copilot-ssh` (bash/zsh) / `copilot_ssh` (fish) /
  `copilot-ssh` (PowerShell) helper reads the token(s) via `op run` and forwards
  them with SSH `SendEnv`.
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
copilot-ssh svldev        # PowerShell (Windows workstation)
```

Then run `copilot` (and `gh`, if you added `GH_TOKEN`) on the server as usual —
they pick up the forwarded tokens.

On the **bash/zsh/fish** helpers, extra `ssh` arguments are passed through
directly (e.g. `copilot-ssh -A svldev`). On the **PowerShell** helper the host
name is a real parameter that tab-completes from your `~/.ssh/config` `Host`
entries; because ssh flags such as `-p`/`-o` collide with PowerShell's parameter
binder, pass any extra ssh options after a `--` separator:

```powershell
copilot-ssh svldev                 # host name tab-completes
copilot-ssh svldev -- -A -p 2222   # extra ssh flags after --
```

If `op` or `OP_COPILOT_ENVIRONMENT_ID` is unavailable, the **bash/zsh/fish**
helpers fall back to a plain `ssh` (you connect, but the tools won't receive a
token). The **PowerShell** helper instead runs fatal pre-flight checks and
**aborts** if `ssh` or `op` is missing, or the Environment ID is unset — it
never opens a token-less session. When the 1Password CLI is not found it tells
you to (1) install it and (2) enable it in
**1Password → Settings → Developer → "Integrate with 1Password CLI"**.

## Reachability pre-flight (and stopped Azure VMs)

Before unlocking 1Password, all three helpers run a fast reachability check so
an unreachable host fails in about three seconds instead of hanging on ssh's
own connect timeout:

1. The destination is resolved with `ssh -G <args>`, so `~/.ssh/config`
   aliases, `HostName`/`Port` overrides and `-o` flags are all honoured.
2. Its TCP port is probed with a hard timeout (`nc`, or bash `/dev/tcp`, or a
   .NET `TcpClient` on Windows). If nothing can probe, the check is skipped and
   `ssh` decides.
3. When the probe fails **and** the Azure CLI (`az`) is installed, the host is
   looked up with `az vm list -d`: first by VM name — matching both the full
   host and its short form, so `vm01.example.com` also matches a VM named
   `vm01` — then by the VM's public/private IP addresses.
4. If that VM is **stopped** or **deallocated**, you are asked whether to start
   it. On yes, the helper runs `az vm start`, waits for the SSH port to answer
   and then connects as usual. On no (or in a non-interactive shell, which
   always answers no) it aborts.
5. If the VM is **running** but the port is closed, it says so and points at
   NSG rules, the VPN/network path or `sshd` — no VM is touched.

Ambiguous matches (several VMs with the same name in different resource
groups) are listed and the helper refuses to guess.

Environment variables:

| Variable                        | Default | Effect                                          |
| ------------------------------- | ------- | ----------------------------------------------- |
| `COPILOT_SSH_SKIP_PREFLIGHT`    | unset   | `1` skips the reachability check entirely       |
| `COPILOT_SSH_PREFLIGHT_TIMEOUT` | `3`     | TCP probe timeout in seconds                    |
| `COPILOT_SSH_START_TIMEOUT`     | `180`   | How long to wait for SSH after `az vm start`    |
| `COPILOT_SSH_ASSUME_YES`        | unset   | `1` auto-confirms starting a stopped VM         |
| `COPILOT_SSH_ASSUME_NO`         | unset   | `1` never starts a VM, even on a TTY            |

## Local authentication with the 1Password shell plugin

`copilot-ssh` solves the *remote* case: forwarding a token to a headless
server. On your **workstation** you don't need to forward anything — the
[1Password Copilot shell plugin][opcopilot] authenticates the local `copilot`
command with biometrics, injecting the same `COPILOT_GITHUB_TOKEN` for the
duration of each command.

This repo wraps `copilot` (and `gh`) automatically; see
[1password-shell-plugins.md](1password-shell-plugins.md). The two mechanisms
are complementary and use the same variable name:

| Where | Mechanism | Token source |
| --- | --- | --- |
| Workstation | `op plugin run -- copilot` | 1Password item, per command |
| Headless server | `copilot-ssh` + SSH `SendEnv` | 1Password Environment |

Note that the plugin wrappers are not applied on WSL, where shell plugins are
unsupported — `copilot-ssh` still works there.

### They cannot collide

The wrappers deliberately do **not** activate in an SSH session (they are
guarded on `SSH_CONNECTION`). `op plugin run` needs the 1Password desktop app
for biometric unlock, which a headless server does not have, so a wrapper on
the far side of `copilot-ssh` would replace a working CLI with one that always
fails — exactly the situation `copilot-ssh` exists to avoid.

| Session | `copilot` resolves to | Credential |
| --- | --- | --- |
| Local workstation | `op plugin run -- copilot` | 1Password, per command |
| Inside `copilot-ssh` | the real `copilot` binary | forwarded `COPILOT_GITHUB_TOKEN` |

In practice the remote host usually has no `op` installed either, which is a
second, independent guard. The same reasoning applies to `gh` and `GH_TOKEN`.

[opcopilot]: https://www.1password.dev/cli/shell-plugins/github-copilot

## Pre-approving safe file writes (PowerShell)

In a trusted, git-tracked repo, Copilot CLI's per-edit "accept" prompt is a
lot of clicking — git already provides the safety net (`/diff`, `/rewind`,
`git restore`). PowerShell sessions get a `copilot` function (aliased over
the real CLI, defined in
[`Copilot.ps1`](../home/dot_config/powershell/modules/DotfilesHelpers/Public/Copilot.ps1))
that runs the CLI with `--allow-tool=write`, pre-approving file create/edit
**only**. Shell (`shell`/`bash`) tools stay gated, and MCP tools (e.g.
WorkIQ) are unaffected, so it remains least-privilege.

```powershell
copilot                # runs the CLI with --allow-tool=write
copilot -Raw           # bypasses the wrapper; every tool call prompts
```

The pre-approved tool list is configurable via `$env:COPILOT_ALLOW_TOOLS`
(default `write`), so it can be widened — e.g. to also pre-approve read-only
git commands — or narrowed without editing the function:

```powershell
$env:COPILOT_ALLOW_TOOLS = 'write,shell(git status),shell(git diff)'
```

Never set it to `--allow-all-tools` / `--yolo` equivalents — that grants
shell and URL access too, defeating the purpose of an allow-list.
`Invoke-Copilot` resolves and calls the real `copilot` executable on `PATH`
directly (never itself, avoiding recursion). Note this PowerShell wrapper is
separate from the [1Password shell plugin](#local-authentication-with-the-1password-shell-plugin)
above, which currently only wraps `copilot` in bash/zsh/fish.

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
