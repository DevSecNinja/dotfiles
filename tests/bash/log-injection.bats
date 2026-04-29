#!/usr/bin/env bats
# Injection / sanitization tests

load 'helpers/common'

setup() {
	common_setup
	LOG_SCRIPT="$REPO_ROOT/home/dot_config/shell/functions/log.sh"
	export LOG_SCRIPT LOG_JOURNAL=never LOG_COLOR=never
	export LOG_TIMESTAMP="2026-04-29T12:00:00Z"
}

teardown() { common_teardown; }

@test "injection: ANSI escape stripped from message" {
	run sh -c '. "$1"; LOG_TAG=t log_info "$(printf "evil\033[31mRED\033[0m")"' sh "$LOG_SCRIPT"
	assert_success
	# Output line must not contain any literal ESC (\033)
	refute_output --partial $'\033'
	assert_output --partial "evil"
	assert_output --partial "RED"
}

@test "injection: BEL stripped from message" {
	run sh -c '. "$1"; LOG_TAG=t log_info "$(printf "ding\007done")"' sh "$LOG_SCRIPT"
	assert_success
	refute_output --partial $'\007'
	assert_output --partial "dingdone"
}

@test "injection: newline in message becomes literal \\n on TTY/file (single line)" {
	run sh -c '. "$1"; LOG_TAG=t log_info "$(printf "line1\nline2")"' sh "$LOG_SCRIPT"
	assert_success
	[ "${#lines[@]}" -eq 1 ]
	assert_output --partial 'line1\nline2'
}

@test "injection: CR is escaped" {
	run sh -c '. "$1"; LOG_TAG=t log_info "$(printf "a\rb")"' sh "$LOG_SCRIPT"
	assert_success
	assert_output --partial 'a\rb'
}

@test "injection: format specifiers in message rendered literally" {
	run sh -c '. "$1"; LOG_TAG=t log_info "value=%s count=%d %n"' sh "$LOG_SCRIPT"
	assert_success
	assert_output "2026-04-29T12:00:00Z INFO   [t] value=%s count=%d %n"
}

@test "injection: long messages truncated to LOG_MAX_BYTES" {
	run sh -c 'LOG_MAX_BYTES=64; . "$1"; LOG_TAG=t log_info "$(yes ABCDEFGH | head -c 500 | tr -d \"\\n\")"' sh "$LOG_SCRIPT"
	assert_success
	assert_output --partial "...[truncated]"
	# Total output line shouldn't be ridiculously long
	[ "${#output}" -lt 200 ]
}

@test "injection: tag with shell metacharacters rejected" {
	run sh -c 'LOG_TAG="evil; rm -rf /"; . "$1"; log_info hi' sh "$LOG_SCRIPT"
	assert_success
	# Bad tag => no tag rendered
	refute_output --partial "evil"
	refute_output --partial "rm -rf"
	assert_output "2026-04-29T12:00:00Z INFO   hi"
}

@test "injection: tag with leading dash rejected (would look like a flag)" {
	run sh -c 'LOG_TAG="--inject"; . "$1"; log_info hi' sh "$LOG_SCRIPT"
	assert_success
	refute_output --partial "--inject"
}

@test "injection: tag with whitespace rejected" {
	run sh -c 'LOG_TAG="bad tag"; . "$1"; log_info hi' sh "$LOG_SCRIPT"
	assert_success
	refute_output --partial "bad tag"
	assert_output "2026-04-29T12:00:00Z INFO   hi"
}

@test "injection: LOG_FILE symlink is refused" {
	target="$BATS_TEST_TMPDIR/real.log"
	link="$BATS_TEST_TMPDIR/link.log"
	: >"$target"
	ln -s "$target" "$link"
	run sh -c '. "$1"; LOG_TAG=t LOG_FILE="$2" LOG_FILE_MAX_BYTES=10000 log_info "secret"' sh "$LOG_SCRIPT" "$link"
	assert_success
	# No write through symlink
	run cat "$target"
	assert_output ""
}

@test "injection: NUL byte stripped from message" {
	# Bash strips NUL from command substitution and emits a stderr warning;
	# silence the warning so we can assert on the resulting log line shape.
	out_file="$BATS_TEST_TMPDIR/out"
	bash -c '. "$1"; LOG_TAG=t log_info "$(printf "a\0b")"' bash "$LOG_SCRIPT" >"$out_file" 2>/dev/null
	run cat "$out_file"
	assert_success
	[ "${#lines[@]}" -eq 1 ]
	run grep -P '[\x00\x07\x1b]' "$out_file"
	assert_failure
}

@test "injection: ANSI in JSON output is escaped or stripped" {
	run sh -c 'LOG_FORMAT=json; . "$1"; LOG_TAG=t log_info "$(printf "x\033[31my")"' sh "$LOG_SCRIPT"
	assert_success
	refute_output --partial $'\033'
}
