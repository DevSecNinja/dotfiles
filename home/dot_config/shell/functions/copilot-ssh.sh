#!/bin/bash
# copilot-ssh - SSH into a host with GitHub tokens forwarded from 1Password.
#
# Reads COPILOT_GITHUB_TOKEN (for GitHub Copilot CLI) and, if present, GH_TOKEN
# (for the GitHub CLI) from a 1Password Environment on this (workstation)
# machine via `op run`, then forwards them to the remote session using SSH
# SendEnv. This lets both tools authenticate on headless servers that have no
# secure vault (no gnome-keyring needed). The tokens are never written to disk;
# they live only in 1Password, transiently in this function's memory, the
# encrypted SSH channel, and the remote session's environment.
#
# The remote sshd must `AcceptEnv COPILOT_GITHUB_TOKEN GH_TOKEN` (handled by the
# docker repo's `system_setup` Ansible role). Copilot CLI reads
# COPILOT_GITHUB_TOKEN (precedence over GH_TOKEN); the `gh` CLI reads GH_TOKEN.
# Using separate variables keeps each tool's token independently scoped.
#
# Requirements:
#   - 1Password CLI (`op`) >= 2.33.0-beta.02 with the desktop-app integration on.
#   - OP_COPILOT_ENVIRONMENT_ID set to your 1Password Environment ID (rendered
#     from the chezmoi `opCopilotEnvironmentId` variable). The Environment must
#     contain COPILOT_GITHUB_TOKEN; GH_TOKEN is optional (forwarded if present).
#
# Usage: copilot-ssh [ssh options...] <host>
#   e.g. copilot-ssh svldev
#
# If `op` or the Environment ID is unavailable, it falls back to a plain ssh so
# the command still connects (the tools just won't receive a token).
copilot-ssh() {
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        echo "Usage: copilot-ssh [ssh options...] <host>"
        echo "SSH with COPILOT_GITHUB_TOKEN (and GH_TOKEN) forwarded from a 1Password Environment."
        return 0
    fi

    if [ "$#" -eq 0 ]; then
        echo "copilot-ssh: no destination given." >&2
        echo "Usage: copilot-ssh [ssh options...] <host>   (e.g. copilot-ssh svldev)" >&2
        return 1
    fi

    if ! command -v op >/dev/null 2>&1; then
        echo "copilot-ssh: 'op' (1Password CLI) not found; using plain ssh (no token forwarded)." >&2
        command ssh "$@"
        return
    fi

    if [ -z "${OP_COPILOT_ENVIRONMENT_ID:-}" ]; then
        echo "copilot-ssh: OP_COPILOT_ENVIRONMENT_ID is not set (set the chezmoi 'opCopilotEnvironmentId' variable); using plain ssh." >&2
        command ssh "$@"
        return
    fi

    # Read both tokens in a single `op run` (one 1Password unlock) so the
    # *interactive* ssh below is not wrapped by op run, whose stdout/stderr
    # masking can disturb a TTY. `--no-masking` is required because Environment
    # values are hidden by default and would otherwise be returned as
    # "<concealed>". Tab-separated because GitHub tokens never contain a tab.
    local creds
    # SC2016: the ${…} expansions are intentionally single-quoted so they expand
    # inside the remote `sh -c`, reading the 1Password Environment values loaded
    # by `op run` — not in this local shell.
    # shellcheck disable=SC2016
    if ! creds="$(op run --environment "${OP_COPILOT_ENVIRONMENT_ID}" --no-masking -- \
        sh -c 'printf "%s\t%s" "${COPILOT_GITHUB_TOKEN:-}" "${GH_TOKEN:-}"' 2>/dev/null)"; then
        echo "copilot-ssh: failed to read tokens from 1Password Environment '${OP_COPILOT_ENVIRONMENT_ID}'." >&2
        echo "            Ensure 'op' >= 2.33.0-beta.02 and the desktop-app integration is enabled." >&2
        return 1
    fi

    local copilot_token="${creds%%$'\t'*}"
    local gh_token="${creds#*$'\t'}"

    if [ -z "${copilot_token}" ]; then
        echo "copilot-ssh: COPILOT_GITHUB_TOKEN not found in Environment '${OP_COPILOT_ENVIRONMENT_ID}'." >&2
        return 1
    fi

    # Forward COPILOT_GITHUB_TOKEN always; GH_TOKEN only when it is set.
    local -a ssh_env_opts=(-o SendEnv=COPILOT_GITHUB_TOKEN)
    if [ -n "${gh_token}" ]; then
        ssh_env_opts+=(-o SendEnv=GH_TOKEN)
    fi

    COPILOT_GITHUB_TOKEN="${copilot_token}" GH_TOKEN="${gh_token}" \
        command ssh "${ssh_env_opts[@]}" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    copilot-ssh "$@"
fi
