function yk_enroll --description "Idempotent YubiKey enrollment wizard"
    argparse --name=yk_enroll h/help check 't/type=' no-resident no-verify-required -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: yk_enroll [OPTIONS]"
        echo "Idempotent YubiKey enrollment wizard. Re-run any time to verify state."
        echo ""
        echo "Options:"
        echo "  --check                Read-only audit; never prompt or write."
        echo "  --type {ed25519-sk|ecdsa-sk}"
        echo "                         SSH key type (default: ed25519-sk)."
        echo "  --no-verify-required   Skip PIN-on-every-use for SSH (touch only)."
        echo "  --no-resident          Don't store SSH credential on the key."
        return 0
    end

    set -l check_only false
    set -q _flag_check; and set check_only true
    set -l type ed25519-sk
    set -q _flag_type; and set type $_flag_type
    set -l verify_required true
    set -q _flag_no_verify_required; and set verify_required false
    set -l resident true
    set -q _flag_no_resident; and set resident false

    # ----- Step 1: preflight ------------------------------------------------
    echo "" >&2
    echo "[1/5] Preflight" >&2
    if not command -q ykman
        echo "  'ykman' not found. Install with: brew install ykman" >&2
        return 1
    end
    echo "  ykman found: "(command -v ykman) >&2
    if not command -q ssh-keygen
        echo "  ssh-keygen not found." >&2
        return 1
    end
    if test (uname) = Darwin
        set -l sshk (command -v ssh-keygen)
        if test "$sshk" = /usr/bin/ssh-keygen; or test "$sshk" = /usr/sbin/ssh-keygen
            echo "  Apple's bundled $sshk lacks FIDO2. Run: brew install openssh" >&2
            echo "  Then put Homebrew bin ahead of /usr/bin and re-run yk_enroll." >&2
            return 1
        end
    end
    echo "  ssh-keygen found: "(command -v ssh-keygen) >&2

    # ----- Step 2: detect a single YubiKey ---------------------------------
    echo "" >&2
    echo "[2/5] Detect YubiKey" >&2
    set -l serials (ykman list --serials 2>/dev/null)
    if test (count $serials) -eq 0
        echo "  No YubiKey detected. Plug one in and re-run." >&2
        return 1
    end
    if test (count $serials) -gt 1
        echo "  Multiple YubiKeys connected ("(count $serials)"). Enrollment must be unambiguous." >&2
        echo "  Unplug all but the one to enroll, then re-run. Detected:" >&2
        for s in $serials
            echo "    - $s" >&2
        end
        return 1
    end
    set -l serial $serials[1]
    set -l info (ykman --device $serial info 2>/dev/null)
    set -l device_type (printf '%s\n' $info | awk -F': *' 'tolower($1) ~ /device type/ {print $2; exit}')
    set -l fw (printf '%s\n' $info | awk -F': *' 'tolower($1) ~ /firmware version/ {print $2; exit}')
    test -z "$device_type"; and set device_type "YubiKey"
    test -z "$fw"; and set fw "?"
    echo "  $device_type (serial $serial, firmware $fw)" >&2

    # ----- Step 3: capability check ----------------------------------------
    echo "" >&2
    echo "[3/5] Capability check" >&2
    if test "$type" = ed25519-sk
        set -l major (string split . -- $fw)[1]
        set -l minor (string split . -- $fw)[2]
        if test -n "$major" -a -n "$minor"
            if test "$major" -lt 5; or begin; test "$major" -eq 5; and test "$minor" -lt 2; end
                echo "  Firmware $fw is too old for ed25519-sk (need >=5.2.3)." >&2
                echo "  Re-run with: yk_enroll --type ecdsa-sk" >&2
                return 1
            end
        end
    end
    echo "  $type supported on firmware $fw" >&2

    # ----- Step 4: FIDO2 PIN -----------------------------------------------
    echo "" >&2
    echo "[4/5] FIDO2 PIN" >&2
    set -l fido_info (ykman --device $serial fido info 2>/dev/null)
    set -l pin_set false
    if printf '%s\n' $fido_info | grep -qiE 'PIN is set|PIN.*set'
        if not printf '%s\n' $fido_info | grep -qiE 'PIN is not set'
            set pin_set true
        end
    end
    if test "$pin_set" = true
        echo "  FIDO2 PIN is set." >&2
    else if test "$check_only" = true
        echo "  FIDO2 PIN is NOT set. (skipped: --check)" >&2
    else
        echo "  No FIDO2 PIN set. Setting one now (you'll be prompted)..." >&2
        echo "  Tip: 6-8+ chars, anything you can re-type under stress." >&2
        if not ykman --device $serial fido access change-pin
            echo "  Failed to set FIDO2 PIN." >&2
            return 1
        end
        echo "  FIDO2 PIN set." >&2
    end

    # ----- Step 5: SSH key -------------------------------------------------
    echo "" >&2
    echo "[5/5] SSH key" >&2
    set -l type_under (string replace -a - _ -- $type)
    set -l out_path "$HOME/.ssh/id_$type_under"_"$serial"
    if test -e "$out_path"
        echo "  Resident SSH key already enrolled: $out_path" >&2
    else if test "$check_only" = true
        echo "  No SSH key at $out_path. (skipped: --check)" >&2
    else
        echo "  Generating $type SSH key on YubiKey $serial..." >&2
        set -l new_args --type $type --output $out_path
        test "$resident" = false; and set new_args $new_args --no-resident
        test "$verify_required" = false; and set new_args $new_args --no-verify-required
        if not yk_ssh_new $new_args
            echo "  SSH key generation failed." >&2
            return 1
        end
        echo "  Enrolled: $out_path" >&2
    end

    # ----- Summary ----------------------------------------------------------
    set -l hostshort (hostname -s 2>/dev/null; or hostname)
    echo "" >&2
    echo "Done. Next steps for serial $serial:" >&2
    if test -e "$out_path.pub"
        echo "  1. Add to GitHub:    gh ssh-key add $out_path.pub --title \"$hostshort-yk-$serial\"" >&2
        echo "  2. Add to ssh-agent: ssh-add $out_path" >&2
        if test "$resident" = true
            echo "  3. On new machines:  ssh-add -K   # reload all resident keys from this YubiKey" >&2
        end
        echo "" >&2
        echo "  Multi-key tip: re-run yk_enroll with each YubiKey plugged in (one" >&2
        echo "  at a time), add every resulting .pub to GitHub, and any of them" >&2
        echo "  can then sign / SSH." >&2
    end
end
