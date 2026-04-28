#!/usr/bin/env bats
# Tests for dns_flush fish function

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	FUNCTION_PATH="$REPO_ROOT/home/dot_config/fish/functions/dns_flush.fish"
	export FUNCTION_PATH
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_BIN_DIR
	export ORIGINAL_PATH="$PATH"
}

teardown() {
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
}

@test "dns_flush: function file exists" {
	[ -f "$FUNCTION_PATH" ]
}

@test "dns_flush: function file has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish -n "$FUNCTION_PATH"
	[ "$status" -eq 0 ]
}

@test "dns_flush: help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; dns_flush --help"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: dns_flush" ]]
	[[ "$output" =~ "macOS" ]]
}

@test "dns_flush: short help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; dns_flush -h"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: dns_flush" ]]
}

@test "dns_flush: unknown option returns error" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; dns_flush --invalid-option"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
}

@test "dns_flush: fails on non-macOS systems (mocked uname)" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	# Mock uname to return Linux
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Linux"
EOF
	chmod +x "$TEST_BIN_DIR/uname"
	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; dns_flush"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "only works on macOS" ]]
}

@test "dns_flush: succeeds with mocked uname=Darwin and mocked sudo/killall" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
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
	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; dns_flush"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "DNS cache flushed" ]]
}

@test "dns_flush: verbose mode produces extra output" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
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
	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; dns_flush --verbose"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Flushing DNS cache" ]]
}
