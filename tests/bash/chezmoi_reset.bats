#!/usr/bin/env bats
# Tests for chezmoi_reset fish function

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT

	FUNCTION_PATH="$REPO_ROOT/home/dot_config/fish/functions/chezmoi_reset.fish"
	export FUNCTION_PATH

	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_BIN_DIR
	export ORIGINAL_PATH="$PATH"
}

teardown() {
	if [ -n "$ORIGINAL_PATH" ]; then
		export PATH="$ORIGINAL_PATH"
	fi
	if [ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ]; then
		rm -rf "$TEST_BIN_DIR"
	fi
}

@test "chezmoi_reset: function file exists" {
	[ -f "$FUNCTION_PATH" ]
}

@test "chezmoi_reset: function file has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish -n "$FUNCTION_PATH"
	[ "$status" -eq 0 ]
}

@test "chezmoi_reset: help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; chezmoi_reset --help"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: chezmoi_reset" ]]
	[[ "$output" =~ "once" ]]
	[[ "$output" =~ "onchange" ]]
	[[ "$output" =~ "all" ]]
}

@test "chezmoi_reset: short help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; chezmoi_reset -h"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: chezmoi_reset" ]]
}

@test "chezmoi_reset: fails when chezmoi is not installed" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	# Empty PATH so chezmoi is not found
	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR'; source '$FUNCTION_PATH'; chezmoi_reset once -f"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "chezmoi is not installed" ]]
}

@test "chezmoi_reset: fails when no argument is provided" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	# Mock chezmoi
	cat >"$TEST_BIN_DIR/chezmoi" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/chezmoi"
	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; chezmoi_reset"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Expected exactly one argument" ]]
}

@test "chezmoi_reset: fails with invalid type" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	cat >"$TEST_BIN_DIR/chezmoi" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/chezmoi"
	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; chezmoi_reset invalid -f"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Invalid type" ]]
}

@test "chezmoi_reset: succeeds for 'once' with --force" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	cat >"$TEST_BIN_DIR/chezmoi" <<'EOF'
#!/bin/bash
echo "chezmoi $@"
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/chezmoi"
	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; chezmoi_reset once --force"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "scriptState" ]]
	[[ "$output" =~ "Successfully reset" ]]
}

@test "chezmoi_reset: succeeds for 'onchange' with --force" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	cat >"$TEST_BIN_DIR/chezmoi" <<'EOF'
#!/bin/bash
echo "chezmoi $@"
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/chezmoi"
	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; chezmoi_reset onchange -f"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "entryState" ]]
}

@test "chezmoi_reset: succeeds for 'all' with --force" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	cat >"$TEST_BIN_DIR/chezmoi" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/chezmoi"
	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; chezmoi_reset all -f"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "entryState" ]]
	[[ "$output" =~ "scriptState" ]]
}

@test "chezmoi_reset: reports failure when chezmoi command fails" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	cat >"$TEST_BIN_DIR/chezmoi" <<'EOF'
#!/bin/bash
echo "chezmoi error" >&2
exit 1
EOF
	chmod +x "$TEST_BIN_DIR/chezmoi"
	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; chezmoi_reset once -f"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Failed to reset" ]]
}
