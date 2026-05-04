#!/usr/bin/env bats
# Tests for yk-touch-watch (smoke/cli only — does not exercise the watch loop)

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-touch-watch.sh"
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_BIN_DIR
	export ORIGINAL_PATH="$PATH"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
}

teardown() {
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
}

@test "yk-touch-watch: --help prints usage" {
	cat >"$TEST_BIN_DIR/ykman" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/ykman"
	run yk-touch-watch --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: yk-touch-watch" ]]
}

@test "yk-touch-watch: errors when ykman missing" {
	export PATH=/nonexistent
	run yk-touch-watch
	[ "$status" -eq 1 ]
	[[ "$output" =~ "'ykman' not found" ]]
}

@test "yk-touch-watch: rejects unknown option" {
	cat >"$TEST_BIN_DIR/ykman" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/ykman"
	run yk-touch-watch --bogus
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
}

@test "yk-touch-watch: --once exits on first detected touch state" {
	# Mock ykman info to print a touch line on every call.
	cat >"$TEST_BIN_DIR/ykman" <<'EOF'
#!/bin/bash
[ "$1" = "info" ] && echo "Touch policy: required"
EOF
	chmod +x "$TEST_BIN_DIR/ykman"
	# Invoke the script file directly so `timeout` resolves it as an executable.
	run timeout 5 "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-touch-watch.sh" --once --no-bell --interval 0.05
	[ "$status" -eq 0 ]
	[[ "$output" =~ "YubiKey touch" ]]
}
