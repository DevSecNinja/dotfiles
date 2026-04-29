#!/usr/bin/env bats
# Kind helpers (state/result/hint/step) and color/journal mapping

load 'helpers/common'

setup() {
	common_setup
	LOG_SCRIPT="$REPO_ROOT/home/dot_config/shell/functions/log.sh"
	export LOG_SCRIPT LOG_JOURNAL=never LOG_COLOR=never
	export LOG_TIMESTAMP="2026-04-29T12:00:00Z"
}

teardown() { common_teardown; }

@test "kinds: log_state emits STATE label" {
	run sh -c '. "$1"; LOG_TAG=t log_state "Deploying"' sh "$LOG_SCRIPT"
	assert_success
	assert_output "2026-04-29T12:00:00Z STATE  [t] Deploying"
}

@test "kinds: log_result emits RESULT label" {
	run sh -c '. "$1"; LOG_TAG=t log_result "30 done"' sh "$LOG_SCRIPT"
	assert_success
	assert_output "2026-04-29T12:00:00Z RESULT [t] 30 done"
}

@test "kinds: log_hint emits HINT label" {
	run sh -c '. "$1"; LOG_TAG=t log_hint "retry"' sh "$LOG_SCRIPT"
	assert_success
	assert_output "2026-04-29T12:00:00Z HINT   [t] retry"
}

@test "kinds: log_step emits STEP label" {
	run sh -c '. "$1"; LOG_TAG=t log_step "pulling"' sh "$LOG_SCRIPT"
	assert_success
	assert_output "2026-04-29T12:00:00Z STEP   [t] pulling"
}

@test "kinds: state/result/hint/step go to stdout (info priority)" {
	out_file="$BATS_TEST_TMPDIR/out"
	err_file="$BATS_TEST_TMPDIR/err"
	run sh -c '. "$1"; LOG_TAG=t; log_state s; log_result r; log_hint h; log_step p; >"$2" 2>"$3"' sh "$LOG_SCRIPT" "$out_file" "$err_file"
	# Re-run with redirection done from the outside instead.
	run sh -c '. "$1"; LOG_TAG=t; { log_state s; log_result r; log_hint h; log_step p; } >"$2" 2>"$3"' sh "$LOG_SCRIPT" "$out_file" "$err_file"
	assert_success
	assert_file_contains "$out_file" "STATE  \[t\] s"
	assert_file_contains "$out_file" "RESULT \[t\] r"
	assert_file_contains "$out_file" "HINT   \[t\] h"
	assert_file_contains "$out_file" "STEP   \[t\] p"
	assert_file_empty "$err_file"
}

@test "kinds: log() accepts kind names as first arg" {
	run sh -c '. "$1"; LOG_TAG=t log STATE "hi"' sh "$LOG_SCRIPT"
	assert_success
	assert_output "2026-04-29T12:00:00Z STATE  [t] hi"
}

@test "kinds: STATE filtered out when LOG_LEVEL above INFO" {
	run sh -c 'LOG_LEVEL=WARN; . "$1"; LOG_TAG=t log_state "hidden"' sh "$LOG_SCRIPT"
	assert_success
	assert_output ""
}

@test "color: distinct ANSI codes per kind when LOG_COLOR=always" {
	run sh -c 'LOG_COLOR=always; . "$1"; LOG_TAG=t log_state "s"' sh "$LOG_SCRIPT"
	assert_success
	# Cyan for STATE
	assert_output --partial $'\033[36m'
}

@test "color: RESULT uses green" {
	run sh -c 'LOG_COLOR=always; . "$1"; LOG_TAG=t log_result "r"' sh "$LOG_SCRIPT"
	assert_success
	assert_output --partial $'\033[32m'
}

@test "color: WARN uses bold yellow on stderr" {
	run sh -c 'LOG_COLOR=always; . "$1"; LOG_TAG=t log_warn "w" 2>&1' sh "$LOG_SCRIPT"
	assert_success
	assert_output --partial $'\033[1;33m'
}

@test "color: NO_COLOR overrides LOG_COLOR=always" {
	run sh -c 'NO_COLOR=1 LOG_COLOR=always; . "$1"; LOG_TAG=t log_state "s"' sh "$LOG_SCRIPT"
	assert_success
	refute_output --partial $'\033['
}

@test "journal: kind name is forwarded to logger" {
	fake_logger="$BATS_TEST_TMPDIR/logger"
	cap="$BATS_TEST_TMPDIR/cap"
	cat >"$fake_logger" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$LOG_CAPTURE_FILE"
EOF
	chmod +x "$fake_logger"

	run sh -c '. "$1"; LOG_TAG=t LOG_JOURNAL=always LOG_LOGGER_COMMAND="$2" LOG_CAPTURE_FILE="$3" log_state "deploying"' sh "$LOG_SCRIPT" "$fake_logger" "$cap"

	assert_success
	assert_file_contains "$cap" "user.info -- INFO STATE deploying"
}
