#!/usr/bin/env bats
# Tests for generate-passwords shell function

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/generate-passwords.sh"
}

# Wrapper that runs generate-passwords in a subshell with Bats's internal
# file descriptor 3 closed AND with stdout/stderr redirected to a file.
#
# The function under test spawns `tr -cd '[:alnum:]' </dev/urandom | fold | head`.
# `tr`/`fold` inherit ALL the parent shell's file descriptors, including:
#   - fd 3 (Bats's internal log channel — keeps Bats waiting forever)
#   - fd 1/2 connected to Bats's `tee` capture pipe
# Even though `head` exits after one line and SIGPIPE *should* kill the upstream
# pipeline, on the GitHub Actions Linux runner `tr` and `fold` are sometimes
# orphaned and keep all inherited fds open, hanging the test.
#
# Closing fd 3 + redirecting stdout/stderr to a temp file (then catting it
# back) ensures none of those fds is held open by orphaned children.
# Ref: https://bats-core.readthedocs.io/en/stable/writing-tests.html#file-descriptor-3-read-this-if-bats-hangs
_gp() {
	local out
	out="$(mktemp)"
	(
		exec 3>&- 4>&- 5>&-
		generate-passwords "$@"
	) >"$out" 2>&1 </dev/null
	local rc=$?
	cat "$out"
	rm -f "$out"
	return "$rc"
}

@test "generate-passwords: help option displays usage" {
	run _gp --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: generate-passwords" ]]
	[[ "$output" =~ "LENGTH" ]]
	[[ "$output" =~ "--count" ]]
}

@test "generate-passwords: short help option works" {
	run _gp -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: generate-passwords" ]]
}

@test "generate-passwords: invalid count returns error" {
	run _gp --count abc
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Count must be a positive integer" ]]
}

@test "generate-passwords: missing count argument returns error" {
	run _gp --count
	[ "$status" -eq 1 ]
	[[ "$output" =~ "--count requires" ]]
}

@test "generate-passwords: invalid length returns error" {
	run _gp abc
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Password length must be a positive integer" ]]
}

@test "generate-passwords: unknown option returns error" {
	run _gp --invalid-option
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
}

@test "generate-passwords: defaults produce 5 passwords of length 64" {
	run _gp
	[ "$status" -eq 0 ]
	password_lines=$(echo "$output" | grep -E '^[A-Za-z0-9]{64}$' | wc -l)
	[ "$password_lines" -eq 5 ]
}

@test "generate-passwords: custom length produces correct length passwords" {
	run _gp 16
	[ "$status" -eq 0 ]
	password_lines=$(echo "$output" | grep -E '^[A-Za-z0-9]{16}$' | wc -l)
	[ "$password_lines" -eq 5 ]
}

@test "generate-passwords: custom count produces correct number of passwords" {
	run _gp 12 --count 3
	[ "$status" -eq 0 ]
	password_lines=$(echo "$output" | grep -E '^[A-Za-z0-9]{12}$' | wc -l)
	[ "$password_lines" -eq 3 ]
}

@test "generate-passwords: short -c count flag works" {
	run _gp 10 -c 2
	[ "$status" -eq 0 ]
	password_lines=$(echo "$output" | grep -E '^[A-Za-z0-9]{10}$' | wc -l)
	[ "$password_lines" -eq 2 ]
}

@test "generate-passwords: header includes count and length" {
	run _gp 8 --count 2
	[ "$status" -eq 0 ]
	[[ "$output" =~ "2 password" ]]
	[[ "$output" =~ "8 characters" ]]
}
