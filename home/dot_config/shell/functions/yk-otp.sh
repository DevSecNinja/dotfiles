#!/bin/bash
# yk-otp - Generate a TOTP code from your YubiKey's OATH applet
#
# Wraps `ykman oath accounts code` with an interactive picker (fzf) and copies
# the chosen 6/8-digit code to the clipboard via clipboard-copy.
#
# Usage:
#   yk-otp                          # interactive picker (or sole match)
#   yk-otp github                   # filter accounts; touch when prompted
#   yk-otp --serial 12345 github    # target a specific YubiKey
#   yk-otp --no-copy github         # print only, don't copy
#   yk-otp --list                   # list account names without codes
#
# Requirements:
#   - `ykman` (yubikey-manager) >= 5.0
#   - `fzf` recommended for multi-account selection (falls back to `select`)
#   - clipboard-copy for the copy step (shipped with this dotfiles repo)
#
# Notes:
#   - If the OATH applet is password-protected, ykman will prompt for it.
#   - Accounts marked "requires touch" will block until you tap the YubiKey.

yk-otp() {
	local serial="" copy=true list=false query=""

	while [[ $# -gt 0 ]]; do
		case $1 in
		--serial)
			serial="$2"
			shift 2
			;;
		--no-copy)
			copy=false
			shift
			;;
		--list)
			list=true
			shift
			;;
		-h | --help)
			cat <<EOF
Usage: yk-otp [OPTIONS] [ACCOUNT-FILTER]
Generate a TOTP code from your YubiKey's OATH applet.

Options:
  --serial SN     Target a specific YubiKey by serial
  --no-copy       Print the code without copying to clipboard
  --list          List account names only (no codes)
  -h, --help      Show this help
EOF
			return 0
			;;
		--)
			shift
			query="$*"
			break
			;;
		-*)
			echo "Unknown option: $1" >&2
			return 1
			;;
		*)
			query="$1"
			shift
			;;
		esac
	done

	if ! command -v ykman >/dev/null 2>&1; then
		echo "Error: 'ykman' not found. Install yubikey-manager." >&2
		return 1
	fi

	local ykman_args=()
	if [[ -n "$serial" ]]; then
		ykman_args+=(--device "$serial")
	fi

	if [[ "$list" == true ]]; then
		ykman "${ykman_args[@]}" oath accounts list
		return $?
	fi

	# `ykman oath accounts code` returns "<name> <code>" lines, or
	# "<name> [Requires Touch]" for touch-required accounts (no code yet).
	local lines
	if [[ -n "$query" ]]; then
		lines="$(ykman "${ykman_args[@]}" oath accounts code "$query" 2>/dev/null)"
	else
		lines="$(ykman "${ykman_args[@]}" oath accounts code 2>/dev/null)"
	fi
	if [[ -z "$lines" ]]; then
		echo "Error: no OATH accounts found (filter: '${query:-*}')" >&2
		return 1
	fi

	local count
	count="$(echo "$lines" | grep -c .)"

	local pick
	if [[ "$count" -gt 1 ]]; then
		if command -v fzf >/dev/null 2>&1 && [[ -t 0 ]]; then
			pick="$(echo "$lines" | fzf --prompt='OATH> ' --height=15 --no-multi)" || return 1
		else
			echo "Multiple accounts match; pass a more specific filter or install fzf:" >&2
			echo "$lines" >&2
			return 1
		fi
	else
		pick="$lines"
	fi

	# Strip name; the code is the *last* whitespace-separated field. If it's
	# the placeholder "[Requires", re-fetch with the exact account name to
	# trigger the touch prompt.
	local name code
	# Account names can contain spaces, so anchor on the trailing field.
	code="${pick##* }"
	name="${pick% *}"
	if [[ "$code" == "Touch]" || "$code" == "Touch" || "$code" == "[Requires" ]]; then
		echo "Touch your YubiKey for: $name"
		pick="$(ykman "${ykman_args[@]}" oath accounts code "$name" 2>/dev/null | head -n1)"
		code="${pick##* }"
		name="${pick% *}"
	fi

	if [[ ! "$code" =~ ^[0-9]{6,8}$ ]]; then
		echo "Error: failed to obtain a code (got: '$pick')" >&2
		return 1
	fi

	echo "$name: $code"
	if [[ "$copy" == true ]] && command -v clipboard-copy >/dev/null 2>&1 &&
		clipboard-copy --check >/dev/null 2>&1; then
		printf '%s' "$code" | clipboard-copy
		echo "(copied to clipboard)"
	fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	yk-otp "$@"
fi
