#!/bin/bash
# yk-status - One-glance health check for connected YubiKey(s)
#
# For every connected YubiKey, shows the device type, serial, firmware,
# form factor, FIPS status, and a small per-device checklist:
#
#   - FIDO2 PIN set?
#   - Resident SSH key file present at ~/.ssh/id_*_sk_<serial>?
#
# Warns on firmware below 5.7.
#
# Usage: yk-status [--json] [--serial <SN>]
#
# Notes:
#   - Requires `ykman` (https://developers.yubico.com/yubikey-manager/).
#   - Works with multiple YubiKeys connected simultaneously.

yk-status() {
	# Declare ALL locals once at the function top. zsh's `local` is
	# function-scoped, and re-declaring an already-declared local inside a
	# loop iteration causes zsh to print the assignment (a typeset side
	# effect). Bash doesn't have this quirk; declaring once works in both.
	local json=false
	local target_serial=""
	local serials=""
	local first=true
	local serial=""
	local info=""
	local device_type=""
	local fw=""
	local form_factor=""
	local fips="false"
	local major=""
	local minor=""
	local fido_info=""
	local pin_set="unknown"
	local ssh_key=""
	local ssh_pub=""

	while [[ $# -gt 0 ]]; do
		case $1 in
		--json)
			json=true
			shift
			;;
		--serial)
			target_serial="$2"
			shift 2
			;;
		-h | --help)
			echo "Usage: yk-status [--json] [--serial <SN>]"
			echo "Show status of connected YubiKey(s)."
			return 0
			;;
		*)
			echo "Unknown option: $1" >&2
			return 1
			;;
		esac
	done

	if ! command -v ykman >/dev/null 2>&1; then
		echo "Error: 'ykman' not found. Install yubikey-manager." >&2
		return 1
	fi

	if ! serials="$(ykman list --serials 2>/dev/null)"; then
		echo "Error: failed to list YubiKeys (is one inserted?)" >&2
		return 1
	fi
	if [[ -z "$serials" ]]; then
		echo "No YubiKey detected."
		return 1
	fi

	if [[ -n "$target_serial" ]]; then
		serials="$target_serial"
	fi

	if [[ "$json" == true ]]; then
		printf '['
	fi

	while IFS= read -r serial; do
		[[ -z "$serial" ]] && continue
		info="$(ykman --device "$serial" info 2>/dev/null)" || {
			echo "Error: failed to query device $serial" >&2
			continue
		}
		device_type="$(echo "$info" | awk -F': *' 'tolower($1) ~ /device type/ {print $2; exit}')"
		fw="$(echo "$info" | awk -F': *' 'tolower($1) ~ /firmware version/ {print $2; exit}')"
		form_factor="$(echo "$info" | awk -F': *' 'tolower($1) ~ /form factor/ {print $2; exit}')"
		fips="false"
		if echo "$device_type" | grep -qiE 'fips'; then
			fips="true"
		fi

		# Health: FIDO2 PIN. Same regex logic as yk-enroll: positive
		# signals 'PIN is set' (legacy) or 'PIN: N attempt(s) remaining'
		# / 'PIN: Configured' (modern); negative signals 'PIN is not
		# set' / 'PIN: Not set' / 'PIN: not configured'.
		fido_info="$(ykman --device "$serial" fido info 2>/dev/null || true)"
		pin_set="unknown"
		if [[ -n "$fido_info" ]]; then
			if grep -qiE 'PIN is set|PIN:[[:space:]]*[0-9]+[[:space:]]+attempt|PIN:[[:space:]]*configured' <<<"$fido_info" &&
				! grep -qiE 'PIN is not set|PIN:[[:space:]]*not[[:space:]]+(set|configured)' <<<"$fido_info"; then
				pin_set="true"
			else
				pin_set="false"
			fi
		fi

		# Health: SSH key file. yk-enroll writes per-serial files.
		ssh_key=""
		ssh_pub=""
		for _yk_pat in \
			"$HOME/.ssh/id_ed25519_sk_${serial}" \
			"$HOME/.ssh/id_ecdsa_sk_${serial}"; do
			if [[ -f "$_yk_pat" && -f "${_yk_pat}.pub" ]]; then
				ssh_key="$_yk_pat"
				ssh_pub="${_yk_pat}.pub"
				break
			fi
		done
		unset _yk_pat

		if [[ "$json" == true ]]; then
			[[ "$first" == false ]] && printf ','
			first=false
			printf '{"serial":"%s","device_type":"%s","firmware":"%s","form_factor":"%s","fips":%s,"pin_set":"%s","ssh_key":"%s"}' \
				"$serial" "${device_type:-unknown}" "${fw:-unknown}" "${form_factor:-unknown}" "$fips" "$pin_set" "$ssh_key"
		else
			# Heading line: device type is the most recognisable thing.
			local heading="${device_type:-YubiKey}"
			heading="$heading  ·  serial $serial  ·  fw ${fw:-?}"
			[[ "$fips" == "true" ]] && heading="$heading  ·  FIPS"
			echo "$heading"
			echo "  Form factor:   ${form_factor:-unknown}"
			case "$pin_set" in
			true) echo "  FIDO2 PIN:     [OK] set" ;;
			false) echo "  FIDO2 PIN:     [WARN] not set    (run \`yk-enroll\`)" ;;
			*) echo "  FIDO2 PIN:     [?]  could not query (ykman fido info failed)" ;;
			esac
			if [[ -n "$ssh_key" ]]; then
				echo "  SSH key:       [OK] $ssh_pub"
			else
				echo "  SSH key:       [WARN] not enrolled  (run \`yk-enroll\`)"
			fi
			if [[ -n "$fw" ]]; then
				major="${fw%%.*}"
				minor="${fw#*.}"
				minor="${minor%%.*}"
				if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$minor" =~ ^[0-9]+$ ]]; then
					if ((major < 5)) || { ((major == 5)) && ((minor < 7)); }; then
						echo "  Note:          firmware <5.7 — some features (e.g. PIV ed25519) unavailable"
					fi
				fi
			fi
			echo
		fi
	done <<<"$serials"

	if [[ "$json" == true ]]; then
		printf ']\n'
	fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	yk-status "$@"
fi
