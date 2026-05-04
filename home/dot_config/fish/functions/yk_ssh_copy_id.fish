function yk_ssh_copy_id --description "Push YubiKey SSH pubkey(s) into a remote authorized_keys (idempotent)"
    argparse --name=yk_ssh_copy_id h/help 'i/identity=' 'p/port=' check dry-run -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: yk_ssh_copy_id [OPTIONS] [user@]host"
        echo "Push YubiKey SSH pubkey(s) into a remote authorized_keys (idempotent)."
        echo ""
        echo "Options:"
        echo "  -i, --identity PATH    Push only this specific .pub file (default: all"
        echo "                         id_*_sk*.pub files in ~/.ssh)"
        echo "  -p, --port N           SSH port (default: 22)"
        echo "  --check                Connect and report which keys are already authorized"
        echo "  --dry-run              Print the keys that would be pushed; don't connect"
        return 0
    end

    set -l port 22
    set -q _flag_port; and set port $_flag_port
    set -l check false
    set -q _flag_check; and set check true
    set -l dry_run false
    set -q _flag_dry_run; and set dry_run true

    if test (count $argv) -gt 1
        echo "Error: only one [user@]host argument allowed (got: $argv)" >&2
        return 1
    end
    set -l target ""
    test (count $argv) -eq 1; and set target $argv[1]

    if test -z "$target"; and test "$dry_run" != true
        echo "Error: missing [user@]host argument. See --help." >&2
        return 1
    end

    # Collect the set of pubkeys to push.
    set -l keys
    if set -q _flag_identity
        if not test -f "$_flag_identity"
            echo "Error: --identity file not found: $_flag_identity" >&2
            return 1
        end
        set keys $_flag_identity
    else
        for pat in 'id_ed25519_sk_*' 'id_ed25519_sk' 'id_ecdsa_sk_*' 'id_ecdsa_sk'
            for candidate in (find "$HOME/.ssh" -maxdepth 1 -name "$pat.pub" -type f 2>/dev/null | sort)
                if test -n "$candidate"; and test -f "$candidate"
                    set keys $keys $candidate
                end
            end
        end
    end

    if test (count $keys) -eq 0
        echo "Error: no YubiKey pubkey found in ~/.ssh. Run \`yk_enroll\` first." >&2
        return 1
    end

    # Build the payload (blank lines stripped).
    set -l payload ""
    for k in $keys
        set payload "$payload"(grep -vE '^[[:space:]]*$' $k)\n
    end

    if test "$dry_run" = true
        echo "Would push "(count $keys)" pubkey(s)"(test -n "$target"; and echo " to $target")":"
        for k in $keys
            echo "  - $k"
        end
        echo ""
        echo "Payload:"
        printf '%s' $payload
        return 0
    end

    if not command -q ssh
        echo "Error: ssh not found." >&2
        return 1
    end

    set -l remote_install '
set -e
umask 077
mkdir -p ~/.ssh
touch ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
existing="$(cat ~/.ssh/authorized_keys 2>/dev/null || true)"
new=0
present=0
while IFS= read -r line; do
\t[ -z "$line" ] && continue
\tif printf "%s\\n" "$existing" | grep -qFx -- "$line"; then
\t\tpresent=$((present + 1))
\telse
\t\tprintf "%s\\n" "$line" >>~/.ssh/authorized_keys
\t\tnew=$((new + 1))
\tfi
done
echo "yk-ssh-copy-id: $new added, $present already present" >&2
'
    set -l remote_check '
set -e
existing=""
[ -f ~/.ssh/authorized_keys ] && existing="$(cat ~/.ssh/authorized_keys)"
new=0
present=0
while IFS= read -r line; do
\t[ -z "$line" ] && continue
\tif printf "%s\\n" "$existing" | grep -qFx -- "$line"; then
\t\techo "[OK]   $line"
\t\tpresent=$((present + 1))
\telse
\t\techo "[MISS] $line"
\t\tnew=$((new + 1))
\tfi
done
echo "yk-ssh-copy-id: $present already present, $new missing" >&2
'
    set -l script "$remote_install"
    test "$check" = true; and set script "$remote_check"

    printf '%s' $payload | ssh -T -p $port $target "/bin/sh -c '$script'"
end
