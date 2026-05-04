#!/usr/bin/env bats
# Tests for yk-status

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-status.sh"
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_BIN_DIR
	export ORIGINAL_PATH="$PATH"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
}

teardown() {
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
}

mock_ykman() {
	cat >"$TEST_BIN_DIR/ykman" <<'EOF'
#!/bin/bash
case "$1 $2" in
	"list --serials")
		printf '%s\n' $YKMAN_SERIALS
		;;
	"--device "*)
		serial="$2"
		shift 3  # drop --device <sn> info
		varname="YKMAN_INFO_${serial}"
		printf '%s\n' "${!varname}"
		;;
esac
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

@test "yk-status: prints fw 5.7 fips device" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC FIPS
Serial number: 12345
Firmware version: 5.7.4
Form factor: Keychain (USB-C), NFC
FIPS approved: Yes"
	run yk-status
	[ "$status" -eq 0 ]
	[[ "$output" =~ "YubiKey #12345" ]]
	[[ "$output" =~ "Firmware:" ]]
	[[ "$output" =~ "5.7.4" ]]
	[[ "$output" =~ "FIPS:        true" ]]
	[[ ! "$output" =~ "firmware <5.7" ]]
}

@test "yk-status: warns on firmware <5.7" {
	mock_ykman
	export YKMAN_SERIALS="99"
	export YKMAN_INFO_99="Firmware version: 5.4.3
Form factor: Keychain (USB-C)"
	run yk-status
	[ "$status" -eq 0 ]
	[[ "$output" =~ "firmware <5.7" ]]
	[[ "$output" =~ "FIPS:        false" ]]
}

@test "yk-status: handles multiple keys" {
	mock_ykman
	export YKMAN_SERIALS="11
22"
	export YKMAN_INFO_11="Firmware version: 5.7.4"
	export YKMAN_INFO_22="Firmware version: 5.4.3"
	run yk-status
	[ "$status" -eq 0 ]
	[[ "$output" =~ "YubiKey #11" ]]
	[[ "$output" =~ "YubiKey #22" ]]
}

@test "yk-status: --json emits parseable array" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Firmware version: 5.7.4
Form factor: Keychain (USB-C)"
	run yk-status --json
	[ "$status" -eq 0 ]
	[[ "$output" =~ ^\[.*\]$ ]]
	[[ "$output" =~ \"serial\":\"12345\" ]]
	[[ "$output" =~ \"firmware\":\"5.7.4\" ]]
}

@test "yk-status: --serial filters output" {
	mock_ykman
	export YKMAN_SERIALS="11
22"
	export YKMAN_INFO_22="Firmware version: 5.7.4"
	run yk-status --serial 22
	[ "$status" -eq 0 ]
	[[ "$output" =~ "YubiKey #22" ]]
	[[ ! "$output" =~ "YubiKey #11" ]]
}
