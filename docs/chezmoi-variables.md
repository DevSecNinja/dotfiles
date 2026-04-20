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
