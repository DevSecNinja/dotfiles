function yk_touch_watch --description "Notify when a YubiKey operation is waiting for a touch"
    argparse --name=yk_touch_watch h/help once no-bell 'interval=' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: yk_touch_watch [OPTIONS]"
        echo "Notify when a YubiKey is waiting for a touch."
        echo ""
        echo "Options:"
        echo "  --once             Exit after the first touch event"
        echo "  --interval SECS    Poll interval (default: 0.5)"
        echo "  --no-bell          Don't emit a terminal bell"
        return 0
    end

    if not command -q ykman
        echo "Error: 'ykman' not found." >&2
        return 1
    end

    set -l interval 0.5
    set -q _flag_interval; and set interval $_flag_interval

    function __yk_touch_notify
        set -l title $argv[1]
        set -l body $argv[2]
        echo "[yk_touch_watch] $title — $body"
        if not set -q _flag_no_bell
            printf '\a'
        end
        if command -q notify-send
            notify-send -u critical -i security-high "$title" "$body" 2>/dev/null
        else if test (uname) = Darwin; and command -q osascript
            osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null
        end
    end

    echo "Watching for YubiKey touch requests... (ctrl-c to stop)"
    set -l last_state ""
    while true
        set -l state (ykman info 2>/dev/null | grep -Ei 'touch|locked')
        if test -n "$state"; and test "$state" != "$last_state"
            __yk_touch_notify "YubiKey touch" "$state"
            set last_state $state
            if set -q _flag_once
                return 0
            end
        end
        sleep $interval
    end
end
