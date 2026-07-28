# 🔧 Chezmoi Variables

The dotfiles repository provides several variables that can be used in
templates and scripts.

## User Information

- `firstname` / `lastname` / `name` — Your name (prompted on first run).
- `username` — System username (prompted on first run).
- `email` — Your email address (prompted on first run).
- `githubUsername` — Your GitHub username (auto-detected from email or
  git remote).

## Environment Detection

- `codespaces` — Running in GitHub Codespaces (`true` / `false`).
- `devcontainer` — Running in a dev container (`true` / `false`).
- `wsl` — Running in Windows Subsystem for Linux (`true` / `false`).
- `ci` — Running in CI environment (`true` / `false`).
- `installType` — Installation mode (`light` or `full`).

## Hardware tokens

- `useYubiKey` — When `true`, the SSH config is wired for a hardware-backed
  FIDO2 key (`~/.ssh/id_ed25519_sk`) and the 1Password SSH agent include is
  skipped. Defaults to `false` to preserve the existing 1Password flow.
  See [yubikey.md](yubikey.md) for the provisioning workflow.

## GitHub Copilot CLI

- `opCopilotEnvironmentId` — The [1Password Environment][openv] ID that holds the
  `COPILOT_GITHUB_TOKEN` (and optional `GH_TOKEN`) variables. Used by the
  `copilot-ssh` / `copilot_ssh` helper to forward the tokens to headless servers
  over SSH. This is a **non-secret** identifier (useless without authenticating
  to 1Password), so a shared default is hardcoded in `.chezmoi.yaml.tmpl`.
  Override it per-machine by setting `opCopilotEnvironmentId` in your local
  chezmoi config or at the interactive init prompt. Exported to your shell as
  `OP_COPILOT_ENVIRONMENT_ID`. See [copilot-cli.md](copilot-cli.md).
- `copilotSshHost` — The SSH host used by the Windows Terminal "Copilot SSH"
  profile that runs the `copilot-ssh` PowerShell helper. Defaults to
  `svlazdev.<privateDomain>` when `privateDomain` is set, otherwise `svlazdev`.
  Override it per-machine by setting `copilotSshHost` in your local chezmoi
  config or at the interactive init prompt.

[openv]: https://www.1password.dev/environments

## 1Password shell plugins

- `opShellPlugins` — CLIs wrapped by a [1Password shell plugin][opsp] so they
  authenticate with biometrics instead of a token on disk. Defaults to
  `["gh", "copilot"]`. Accepts either a YAML list or a comma-separated string
  in your local chezmoi config (the string form is trimmed, de-duplicated and
  sorted). Not prompted. Each entry still needs a one-off
  `op plugin init <cli>`, and the wrappers are skipped entirely on WSL, where
  shell plugins are unsupported.
  See [1password-shell-plugins.md](1password-shell-plugins.md).

[opsp]: https://developer.1password.com/docs/cli/shell-plugins/

## Git commit signing

- `gitSigningKey` — The SSH **public** key used to sign Git commits when the
  1Password SSH agent drives signing (notably in WSL, where signing runs
  through `op-ssh-sign-wsl.exe`). Paste the literal key from the 1Password app
  — *item → ⋮ → Configure Commit Signing → Copy Snippet* — for example
  `ssh-ed25519 AAAA… comment`. A public key is not a secret. Empty by default,
  which leaves signing off; ignored when `useYubiKey` is `true`, since the
  YubiKey flow derives its key from `~/.ssh/id_*_sk*.pub` instead.
  See [wsl.md](wsl.md).
- `opSshSignProgram` — Explicit path to the 1Password SSH signer used in WSL.
  Empty by default, which auto-detects the MSIX `WindowsApps` path and then the
  pre-8.11.18 one. Set it only for a non-standard 1Password install. When no
  signer is found, signing stays off rather than breaking every `git commit`.

## Windows Enterprise (Windows and WSL)

- `isEntraIDJoined` — Device is Entra ID (Azure AD) joined.
- `isIntuneJoined` — Device is Intune (MDM) enrolled.
- `isEntraRegistered` — Device is Entra ID registered / workplace joined.
- `isADDomainJoined` — Device is Active Directory domain joined.
- `entraIDTenantName` — Entra ID tenant name (for example, `Microsoft`).
- `entraIDTenantId` — Entra ID tenant ID (GUID).
- `isWork` — Device is joined to a `*Microsoft` tenant.

## Shell Environment Variables

These variables are also exposed as environment variables in your shell:

- **PowerShell**: `$env:CHEZMOI_*`
  (for example, `$env:CHEZMOI_IS_ENTRA_ID_JOINED`,
  `$env:CHEZMOI_ENTRA_ID_TENANT_NAME`).
- **Bash / Zsh**: `$CHEZMOI_*`
  (for example, `$CHEZMOI_IS_ENTRA_ID_JOINED`,
  `$CHEZMOI_ENTRA_ID_TENANT_NAME`).
- **Fish**: `$CHEZMOI_*`
  (for example, `$CHEZMOI_IS_ENTRA_ID_JOINED`,
  `$CHEZMOI_ENTRA_ID_TENANT_NAME`).

Additionally, when set, `opCopilotEnvironmentId` is exported as
`OP_COPILOT_ENVIRONMENT_ID` (PowerShell: `$env:OP_COPILOT_ENVIRONMENT_ID`).
