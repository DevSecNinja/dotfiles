#!/usr/bin/env bats
# Tests for the reusable shell logging helper.

load 'helpers/common'

setup() {
	common_setup
	LOG_SCRIPT="$REPO_ROOT/home/dot_config/shell/functions/log.sh"
	TEST_BIN_DIR="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$TEST_BIN_DIR"
	export LOG_SCRIPT TEST_BIN_DIR
}

teardown() {
	common_teardown
}

@test "log: helper has valid sh and bash syntax" {
	run sh -n "$LOG_SCRIPT"
	assert_success

	run bash -n "$LOG_SCRIPT"
	assert_success
}

@test "log: helper is executable for standalone use" {
	assert_file_executable "$LOG_SCRIPT"
}

@test "log: executable helper emits standalone messages" {
	run env LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG="unit" LOG_JOURNAL="never" "$LOG_SCRIPT" INFO "standalone message"

	assert_success
	assert_output "2026-04-29T12:00:00Z INFO unit: standalone message"
}

@test "log: emits timestamped INFO messages to stdout without color in non-TTY" {
	run sh -c '. "$1"; LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG="unit" LOG_JOURNAL="never" log INFO "hello world"' sh "$LOG_SCRIPT"

	assert_success
	assert_output "2026-04-29T12:00:00Z INFO unit: hello world"
	refute_output --partial $'\033['
}

@test "log: respects minimum level filtering" {
	run sh -c '. "$1"; LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG="unit" LOG_JOURNAL="never" LOG_LEVEL="WARN" log INFO "hidden"' sh "$LOG_SCRIPT"

	assert_success
	assert_output ""
}

@test "log: writes WARN and ERROR levels to stderr" {
	out_file="$BATS_TEST_TMPDIR/stdout.txt"
	err_file="$BATS_TEST_TMPDIR/stderr.txt"

	run sh -c '. "$1"; LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG="unit" LOG_JOURNAL="never" log_error "broken" >"$2" 2>"$3"' sh "$LOG_SCRIPT" "$out_file" "$err_file"

	assert_success
	assert_file_empty "$out_file"
	assert_file_contains "$err_file" "2026-04-29T12:00:00Z ERROR unit: broken"
}

@test "log: can force logger integration and stub logger command" {
	capture_file="$BATS_TEST_TMPDIR/logger.txt"
	fake_logger="$TEST_BIN_DIR/logger"
	cat >"$fake_logger" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$LOG_CAPTURE_FILE"
EOF
	chmod +x "$fake_logger"

	run sh -c '. "$1"; LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG="unit" LOG_JOURNAL="always" LOG_LOGGER_COMMAND="$2" LOG_CAPTURE_FILE="$3" log WARN "journal message"' sh "$LOG_SCRIPT" "$fake_logger" "$capture_file"

	assert_success
	assert_file_contains "$capture_file" "unit -p user\\.warning -- WARN journal message"
}

@test "log: does not create LOG_FILE unless rotation or lifetime is configured" {
	log_file="$BATS_TEST_TMPDIR/no-policy.log"

	run sh -c '. "$1"; LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG="unit" LOG_JOURNAL="never" LOG_FILE="$2" log INFO "terminal only"' sh "$LOG_SCRIPT" "$log_file"

	assert_success
	assert_file_not_exist "$log_file"
}

@test "log: writes optional file output when rotation policy is configured" {
	log_file="$BATS_TEST_TMPDIR/with-policy.log"

	run sh -c '. "$1"; LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG="unit" LOG_JOURNAL="never" LOG_FILE="$2" LOG_FILE_MAX_BYTES=100000 log INFO "file message"' sh "$LOG_SCRIPT" "$log_file"

	assert_success
	assert_file_contains "$log_file" "2026-04-29T12:00:00Z INFO unit: file message"
}

@test "log: rotates optional file output when max bytes is reached" {
	log_file="$BATS_TEST_TMPDIR/rotate.log"
	printf '%s\n' "old content" >"$log_file"

	run sh -c '. "$1"; LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG="unit" LOG_JOURNAL="never" LOG_FILE="$2" LOG_FILE_MAX_BYTES=1 log INFO "new content"' sh "$LOG_SCRIPT" "$log_file"

	assert_success
	assert_file_contains "$log_file" "2026-04-29T12:00:00Z INFO unit: new content"
	assert_file_contains "$log_file.1" "old content"
}

@test "log: can be sourced from zsh when zsh is available" {
	if ! command -v zsh >/dev/null 2>&1; then
		skip "zsh not installed"
	fi

	run zsh -c '. "$1"; LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG="unit" LOG_JOURNAL="never" log_notice "from zsh"' zsh "$LOG_SCRIPT"

	assert_success
	assert_output "2026-04-29T12:00:00Z NOTICE unit: from zsh"
}
