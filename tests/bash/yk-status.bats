#!/usr/bin/env bats
# Tests for yk-status

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-status.sh"
	TEST_BIN_DIR="$(mktemp -d)"
	TEST_HOME="$(mktemp -d)"
	export TEST_BIN_DIR TEST_HOME
	export ORIGINAL_PATH="$PATH"
	export ORIGINAL_HOME="$HOME"
	export HOME="$TEST_HOME"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
}

teardown() {
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$ORIGINAL_HOME" ] && export HOME="$ORIGINAL_HOME"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
	[ -n "$TEST_HOME" ] && [ -d "$TEST_HOME" ] && rm -rf "$TEST_HOME"
}

mock_ykman() {
	cat >"$TEST_BIN_DIR/ykman" <<'EOF'
#!/bin/bash
if [[ "$1 $2" == "list --serials" ]]; then
	printf '%s\n' $YKMAN_SERIALS
	exit 0
fi
if [[ "$1" == "--device" ]]; then
	serial="$2"
	shift 2
	case "$1 $2" in
		"info ")
			varname="YKMAN_INFO_${serial}"
			printf '%s\n' "${!varname}"
			;;
		"fido info")
			varname="YKMAN_FIDO_${serial}"
			printf '%s\n' "${!varname}"
			;;
	esac
fi
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/ykman"
}

@test "yk-status: errors when ykman missing" {
	export PATH="/nonexistent"
	run yk-status
	[ "$status" -eq 1 ]
	[[ "$output" =~ "'ykman' not found" ]]
}

@test "yk-status: reports no device" {
	mock_ykman
	export YKMAN_SERIALS=""
	run yk-status
	[ "$status" -eq 1 ]
	[[ "$output" =~ "No YubiKey detected" ]]
}

@test "yk-status: heading uses device type, serial, fw, FIPS marker" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC FIPS
Serial number: 12345
Firmware version: 5.7.4
Form factor: Keychain (USB-C), NFC"
	export YKMAN_FIDO_12345="PIN:                          8 attempt(s) remaining"
	run yk-status
	[ "$status" -eq 0 ]
	[[ "$output" =~ "YubiKey 5C NFC FIPS" ]]
	[[ "$output" =~ "serial 12345" ]]
	[[ "$output" =~ "fw 5.7.4" ]]
	[[ "$output" =~ "·  FIPS" ]]
	[[ "$output" =~ "Form factor:" ]]
	# No more legacy "YubiKey #<serial>" header.
	[[ ! "$output" =~ "YubiKey #" ]]
}

@test "yk-status: PIN check shows [OK] when PIN is set (modern ykman)" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="PIN:                          8 attempt(s) remaining"
	run yk-status
	[ "$status" -eq 0 ]
	[[ "$output" =~ "FIDO2 PIN:     [OK] set" ]]
}

@test "yk-status: PIN check shows [WARN] when PIN is not set" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="PIN:                          Not set"
	run yk-status
	[ "$status" -eq 0 ]
	[[ "$output" =~ "FIDO2 PIN:     [WARN] not set" ]]
	[[ "$output" =~ "yk-enroll" ]]
}

@test "yk-status: SSH key check shows [OK] when ~/.ssh/id_ed25519_sk_<serial> exists" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="PIN:                          8 attempt(s) remaining"
	mkdir -p "$TEST_HOME/.ssh"
	echo handle >"$TEST_HOME/.ssh/id_ed25519_sk_12345"
	echo pub >"$TEST_HOME/.ssh/id_ed25519_sk_12345.pub"
	run yk-status
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SSH key:       [OK]" ]]
	[[ "$output" =~ "id_ed25519_sk_12345.pub" ]]
}

@test "yk-status: SSH key check shows [WARN] when no per-serial file exists" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="PIN:                          Not set"
	run yk-status
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SSH key:       [WARN] not enrolled" ]]
}

@test "yk-status: warns on firmware <5.7" {
	mock_ykman
	export YKMAN_SERIALS="99"
	export YKMAN_INFO_99="Device type: YubiKey 5C
Firmware version: 5.4.3
Form factor: Keychain (USB-C)"
	run yk-status
	[ "$status" -eq 0 ]
	[[ "$output" =~ "firmware <5.7" ]]
	# Non-FIPS heading must NOT have the FIPS marker.
	[[ ! "$output" =~ "·  FIPS" ]]
}

@test "yk-status: handles multiple keys" {
	mock_ykman
	export YKMAN_SERIALS="11
22"
	export YKMAN_INFO_11="Device type: YubiKey 5C NFC FIPS
Firmware version: 5.7.4"
	export YKMAN_INFO_22="Device type: YubiKey 5C
Firmware version: 5.4.3"
	export YKMAN_FIDO_11="PIN:                          8 attempt(s) remaining"
	export YKMAN_FIDO_22="PIN:                          Not set"
	run yk-status
	[ "$status" -eq 0 ]
	[[ "$output" =~ "serial 11" ]]
	[[ "$output" =~ "serial 22" ]]
}

@test "yk-status: --json includes device_type, pin_set, ssh_key" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5 NFC
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="PIN:                          8 attempt(s) remaining"
	run yk-status --json
	[ "$status" -eq 0 ]
	[[ "$output" =~ ^\[.*\]$ ]]
	[[ "$output" =~ \"serial\":\"12345\" ]]
	[[ "$output" =~ \"device_type\":\"YubiKey\ 5\ NFC\" ]]
	[[ "$output" =~ \"firmware\":\"5.7.4\" ]]
	[[ "$output" =~ \"pin_set\":\"true\" ]]
	[[ "$output" =~ \"ssh_key\":\"\" ]]
}

@test "yk-status: --serial filters output" {
	mock_ykman
	export YKMAN_SERIALS="11
22"
	export YKMAN_INFO_11="Device type: YubiKey 5C
Firmware version: 5.7.4"
	export YKMAN_INFO_22="Device type: YubiKey 5C NFC FIPS
Firmware version: 5.7.4"
	export YKMAN_FIDO_11="PIN:                          Not set"
	export YKMAN_FIDO_22="PIN:                          8 attempt(s) remaining"
	run yk-status --serial 22
	[ "$status" -eq 0 ]
	[[ "$output" =~ "serial 22" ]]
	[[ ! "$output" =~ "serial 11" ]]
}

@test "yk-status: zsh does not leak local declarations across iterations" {
	# Regression: with multiple YubiKeys connected, zsh used to print
	# `info=$'...'`, `fw=...` etc. on every iteration after the first
	# because `local` was re-declared inside the read loop. Fix: declare
	# all locals once at the function top.
	if ! command -v zsh >/dev/null 2>&1; then
		skip "zsh not installed"
	fi
	mock_ykman
	export YKMAN_SERIALS="11
22
33"
	export YKMAN_INFO_11="Device type: YubiKey 5C NFC FIPS
Firmware version: 5.7.4"
	export YKMAN_INFO_22="Device type: YubiKey 5C NFC FIPS
Firmware version: 5.4.3"
	export YKMAN_INFO_33="Device type: YubiKey 5C
Firmware version: 5.2.4"
	export YKMAN_FIDO_11="PIN:                          8 attempt(s) remaining"
	export YKMAN_FIDO_22="PIN:                          8 attempt(s) remaining"
	export YKMAN_FIDO_33="PIN:                          Not set"
	run zsh -c "
		source '${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-status.sh'
		export PATH='$TEST_BIN_DIR:$PATH'
		export HOME='$TEST_HOME'
		yk-status
	"
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ info=\$\' ]]
	[[ ! "$output" =~ fw=5\.7\.4$ ]]
	[[ ! "$output" =~ ^major=5$ ]]
	[[ ! "$output" =~ ^minor=[0-9]+$ ]]
	[[ "$output" =~ "serial 11" ]]
	[[ "$output" =~ "serial 22" ]]
	[[ "$output" =~ "serial 33" ]]
}
