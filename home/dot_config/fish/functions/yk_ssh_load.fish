function yk_ssh_load --description "Load resident FIDO2 SSH keys from a YubiKey into ssh-agent"
    argparse --name=yk_ssh_load h/help q/quiet -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: yk_ssh_load [--quiet]"
        echo "Load resident FIDO2 SSH keys from a YubiKey into ssh-agent."
        return 0
    end

    if not command -q ssh-add
        echo "Error: ssh-add not found." >&2
        return 1
    end

    if not set -q SSH_AUTH_SOCK
        echo "Error: no ssh-agent running (SSH_AUTH_SOCK is unset)." >&2
        echo "Hint: eval (ssh-agent -c)" >&2
        return 1
    end

    if not set -q _flag_quiet
        echo "Touch your YubiKey when it blinks..."
    end

    if ssh-add -K
        if not set -q _flag_quiet
            echo "Resident keys loaded."
        end
        return 0
    end

    echo "Error: ssh-add -K failed (no resident keys, OpenSSH too old, or wrong PIN)." >&2
    return 1
end
