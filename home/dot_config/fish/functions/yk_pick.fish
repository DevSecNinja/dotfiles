function yk_pick --description "Print the serial of a connected YubiKey"
    argparse --name=yk_pick h/help first -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: yk_pick [--first]"
        return 0
    end

    if not command -q ykman
        echo "Error: 'ykman' not found." >&2
        return 1
    end

    set -l serials (ykman list --serials 2>/dev/null)
    if test -z "$serials"
        echo "Error: no YubiKey detected." >&2
        return 1
    end

    if test (count $serials) -eq 1; or set -q _flag_first
        echo $serials[1]
        return 0
    end

    if command -q fzf; and isatty stdin
        set -l pick (printf '%s\n' $serials | fzf --prompt='YubiKey> ' --height=10 --no-multi)
        or return 1
        echo $pick
        return 0
    end

    echo "Error: multiple YubiKeys connected; pass --serial or install fzf:" >&2
    printf '%s\n' $serials >&2
    return 1
end
