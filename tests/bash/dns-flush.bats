#!/usr/bin/env bats
# Tests for dns-flush shell function

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/dns-flush.sh"
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_BIN_DIR
	export ORIGINAL_PATH="$PATH"
}

teardown() {
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
}

@test "dns-flush: help option displays usage" {
	run dns-flush --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: dns-flush" ]]
	[[ "$output" =~ "macOS" ]]
}

@test "dns-flush: short help option works" {
	run dns-flush -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: dns-flush" ]]
}

@test "dns-flush: unknown option returns error" {
	run dns-flush --invalid-option
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
}

@test "dns-flush: fails on non-macOS systems (mocked uname)" {
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Linux"
EOF
	chmod +x "$TEST_BIN_DIR/uname"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
	run dns-flush
	[ "$status" -eq 1 ]
	[[ "$output" =~ "only works on macOS" ]]
}

@test "dns-flush: succeeds with mocked uname=Darwin and mocked sudo" {
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Darwin"
EOF
	chmod +x "$TEST_BIN_DIR/uname"
	cat >"$TEST_BIN_DIR/sudo" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/sudo"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
	run dns-flush
	[ "$status" -eq 0 ]
	[[ "$output" =~ "DNS cache flushed" ]]
}

@test "dns-flush: verbose mode produces extra output" {
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Darwin"
EOF
	chmod +x "$TEST_BIN_DIR/uname"
	cat >"$TEST_BIN_DIR/sudo" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/sudo"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
	run dns-flush --verbose
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Flushing DNS cache" ]]
	[[ "$output" =~ "successfully" ]]
}

@test "dns-flush: fails when sudo killall fails" {
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Darwin"
EOF
	chmod +x "$TEST_BIN_DIR/uname"
	cat >"$TEST_BIN_DIR/sudo" <<'EOF'
#!/bin/bash
exit 1
EOF
	chmod +x "$TEST_BIN_DIR/sudo"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
	run dns-flush
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Failed to flush DNS cache" ]]
}
