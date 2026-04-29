#!/usr/bin/env bats
# Structured-data tests: log_kv, log_data, JSON output

load 'helpers/common'

setup() {
	common_setup
	LOG_SCRIPT="$REPO_ROOT/home/dot_config/shell/functions/log.sh"
	export LOG_SCRIPT LOG_JOURNAL=never LOG_COLOR=never
	export LOG_TIMESTAMP="2026-04-29T12:00:00Z"
}

teardown() { common_teardown; }

@test "log_kv: simple pairs render as logfmt" {
	run sh -c '. "$1"; LOG_TAG=t log_kv app=adguard duration=12s status=ok' sh "$LOG_SCRIPT"
	assert_success
	assert_output "2026-04-29T12:00:00Z INFO   [t] app=adguard duration=12s status=ok"
}

@test "log_kv: values with spaces get quoted" {
	run sh -c '. "$1"; LOG_TAG=t log_kv "msg=hello world" status=ok' sh "$LOG_SCRIPT"
	assert_success
	assert_output --partial 'msg="hello world"'
	assert_output --partial 'status=ok'
}

@test "log_kv: embedded quotes escaped" {
	run sh -c '. "$1"; LOG_TAG=t log_kv "note=he said \"hi\""' sh "$LOG_SCRIPT"
	assert_success
	assert_output --partial 'note="he said \"hi\""'
}

@test "log_data: multiline payload rendered with continuation prefix on TTY" {
	run sh -c 'printf "key: value\nlist:\n  - a\n  - b\n" | { . "$1"; LOG_TAG=t log_data INFO config; }' sh "$LOG_SCRIPT"
	assert_success
	assert_line --index 0 "2026-04-29T12:00:00Z INFO   [t] config"
	assert_line --index 1 "2026-04-29T12:00:00Z INFO   [t] │ key: value"
	assert_line --index 2 "2026-04-29T12:00:00Z INFO   [t] │ list:"
	assert_line --index 3 "2026-04-29T12:00:00Z INFO   [t] │   - a"
	assert_line --index 4 "2026-04-29T12:00:00Z INFO   [t] │   - b"
}

@test "log_data: file output uses ASCII pipe continuation" {
	log_file="$BATS_TEST_TMPDIR/data.log"
	run sh -c 'printf "a\nb\n" | { . "$1"; LOG_TAG=t LOG_FILE="$2" LOG_FILE_MAX_BYTES=100000 log_data INFO config; }' sh "$LOG_SCRIPT" "$log_file"
	assert_success
	assert_file_contains "$log_file" "INFO   \[t\] config"
	assert_file_contains "$log_file" "INFO   \[t\] | a"
	assert_file_contains "$log_file" "INFO   \[t\] | b"
}

@test "log_data: JSON payload with quotes is sanitized but readable" {
	run sh -c 'printf "%s" "{\"a\":\"x\",\"b\":[1,2]}" | { . "$1"; LOG_TAG=t log_data INFO payload; }' sh "$LOG_SCRIPT"
	assert_success
	assert_output --partial '│ {"a":"x","b":[1,2]}'
}

@test "log_data: STATE kind colored on stdio" {
	run sh -c 'printf "x\n" | { LOG_COLOR=always; . "$1"; LOG_TAG=t log_data STATE deploy; }' sh "$LOG_SCRIPT"
	assert_success
	assert_output --partial $'\033[36m'
}

@test "json: log_state emits valid JSON object" {
	if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
	run sh -c 'LOG_FORMAT=json; . "$1"; LOG_TAG=t log_state "Deploying"' sh "$LOG_SCRIPT"
	assert_success
	# Must parse as JSON
	echo "$output" | jq -e '.timestamp, .level, .kind, .tag, .message' >/dev/null
	echo "$output" | jq -e '.kind == "STATE"' >/dev/null
	echo "$output" | jq -e '.tag == "t"' >/dev/null
	echo "$output" | jq -e '.message == "Deploying"' >/dev/null
}

@test "json: each log call produces one JSON line" {
	if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
	run sh -c 'LOG_FORMAT=json; . "$1"; LOG_TAG=t; log_info a; log_warn b 2>&1; log_state c' sh "$LOG_SCRIPT"
	assert_success
	[ "${#lines[@]}" -eq 3 ]
	for line in "${lines[@]}"; do
		echo "$line" | jq -e . >/dev/null
	done
}

@test "json: special characters in message escaped correctly" {
	if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
	# Build the message via printf so we control byte-exact content.
	log_file="$BATS_TEST_TMPDIR/json-esc.log"
	msg=$(printf 'q="hi" b=\\ end')
	LOG_FORMAT=json LOG_TAG=t LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_JOURNAL=never LOG_COLOR=never \
		bash -c '. "$1"; log_info "$2"' bash "$LOG_SCRIPT" "$msg" >"$log_file"
	run jq -e . "$log_file"
	assert_success
	parsed=$(jq -r .message <"$log_file")
	[ "$parsed" = "$msg" ] || { echo "want=[$msg] got=[$parsed]"; false; }
}

@test "json: log_data includes data field" {
	if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
	run sh -c 'printf "k: v\nl: 1\n" | { LOG_FORMAT=json; . "$1"; LOG_TAG=t log_data INFO config; }' sh "$LOG_SCRIPT"
	assert_success
	echo "$output" | jq -e '.data' >/dev/null
	parsed=$(echo "$output" | jq -r .data)
	# Newlines in payloads are flattened to the literal two-char sequence
	# `\n` (consistent with text-mode file output) so each log entry stays
	# on a single line in JSON Lines streams.
	[ "$parsed" = 'k: v\nl: 1' ]
}

@test "json: banner collapses to single JSON object" {
	if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
	run sh -c 'LOG_FORMAT=json; . "$1"; LOG_TAG=t log_banner "Phase 1" STATE' sh "$LOG_SCRIPT"
	assert_success
	[ "${#lines[@]}" -eq 1 ]
	echo "$output" | jq -e '.kind == "BANNER"' >/dev/null
	echo "$output" | jq -e '.message == "Phase 1"' >/dev/null
}

@test "json: file output also valid JSON" {
	if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
	log_file="$BATS_TEST_TMPDIR/json.log"
	run sh -c 'LOG_FORMAT=json; . "$1"; LOG_TAG=t LOG_FILE="$2" LOG_FILE_MAX_BYTES=100000 log_state "x"' sh "$LOG_SCRIPT" "$log_file"
	assert_success
	jq -e . <"$log_file" >/dev/null
}
