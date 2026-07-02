function copilot_ssh --description "SSH with COPILOT_GITHUB_TOKEN and GH_TOKEN forwarded from a 1Password Environment"
    # copilot_ssh - SSH into a host with GitHub tokens forwarded from 1Password.
    #
    # Reads COPILOT_GITHUB_TOKEN (for GitHub Copilot CLI) and, if present,
    # GH_TOKEN (for the GitHub CLI) from a 1Password Environment on this
    # (workstation) machine via `op run`, then forwards them to the remote
    # session using SSH SendEnv, so both tools can authenticate on headless
    # servers that have no secure vault. The tokens are never written to disk.
    #
    # The remote sshd must `AcceptEnv COPILOT_GITHUB_TOKEN GH_TOKEN` (handled by
    # the docker repo's system_setup Ansible role). Copilot CLI reads
    # COPILOT_GITHUB_TOKEN (precedence over GH_TOKEN); `gh` reads GH_TOKEN.
    #
    # Requirements:
    #   - 1Password CLI (`op`) >= 2.33.0-beta.02 with the desktop-app integration.
    #   - OP_COPILOT_ENVIRONMENT_ID set to your 1Password Environment ID (from the
    #     chezmoi `opCopilotEnvironmentId` variable). The Environment must contain
    #     COPILOT_GITHUB_TOKEN; GH_TOKEN is optional (forwarded if present).
    #
    # Usage: copilot_ssh [ssh options...] <host>   (e.g. copilot_ssh svldev)

    if contains -- -h $argv; or contains -- --help $argv
        echo "Usage: copilot_ssh [ssh options...] <host>"
        echo "SSH with COPILOT_GITHUB_TOKEN (and GH_TOKEN) forwarded from a 1Password Environment."
        return 0
    end

    if test (count $argv) -eq 0
        echo "copilot_ssh: no destination given." >&2
        echo "Usage: copilot_ssh [ssh options...] <host>   (e.g. copilot_ssh svldev)" >&2
        return 1
    end

    if not command -q op
        echo "copilot_ssh: 'op' (1Password CLI) not found; using plain ssh (no token forwarded)." >&2
        command ssh $argv
        return
    end

    if test -z "$OP_COPILOT_ENVIRONMENT_ID"
        echo "copilot_ssh: OP_COPILOT_ENVIRONMENT_ID is not set (set the chezmoi 'opCopilotEnvironmentId' variable); using plain ssh." >&2
        command ssh $argv
        return
    end

    # Read both tokens in a single `op run` (one 1Password unlock) so the
    # interactive ssh below is not wrapped by op run. `--no-masking` is required
    # because Environment values are hidden by default. Tab-separated because
    # GitHub tokens never contain a tab.
    set -l tab (printf '\t')
    set -l creds (op run --environment "$OP_COPILOT_ENVIRONMENT_ID" --no-masking -- sh -c 'printf "%s\t%s" "${COPILOT_GITHUB_TOKEN:-}" "${GH_TOKEN:-}"' 2>/dev/null)
    set -l op_status $status
    if test $op_status -ne 0
        echo "copilot_ssh: failed to read tokens from 1Password Environment '$OP_COPILOT_ENVIRONMENT_ID'." >&2
        echo "            Ensure 'op' >= 2.33.0-beta.02, the desktop-app integration is enabled, and the Environment ID is correct." >&2
        return 1
    end

    set -l parts (string split -- $tab $creds)
    set -l copilot_token $parts[1]
    set -l gh_token ""
    if test (count $parts) -ge 2
        set gh_token $parts[2]
    end

    if test -z "$copilot_token"
        echo "copilot_ssh: COPILOT_GITHUB_TOKEN not found in Environment '$OP_COPILOT_ENVIRONMENT_ID'." >&2
        return 1
    end

    # Forward COPILOT_GITHUB_TOKEN always; GH_TOKEN only when it is set.
    set -l ssh_env_opts -o SendEnv=COPILOT_GITHUB_TOKEN
    if test -n "$gh_token"
        set -a ssh_env_opts -o SendEnv=GH_TOKEN
    end

    # Export the tokens locally (function-scoped) for the ssh child, and use
    # `command ssh` to avoid any alias/function shadowing (matches the fallback
    # branches above).
    set -lx COPILOT_GITHUB_TOKEN $copilot_token
    set -lx GH_TOKEN $gh_token
    command ssh $ssh_env_opts $argv
end

# Completions: delegate to ssh's own completions for host/option arguments.
complete -c copilot_ssh -w ssh
