#!/usr/bin/env bats
# Tests for git-undo bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-undo.sh"

	# Create a temporary test directory
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

	# Save original directory
	ORIGINAL_DIR="$(pwd)"
	export ORIGINAL_DIR

	# Change to test directory and initialize git repo
	cd "$TEST_DIR"
	git init -q -b main
	git config user.email "test@example.com"
	git config user.name "Test User"
}

# Teardown function runs after each test
teardown() {
	# Return to original directory
	cd "$ORIGINAL_DIR" || true

	# Clean up test directory
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi
}

@test "git-undo: help option displays usage" {
	run git-undo --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-undo" ]]
	[[ "$output" =~ "--verbose" ]]
	[[ "$output" =~ "Undo the last Git commit" ]]
}

@test "git-undo: short help option displays usage" {
	run git-undo -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-undo" ]]
}

@test "git-undo: unknown option returns error" {
	run git-undo --invalid-option
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
	[[ "$output" =~ "Use 'git-undo --help'" ]]
}

@test "git-undo: fails when not in git repo" {
	NO_GIT_DIR="$(mktemp -d)"
	cd "$NO_GIT_DIR"

	run git-undo
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Not in a Git repository" ]]

	rm -rf "$NO_GIT_DIR"
	cd "$TEST_DIR"
}

@test "git-undo: fails when there are no commits" {
	# Repo is initialized but has no commits
	run git-undo
	[ "$status" -eq 1 ]
	[[ "$output" =~ "No commits to undo" ]]
}

@test "git-undo: undoes last commit and keeps changes staged" {
	# Create initial commit
	echo "first" >file1.txt
	git add file1.txt
	git commit -q -m "First commit"

	# Create second commit
	echo "second" >file2.txt
	git add file2.txt
	git commit -q -m "Second commit"

	# Verify HEAD is at second commit
	[ "$(git log --oneline | wc -l)" -eq 2 ]

	run git-undo
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Last commit undone" ]]

	# HEAD should now be at first commit
	[ "$(git log --oneline | wc -l)" -eq 1 ]

	# file2.txt should still be staged (because of --soft)
	run git diff --cached --name-only
	[[ "$output" =~ "file2.txt" ]]
}

@test "git-undo: verbose mode shows additional output and status" {
	# Create initial commit
	echo "first" >file1.txt
	git add file1.txt
	git commit -q -m "First commit"

	# Create second commit
	echo "second" >file2.txt
	git add file2.txt
	git commit -q -m "Second commit"

	run git-undo --verbose
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Undoing last commit" ]]
	[[ "$output" =~ "Last commit undone successfully" ]]
}

@test "git-undo: short verbose option works" {
	echo "first" >file1.txt
	git add file1.txt
	git commit -q -m "First commit"

	echo "second" >file2.txt
	git add file2.txt
	git commit -q -m "Second commit"

	run git-undo -v
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Undoing last commit" ]]
}

@test "git-undo: fails when only one commit and no parent exists" {
	echo "only" >file1.txt
	git add file1.txt
	git commit -q -m "Only commit"

	# Should fail because HEAD^ does not exist
	run git-undo
	[ "$status" -eq 1 ]
}
