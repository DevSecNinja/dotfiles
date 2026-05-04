#!/bin/bash
# yk-ssh-load - Load resident FIDO2 SSH keys from a YubiKey into ssh-agent
#
# Wraps `ssh-add -K` (download resident keys) with friendlier diagnostics.
# Useful on a fresh machine after `chezmoi apply`: insert your YubiKey, run
# `yk-ssh-load`, touch when prompted, and your SSH keys are available.
#
# Usage: yk-ssh-load [--quiet]

yk-ssh-load() {
	local quiet=false
	while [[ $# -gt 0 ]]; do
		case $1 in
		-q | --quiet)
			quiet=true
			shift
			;;
		-h | --help)
			echo "Usage: yk-ssh-load [--quiet]"
			echo "Load resident FIDO2 SSH keys from a YubiKey into ssh-agent."
			return 0
			;;
		*)
			echo "Unknown option: $1" >&2
			return 1
			;;
		esac
	done

	if ! command -v ssh-add >/dev/null 2>&1; then
		echo "Error: ssh-add not found." >&2
		return 1
	fi

	if [[ -z "$SSH_AUTH_SOCK" ]]; then
		echo "Error: no ssh-agent running (SSH_AUTH_SOCK is unset)." >&2
		echo "Hint: eval \"\$(ssh-agent -s)\"" >&2
		return 1
	fi

	[[ "$quiet" == true ]] || echo "Touch your YubiKey when it blinks..."
	if ssh-add -K; then
		[[ "$quiet" == true ]] || echo "Resident keys loaded."
		return 0
	fi
	echo "Error: ssh-add -K failed (no resident keys, OpenSSH too old, or wrong PIN)." >&2
	return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	yk-ssh-load "$@"
fi
