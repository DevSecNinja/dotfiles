#!/bin/bash
# yk-pick - Print the serial of a connected YubiKey
#
# When exactly one YubiKey is connected, prints its serial to stdout.
# When multiple are connected:
#   - if `fzf` is available and stdin is a TTY, asks the user to pick one
#   - otherwise prints an error and lists serials on stderr
#
# Usage: yk-pick [--first]
#   --first   Skip the picker and just print the first serial

yk-pick() {
	local first_only=false
	while [[ $# -gt 0 ]]; do
		case $1 in
		--first)
			first_only=true
			shift
			;;
		-h | --help)
			echo "Usage: yk-pick [--first]"
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

	local serials
	serials="$(ykman list --serials 2>/dev/null)" || serials=""
	if [[ -z "$serials" ]]; then
		echo "Error: no YubiKey detected." >&2
		return 1
	fi

	local count
	count="$(echo "$serials" | grep -c .)"
	if [[ "$count" -eq 1 ]] || [[ "$first_only" == true ]]; then
		echo "$serials" | head -n1
		return 0
	fi

	if command -v fzf >/dev/null 2>&1 && [[ -t 0 ]]; then
		local pick
		pick="$(echo "$serials" | fzf --prompt='YubiKey> ' --height=10 --no-multi)" || return 1
		echo "$pick"
		return 0
	fi

	echo "Error: multiple YubiKeys connected; pass --serial or install fzf:" >&2
	echo "$serials" >&2
	return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	yk-pick "$@"
fi
