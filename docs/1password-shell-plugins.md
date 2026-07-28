# 🔐 1Password shell plugins

[1Password shell plugins][opsp] let a CLI authenticate with your fingerprint
instead of a long-lived token sitting in a plaintext config file. Running
`gh`, for example, prompts 1Password for approval and injects the credential
into that single command's environment — nothing is written to disk.

## Why this repo defines the wrappers itself

By default `op plugin init` writes shell functions to
`~/.config/op/plugins.sh` and manages that file for you. That file is outside
version control, so a new machine silently loses the configuration.

1Password documents an alternative: [define the wrapper functions yourself and
track them in your dotfiles][opdotfiles]. That is what this repo does.

| | `op plugin init` default | This repo |
| --- | --- | --- |
| Wrapper location | `~/.config/op/plugins.sh` | `~/.config/shell/functions/op-plugins.sh`, `~/.config/fish/conf.d/op-plugins.fish` |
| Tracked in git | ❌ | ✅ (generated from chezmoi templates) |
| New machine | re-run `op plugin init` per CLI | wrappers apply with `chezmoi apply` |

`OP_PLUGIN_ALIASES_SOURCED=1` is exported alongside the wrappers, which tells
1Password CLI the aliases are already set up so it stops asking you to source
`plugins.sh`.

## Which CLIs are wrapped

The list comes from the chezmoi `opShellPlugins` variable and defaults to:

- **`gh`** — [GitHub CLI][opgh]
- **`copilot`** — [GitHub Copilot CLI][opcopilot], which the plugin
  authenticates with a `COPILOT_GITHUB_TOKEN`

Override it per machine in your local chezmoi config, as a list:

```yaml
data:
  opShellPlugins:
    - gh
    - copilot
    - aws
```

or as a comma-separated string (trimmed, de-duplicated and sorted for you):

```yaml
data:
  opShellPlugins: "gh, copilot, aws"
```

Then re-run `chezmoi apply`. Run `op plugin list` to see the 60+ supported
CLIs.

## First-time setup per CLI

The wrappers only decide *how* a CLI is invoked. You still tell 1Password
*which* item holds the credential, once per CLI and machine:

```bash
op signin
op plugin init gh
```

You will be asked to import a new item or pick an existing one, then choose
when the credential applies (this terminal session, this directory tree, or
globally).

Useful follow-ups:

```bash
op plugin inspect gh   # show configured credentials and scopes
op plugin clear gh     # reset the credential defaults
```

After importing a credential into 1Password, delete any plaintext copy that is
still lying around (for example `~/.config/gh/hosts.yml`).

## Safety rails

The generated wrappers are deliberately defensive, because a wrapper that
cannot run would otherwise *replace* a working CLI:

- **No `op`, no wrappers.** If the 1Password CLI is not on `PATH`, nothing is
  defined at all and every CLI behaves normally.
- **Only installed CLIs are wrapped.** Defining a `gh` function on a machine
  without `gh` would make `command -v gh` succeed and break the usual
  "is it installed?" checks, so each wrapper is guarded on the real CLI
  existing.
- **Completions keep working.** The fish wrappers use `--wraps`, and the
  bash/zsh completion files load *before* the wrappers, so generating
  completions never triggers a 1Password prompt at shell startup.

## WSL is not supported

`op plugin run` refuses to run under WSL — you get *"Shell Plugins are
currently not supported on this operating system"* (tracked upstream in
[1Password/shell-plugins#402][issue402]). Wrapping a CLI with a command that
always fails is worse than not wrapping it, so chezmoi skips both wrapper
files on WSL hosts via `.chezmoiignore`.

WSL still reaches 1Password for SSH and Git signing through the Windows host —
see [wsl.md](wsl.md).

[opsp]: https://developer.1password.com/docs/cli/shell-plugins/
[opdotfiles]: https://github.com/1Password/shell-plugins#managing-shell-plugins-in-your-own-dotfiles
[opgh]: https://www.1password.dev/cli/shell-plugins/github
[opcopilot]: https://www.1password.dev/cli/shell-plugins/github-copilot
[issue402]: https://github.com/1Password/shell-plugins/issues/402
