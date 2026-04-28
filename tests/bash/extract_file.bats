#!/usr/bin/env bats
# Tests for extract_file fish function

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	FUNCTION_PATH="$REPO_ROOT/home/dot_config/fish/functions/extract_file.fish"
	export FUNCTION_PATH
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
	export ORIGINAL_PATH="$PATH"
}

teardown() {
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ] && rm -rf "$TEST_DIR"
}

@test "extract_file: function file exists" {
	[ -f "$FUNCTION_PATH" ]
}

@test "extract_file: function file has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish -n "$FUNCTION_PATH"
	[ "$status" -eq 0 ]
}

@test "extract_file: help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; extract_file --help"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: extract_file" ]]
	[[ "$output" =~ ".tar.gz" ]]
	[[ "$output" =~ ".zip" ]]
}

@test "extract_file: fails when no file is specified" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; extract_file"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "No file specified" ]]
}

@test "extract_file: fails when file does not exist" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; extract_file /nonexistent/file.tar.gz"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "not a valid file" ]]
}

@test "extract_file: fails when unsupported format" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	touch "$TEST_DIR/file.unknown"
	run fish --no-config -c "source '$FUNCTION_PATH'; extract_file '$TEST_DIR/file.unknown'"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unsupported file format" ]] || [[ "$output" =~ "cannot be extracted" ]]
}

@test "extract_file: fails with multiple files" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	touch "$TEST_DIR/a.zip" "$TEST_DIR/b.zip"
	run fish --no-config -c "source '$FUNCTION_PATH'; extract_file '$TEST_DIR/a.zip' '$TEST_DIR/b.zip'"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Multiple files specified" ]]
}

@test "extract_file: unknown option returns error" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; extract_file --invalid-flag file.zip"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
}

@test "extract_file: extracts a real .tar.gz archive" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	# Create real archive
	echo "hello" >"$TEST_DIR/hello.txt"
	(cd "$TEST_DIR" && tar -czf archive.tar.gz hello.txt && rm hello.txt)
	run fish --no-config -c "cd '$TEST_DIR'; source '$FUNCTION_PATH'; extract_file archive.tar.gz"
	[ "$status" -eq 0 ]
	[ -f "$TEST_DIR/hello.txt" ]
}

@test "extract_file: extracts a real .zip archive" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	if ! command -v zip >/dev/null 2>&1; then
		skip "zip not installed"
	fi
	echo "hello" >"$TEST_DIR/hello.txt"
	(cd "$TEST_DIR" && zip -q archive.zip hello.txt && rm hello.txt)
	run fish --no-config -c "cd '$TEST_DIR'; source '$FUNCTION_PATH'; extract_file archive.zip"
	[ "$status" -eq 0 ]
	[ -f "$TEST_DIR/hello.txt" ]
}
