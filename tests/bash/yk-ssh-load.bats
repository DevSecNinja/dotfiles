#!/usr/bin/env bats
# Tests for yk-ssh-load

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-ssh-load.sh"
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_BIN_DIR
	export ORIGINAL_PATH="$PATH"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
}

teardown() {
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
}

mock_ssh_add() {
	cat >"$TEST_BIN_DIR/ssh-add" <<EOF
#!/bin/bash
exit $1
EOF
	chmod +x "$TEST_BIN_DIR/ssh-add"
}

@test "yk-ssh-load: errors without ssh-agent" {
	mock_ssh_add 0
	unset SSH_AUTH_SOCK
	run yk-ssh-load
	[ "$status" -eq 1 ]
	[[ "$output" =~ "no ssh-agent running" ]]
}

@test "yk-ssh-load: succeeds with mocked ssh-add" {
	mock_ssh_add 0
	export SSH_AUTH_SOCK="/tmp/fake.sock"
	run yk-ssh-load --quiet
	[ "$status" -eq 0 ]
}

@test "yk-ssh-load: surfaces ssh-add failure" {
	mock_ssh_add 1
	export SSH_AUTH_SOCK="/tmp/fake.sock"
	run yk-ssh-load --quiet
	[ "$status" -eq 1 ]
	[[ "$output" =~ "ssh-add -K failed" ]]
}
