function yk_status --description "One-glance health check for connected YubiKey(s)"
    argparse --name=yk_status h/help json 's/serial=' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: yk_status [--json] [--serial SN]"
        echo "Show status of connected YubiKey(s)."
        return 0
    end

    if not command -q ykman
        echo "Error: 'ykman' not found. Install yubikey-manager." >&2
        return 1
    end

    set -l serials (ykman list --serials 2>/dev/null)
    if test -z "$serials"
        echo "No YubiKey detected."
        return 1
    end

    if set -q _flag_serial
        set serials $_flag_serial
    end

    set -l first true
    if set -q _flag_json
        printf '['
    end

    for serial in $serials
        test -z "$serial"; and continue
        set -l info (ykman --device $serial info 2>/dev/null)
        if test -z "$info"
            echo "Error: failed to query device $serial" >&2
            continue
        end
        set -l fw (printf '%s\n' $info | awk -F': *' 'tolower($1) ~ /firmware version/ {print $2; exit}')
        set -l form_factor (printf '%s\n' $info | awk -F': *' 'tolower($1) ~ /form factor/ {print $2; exit}')
        set -l fips false
        if printf '%s\n' $info | grep -qiE 'fips'
            set fips true
        end

        if set -q _flag_json
            test "$first" = false; and printf ','
            set first false
            printf '{"serial":"%s","firmware":"%s","form_factor":"%s","fips":%s}' \
                "$serial" "$fw" "$form_factor" "$fips"
        else
            echo "YubiKey #$serial"
            echo "  Firmware:    $fw"
            echo "  Form factor: $form_factor"
            echo "  FIPS:        $fips"
            if test -n "$fw"
                set -l major (string split . -- $fw)[1]
                set -l minor (string split . -- $fw)[2]
                if string match -qr '^\d+$' -- "$major"; and string match -qr '^\d+$' -- "$minor"
                    if test "$major" -lt 5; or begin; test "$major" -eq 5; and test "$minor" -lt 7; end
                        echo "  Note:        firmware <5.7 — some features (e.g. PIV ed25519) unavailable"
                    end
                end
            end
            echo
        end
    end

    if set -q _flag_json
        printf ']\n'
    end
end
