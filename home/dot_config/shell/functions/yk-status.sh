#!/bin/bash
# yk-status - One-glance health check for connected YubiKey(s)
#
# Lists every connected YubiKey (by serial) and prints firmware, form factor,
# and enabled applications. Highlights FIPS devices and warns on firmware
# below 5.7 (where some newer features like ed25519 PIV are unavailable).
#
# Usage: yk-status [--json] [--serial <SN>]
#
# Notes:
#   - Requires `ykman` (https://developers.yubico.com/yubikey-manager/).
#   - Works with multiple YubiKeys connected simultaneously.

yk-status() {
	local json=false
	local target_serial=""

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

	# Collect serials. `ykman list` prints one device per line including serial.
	local serials
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

	local first=true
	if [[ "$json" == true ]]; then
		printf '['
	fi

	while IFS= read -r serial; do
		[[ -z "$serial" ]] && continue
		local info
		info="$(ykman --device "$serial" info 2>/dev/null)" || {
			echo "Error: failed to query device $serial" >&2
			continue
		}
		local fw form_factor fips
		fw="$(echo "$info" | awk -F': *' 'tolower($1) ~ /firmware version/ {print $2; exit}')"
		form_factor="$(echo "$info" | awk -F': *' 'tolower($1) ~ /form factor/ {print $2; exit}')"
		fips="false"
		if echo "$info" | grep -qiE 'fips'; then
			fips="true"
		fi

		if [[ "$json" == true ]]; then
			[[ "$first" == false ]] && printf ','
			first=false
			printf '{"serial":"%s","firmware":"%s","form_factor":"%s","fips":%s}' \
				"$serial" "${fw:-unknown}" "${form_factor:-unknown}" "$fips"
		else
			echo "YubiKey #$serial"
			echo "  Firmware:    ${fw:-unknown}"
			echo "  Form factor: ${form_factor:-unknown}"
			echo "  FIPS:        $fips"
			# Warn about features that need >= 5.7
			if [[ -n "$fw" ]]; then
				local major minor
				major="${fw%%.*}"
				minor="${fw#*.}"
				minor="${minor%%.*}"
				if [[ "$major" =~ ^[0-9]+$ ]] && [[ "$minor" =~ ^[0-9]+$ ]]; then
					if ((major < 5)) || { ((major == 5)) && ((minor < 7)); }; then
						echo "  Note:        firmware <5.7 — some features (e.g. PIV ed25519) unavailable"
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
