#!/usr/bin/env bats
# Tests for extract-file shell function

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/extract-file.sh"
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
}

teardown() {
	[ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ] && rm -rf "$TEST_DIR"
}

@test "extract-file: help option displays usage" {
	run extract-file --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: extract-file" ]]
	[[ "$output" =~ ".tar.gz" ]]
	[[ "$output" =~ ".zip" ]]
}

@test "extract-file: short help option works" {
	run extract-file -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: extract-file" ]]
}

@test "extract-file: fails when no file is specified" {
	run extract-file
	[ "$status" -eq 1 ]
	[[ "$output" =~ "No file specified" ]]
}

@test "extract-file: fails when file does not exist" {
	run extract-file /nonexistent/path/file.tar.gz
	[ "$status" -eq 1 ]
	[[ "$output" =~ "not a valid file" ]]
}

@test "extract-file: fails for unsupported format" {
	touch "$TEST_DIR/file.unknown"
	run extract-file "$TEST_DIR/file.unknown"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unsupported file format" ]] || [[ "$output" =~ "cannot be extracted" ]]
}

@test "extract-file: fails with multiple files specified" {
	touch "$TEST_DIR/a.zip" "$TEST_DIR/b.zip"
	run extract-file "$TEST_DIR/a.zip" "$TEST_DIR/b.zip"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Multiple files specified" ]]
}

@test "extract-file: unknown option returns error" {
	run extract-file --invalid-flag file.zip
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
}

@test "extract-file: extracts a real .tar.gz archive" {
	echo "hello" >"$TEST_DIR/hello.txt"
	(cd "$TEST_DIR" && tar -czf archive.tar.gz hello.txt && rm hello.txt)
	cd "$TEST_DIR"
	run extract-file archive.tar.gz
	[ "$status" -eq 0 ]
	[ -f "$TEST_DIR/hello.txt" ]
}

@test "extract-file: extracts a real .tar archive" {
	echo "hello" >"$TEST_DIR/hello.txt"
	(cd "$TEST_DIR" && tar -cf archive.tar hello.txt && rm hello.txt)
	cd "$TEST_DIR"
	run extract-file archive.tar
	[ "$status" -eq 0 ]
	[ -f "$TEST_DIR/hello.txt" ]
}

@test "extract-file: extracts a real .zip archive" {
	if ! command -v zip >/dev/null 2>&1; then
		skip "zip not installed"
	fi
	echo "hello" >"$TEST_DIR/hello.txt"
	(cd "$TEST_DIR" && zip -q archive.zip hello.txt && rm hello.txt)
	cd "$TEST_DIR"
	run extract-file archive.zip
	[ "$status" -eq 0 ]
	[ -f "$TEST_DIR/hello.txt" ]
}

@test "extract-file: verbose flag prints extracting message" {
	echo "hello" >"$TEST_DIR/hello.txt"
	(cd "$TEST_DIR" && tar -czf archive.tar.gz hello.txt && rm hello.txt)
	cd "$TEST_DIR"
	run extract-file --verbose archive.tar.gz
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Extracting" ]]
	[[ "$output" =~ "Successfully extracted" ]]
}
