function yk_ssh_new --description "Generate a hardware-backed SSH key on a YubiKey"
    argparse --name=yk_ssh_new h/help 't/type=' no-resident no-verify-required no-summary \
        'o/output=' 'application=' 'C/comment=' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: yk_ssh_new [OPTIONS]"
        echo "Generate a hardware-backed SSH key on a YubiKey."
        echo ""
        echo "Options:"
        echo "  --type {ed25519-sk|ecdsa-sk}   Key type (default: ed25519-sk)"
        echo "  --no-resident                  Don't store credential on the key"
        echo "  --no-verify-required           Don't require PIN (touch only)"
        echo "  --no-summary                   Don't print the 'Next steps' footer (used"
        echo "                                 by yk_enroll, which prints its own)."
        echo "  -o, --output PATH              Output path (default: ~/.ssh/id_<type>)"
        echo "  --application STR              FIDO application (default: ssh:<hostname>)"
        echo "  -C, --comment STR              SSH key comment (default: user@host)"
        return 0
    end

    set -l type ed25519-sk
    set -q _flag_type; and set type $_flag_type

    switch $type
        case ed25519-sk ecdsa-sk
        case '*'
            echo "Error: --type must be ed25519-sk or ecdsa-sk" >&2
            return 1
    end

    set -l output "$HOME/.ssh/id_$(string replace - _ -- $type)"
    set -q _flag_output; and set output $_flag_output

    set -l hostshort (hostname -s 2>/dev/null; or hostname)
    set -l application "ssh:$hostshort"
    set -q _flag_application; and set application $_flag_application
    if not string match -q 'ssh:*' -- $application
        echo "Error: --application must start with 'ssh:'" >&2
        return 1
    end

    set -l comment "$USER@$hostshort"
    set -q _flag_comment; and set comment $_flag_comment

    if not command -q ssh-keygen
        echo "Error: ssh-keygen not found." >&2
        return 1
    end

    # macOS guard: Apple's bundled OpenSSH lacks libfido2 / SecurityKeyProvider.
    if test (uname) = Darwin
        set -l sshkeygen_path (command -v ssh-keygen)
        if test "$sshkeygen_path" = /usr/bin/ssh-keygen; or test "$sshkeygen_path" = /usr/sbin/ssh-keygen
            echo "Error: Apple's bundled ssh-keygen at $sshkeygen_path lacks FIDO2 support." >&2
            echo "       The error 'No FIDO SecurityKeyProvider specified' / 'invalid format'" >&2
            echo "       comes from this. Install Homebrew's OpenSSH and put it ahead of /usr/bin:" >&2
            echo "" >&2
            echo "         brew install openssh" >&2
            set -l brew_prefix ""
            if command -q brew
                set brew_prefix (brew --prefix 2>/dev/null)
            else if test -x /opt/homebrew/bin/brew
                set brew_prefix /opt/homebrew
            else if test -x /usr/local/bin/brew
                set brew_prefix /usr/local
            end
            if test -n "$brew_prefix"
                echo "         fish_add_path -m $brew_prefix/bin" >&2
            else
                echo "         fish_add_path -m /opt/homebrew/bin   # Apple Silicon" >&2
                echo "         fish_add_path -m /usr/local/bin      # Intel" >&2
            end
            echo "" >&2
            echo "       Then re-run yk_ssh_new." >&2
            return 1
        end
    end

    mkdir -p (dirname $output)
    chmod 700 (dirname $output) 2>/dev/null

    if test -e $output
        echo "Error: $output already exists. Choose another --output or remove it." >&2
        return 1
    end

    set -l args -t $type -f $output -C $comment -O "application=$application"
    if not set -q _flag_no_resident
        set args $args -O resident
    end
    if not set -q _flag_no_verify_required
        set args $args -O verify-required
    end

    echo "Generating $type key (touch your YubiKey when it blinks)..."
    echo "  Output:      $output"
    echo "  Application: $application"
    echo

    if not ssh-keygen $args
        echo "Error: ssh-keygen failed." >&2
        return 1
    end

    echo
    echo "Public key:"
    cat "$output.pub"
    if set -q _flag_no_summary
        return 0
    end
    echo
    echo "Next steps:"
    echo "  1. Add to GitHub:    gh ssh-key add $output.pub --title \"<descriptive title>\""
    echo "  2. Test it:          ssh -T git@github.com  # AddKeysToAgent in ~/.ssh/config handles ssh-add automatically"
    if not set -q _flag_no_resident
        echo "  3. On new machines:  ssh-add -K   # reload from YubiKey"
    end
end
