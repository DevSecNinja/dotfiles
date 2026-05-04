function yk_ssh_new --description "Generate a hardware-backed SSH key on a YubiKey"
    argparse --name=yk_ssh_new h/help 't/type=' no-resident no-verify-required \
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
    echo
    echo "Next steps:"
    echo "  1. Add to GitHub:    gh ssh-key add $output.pub --title \"$hostshort-yk\""
    echo "  2. Add to ssh-agent: ssh-add $output"
    if not set -q _flag_no_resident
        echo "  3. On new machines:  ssh-add -K   # reload from YubiKey"
    end
end
