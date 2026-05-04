#!/usr/bin/env bats
# Tests for yk-ssh-new

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-ssh-new.sh"
	TEST_BIN_DIR="$(mktemp -d)"
	TEST_HOME="$(mktemp -d)"
	export TEST_BIN_DIR TEST_HOME
	export ORIGINAL_PATH="$PATH"
	export ORIGINAL_HOME="$HOME"
	export HOME="$TEST_HOME"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"

	# Mock ssh-keygen: write a fake pubkey at -f path + ".pub"
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

@test "yk-ssh-new: help" {
	run yk-ssh-new --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Generate a hardware-backed SSH key" ]]
}

@test "yk-ssh-new: rejects unknown type" {
	run yk-ssh-new --type rsa
	[ "$status" -eq 1 ]
	[[ "$output" =~ "must be ed25519-sk or ecdsa-sk" ]]
}

@test "yk-ssh-new: rejects non-ssh application string" {
	run yk-ssh-new --application web:foo
	[ "$status" -eq 1 ]
	[[ "$output" =~ "must start with 'ssh:'" ]]
}

@test "yk-ssh-new: writes default ed25519-sk and prints next steps" {
	run yk-ssh-new
	[ "$status" -eq 0 ]
	[ -f "$TEST_HOME/.ssh/id_ed25519_sk" ]
	[ -f "$TEST_HOME/.ssh/id_ed25519_sk.pub" ]
	[[ "$output" =~ "Public key" ]]
	[[ "$output" =~ "Next steps" ]]
	[[ "$output" =~ "ssh-add -K" ]]
}

@test "yk-ssh-new: ecdsa-sk uses different default path" {
	run yk-ssh-new --type ecdsa-sk
	[ "$status" -eq 0 ]
	[ -f "$TEST_HOME/.ssh/id_ecdsa_sk.pub" ]
}

@test "yk-ssh-new: refuses to overwrite existing key" {
	mkdir -p "$TEST_HOME/.ssh"
	echo "existing" >"$TEST_HOME/.ssh/id_ed25519_sk"
	run yk-ssh-new
	[ "$status" -eq 1 ]
	[[ "$output" =~ "already exists" ]]
}

@test "yk-ssh-new: --no-resident omits ssh-add -K hint" {
	run yk-ssh-new --no-resident
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ "ssh-add -K" ]]
}

@test "yk-ssh-new: --no-summary suppresses Next steps footer" {
	run yk-ssh-new --no-summary
	[ "$status" -eq 0 ]
	# Public key block still printed.
	[[ "$output" =~ "Public key" ]]
	# But the Next steps footer is gone.
	[[ ! "$output" =~ "Next steps:" ]]
	[[ ! "$output" =~ "ssh-add -K" ]]
	[[ ! "$output" =~ "gh ssh-key add" ]]
}
