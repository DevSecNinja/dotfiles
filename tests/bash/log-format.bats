#!/usr/bin/env bats
# Format / level / tag tests for log.sh

load 'helpers/common'

setup() {
	common_setup
	LOG_SCRIPT="$REPO_ROOT/home/dot_config/shell/functions/log.sh"
	export LOG_SCRIPT
	# Defaults the tests rely on
	export LOG_JOURNAL=never
	export LOG_COLOR=never
	export LOG_TIMESTAMP="2026-04-29T12:00:00Z"
}

teardown() { common_teardown; }

@test "log: helper has valid sh and bash syntax" {
	run sh -n "$LOG_SCRIPT"
	assert_success
	run bash -n "$LOG_SCRIPT"
	assert_success
}

@test "log: helper is executable" {
	assert_file_executable "$LOG_SCRIPT"
}

@test "log_info: padded label, explicit tag in brackets" {
	run sh -c '. "$1"; log_info "hello"' sh "$LOG_SCRIPT"
	assert_success
	# When sourced interactively (no script $0), no tag should be shown.
	assert_output "2026-04-29T12:00:00Z INFO   hello"
}

@test "log_info: explicit LOG_TAG appears in brackets" {
	run sh -c 'LOG_TAG=demo; . "$1"; log_info "hello"' sh "$LOG_SCRIPT"
	assert_success
	assert_output "2026-04-29T12:00:00Z INFO   [demo] hello"
}

@test "log: levels render with 6-char padding" {
	run sh -c '. "$1"; LOG_TAG=t; log INFO "a"; log NOTICE "b"; log WARN "c" 2>&1; log ERROR "d" 2>&1; log_state "s"; log_result "r"' sh "$LOG_SCRIPT"
	assert_success
	assert_line --index 0 "2026-04-29T12:00:00Z INFO   [t] a"
	assert_line --index 1 "2026-04-29T12:00:00Z NOTICE [t] b"
	assert_line --index 2 "2026-04-29T12:00:00Z WARN   [t] c"
	assert_line --index 3 "2026-04-29T12:00:00Z ERROR  [t] d"
	assert_line --index 4 "2026-04-29T12:00:00Z STATE  [t] s"
	assert_line --index 5 "2026-04-29T12:00:00Z RESULT [t] r"
}

@test "log: WARN and ERROR go to stderr" {
	out_file="$BATS_TEST_TMPDIR/out"
	err_file="$BATS_TEST_TMPDIR/err"
	run sh -c '. "$1"; LOG_TAG=t log_error "boom" >"$2" 2>"$3"' sh "$LOG_SCRIPT" "$out_file" "$err_file"
	assert_success
	assert_file_empty "$out_file"
	assert_file_contains "$err_file" "ERROR  \[t\] boom"
}

@test "log: respects LOG_LEVEL filtering" {
	run sh -c 'LOG_LEVEL=WARN; . "$1"; LOG_TAG=t log_info "hidden"; LOG_TAG=t log_warn "shown" 2>&1' sh "$LOG_SCRIPT"
	assert_success
	refute_output --partial "hidden"
	assert_output --partial "shown"
}

@test "log: log_set_level changes effective level" {
	run sh -c '. "$1"; LOG_TAG=t; log_set_level ERROR; log_info "skip"; log_error "show" 2>&1' sh "$LOG_SCRIPT"
	assert_success
	refute_output --partial "skip"
	assert_output --partial "show"
}

@test "tag: auto-detected from script basename without extension" {
	tmp="$BATS_TEST_TMPDIR/myjob.sh"
	cat >"$tmp" <<-EOF
		#!/bin/sh
		. "$LOG_SCRIPT"
		log_info "hi"
	EOF
	chmod +x "$tmp"
	run env LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_JOURNAL=never LOG_COLOR=never "$tmp"
	assert_success
	assert_output "2026-04-29T12:00:00Z INFO   [myjob] hi"
}

@test "tag: bash and zsh produce identical tags from real scripts" {
	tmp="$BATS_TEST_TMPDIR/dual.sh"
	cat >"$tmp" <<-EOF
		#!/bin/sh
		. "$LOG_SCRIPT"
		log_info "x"
	EOF
	chmod +x "$tmp"
	run bash "$tmp"
	assert_success
	assert_output --partial "[dual] x"
	bash_out="$output"

	if command -v zsh >/dev/null 2>&1; then
		run zsh "$tmp"
		assert_success
		assert_output --partial "[dual] x"
		[ "$bash_out" = "$output" ]
	fi
}

@test "tag: invalid LOG_TAG falls back to no tag" {
	run sh -c 'LOG_TAG="bad;tag"; . "$1"; log_info "hi"' sh "$LOG_SCRIPT"
	assert_success
	assert_output "2026-04-29T12:00:00Z INFO   hi"
}

@test "tag: too long LOG_TAG is rejected" {
	long=$(printf 'a%.0s' $(seq 1 40))
	run sh -c 'LOG_TAG="$1"; . "$2"; log_info hi' sh "$long" "$LOG_SCRIPT"
	assert_success
	assert_output "2026-04-29T12:00:00Z INFO   hi"
}

@test "standalone: executable invocation works" {
	run env LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG=unit LOG_JOURNAL=never LOG_COLOR=never "$LOG_SCRIPT" INFO "standalone"
	assert_success
	assert_output "2026-04-29T12:00:00Z INFO   [unit] standalone"
}

@test "stdio: empty message becomes -" {
	run sh -c '. "$1"; LOG_TAG=t log_info ""' sh "$LOG_SCRIPT"
	assert_success
	assert_output "2026-04-29T12:00:00Z INFO   [t] -"
}
