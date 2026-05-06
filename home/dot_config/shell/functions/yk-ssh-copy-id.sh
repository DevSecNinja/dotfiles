#!/bin/bash
# yk-ssh-copy-id - Push YubiKey SSH pubkey(s) into a remote authorized_keys.
#
# Like ssh-copy-id, but tailored for FIDO2 (`*-sk`) keys with per-serial
# filenames written by `yk-enroll` (id_*_sk_<serial>.pub). Pushes every
# YubiKey-backed pubkey it finds in ~/.ssh in one SSH call (one touch +
# one PIN, not N touches), and is idempotent: keys already present in the
# remote authorized_keys are skipped.
#
# Usage:
#   yk-ssh-copy-id [user@]host                # push every YubiKey pubkey
#   yk-ssh-copy-id -i ~/.ssh/id_yk.pub host   # push one specific pubkey
#   yk-ssh-copy-id -p 2222 user@host          # custom SSH port
#   yk-ssh-copy-id --check user@host          # report which keys are already there
#   yk-ssh-copy-id --dry-run user@host        # print payload locally; don't connect
#
# Notes:
#   - Requires existing SSH access (password, gh-cli'd key, etc.) to bootstrap.
#   - Discovers per-serial files first (id_*_sk_<serial>.pub), then legacy
#     un-suffixed names. Same priority as `pubkey`.
#   - Remote authorized_keys gets `chmod 600`, ~/.ssh `chmod 700`, umask 077.

yk-ssh-copy-id() {
	local port=22
	local identity=""
	local check=false
	local dry_run=false
	local target=""

	while [[ $# -gt 0 ]]; do
		case $1 in
		-i | --identity)
			identity="$2"
			shift 2
			;;
		-p | --port)
			port="$2"
			shift 2
			;;
		--check)
			check=true
			shift
			;;
		--dry-run)
			dry_run=true
			shift
			;;
		-h | --help)
			cat <<EOF
Usage: yk-ssh-copy-id [OPTIONS] [user@]host
Push YubiKey SSH pubkey(s) into a remote authorized_keys (idempotent).

Options:
  -i, --identity PATH    Push only this specific .pub file (default: all
                         id_*_sk*.pub files in ~/.ssh)
  -p, --port N           SSH port (default: 22)
  --check                Connect and report which keys are already authorized;
                         don't write
  --dry-run              Print the keys that would be pushed locally; don't
                         connect to the remote
EOF
			return 0
			;;
		-*)
			echo "Error: unknown option: $1" >&2
			return 1
			;;
		*)
			if [[ -n "$target" ]]; then
				echo "Error: only one [user@]host argument allowed (got '$target' and '$1')" >&2
				return 1
			fi
			target="$1"
			shift
			;;
		esac
	done

	if [[ -z "$target" && "$dry_run" != true ]]; then
		echo "Error: missing [user@]host argument. See --help." >&2
		return 1
	fi

	# Collect the set of pubkeys to push.
	local -a keys=()
	if [[ -n "$identity" ]]; then
		if [[ ! -f "$identity" ]]; then
			echo "Error: --identity file not found: $identity" >&2
			return 1
		fi
		keys=("$identity")
	else
		# Per-serial first, then legacy. Use find for zsh NOMATCH-safety.
		local pat candidate
		for pat in 'id_ed25519_sk_*' 'id_ed25519_sk' 'id_ecdsa_sk_*' 'id_ecdsa_sk'; do
			while IFS= read -r candidate; do
				[[ -n "$candidate" && -f "$candidate" ]] && keys+=("$candidate")
			done < <(find "$HOME/.ssh" -maxdepth 1 -name "${pat}.pub" -type f 2>/dev/null | sort)
		done
	fi

	if [[ ${#keys[@]} -eq 0 ]]; then
		echo "Error: no YubiKey pubkey found in ~/.ssh. Run \`yk-enroll\` first." >&2
		return 1
	fi

	# Build the payload (one pubkey line per file, blank lines stripped).
	local payload=""
	local k
	for k in "${keys[@]}"; do
		payload+="$(grep -vE '^[[:space:]]*$' "$k")"$'\n'
	done

	if [[ "$dry_run" == true ]]; then
		echo "Would push ${#keys[@]} pubkey(s)${target:+ to ${target}}:"
		for k in "${keys[@]}"; do
			echo "  - $k"
		done
		echo
		echo "Payload:"
		printf '%s' "$payload"
		return 0
	fi

	if ! command -v ssh >/dev/null 2>&1; then
		echo "Error: ssh not found." >&2
		return 1
	fi

	# Single SSH call: dedupe against the remote's existing authorized_keys
	# and append only the missing entries. One FIDO2 touch + PIN, not N.
	local remote_install
	# shellcheck disable=SC2016 # $variables are intentionally literal here — they're evaluated by the remote shell.
	remote_install='set -e
umask 077
mkdir -p ~/.ssh
touch ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
existing="$(cat ~/.ssh/authorized_keys 2>/dev/null || true)"
new=0
present=0
while IFS= read -r line; do
	[ -z "$line" ] && continue
	if printf "%s\n" "$existing" | grep -qFx -- "$line"; then
		present=$((present + 1))
	else
		printf "%s\n" "$line" >>~/.ssh/authorized_keys
		new=$((new + 1))
	fi
done
echo "yk-ssh-copy-id: $new added, $present already present" >&2'

	local remote_check
	# shellcheck disable=SC2016 # $variables are intentionally literal here — they're evaluated by the remote shell.
	remote_check='set -e
existing=""
[ -f ~/.ssh/authorized_keys ] && existing="$(cat ~/.ssh/authorized_keys)"
new=0
present=0
while IFS= read -r line; do
	[ -z "$line" ] && continue
	if printf "%s\n" "$existing" | grep -qFx -- "$line"; then
		echo "[OK]   $line"
		present=$((present + 1))
	else
		echo "[MISS] $line"
		new=$((new + 1))
	fi
done
echo "yk-ssh-copy-id: $present already present, $new missing" >&2'

	local script
	if [[ "$check" == true ]]; then
		script="$remote_check"
	else
		script="$remote_install"
	fi

	# Pipe the payload to the remote bash. Use -T to skip the pty, -o
	# BatchMode=no so password/PIN prompts still work, and explicit /bin/sh
	# on the far side to avoid login-shell surprises.
	printf '%s' "$payload" | ssh -T -p "$port" "$target" "/bin/sh -c '$script'"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	yk-ssh-copy-id "$@"
fi
