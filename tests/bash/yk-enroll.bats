#!/usr/bin/env bats
# Tests for yk-enroll

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-enroll.sh"
	# yk-enroll calls yk-ssh-new internally; load it so it's resolvable.
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-ssh-new.sh"
	TEST_BIN_DIR="$(mktemp -d)"
	TEST_HOME="$(mktemp -d)"
	export TEST_BIN_DIR TEST_HOME
	export ORIGINAL_PATH="$PATH"
	export ORIGINAL_HOME="$HOME"
	export HOME="$TEST_HOME"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"

	# Default ssh-keygen mock — writes a fake pubkey.
	cat >"$TEST_BIN_DIR/ssh-keygen" <<'EOF'
#!/bin/bash
out=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		-f) out="$2"; shift 2 ;;
		*) shift ;;
	esac
done
: >"$out"
echo "ssh-ed25519-sk AAAAfake user@host" >"${out}.pub"
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/ssh-keygen"
}

teardown() {
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$ORIGINAL_HOME" ] && export HOME="$ORIGINAL_HOME"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
	[ -n "$TEST_HOME" ] && [ -d "$TEST_HOME" ] && rm -rf "$TEST_HOME"
}

# Mock ykman supporting:
#   list --serials                       -> $YKMAN_SERIALS
#   --device <sn> info                   -> $YKMAN_INFO_<sn>
#   --device <sn> fido info              -> $YKMAN_FIDO_<sn>
#   --device <sn> fido access change-pin -> exit 0 unless YKMAN_PIN_FAIL=1
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
		"fido access")
			if [[ "$3" == "change-pin" ]]; then
				[[ -n "$YKMAN_PIN_FAIL" ]] && exit 1
				exit 0
			fi
			;;
	esac
fi
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/ykman"
}

@test "yk-enroll: help" {
	run yk-enroll --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Idempotent YubiKey enrollment wizard" ]]
}

@test "yk-enroll: errors when ykman missing" {
	export PATH="/nonexistent"
	run yk-enroll
	[ "$status" -eq 1 ]
	[[ "$output" =~ "'ykman' not found" ]]
}

@test "yk-enroll: errors when no YubiKey detected" {
	mock_ykman
	export YKMAN_SERIALS=""
	run yk-enroll
	[ "$status" -eq 1 ]
	[[ "$output" =~ "No YubiKey detected" ]]
}

@test "yk-enroll: errors with multiple keys connected" {
	mock_ykman
	export YKMAN_SERIALS="11
22"
	run yk-enroll
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Multiple YubiKeys connected" ]]
	[[ "$output" =~ "- 11" ]]
	[[ "$output" =~ "- 22" ]]
}

@test "yk-enroll: rejects ed25519-sk on firmware <5.2.3" {
	mock_ykman
	export YKMAN_SERIALS="55"
	export YKMAN_INFO_55="Device type: YubiKey 4
Firmware version: 4.3.7"
	run yk-enroll
	[ "$status" -eq 1 ]
	[[ "$output" =~ "too old for ed25519-sk" ]]
	[[ "$output" =~ "yk-enroll --type ecdsa-sk" ]]
}

@test "yk-enroll: full happy path enrolls a fresh key" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC FIPS
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="PIN is set, with 8 attempts remaining."
	run yk-enroll
	[ "$status" -eq 0 ]
	[[ "$output" =~ "[1/5] Preflight" ]]
	[[ "$output" =~ "[2/5] Detect YubiKey" ]]
	[[ "$output" =~ "YubiKey 5C NFC FIPS (serial 12345" ]]
	[[ "$output" =~ "FIDO2 PIN is set" ]]
	[[ "$output" =~ "Enrolled: " ]]
	[ -f "$TEST_HOME/.ssh/id_ed25519_sk_12345" ]
	[ -f "$TEST_HOME/.ssh/id_ed25519_sk_12345.pub" ]
	[[ "$output" =~ "gh ssh-key add" ]]
	[[ "$output" =~ "id_ed25519_sk_12345.pub" ]]
	# Suggested title uses device type + last 4 of serial; no hostname
	# (a YubiKey is portable, so a host-prefixed title is misleading).
	[[ "$output" =~ "YubiKey 5C NFC FIPS (·2345)" ]]
	[[ ! "$output" =~ "@ " ]]
	# yk-ssh-new's "Next steps" footer must NOT appear (yk-enroll prints
	# its own Done block and passes --no-summary to yk-ssh-new).
	[[ ! "$output" =~ "Next steps:" ]]
	# But the wizard's own "Done. Next steps for serial" block must.
	[[ "$output" =~ "Done. Next steps for serial" ]]
	# Both gh ssh-key add invocations (auth + signing) must be present —
	# uploading a *signing* key isn't optional, that's the whole point.
	[[ "$output" =~ "--type authentication" ]]
	[[ "$output" =~ "--type signing" ]]
	# The wizard nudges users through the git-signing wiring.
	[[ "$output" =~ "yk-git-sign-setup" ]]
	[[ "$output" =~ "chezmoi apply" ]]
}

@test "yk-enroll: idempotent — skips key generation when file exists" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC FIPS
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="PIN is set, with 8 attempts remaining."
	mkdir -p "$TEST_HOME/.ssh"
	echo "existing" >"$TEST_HOME/.ssh/id_ed25519_sk_12345"
	echo "existing-pub" >"$TEST_HOME/.ssh/id_ed25519_sk_12345.pub"
	# Make ssh-keygen explode if it's actually called — proves we skipped.
	cat >"$TEST_BIN_DIR/ssh-keygen" <<'EOF'
#!/bin/bash
echo "ssh-keygen should not have run on idempotent path" >&2
exit 99
EOF
	chmod +x "$TEST_BIN_DIR/ssh-keygen"
	run yk-enroll
	[ "$status" -eq 0 ]
	[[ "$output" =~ "already enrolled" ]]
}

@test "yk-enroll: --check is read-only when PIN missing and key missing" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="PIN is not set."
	# Make ssh-keygen and change-pin explode — --check must not call them.
	cat >"$TEST_BIN_DIR/ssh-keygen" <<'EOF'
#!/bin/bash
echo "ssh-keygen called under --check" >&2; exit 99
EOF
	chmod +x "$TEST_BIN_DIR/ssh-keygen"
	export YKMAN_PIN_FAIL=1
	run yk-enroll --check
	[ "$status" -eq 0 ]
	[[ "$output" =~ "FIDO2 PIN is NOT set" ]]
	[[ "$output" =~ "skipped: --check" ]]
	[[ "$output" =~ "No SSH key at " ]]
	[ ! -f "$TEST_HOME/.ssh/id_ed25519_sk_12345" ]
}

@test "yk-enroll: sets PIN when not present" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="PIN is not set."
	run yk-enroll
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Setting one now" ]]
	[[ "$output" =~ "FIDO2 PIN set" ]]
}

@test "yk-enroll: errors when change-pin fails" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="PIN is not set."
	export YKMAN_PIN_FAIL=1
	run yk-enroll
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Failed to set FIDO2 PIN" ]]
}

@test "yk-enroll: per-serial filename for multi-key setup" {
	mock_ykman
	export YKMAN_INFO_11="Device type: YubiKey 5C NFC
Firmware version: 5.7.4"
	export YKMAN_INFO_22="Device type: YubiKey 5C
Firmware version: 5.4.3"
	export YKMAN_FIDO_11="PIN is set."
	export YKMAN_FIDO_22="PIN is set."
	export YKMAN_SERIALS="11"
	run yk-enroll
	[ "$status" -eq 0 ]
	[ -f "$TEST_HOME/.ssh/id_ed25519_sk_11" ]
	export YKMAN_SERIALS="22"
	run yk-enroll
	[ "$status" -eq 0 ]
	[ -f "$TEST_HOME/.ssh/id_ed25519_sk_22" ]
	[ -f "$TEST_HOME/.ssh/id_ed25519_sk_11" ]
}

@test "yk-enroll: warns about FIPS factory default PIN" {
	mock_ykman
	export YKMAN_SERIALS="35984479"
	export YKMAN_INFO_35984479="Device type: YubiKey 5C NFC FIPS
Firmware version: 5.7.4"
	export YKMAN_FIDO_35984479="PIN is set, with 8 attempts remaining."
	# Non-interactive (run by bats has no controlling tty), so no prompt.
	run yk-enroll --check
	[ "$status" -eq 0 ]
	[[ "$output" =~ "FIPS YubiKey" ]]
	[[ "$output" =~ "factory default PIN '123456'" ]]
	[[ "$output" =~ "rotate it now" ]]
}

@test "yk-enroll: --rotate-pin forces change-pin even when PIN is set" {
	mock_ykman
	export YKMAN_SERIALS="35984479"
	export YKMAN_INFO_35984479="Device type: YubiKey 5C NFC FIPS
Firmware version: 5.7.4"
	export YKMAN_FIDO_35984479="PIN is set, with 8 attempts remaining."
	# Existing key file so step 5 short-circuits cleanly.
	mkdir -p "$TEST_HOME/.ssh"
	echo "existing" >"$TEST_HOME/.ssh/id_ed25519_sk_35984479"
	echo "existing" >"$TEST_HOME/.ssh/id_ed25519_sk_35984479.pub"
	run yk-enroll --rotate-pin
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Rotating FIDO2 PIN now" ]]
	[[ "$output" =~ "FIDO2 PIN rotated" ]]
}

@test "yk-enroll: --rotate-pin under --check is a no-op" {
	mock_ykman
	export YKMAN_SERIALS="35984479"
	export YKMAN_INFO_35984479="Device type: YubiKey 5C NFC FIPS
Firmware version: 5.7.4"
	export YKMAN_FIDO_35984479="PIN is set, with 8 attempts remaining."
	export YKMAN_PIN_FAIL=1 # would fail if actually called
	run yk-enroll --rotate-pin --check
	[ "$status" -eq 0 ]
	[[ "$output" =~ "--rotate-pin requested but --check is read-only" ]]
}

@test "yk-enroll: non-FIPS key with PIN set does NOT prompt for rotation" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="PIN is set, with 8 attempts remaining."
	mkdir -p "$TEST_HOME/.ssh"
	echo "existing" >"$TEST_HOME/.ssh/id_ed25519_sk_12345"
	echo "existing" >"$TEST_HOME/.ssh/id_ed25519_sk_12345.pub"
	run yk-enroll
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ "factory default" ]]
	[[ ! "$output" =~ "Change FIDO2 PIN now" ]]
	[[ "$output" =~ "FIDO2 PIN is set." ]]
}

@test "yk-enroll: aborts when ssh-keygen exits 0 but no file was written (Ctrl+C)" {
	# Regression: user pressed Ctrl+C at the FIDO2 PIN prompt during
	# enrollment. ssh-keygen returned 0 (or fish's pipeline lost the
	# non-zero), so the wizard previously printed "Enrolled" and "Done"
	# even though no key file was created. Trust the filesystem.
	mock_ykman
	export YKMAN_SERIALS="35984479"
	export YKMAN_INFO_35984479="Device type: YubiKey 5C NFC FIPS
Firmware version: 5.7.4"
	export YKMAN_FIDO_35984479="PIN is set, with 8 attempts remaining."
	# Replace the default ssh-keygen mock with one that "succeeds" but
	# writes nothing (mimicking interrupted FIDO2 enrollment).
	cat >"$TEST_BIN_DIR/ssh-keygen" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/ssh-keygen"
	run yk-enroll
	[ "$status" -eq 1 ]
	[[ ! "$output" =~ "Enrolled:" ]]
	[[ ! "$output" =~ "Done. Next steps" ]]
	[[ "$output" =~ "was not created" ]]
	[ ! -f "$TEST_HOME/.ssh/id_ed25519_sk_35984479" ]
}

@test "yk-enroll: detects modern ykman PIN format ('PIN: 8 attempt(s) remaining')" {
	# Regression: real-world ykman 5.x output is
	#   PIN:                          8 attempt(s) remaining
	# The old regex 'PIN is set|PIN.*set' missed this entirely, so the
	# wizard treated a configured PIN as 'PIN is not set' and tried to
	# set a new one (which then prompted for the *current* PIN, very
	# confusing).
	mock_ykman
	export YKMAN_SERIALS="35984479"
	export YKMAN_INFO_35984479="Device type: YubiKey 5C NFC FIPS
Firmware version: 5.7.4"
	export YKMAN_FIDO_35984479="FIPS approved:                True
AAGUID:                       79f3c8ba-9e35-484b-8f47-53a5a0f5c630
PIN:                          8 attempt(s) remaining
Minimum PIN length:           8
Always Require UV:            On
Credential storage remaining: 99
Enterprise Attestation:       Enabled"
	mkdir -p "$TEST_HOME/.ssh"
	echo existing >"$TEST_HOME/.ssh/id_ed25519_sk_35984479"
	echo existing >"$TEST_HOME/.ssh/id_ed25519_sk_35984479.pub"
	run yk-enroll
	[ "$status" -eq 0 ]
	# Must NOT think the PIN is missing.
	[[ ! "$output" =~ "No FIDO2 PIN set" ]]
	[[ ! "$output" =~ "Setting one now" ]]
	# It's a FIPS key, so the FIPS warning fires (correctly).
	[[ "$output" =~ "factory default PIN" ]]
}

@test "yk-enroll: detects modern ykman 'PIN: Not set' as no PIN" {
	mock_ykman
	export YKMAN_SERIALS="12345"
	export YKMAN_INFO_12345="Device type: YubiKey 5C NFC
Firmware version: 5.7.4"
	export YKMAN_FIDO_12345="AAGUID:                       deadbeef
PIN:                          Not set
Minimum PIN length:           4"
	run yk-enroll --check
	[ "$status" -eq 0 ]
	[[ "$output" =~ "FIDO2 PIN is NOT set" ]]
}
