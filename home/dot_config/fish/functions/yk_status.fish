function yk_status --description "One-glance health check for connected YubiKey(s)"
    argparse --name=yk_status h/help json 's/serial=' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: yk_status [--json] [--serial SN]"
        echo "Show status of connected YubiKey(s) including FIDO2 PIN + SSH key health."
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
        set -l device_type (printf '%s\n' $info | awk -F': *' 'tolower($1) ~ /device type/ {print $2; exit}')
        set -l fw (printf '%s\n' $info | awk -F': *' 'tolower($1) ~ /firmware version/ {print $2; exit}')
        set -l form_factor (printf '%s\n' $info | awk -F': *' 'tolower($1) ~ /form factor/ {print $2; exit}')
        set -l fips false
        if string match -qi '*FIPS*' -- $device_type
            set fips true
        end

        # Health: FIDO2 PIN. Same regex as yk_enroll: positive signals
        # 'PIN is set' (legacy) / 'PIN: N attempt(s) remaining' (modern) /
        # 'PIN: Configured'; negative signals 'PIN is not set' / 'PIN: Not
        # set' / 'PIN: not configured'.
        set -l fido_info (ykman --device $serial fido info 2>/dev/null)
        set -l pin_set unknown
        if test -n "$fido_info"
            if printf '%s\n' $fido_info | grep -qiE 'PIN is set|PIN:[[:space:]]*[0-9]+[[:space:]]+attempt|PIN:[[:space:]]*configured'
                if printf '%s\n' $fido_info | grep -qiE 'PIN is not set|PIN:[[:space:]]*not[[:space:]]+(set|configured)'
                    set pin_set false
                else
                    set pin_set true
                end
            else
                set pin_set false
            end
        end

        # Health: SSH key file from yk_enroll (per-serial filename).
        set -l ssh_key ""
        set -l ssh_pub ""
        for candidate in "$HOME/.ssh/id_ed25519_sk_$serial" "$HOME/.ssh/id_ecdsa_sk_$serial"
            if test -f "$candidate"; and test -f "$candidate.pub"
                set ssh_key $candidate
                set ssh_pub "$candidate.pub"
                break
            end
        end

        if set -q _flag_json
            test "$first" = false; and printf ','
            set first false
            printf '{"serial":"%s","device_type":"%s","firmware":"%s","form_factor":"%s","fips":%s,"pin_set":"%s","ssh_key":"%s"}' \
                "$serial" "$device_type" "$fw" "$form_factor" "$fips" "$pin_set" "$ssh_key"
        else
            set -l label "$device_type"
            test -z "$label"; and set label "YubiKey"
            # Heading: device type only. Detail lines are vertical so a
            # glance at the column gives every fact.
            echo "$label"
            echo "  Serial:        $serial"
            echo "  Firmware:      $fw"
            if test "$fips" = true
                echo "  FIPS:          yes"
            else
                echo "  FIPS:          no"
            end
            echo "  Form factor:   $form_factor"
            switch $pin_set
                case true
                    echo "  FIDO2 PIN:     [OK] set"
                case false
                    echo "  FIDO2 PIN:     [WARN] not set    (run yk_enroll)"
                case '*'
                    echo "  FIDO2 PIN:     [?]  could not query (ykman fido info failed)"
            end
            if test -n "$ssh_key"
                echo "  SSH key:       [OK] $ssh_pub"
            else
                echo "  SSH key:       [WARN] not enrolled  (run yk_enroll)"
            end
            if test -n "$fw"
                set -l major (string split . -- $fw)[1]
                set -l minor (string split . -- $fw)[2]
                if string match -qr '^\d+$' -- "$major"; and string match -qr '^\d+$' -- "$minor"
                    if test "$major" -lt 5; or begin; test "$major" -eq 5; and test "$minor" -lt 7; end
                        echo "  Note:          firmware <5.7 — some features (e.g. PIV ed25519) unavailable"
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
