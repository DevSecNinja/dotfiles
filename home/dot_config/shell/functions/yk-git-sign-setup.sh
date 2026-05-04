#!/bin/bash
# yk-git-sign-setup - Configure git to sign commits with your YubiKey SSH key
#
# Verifies your git config is wired for SSH commit signing and that
# ~/.config/git/allowed_signers contains every YubiKey pubkey present at
# ~/.ssh/id_*_sk*.pub (per-serial files from yk-enroll). Optionally adds
# a coworker's public key as a trusted signer.
#
# Usage:
#   yk-git-sign-setup                          # validate + self-register all keys
#   yk-git-sign-setup --key ~/.ssh/id_yk.pub   # use a specific public key
#   yk-git-sign-setup --add path/to/key.pub --principal someone@example.com
#   yk-git-sign-setup --check                  # exit non-zero if not configured
#
# Notes:
#   - Requires git >= 2.34 (SSH signing support).
#   - Set chezmoi var `useYubiKey: true` first so git/config.tmpl wires up
#     [gpg] format = ssh and friends.

yk-git-sign-setup() {
	local key="" add_key="" principal="" mode="setup"
	local allowed_signers="${ALLOWED_SIGNERS_FILE:-$HOME/.config/git/allowed_signers}"

	while [[ $# -gt 0 ]]; do
		case $1 in
		--key)
			key="$2"
			shift 2
			;;
		--add)
			add_key="$2"
			mode="add"
			shift 2
			;;
		--principal)
			principal="$2"
			shift 2
			;;
		--check)
			mode="check"
			shift
			;;
		-h | --help)
			cat <<EOF
Usage: yk-git-sign-setup [OPTIONS]
Configure git to sign commits with your YubiKey SSH key.

Options:
  --key PATH                  Public key to register as your signer
                              (default: register every per-serial pubkey
                              found in ~/.ssh, e.g. id_ed25519_sk_<serial>.pub)
  --add PATH                  Add another principal's public key
  --principal STR             Principal (email) to associate with --add
  --check                     Exit 0 if signing is configured, 1 otherwise
EOF
			return 0
			;;
		*)
			echo "Unknown option: $1" >&2
			return 1
			;;
		esac
	done

	if ! command -v git >/dev/null 2>&1; then
		echo "Error: git not found." >&2
		return 1
	fi

	if [[ "$mode" == "check" ]]; then
		local fmt sign signer
		fmt="$(git config --get gpg.format 2>/dev/null || true)"
		sign="$(git config --get commit.gpgsign 2>/dev/null || true)"
		signer="$(git config --get user.signingkey 2>/dev/null || true)"
		if [[ "$fmt" == "ssh" && "$sign" == "true" && -n "$signer" ]]; then
			echo "ssh signing: ON  signingkey=$signer"
			return 0
		fi
		echo "ssh signing: OFF (gpg.format='$fmt' commit.gpgsign='$sign' signingkey='$signer')" >&2
		return 1
	fi

	# Ensure allowed_signers exists
	mkdir -p "$(dirname "$allowed_signers")"
	[[ -f "$allowed_signers" ]] || {
		printf '# Managed by yk-git-sign-setup\n' >"$allowed_signers"
	}

	if [[ "$mode" == "add" ]]; then
		if [[ -z "$add_key" || ! -f "$add_key" ]]; then
			echo "Error: --add file not found: $add_key" >&2
			return 1
		fi
		if [[ -z "$principal" ]]; then
			echo "Error: --principal <email> is required with --add" >&2
			return 1
		fi
		local pubkey
		pubkey="$(cat "$add_key")"
		if grep -Fq -- "$pubkey" "$allowed_signers" 2>/dev/null; then
			echo "Already present: $principal"
			return 0
		fi
		printf '%s %s\n' "$principal" "$pubkey" >>"$allowed_signers"
		echo "Added principal $principal -> $allowed_signers"
		return 0
	fi

	# Setup mode: pick public key(s), ensure each is in allowed_signers, and
	# verify git config. We don't *write* git config here — that's owned by
	# git/config.tmpl + the chezmoi `useYubiKey` var. Instead we explain how
	# to enable it if it isn't on yet.
	local email
	email="$(git config --get user.email 2>/dev/null || true)"
	if [[ -z "$email" ]]; then
		echo "Error: git config user.email is not set." >&2
		return 1
	fi

	# Collect the set of pubkeys to register.
	local -a keys=()
	if [[ -n "$key" ]]; then
		if [[ ! -f "$key" ]]; then
			echo "Error: --key file not found: $key" >&2
			return 1
		fi
		keys=("$key")
	else
		# Per-serial files first (yk-enroll), then legacy un-suffixed, then
		# non-FIDO2.
		local pat
		for pat in \
			"$HOME/.ssh/id_ed25519_sk_"*.pub \
			"$HOME/.ssh/id_ecdsa_sk_"*.pub \
			"$HOME/.ssh/id_ed25519_sk.pub" \
			"$HOME/.ssh/id_ecdsa_sk.pub" \
			"$HOME/.ssh/id_ed25519.pub"; do
			for candidate in $pat; do
				[[ -f "$candidate" ]] && keys+=("$candidate")
			done
		done
	fi
	if [[ ${#keys[@]} -eq 0 ]]; then
		echo "Error: no public key found. Run \`yk-enroll\` first." >&2
		return 1
	fi

	local pubkey registered=0 already=0
	for key in "${keys[@]}"; do
		pubkey="$(cat "$key")"
		if grep -Fq -- "$pubkey" "$allowed_signers" 2>/dev/null; then
			echo "Already registered: $key"
			already=$((already + 1))
		else
			printf '%s %s\n' "$email" "$pubkey" >>"$allowed_signers"
			echo "Registered $key for $email"
			registered=$((registered + 1))
		fi
	done

	# Verify config
	local fmt sign signer
	fmt="$(git config --get gpg.format 2>/dev/null || true)"
	sign="$(git config --get commit.gpgsign 2>/dev/null || true)"
	signer="$(git config --get user.signingkey 2>/dev/null || true)"
	echo
	echo "Current git signing config:"
	echo "  gpg.format        = ${fmt:-(unset)}"
	echo "  commit.gpgsign    = ${sign:-(unset)}"
	echo "  user.signingkey   = ${signer:-(unset)}"
	if [[ "$fmt" != "ssh" || "$sign" != "true" || -z "$signer" ]]; then
		echo
		echo "Hint: set chezmoi data 'useYubiKey: true' and run \`chezmoi apply\`"
		echo "      to wire ~/.config/git/config for SSH signing."
		return 1
	fi

	# Final, mandatory step: upload the pubkey(s) to GitHub as *signing* keys
	# so commits get the green Verified badge. Without this, signing locally
	# does very little.
	echo
	echo "Required next step: upload each pubkey to GitHub as both an"
	echo "  authentication AND signing key (signing isn't useful otherwise):"
	for key in "${keys[@]}"; do
		echo "    gh ssh-key add $key --type signing --title \"<descriptive title>\""
	done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	yk-git-sign-setup "$@"
fi
