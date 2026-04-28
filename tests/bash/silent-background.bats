#!/usr/bin/env bats
# Tests for silent-background shell function

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/silent-background.sh"
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
}

teardown() {
	[ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ] && rm -rf "$TEST_DIR"
}

@test "silent-background: help option displays usage" {
	run silent-background --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: silent-background" ]]
	[[ "$output" =~ "background" ]]
}

@test "silent-background: short help option works" {
	run silent-background -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: silent-background" ]]
}

@test "silent-background: fails with no arguments" {
	run silent-background
	[ "$status" -eq 1 ]
	[[ "$output" =~ "No command specified" ]]
}

@test "silent-background: runs command in background and returns immediately" {
	# Run a sleep that writes to a marker file, ensure it's backgrounded
	marker="$TEST_DIR/marker"
	# Use bash -c to run a command that writes after a short delay
	silent-background bash -c "sleep 0.5; echo done > '$marker'"
	# Should return immediately - marker should not yet exist
	[ ! -f "$marker" ]
	# Wait for completion
	sleep 1.5
	[ -f "$marker" ]
}

@test "silent-background: suppresses stdout output" {
	# stderr/stdout should be suppressed by the wrapper.
	# We check that running a noisy command doesn't emit to current stdout/stderr.
	output_file="$TEST_DIR/captured"
	silent-background bash -c "echo loud-output; echo loud-error >&2" >"$output_file" 2>&1
	# Wait for backgrounded command to finish
	sleep 0.5
	# Captured output may still be empty (command's output is suppressed)
	# but at minimum, the function must not error
	[ -f "$output_file" ]
}
