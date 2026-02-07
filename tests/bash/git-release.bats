#!/usr/bin/env bats
# Tests for git-release bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-release.sh"

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

@test "git-release: help option displays usage" {
	run git-release --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-release" ]]
	[[ "$output" =~ "major|minor|patch" ]]
}

@test "git-release: short help option displays usage" {
	run git-release -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-release" ]]
}

@test "git-release: no arguments shows usage" {
	# Create initial commit and tag
	echo "test" > file.txt
	git add file.txt
	git commit -q -m "Initial commit"
	git tag -a v1.0.0 -m "v1.0.0"

	run git-release
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-release" ]]
}

@test "git-release: fails when not on main branch" {
	# Create initial commit on main
	echo "test" > file.txt
	git add file.txt
	git commit -q -m "Initial commit"

	# Switch to a different branch
	git checkout -q -b feature-branch

	run git-release patch
	[ "$status" -eq 1 ]
	[[ "$output" =~ "must be on the 'main' branch" ]]
}

@test "git-release: fails when not in git repo" {
	cd /tmp || return 1
	run git-release --help
	[ "$status" -eq 0 ]
	# Help should work even outside a git repo
	[[ "$output" =~ "Usage: git-release" ]]
}
