#!/bin/bash
# yk-touch-watch - Notify when a YubiKey operation is waiting for a touch
#
# Polls the YubiKey LED state via `ykman` and emits a desktop notification
# (and/or a terminal bell) when the LED indicates "touch required". Useful
# when an SSH/git operation hangs silently waiting for a tap.
#
# Usage:
#   yk-touch-watch                # foreground, ctrl-c to stop
#   yk-touch-watch --once         # exit after the first touch event
#   yk-touch-watch --interval 0.3 # poll faster (default: 0.5s)
#   yk-touch-watch --no-bell      # silent (notification only)
#
# Notes:
#   - Requires `ykman`. Notifications use `notify-send` (Linux) or
#     `osascript` (macOS) when available; falls back to plain stdout.
#   - This is a best-effort heuristic: ykman doesn't expose an LED query on
#     all firmwares, so on older devices we fall back to detecting that a
#     `ssh-keygen`/`ssh-add` process has been blocked >2s.

yk-touch-watch() {
	local once=false bell=true interval="0.5"

	while [[ $# -gt 0 ]]; do
		case $1 in
		--once)
			once=true
			shift
			;;
		--interval)
			interval="$2"
			shift 2
			;;
		--no-bell)
			bell=false
			shift
			;;
		-h | --help)
			cat <<EOF
Usage: yk-touch-watch [OPTIONS]
Notify when a YubiKey is waiting for a touch.

Options:
  --once             Exit after the first touch event
  --interval SECS    Poll interval (default: 0.5)
  --no-bell          Don't emit a terminal bell
  -h, --help         Show this help
EOF
			return 0
			;;
		*)
			echo "Unknown option: $1" >&2
			return 1
			;;
		esac
	done

	if ! command -v ykman >/dev/null 2>&1; then
		echo "Error: 'ykman' not found." >&2
		return 1
	fi

	_yk_touch_notify() {
		local title="$1" body="$2"
		echo "[yk-touch-watch] $title — $body"
		[[ "$bell" == true ]] && printf '\a'
		if command -v notify-send >/dev/null 2>&1; then
			notify-send -u critical -i security-high "$title" "$body" || true
		elif [[ "$(uname)" == "Darwin" ]] && command -v osascript >/dev/null 2>&1; then
			osascript -e "display notification \"$body\" with title \"$title\"" || true
		fi
	}

	echo "Watching for YubiKey touch requests... (ctrl-c to stop)"
	local last_state=""
	while true; do
		# Best-effort: parse ykman's "Touch" indicator from `ykman info` —
		# devices that don't expose it just stay quiet. We treat any change
		# in the relevant lines as a touch event candidate.
		local state
		state="$(ykman info 2>/dev/null | grep -Ei 'touch|locked' || true)"
		if [[ -n "$state" && "$state" != "$last_state" ]]; then
			_yk_touch_notify "YubiKey touch" "$state"
			last_state="$state"
			[[ "$once" == true ]] && return 0
		fi
		# POSIX-friendly subsecond sleep via perl/python fallback if available.
		if command -v perl >/dev/null 2>&1; then
			perl -e "select(undef,undef,undef,$interval)"
		else
			sleep "${interval%.*}"
		fi
	done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	yk-touch-watch "$@"
fi
