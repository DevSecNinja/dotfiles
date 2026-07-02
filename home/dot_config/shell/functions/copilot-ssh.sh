#!/bin/bash
# copilot-ssh - SSH into a host with the GitHub Copilot CLI token forwarded.
#
# Reads COPILOT_GITHUB_TOKEN from a 1Password Environment on this (workstation)
# machine via `op run`, then forwards it to the remote session using SSH
# SendEnv. This lets GitHub Copilot CLI authenticate on headless servers that
# have no secure vault (no gnome-keyring needed). The token is never written to
# disk; it lives only in 1Password, transiently in this function's memory, the
# encrypted SSH channel, and the remote session's environment.
#
# The remote sshd must be configured to `AcceptEnv COPILOT_GITHUB_TOKEN`
# (handled by the docker repo's `system_setup` Ansible role). Copilot CLI reads
# COPILOT_GITHUB_TOKEN natively (it takes precedence over GH_TOKEN and does not
# collide with the `gh` CLI).
#
# Requirements:
#   - 1Password CLI (`op`) >= 2.33.0-beta.02 with the desktop-app integration on.
#   - OP_COPILOT_ENVIRONMENT_ID set to your 1Password Environment ID (rendered
#     from the chezmoi `opCopilotEnvironmentId` variable). The Environment must
#     contain a variable named COPILOT_GITHUB_TOKEN.
#
# Usage: copilot-ssh [ssh options...] <host>
#   e.g. copilot-ssh svldev
#
# If `op` or the Environment ID is unavailable, it falls back to a plain ssh so
# the command still connects (Copilot just won't receive a token).
copilot-ssh() {
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        echo "Usage: copilot-ssh [ssh options...] <host>"
        echo "SSH with COPILOT_GITHUB_TOKEN forwarded from a 1Password Environment."
        return 0
    fi

    if ! command -v op >/dev/null 2>&1; then
        echo "copilot-ssh: 'op' (1Password CLI) not found; using plain ssh (Copilot won't get a token)." >&2
        command ssh "$@"
        return
    fi

    if [ -z "${OP_COPILOT_ENVIRONMENT_ID:-}" ]; then
        echo "copilot-ssh: OP_COPILOT_ENVIRONMENT_ID is not set (set the chezmoi 'opCopilotEnvironmentId' variable); using plain ssh." >&2
        command ssh "$@"
        return
    fi

    # Extract the token first so the *interactive* ssh below is not wrapped by
    # `op run` (which pipes stdout/stderr for masking and can disturb a TTY).
    # `--no-masking` is required because Environment values are hidden by
    # default and would otherwise be printed as "<concealed>".
    local token
    if ! token="$(op run --environment "${OP_COPILOT_ENVIRONMENT_ID}" --no-masking -- printenv COPILOT_GITHUB_TOKEN 2>/dev/null)" || [ -z "${token}" ]; then
        echo "copilot-ssh: failed to read COPILOT_GITHUB_TOKEN from 1Password Environment '${OP_COPILOT_ENVIRONMENT_ID}'." >&2
        echo "            Ensure 'op' >= 2.33.0-beta.02, the desktop-app integration is enabled, and the variable exists." >&2
        return 1
    fi

    COPILOT_GITHUB_TOKEN="${token}" command ssh -o SendEnv=COPILOT_GITHUB_TOKEN "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    copilot-ssh "$@"
fi
