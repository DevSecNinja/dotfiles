function copilot_ssh --description "SSH with COPILOT_GITHUB_TOKEN forwarded from a 1Password Environment"
    # copilot_ssh - SSH into a host with the GitHub Copilot CLI token forwarded.
    #
    # Reads COPILOT_GITHUB_TOKEN from a 1Password Environment on this
    # (workstation) machine via `op run`, then forwards it to the remote session
    # using SSH SendEnv, so GitHub Copilot CLI can authenticate on headless
    # servers that have no secure vault. The token is never written to disk.
    #
    # The remote sshd must `AcceptEnv COPILOT_GITHUB_TOKEN` (handled by the
    # docker repo's system_setup Ansible role). Copilot CLI reads
    # COPILOT_GITHUB_TOKEN natively (precedence over GH_TOKEN; no `gh` clash).
    #
    # Requirements:
    #   - 1Password CLI (`op`) >= 2.33.0-beta.02 with the desktop-app integration.
    #   - OP_COPILOT_ENVIRONMENT_ID set to your 1Password Environment ID (from the
    #     chezmoi `opCopilotEnvironmentId` variable). The Environment must contain
    #     a variable named COPILOT_GITHUB_TOKEN.
    #
    # Usage: copilot_ssh [ssh options...] <host>   (e.g. copilot_ssh svldev)

    if contains -- -h $argv; or contains -- --help $argv
        echo "Usage: copilot_ssh [ssh options...] <host>"
        echo "SSH with COPILOT_GITHUB_TOKEN forwarded from a 1Password Environment."
        return 0
    end

    if not command -q op
        echo "copilot_ssh: 'op' (1Password CLI) not found; using plain ssh (Copilot won't get a token)." >&2
        command ssh $argv
        return
    end

    if test -z "$OP_COPILOT_ENVIRONMENT_ID"
        echo "copilot_ssh: OP_COPILOT_ENVIRONMENT_ID is not set (set the chezmoi 'opCopilotEnvironmentId' variable); using plain ssh." >&2
        command ssh $argv
        return
    end

    # Extract the token first so the interactive ssh below is not wrapped by
    # `op run`. `--no-masking` is required because Environment values are hidden
    # by default and would otherwise be returned as "<concealed>".
    set -l token (op run --environment "$OP_COPILOT_ENVIRONMENT_ID" --no-masking -- printenv COPILOT_GITHUB_TOKEN 2>/dev/null)
    if test -z "$token"
        echo "copilot_ssh: failed to read COPILOT_GITHUB_TOKEN from 1Password Environment '$OP_COPILOT_ENVIRONMENT_ID'." >&2
        echo "            Ensure 'op' >= 2.33.0-beta.02, the desktop-app integration is enabled, and the variable exists." >&2
        return 1
    end

    env COPILOT_GITHUB_TOKEN="$token" ssh -o SendEnv=COPILOT_GITHUB_TOKEN $argv
end

# Completions: delegate to ssh's own completions for host/option arguments.
complete -c copilot_ssh -w ssh
