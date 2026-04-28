#!/usr/bin/env bats
# Tests for git_undo_commit fish function

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	FUNCTION_PATH="$REPO_ROOT/home/dot_config/fish/functions/git_undo_commit.fish"
	export FUNCTION_PATH

	# Create a temporary test directory
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
	ORIGINAL_DIR="$(pwd)"
	export ORIGINAL_DIR

	cd "$TEST_DIR"
	git init -q -b main
	git config user.email "test@example.com"
	git config user.name "Test User"
}

teardown() {
	cd "$ORIGINAL_DIR" || true
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi
}

@test "git_undo_commit: function file exists" {
	[ -f "$FUNCTION_PATH" ]
}

@test "git_undo_commit: function file has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish -n "$FUNCTION_PATH"
	[ "$status" -eq 0 ]
}

@test "git_undo_commit: help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; git_undo_commit --help"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git_undo_commit" ]]
	[[ "$output" =~ "--soft" ]]
	[[ "$output" =~ "--mixed" ]]
	[[ "$output" =~ "--hard" ]]
}

@test "git_undo_commit: short help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; git_undo_commit -h"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git_undo_commit" ]]
}

@test "git_undo_commit: fails when not in git repo" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	NO_GIT_DIR="$(mktemp -d)"
	cd "$NO_GIT_DIR"
	run fish --no-config -c "source '$FUNCTION_PATH'; git_undo_commit"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Not in a git repository" ]]
	rm -rf "$NO_GIT_DIR"
	cd "$TEST_DIR"
}

@test "git_undo_commit: fails when no commits exist" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	# Repo is initialized but has no commits
	run fish --no-config -c "source '$FUNCTION_PATH'; git_undo_commit"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "No commits to undo" ]]
}

@test "git_undo_commit: removes last commit with default soft reset" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	echo "first" >file1.txt
	git add file1.txt
	git commit -q -m "First"
	echo "second" >file2.txt
	git add file2.txt
	git commit -q -m "Second"

	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_undo_commit"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Last commit removed" ]]
	[[ "$output" =~ "soft" ]]

	# Should have 1 commit and file2.txt staged
	[ "$(git -C "$TEST_DIR" log --oneline | wc -l)" -eq 1 ]
	run git -C "$TEST_DIR" diff --cached --name-only
	[[ "$output" =~ "file2.txt" ]]
}

@test "git_undo_commit: removes last commit with mixed reset" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	echo "first" >file1.txt
	git add file1.txt
	git commit -q -m "First"
	echo "second" >file2.txt
	git add file2.txt
	git commit -q -m "Second"

	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_undo_commit --mixed"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "mixed" ]]

	# After --mixed, file2.txt is unstaged (untracked) but exists on disk
	[ -f "$TEST_DIR/file2.txt" ]
	run git -C "$TEST_DIR" diff --cached --name-only
	[ -z "$output" ]
}

@test "git_undo_commit: rejects invalid commit SHA" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	echo "first" >file1.txt
	git add file1.txt
	git commit -q -m "First"

	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_undo_commit deadbeefdeadbeef"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "not found" ]]
}

@test "git_undo_commit: errors on multiple commit SHAs" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	echo "first" >file1.txt
	git add file1.txt
	git commit -q -m "First"

	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_undo_commit abc123 def456"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Multiple commit SHAs provided" ]]
}

@test "git_undo_commit: --hard aborts when user says no" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	echo "first" >file1.txt
	git add file1.txt
	git commit -q -m "First"
	echo "second" >file2.txt
	git add file2.txt
	git commit -q -m "Second"

	# Pipe "n" to the read prompt
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; echo n | git_undo_commit --hard"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Aborted" ]]

	# Both commits should still be present
	[ "$(git -C "$TEST_DIR" log --oneline | wc -l)" -eq 2 ]
}
