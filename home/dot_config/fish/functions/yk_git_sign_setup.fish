function yk_git_sign_setup --description "Configure git to sign commits with your YubiKey SSH key"
    argparse --name=yk_git_sign_setup h/help 'k/key=' 'add=' 'principal=' check -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: yk_git_sign_setup [OPTIONS]"
        echo "Configure git to sign commits with your YubiKey SSH key."
        echo ""
        echo "Options:"
        echo "  -k, --key PATH         Public key to register as your signer"
        echo "                         (default: register every per-serial pubkey"
        echo "                         found in ~/.ssh, e.g. id_*_sk_<serial>.pub)"
        echo "  --add PATH             Add another principal's public key"
        echo "  --principal STR        Principal (email) to pair with --add"
        echo "  --check                Exit 0 if signing is configured, 1 otherwise"
        return 0
    end

    if not command -q git
        echo "Error: git not found." >&2
        return 1
    end

    set -l allowed_signers "$HOME/.config/git/allowed_signers"
    if set -q ALLOWED_SIGNERS_FILE
        set allowed_signers $ALLOWED_SIGNERS_FILE
    end

    if set -q _flag_check
        set -l fmt (git config --get gpg.format 2>/dev/null)
        set -l sign (git config --get commit.gpgsign 2>/dev/null)
        set -l signer (git config --get user.signingkey 2>/dev/null)
        if test "$fmt" = ssh; and test "$sign" = true; and test -n "$signer"
            echo "ssh signing: ON  signingkey=$signer"
            return 0
        end
        echo "ssh signing: OFF (gpg.format='$fmt' commit.gpgsign='$sign' signingkey='$signer')" >&2
        return 1
    end

    mkdir -p (dirname $allowed_signers)
    test -f $allowed_signers; or printf '# Managed by yk_git_sign_setup\n' >$allowed_signers

    if set -q _flag_add
        if not test -f $_flag_add
            echo "Error: --add file not found: $_flag_add" >&2
            return 1
        end
        if not set -q _flag_principal
            echo "Error: --principal <email> is required with --add" >&2
            return 1
        end
        set -l pubkey (cat $_flag_add)
        if grep -Fq -- "$pubkey" $allowed_signers 2>/dev/null
            echo "Already present: $_flag_principal"
            return 0
        end
        printf '%s %s\n' $_flag_principal "$pubkey" >>$allowed_signers
        echo "Added principal $_flag_principal -> $allowed_signers"
        return 0
    end

    set -l email (git config --get user.email 2>/dev/null)
    if test -z "$email"
        echo "Error: git config user.email is not set." >&2
        return 1
    end

    # Collect the set of pubkeys to register.
    set -l keys
    if set -q _flag_key
        if not test -f $_flag_key
            echo "Error: --key file not found: $_flag_key" >&2
            return 1
        end
        set keys $_flag_key
    else
        for pattern in \
                "$HOME/.ssh/id_ed25519_sk_"*.pub \
                "$HOME/.ssh/id_ecdsa_sk_"*.pub \
                "$HOME/.ssh/id_ed25519_sk.pub" \
                "$HOME/.ssh/id_ecdsa_sk.pub" \
                "$HOME/.ssh/id_ed25519.pub"
            for candidate in $pattern
                if test -f "$candidate"
                    set keys $keys $candidate
                end
            end
        end
    end
    if test (count $keys) -eq 0
        echo "Error: no public key found. Run \`yk_enroll\` first." >&2
        return 1
    end

    for key in $keys
        set -l pubkey (cat $key)
        if grep -Fq -- "$pubkey" $allowed_signers 2>/dev/null
            echo "Already registered: $key"
        else
            printf '%s %s\n' $email "$pubkey" >>$allowed_signers
            echo "Registered $key for $email"
        end
    end

    set -l fmt (git config --get gpg.format 2>/dev/null)
    set -l sign (git config --get commit.gpgsign 2>/dev/null)
    set -l signer (git config --get user.signingkey 2>/dev/null)
    echo
    echo "Current git signing config:"
    echo "  gpg.format        = $fmt"
    echo "  commit.gpgsign    = $sign"
    echo "  user.signingkey   = $signer"
    if test "$fmt" != ssh; or test "$sign" != true; or test -z "$signer"
        echo
        echo "Hint: set chezmoi data 'useYubiKey: true' and run \`chezmoi apply\`"
        echo "      to wire ~/.config/git/config for SSH signing."
        return 1
    end

    echo
    echo "Required next step: upload each pubkey to GitHub as both an"
    echo "  authentication AND signing key (signing isn't useful otherwise):"
    for key in $keys
        echo "    gh ssh-key add $key --type authentication --title \"<descriptive title>\""
        echo "    gh ssh-key add $key --type signing       --title \"<descriptive title>\""
    end
    echo "  Or via the GitHub UI:  https://github.com/settings/keys"
end
