#!/bin/bash
# copilot-ssh-proxy - an `ssh` drop-in for VS Code Remote-SSH.
#
# VS Code Remote-SSH connects with its own `ssh` invocation, so it never goes
# through the interactive `copilot-ssh` / `copilot_ssh` helper. Point VS Code at
# this script via the "remote.SSH.path" setting and it will forward the GitHub
# Copilot CLI / gh tokens (from a 1Password Environment) into the connection for
# matching dev hosts, so the VS Code Server - and every integrated terminal and
# dev container it spawns - is authenticated. All other hosts get a plain ssh.
#
# It is deliberately scoped to hosts matching COPILOT_SSH_HOST_PATTERN (default
# "svl") so unrelated SSH connections don't trigger a 1Password unlock.
#
# Requirements (same as copilot-ssh):
#   - 1Password CLI (`op`) >= 2.33.0-beta.02 with the desktop-app integration on.
#   - OP_COPILOT_ENVIRONMENT_ID set (from the chezmoi opCopilotEnvironmentId var),
#     with a COPILOT_GITHUB_TOKEN variable (and optional GH_TOKEN) in the
#     Environment.
#
# VS Code setting (macOS example):
#   "remote.SSH.path": "/Users/<you>/.local/bin/copilot-ssh-proxy.sh"
#
# See docs/copilot-cli.md.

host_pattern="${COPILOT_SSH_HOST_PATTERN:-svl}"

# Does any non-option argument (i.e. the destination) match the dev-host pattern?
_matches_dev_host=0
for _arg in "$@"; do
    case "${_arg}" in
    -*) ;; # option flag - ignore
    *"${host_pattern}"*) _matches_dev_host=1 ;;
    *) ;; # non-matching destination or value
    esac
done

# Only inject tokens for matching hosts when 1Password is available; otherwise
# behave exactly like plain ssh.
if [ "${_matches_dev_host}" -eq 1 ] &&
    [ -n "${OP_COPILOT_ENVIRONMENT_ID:-}" ] &&
    command -v op >/dev/null 2>&1; then
    # Single `op run` (one unlock); --no-masking because Environment values are
    # hidden by default. Tab-separated: GitHub tokens never contain a tab.
    # shellcheck disable=SC2016
    if creds="$(op run --environment "${OP_COPILOT_ENVIRONMENT_ID}" --no-masking -- \
        sh -c 'printf "%s\t%s" "${COPILOT_GITHUB_TOKEN:-}" "${GH_TOKEN:-}"' 2>/dev/null)"; then
        copilot_token="${creds%%$'\t'*}"
        gh_token="${creds#*$'\t'}"
        if [ -n "${copilot_token}" ]; then
            export COPILOT_GITHUB_TOKEN="${copilot_token}"
            ssh_env_opts=(-o SendEnv=COPILOT_GITHUB_TOKEN)
            if [ -n "${gh_token}" ]; then
                export GH_TOKEN="${gh_token}"
                ssh_env_opts+=(-o SendEnv=GH_TOKEN)
            fi
            exec ssh "${ssh_env_opts[@]}" "$@"
        fi
    fi
fi

exec ssh "$@"
