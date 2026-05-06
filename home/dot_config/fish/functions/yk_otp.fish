function yk_otp --description "Generate a TOTP code from your YubiKey's OATH applet"
    argparse --name=yk_otp h/help 'serial=' no-copy list -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: yk_otp [OPTIONS] [ACCOUNT-FILTER]"
        echo "Generate a TOTP code from your YubiKey's OATH applet."
        echo ""
        echo "Options:"
        echo "  --serial SN     Target a specific YubiKey by serial"
        echo "  --no-copy       Print the code without copying to clipboard"
        echo "  --list          List account names only (no codes)"
        return 0
    end

    if not command -q ykman
        echo "Error: 'ykman' not found. Install yubikey-manager." >&2
        return 1
    end

    set -l ykman_args
    if set -q _flag_serial
        set ykman_args --device $_flag_serial
    end

    if set -q _flag_list
        ykman $ykman_args oath accounts list
        return $status
    end

    set -l query (string join ' ' -- $argv)
    set -l lines
    if test -n "$query"
        set lines (ykman $ykman_args oath accounts code "$query" 2>/dev/null)
    else
        set lines (ykman $ykman_args oath accounts code 2>/dev/null)
    end
    if test -z "$lines"
        echo "Error: no OATH accounts found (filter: '$query')" >&2
        return 1
    end

    set -l pick
    if test (count $lines) -gt 1
        if command -q fzf; and isatty stdin
            set pick (printf '%s\n' $lines | fzf --prompt='OATH> ' --height=15 --no-multi)
            or return 1
        else
            echo "Multiple accounts match; pass a more specific filter or install fzf:" >&2
            printf '%s\n' $lines >&2
            return 1
        end
    else
        set pick $lines[1]
    end

    set -l code (string split ' ' -- $pick)[-1]
    set -l name (string sub --end=-(math (string length -- $code) + 1) -- $pick)
    if test "$code" = "Touch]"; or test "$code" = "Touch"; or test "$code" = "[Requires"
        echo "Touch your YubiKey for: $name"
        set pick (ykman $ykman_args oath accounts code "$name" 2>/dev/null)[1]
        set code (string split ' ' -- $pick)[-1]
        set name (string sub --end=-(math (string length -- $code) + 1) -- $pick)
    end

    if not string match -qr '^[0-9]{6,8}$' -- $code
        echo "Error: failed to obtain a code (got: '$pick')" >&2
        return 1
    end

    echo "$name: $code"
    if not set -q _flag_no_copy; and functions -q clipboard_copy
        if clipboard_copy --check >/dev/null 2>&1
            printf '%s' $code | clipboard_copy
            echo "(copied to clipboard)"
        end
    end
end
