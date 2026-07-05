#!/usr/bin/env bash
# Re-point chezmoi at this workspace when developing the dotfiles repo itself.
#
# Why this exists:
#   * The prebuilt devcontainer image (ghcr.io/devsecninja/dotfiles-devcontainer)
#     is shared across multiple projects and bakes a chezmoi install that points
#     at ~/.dotfiles.
#   * The user-level VS Code "dotfiles" feature also clones a fresh copy to
#     ~/.dotfiles and runs `chezmoi init` against it *after* postCreateCommand.
#   Both leave chezmoi's sourceDir at ~/.dotfiles, so edits made in this checked
#   out workspace (/workspaces/dotfiles) are never the source of truth.
#
# This script runs from postStartCommand (after the dotfiles install) and
# re-points chezmoi's sourceDir at the workspace so `chezmoi apply` / `diff` /
# `update` and autoloaded functions reflect what you are editing here.
set -eu

workspace_home="${1:-/workspaces/dotfiles/home}"

# Prefer the mise-managed chezmoi (pinned by .chezmoiversion) over any older
# fallback binary in ~/.local/bin so re-pointing at the workspace doesn't trip
# the "source state requires chezmoi version X" guard.
export PATH="${HOME}/.local/share/mise/shims:${HOME}/.local/bin:${PATH}"

if ! command -v chezmoi >/dev/null 2>&1; then
    echo "[postStart] chezmoi not on PATH; skipping source re-point" >&2
    exit 0
fi

if [ ! -d "${workspace_home}" ]; then
    echo "[postStart] '${workspace_home}' not found; skipping source re-point" >&2
    exit 0
fi

current_source="$(chezmoi source-path 2>/dev/null || true)"
if [ "${current_source}" = "${workspace_home}" ]; then
    echo "[postStart] chezmoi source already points at ${workspace_home}"
    exit 0
fi

echo "[postStart] Re-pointing chezmoi source: ${current_source:-<unset>} -> ${workspace_home}"
# init (without --apply) only regenerates the config from .chezmoi.yaml.tmpl,
# which persists `sourceDir: {{ .chezmoi.sourceDir }}`. Data is read from the
# existing chezmoi state DB, so this is non-interactive and side-effect free.
chezmoi init --no-tty --source="${workspace_home}"

echo "[postStart] Done. chezmoi now sources from the workspace."
echo "[postStart] Use 'chezmoi diff' to preview and 'chezmoi apply' to sync."
