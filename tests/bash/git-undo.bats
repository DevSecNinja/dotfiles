#!/usr/bin/env bats
# Tests for git-undo bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-undo.sh"

	# Create a temporary test directory with a git repo
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

	# Save original directory
	ORIGINAL_DIR="$(pwd)"
	export ORIGINAL_DIR

	# Initialize a test git repo
	cd "$TEST_DIR" || return 1
	git init -q
	git config user.email "test@test.com"
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
}

@test "git-undo: short help option displays usage" {
	run git-undo -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-undo" ]]
}

@test "git-undo: fails when not in git repo" {
	cd /tmp || return 1
	run git-undo
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Not in a Git repository" ]]
}

@test "git-undo: fails when no commits exist" {
	run git-undo
	[ "$status" -eq 1 ]
	[[ "$output" =~ "No commits to undo" ]]
}

@test "git-undo: successfully undoes last commit" {
	# Create an initial commit
	echo "initial" > file1.txt
	git add file1.txt
	git commit -q -m "Initial commit"

	# Create a second commit to undo
	echo "second" > file2.txt
	git add file2.txt
	git commit -q -m "Second commit"

	# Verify we have 2 commits
	local commit_count
	commit_count=$(git rev-list --count HEAD)
	[ "$commit_count" -eq 2 ]

	run git-undo
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Last commit undone" ]]

	# Verify we're back to 1 commit
	commit_count=$(git rev-list --count HEAD)
	[ "$commit_count" -eq 1 ]
}

@test "git-undo: unknown option returns error" {
	run git-undo --invalid
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
}
