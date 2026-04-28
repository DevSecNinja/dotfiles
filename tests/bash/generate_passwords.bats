#!/usr/bin/env bats
# Tests for generate_passwords fish function

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	FUNCTION_PATH="$REPO_ROOT/home/dot_config/fish/functions/generate_passwords.fish"
	export FUNCTION_PATH
}

# Wrapper that runs `generate_passwords` inside fish with Bats's internal
# file descriptor 3 closed AND with stdout/stderr redirected to a file.
#
# The fish function spawns `tr -cd '[:alnum:]' </dev/urandom | fold | head`.
# `tr`/`fold` inherit ALL of the parent shell's file descriptors, including:
#   - fd 3 (Bats's internal log channel — keeps Bats waiting forever)
#   - fd 1/2 connected to Bats's `tee` capture pipe
# Even though `head` exits after one line and SIGPIPE *should* kill the upstream
# pipeline, on the GitHub Actions Linux runner `tr` and `fold` are sometimes
# orphaned and keep all inherited fds open, hanging the test.
#
# Closing fd 3 + redirecting stdout/stderr to a temp file (then catting it
# back) ensures none of those fds is held open by orphaned children.
# Ref: https://bats-core.readthedocs.io/en/stable/writing-tests.html#file-descriptor-3-read-this-if-bats-hangs
_fish_gp() {
	local out
	out="$(mktemp)"
	(
		exec 3>&- 4>&- 5>&-
		fish --no-config -c "source '$FUNCTION_PATH'; generate_passwords $*"
	) >"$out" 2>&1 </dev/null
	local rc=$?
	cat "$out"
	rm -f "$out"
	return "$rc"
}

@test "generate_passwords: function file exists" {
	[ -f "$FUNCTION_PATH" ]
}

@test "generate_passwords: function file has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish -n "$FUNCTION_PATH"
	[ "$status" -eq 0 ]
}

@test "generate_passwords: help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; generate_passwords --help"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: generate_passwords" ]]
	[[ "$output" =~ "LENGTH" ]]
	[[ "$output" =~ "--count" ]]
}

@test "generate_passwords: short help option works" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; generate_passwords -h"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: generate_passwords" ]]
}

@test "generate_passwords: invalid count returns error" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; generate_passwords --count abc"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Count must be a positive integer" ]]
}

@test "generate_passwords: invalid length returns error" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; generate_passwords abc"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Password length must be a positive integer" ]]
}

@test "generate_passwords: defaults produce 5 passwords of length 64" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run _fish_gp
	[ "$status" -eq 0 ]
	# 5 password lines after header line (count password lines of length 64 alnum)
	password_lines=$(echo "$output" | grep -E '^[A-Za-z0-9]{64}$' | wc -l)
	[ "$password_lines" -eq 5 ]
}

@test "generate_passwords: custom length produces correct length passwords" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run _fish_gp 16
	[ "$status" -eq 0 ]
	password_lines=$(echo "$output" | grep -E '^[A-Za-z0-9]{16}$' | wc -l)
	[ "$password_lines" -eq 5 ]
}

@test "generate_passwords: custom count produces correct number of passwords" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run _fish_gp 12 --count 3
	[ "$status" -eq 0 ]
	password_lines=$(echo "$output" | grep -E '^[A-Za-z0-9]{12}$' | wc -l)
	[ "$password_lines" -eq 3 ]
}

@test "generate_passwords: header includes count and length" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run _fish_gp 8 --count 2
	[ "$status" -eq 0 ]
	[[ "$output" =~ "2 password" ]]
	[[ "$output" =~ "8 characters" ]]
}
