#!/bin/bash
# yk-enroll - Idempotent end-to-end YubiKey enrollment wizard
#
# Walks through every step needed to make a YubiKey usable for SSH:
#   1. Preflight (ykman + FIDO2-capable ssh-keygen)
#   2. Detect exactly one connected YubiKey
#   3. Show device info + firmware sanity check
#   4. Ensure a FIDO2 PIN is set
#   5. Ensure a resident SSH key exists, named per serial
#   6. Print next steps (gh ssh-key add, ssh-add)
#
# Re-running is safe: every step checks current state and skips work that
# has already been done. Use --check for a read-only audit.
#
# Multi-key story:
#   Each YubiKey is its own authenticator — there is no way to clone a
#   resident SSH credential between keys. To use multiple YubiKeys with
#   SSH, run `yk-enroll` once per key (unplug the others), then add every
#   resulting `*.pub` to GitHub. Any plugged-in YubiKey can then sign or
#   authenticate.
#
# Usage:
#   yk-enroll                      # interactive wizard
#   yk-enroll --check              # read-only verify
#   yk-enroll --type ecdsa-sk      # for fw <5.2.3
#   yk-enroll --no-verify-required # touch only, no PIN required for SSH

yk-enroll() {
	local check_only=false
	local type="ed25519-sk"
	local verify_required=true
	local resident=true

	while [[ $# -gt 0 ]]; do
		case $1 in
		--check)
			check_only=true
			shift
			;;
		--type)
			type="$2"
			shift 2
			;;
		--no-verify-required)
			verify_required=false
			shift
			;;
		--no-resident)
			resident=false
			shift
			;;
		-h | --help)
			cat <<EOF
Usage: yk-enroll [OPTIONS]
Idempotent YubiKey enrollment wizard. Re-run any time to verify state.

Options:
  --check                Read-only audit; never prompt or write.
  --type {ed25519-sk|ecdsa-sk}
                         SSH key type (default: ed25519-sk).
  --no-verify-required   Skip PIN-on-every-use for SSH (touch only).
  --no-resident          Don't store SSH credential on the key (no ssh-add -K).
EOF
			return 0
			;;
		*)
			echo "Error: unknown option: $1" >&2
			return 1
			;;
		esac
	done

	# ----- Step 1: preflight -------------------------------------------------
	_yk_step "1/5" "Preflight"
	if ! command -v ykman >/dev/null 2>&1; then
		_yk_fail "  'ykman' not found. Install with: brew install ykman  (or pipx install yubikey-manager)"
		return 1
	fi
	_yk_ok "  ykman found: $(command -v ykman)"
	if ! command -v ssh-keygen >/dev/null 2>&1; then
		_yk_fail "  ssh-keygen not found."
		return 1
	fi
	if [[ "$(uname)" == "Darwin" ]]; then
		local sshk
		sshk="$(command -v ssh-keygen)"
		if [[ "$sshk" == /usr/bin/ssh-keygen || "$sshk" == /usr/sbin/ssh-keygen ]]; then
			_yk_fail "  Apple's bundled $sshk lacks FIDO2 (libfido2). Run: brew install openssh"
			_yk_fail "  Then put Homebrew bin ahead of /usr/bin on PATH and re-run yk-enroll."
			return 1
		fi
	fi
	_yk_ok "  ssh-keygen found: $(command -v ssh-keygen)"

	# ----- Step 2: detect a single YubiKey -----------------------------------
	_yk_step "2/5" "Detect YubiKey"
	local serials
	serials="$(ykman list --serials 2>/dev/null || true)"
	if [[ -z "$serials" ]]; then
		_yk_fail "  No YubiKey detected. Plug one in and re-run."
		return 1
	fi
	local count
	count="$(printf '%s\n' "$serials" | grep -c .)"
	if [[ "$count" -gt 1 ]]; then
		_yk_fail "  Multiple YubiKeys connected ($count). Enrollment must be unambiguous."
		_yk_fail "  Unplug all but the one to enroll, then re-run. Detected:"
		while IFS= read -r s; do
			local s_info s_dt s_fw
			s_info="$(ykman --device "$s" info 2>/dev/null || true)"
			s_dt="$(awk -F': *' 'tolower($1) ~ /device type/ {print $2; exit}' <<<"$s_info")"
			s_fw="$(awk -F': *' 'tolower($1) ~ /firmware version/ {print $2; exit}' <<<"$s_info")"
			printf '    - %s  (serial %s%s)\n' "${s_dt:-YubiKey}" "$s" "${s_fw:+, fw $s_fw}" >&2
		done <<<"$serials"
		return 1
	fi
	local serial
	serial="$(printf '%s\n' "$serials" | head -n1)"
	local info
	info="$(ykman --device "$serial" info 2>/dev/null || true)"
	local device_type fw
	device_type="$(awk -F': *' 'tolower($1) ~ /device type/ {print $2; exit}' <<<"$info")"
	fw="$(awk -F': *' 'tolower($1) ~ /firmware version/ {print $2; exit}' <<<"$info")"
	_yk_ok "  ${device_type:-YubiKey} (serial $serial, firmware ${fw:-?})"

	# ----- Step 3: firmware / capability check -------------------------------
	_yk_step "3/5" "Capability check"
	if [[ "$type" == "ed25519-sk" ]]; then
		# ed25519-sk needs >=5.2.3
		local major minor
		major="$(awk -F. '{print $1}' <<<"$fw")"
		minor="$(awk -F. '{print $2}' <<<"$fw")"
		if [[ -n "$major" && -n "$minor" ]] && {
			[[ "$major" -lt 5 ]] || { [[ "$major" -eq 5 ]] && [[ "$minor" -lt 2 ]]; }
		}; then
			_yk_fail "  Firmware $fw is too old for ed25519-sk (need >=5.2.3)."
			_yk_fail "  Re-run with: yk-enroll --type ecdsa-sk"
			return 1
		fi
	fi
	_yk_ok "  $type supported on firmware ${fw:-?}"

	# ----- Step 4: FIDO2 PIN -------------------------------------------------
	_yk_step "4/5" "FIDO2 PIN"
	local fido_info
	fido_info="$(ykman --device "$serial" fido info 2>/dev/null || true)"
	local pin_set=false
	if grep -qiE 'PIN is set|PIN.*set' <<<"$fido_info" && ! grep -qiE 'PIN is not set' <<<"$fido_info"; then
		pin_set=true
	fi
	if [[ "$pin_set" == true ]]; then
		_yk_ok "  FIDO2 PIN is set."
	else
		if [[ "$check_only" == true ]]; then
			_yk_warn "  FIDO2 PIN is NOT set. (skipped: --check)"
		else
			echo "  No FIDO2 PIN set. Setting one now (you'll be prompted)..." >&2
			echo "  Tip: 6-8+ chars, anything you can re-type under stress." >&2
			if ! ykman --device "$serial" fido access change-pin; then
				_yk_fail "  Failed to set FIDO2 PIN."
				return 1
			fi
			_yk_ok "  FIDO2 PIN set."
		fi
	fi

	# ----- Step 5: SSH key ---------------------------------------------------
	_yk_step "5/5" "SSH key"
	local out_path="$HOME/.ssh/id_${type//-/_}_${serial}"
	if [[ -e "$out_path" ]]; then
		_yk_ok "  Resident SSH key already enrolled: $out_path"
	else
		if [[ "$check_only" == true ]]; then
			_yk_warn "  No SSH key at $out_path. (skipped: --check)"
		else
			echo "  Generating $type SSH key on YubiKey $serial..." >&2
			# Delegate to yk-ssh-new (already loaded as a function or sourced).
			if ! command -v yk-ssh-new >/dev/null 2>&1 &&
				! declare -F yk-ssh-new >/dev/null 2>&1; then
				# Try sourcing it from the standard location.
				# shellcheck disable=SC1091
				. "$HOME/.config/shell/functions/yk-ssh-new.sh" 2>/dev/null || true
			fi
			local new_args=(--type "$type" --output "$out_path")
			[[ "$resident" == false ]] && new_args+=(--no-resident)
			[[ "$verify_required" == false ]] && new_args+=(--no-verify-required)
			if ! yk-ssh-new "${new_args[@]}"; then
				_yk_fail "  SSH key generation failed."
				return 1
			fi
			_yk_ok "  Enrolled: $out_path"
		fi
	fi

	# ----- Summary -----------------------------------------------------------
	echo
	echo "Done. Next steps for serial $serial:"
	if [[ -e "${out_path}.pub" ]]; then
		echo "  1. Add to GitHub:    gh ssh-key add ${out_path}.pub --title \"$(hostname -s 2>/dev/null || hostname)-yk-${serial}\""
		echo "  2. Add to ssh-agent: ssh-add ${out_path}"
		[[ "$resident" == true ]] && echo "  3. On new machines:  ssh-add -K   # reload all resident keys from this YubiKey"
		echo
		echo "  Multi-key tip: re-run yk-enroll with each YubiKey plugged in (one"
		echo "  at a time), add every resulting .pub to GitHub, and any of them"
		echo "  can then sign / SSH."
	fi
}

# --- internal pretty-printers ------------------------------------------------
_yk_step() { printf '\n[%s] %s\n' "$1" "$2" >&2; }
_yk_ok() { printf '%s\n' "$1" >&2; }
_yk_fail() { printf '%s\n' "$1" >&2; }
_yk_warn() { printf '%s\n' "$1" >&2; }

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	yk-enroll "$@"
fi
