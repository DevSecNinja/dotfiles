#!/bin/bash
# yk-ssh-new - Generate a hardware-backed SSH key on a YubiKey
#
# Creates a FIDO2-backed SSH key (ed25519-sk by default; ecdsa-sk fallback)
# stored as a *resident* credential on the YubiKey so it can be reloaded onto
# new machines via `ssh-add -K`. Touch + (optionally) PIN are required for
# every authentication.
#
# Usage:
#   yk-ssh-new                                # ~/.ssh/id_ed25519_sk
#   yk-ssh-new --type ecdsa-sk                # for older firmware (<5.2.3)
#   yk-ssh-new --no-resident                  # skip resident credential
#   yk-ssh-new --no-verify-required           # skip PIN requirement (touch only)
#   yk-ssh-new --output ~/.ssh/id_yk_work     # custom path
#   yk-ssh-new --application ssh:work         # FIDO application string
#
# Notes:
#   - Resident keys + ed25519-sk require firmware >= 5.2.3. Older keys still
#     work but cannot be reloaded with `ssh-add -K`.
#   - On macOS, your OpenSSH must be the modern Apple/Homebrew build (>=8.2)
#     with libfido2.
#   - The FIPS YubiKey enforces a FIDO2 PIN; --no-verify-required is ignored
#     by the device in that case.

yk-ssh-new() {
	local type="ed25519-sk"
	local resident=true
	local verify_required=true
	local output="$HOME/.ssh/id_ed25519_sk"
	local application=""
	local comment=""
	local user_specified_output=false

	while [[ $# -gt 0 ]]; do
		case $1 in
		--type)
			type="$2"
			shift 2
			if [[ "$user_specified_output" == false ]]; then
				case "$type" in
				ecdsa-sk) output="$HOME/.ssh/id_ecdsa_sk" ;;
				ed25519-sk) output="$HOME/.ssh/id_ed25519_sk" ;;
				esac
			fi
			;;
		--no-resident)
			resident=false
			shift
			;;
		--no-verify-required)
			verify_required=false
			shift
			;;
		--output | -o)
			output="$2"
			user_specified_output=true
			shift 2
			;;
		--application)
			application="$2"
			shift 2
			;;
		--comment | -C)
			comment="$2"
			shift 2
			;;
		-h | --help)
			cat <<EOF
Usage: yk-ssh-new [OPTIONS]
Generate a hardware-backed SSH key on a YubiKey.

Options:
  --type {ed25519-sk|ecdsa-sk}   Key type (default: ed25519-sk)
  --no-resident                  Don't store credential on the key
  --no-verify-required           Don't require PIN (touch only)
  --output, -o PATH              Output path (default: ~/.ssh/id_<type>)
  --application STR              FIDO application (default: ssh:<hostname>)
  --comment, -C STR              SSH key comment (default: user@host)
EOF
			return 0
			;;
		*)
			echo "Unknown option: $1" >&2
			return 1
			;;
		esac
	done

	if ! command -v ssh-keygen >/dev/null 2>&1; then
		echo "Error: ssh-keygen not found." >&2
		return 1
	fi

	case "$type" in
	ed25519-sk | ecdsa-sk) ;;
	*)
		echo "Error: --type must be ed25519-sk or ecdsa-sk" >&2
		return 1
		;;
	esac

	if [[ -z "$application" ]]; then
		application="ssh:$(hostname -s 2>/dev/null || hostname)"
	fi
	if [[ -z "$comment" ]]; then
		comment="${USER:-user}@$(hostname -s 2>/dev/null || hostname)"
	fi
	if [[ "$application" != ssh:* ]]; then
		echo "Error: --application must start with 'ssh:'" >&2
		return 1
	fi

	mkdir -p "$(dirname "$output")"
	chmod 700 "$(dirname "$output")" 2>/dev/null || true

	if [[ -e "$output" ]]; then
		echo "Error: $output already exists. Choose another --output or remove it." >&2
		return 1
	fi

	local args=(-t "$type" -f "$output" -C "$comment" -O "application=$application")
	if [[ "$resident" == true ]]; then
		args+=(-O resident)
	fi
	if [[ "$verify_required" == true ]]; then
		args+=(-O verify-required)
	fi

	echo "Generating $type key (touch your YubiKey when it blinks)..."
	echo "  Output:      $output"
	echo "  Resident:    $resident"
	echo "  Verify PIN:  $verify_required"
	echo "  Application: $application"
	echo

	if ! ssh-keygen "${args[@]}"; then
		echo "Error: ssh-keygen failed." >&2
		return 1
	fi

	echo
	echo "Public key:"
	cat "${output}.pub"
	echo
	echo "Next steps:"
	echo "  1. Add to GitHub:    gh ssh-key add ${output}.pub --title \"\$(hostname -s)-yk\""
	echo "  2. Add to ssh-agent: ssh-add $output"
	if [[ "$resident" == true ]]; then
		echo "  3. On new machines:  ssh-add -K   # reload from YubiKey"
	fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	yk-ssh-new "$@"
fi
