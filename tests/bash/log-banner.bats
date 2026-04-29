#!/usr/bin/env bats
# Banner / rule / sep rendering tests

load 'helpers/common'

setup() {
	common_setup
	LOG_SCRIPT="$REPO_ROOT/home/dot_config/shell/functions/log.sh"
	export LOG_SCRIPT LOG_JOURNAL=never LOG_COLOR=never
	export LOG_TIMESTAMP="2026-04-29T12:00:00Z"
	export LOG_RULE_WIDTH=20
}

teardown() { common_teardown; }

@test "banner ascii: 3-line frame" {
	run sh -c 'LOG_BANNER_STYLE=ascii; . "$1"; LOG_TAG=t log_banner "Deploy" STATE' sh "$LOG_SCRIPT"
	assert_success
	[ "${#lines[@]}" -eq 3 ]
	assert_line --index 0 "2026-04-29T12:00:00Z STATE  [t] ===================="
	assert_line --index 1 "2026-04-29T12:00:00Z STATE  [t]  Deploy"
	assert_line --index 2 "2026-04-29T12:00:00Z STATE  [t] ===================="
}

@test "banner heavy: uses # character" {
	run sh -c 'LOG_BANNER_STYLE=heavy; . "$1"; LOG_TAG=t log_banner "Phase 1" STATE' sh "$LOG_SCRIPT"
	assert_success
	assert_line --index 0 --partial "####################"
}

@test "banner unicode: uses heavy-rule character" {
	run sh -c 'LOG_FORCE_TTY=1 LOG_BANNER_STYLE=unicode LANG=en_US.UTF-8; . "$1"; LOG_TAG=t log_banner "Hi" STATE' sh "$LOG_SCRIPT"
	assert_success
	assert_line --index 0 --partial "━"
}

@test "banner unicode: falls back to ascii when LANG=C" {
	run sh -c 'LOG_BANNER_STYLE=unicode LANG=C LC_ALL=C; . "$1"; LOG_TAG=t log_banner "Hi" STATE' sh "$LOG_SCRIPT"
	assert_success
	refute_output --partial "━"
	assert_line --index 0 --partial "===="
}

@test "banner box: renders three lines with box-drawing characters" {
	run sh -c 'LOG_FORCE_TTY=1 LOG_BANNER_STYLE=box LANG=en_US.UTF-8; . "$1"; LOG_TAG=t LOG_RULE_WIDTH=24 log_banner "Hi" STATE' sh "$LOG_SCRIPT"
	assert_success
	[ "${#lines[@]}" -eq 3 ]
	assert_line --index 0 --partial "┌"
	assert_line --index 0 --partial "┐"
	assert_line --index 1 --partial "│ Hi"
	assert_line --index 1 --partial "│"
	assert_line --index 2 --partial "└"
	assert_line --index 2 --partial "┘"
}

@test "log_sep: emits a single separator line" {
	run sh -c 'LOG_BANNER_STYLE=ascii; . "$1"; LOG_TAG=t log_sep STATE' sh "$LOG_SCRIPT"
	assert_success
	[ "${#lines[@]}" -eq 1 ]
	assert_output "2026-04-29T12:00:00Z STATE  [t] ===================="
}

@test "log_rule: embeds title with side rules" {
	run sh -c 'LOG_BANNER_STYLE=ascii; . "$1"; LOG_TAG=t LOG_RULE_WIDTH=24 log_rule STATE "phase 1"' sh "$LOG_SCRIPT"
	assert_success
	[ "${#lines[@]}" -eq 1 ]
	assert_output --partial "==== phase 1 ==========="
	assert_output --partial "STATE  [t]"
}

@test "banner: respects LOG_RULE_WIDTH" {
	run sh -c 'LOG_BANNER_STYLE=ascii; . "$1"; LOG_TAG=t LOG_RULE_WIDTH=10 log_sep STATE' sh "$LOG_SCRIPT"
	assert_success
	assert_output --partial "=========="
	# Should not be 40 chars
	refute_output --partial "==========="
}

@test "banner: file output flattens to single timestamped lines" {
	log_file="$BATS_TEST_TMPDIR/banner.log"
	# Force TTY so unicode style would be selected for stdio; file is the
	# only sink here (non-TTY) so it should still be ASCII.
	run sh -c 'LOG_BANNER_STYLE=unicode LANG=en_US.UTF-8; . "$1"; LOG_TAG=t LOG_FILE="$2" LOG_FILE_MAX_BYTES=100000 log_banner "Hi" STATE' sh "$LOG_SCRIPT" "$log_file"
	assert_success
	assert_file_contains "$log_file" "STATE  \[t\] ===="
	assert_file_contains "$log_file" "STATE  \[t\]  Hi"
	run grep -F "━" "$log_file"
	assert_failure
	run grep -F "┌" "$log_file"
	assert_failure
}

@test "banner: respects LOG_LEVEL filtering" {
	run sh -c 'LOG_LEVEL=WARN LOG_BANNER_STYLE=ascii; . "$1"; LOG_TAG=t log_banner "Hi" STATE' sh "$LOG_SCRIPT"
	assert_success
	assert_output ""
}
