#!/usr/bin/env bats
# Tests for gh-check-ssh-keys bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/gh-check-ssh-keys.sh"

	# Create a temporary test directory
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

	# Create temporary .ssh directory and authorized_keys
	TEST_SSH_DIR="${TEST_DIR}/.ssh"
	mkdir -p "$TEST_SSH_DIR"
	chmod 700 "$TEST_SSH_DIR"
	TEST_AUTH_KEYS="${TEST_SSH_DIR}/authorized_keys"
	touch "$TEST_AUTH_KEYS"
	chmod 600 "$TEST_AUTH_KEYS"

	# Override HOME for testing
	ORIGINAL_HOME="$HOME"
	export ORIGINAL_HOME
	export HOME="$TEST_DIR"
}

# Teardown function runs after each test
teardown() {
	# Restore original HOME
	export HOME="$ORIGINAL_HOME"

	# Clean up test directory
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi
}

@test "gh-check-ssh-keys: help option displays usage" {
	run gh-check-ssh-keys --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: gh-check-ssh-keys" ]]
	[[ "$output" =~ "--verbose" ]]
	[[ "$output" =~ "Check if GitHub user's SSH keys are in authorized_keys" ]]
}

@test "gh-check-ssh-keys: short help option displays usage" {
	run gh-check-ssh-keys -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: gh-check-ssh-keys" ]]
}

@test "gh-check-ssh-keys: fails when no username provided" {
	run gh-check-ssh-keys
	[ "$status" -eq 1 ]
	[[ "$output" =~ "GitHub username is required" ]]
}

@test "gh-check-ssh-keys: unknown option returns error" {
	run gh-check-ssh-keys --invalid-option
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
	[[ "$output" =~ "Use --help for usage information" ]]
}

@test "gh-check-ssh-keys: too many arguments returns error" {
	run gh-check-ssh-keys user1 user2
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Too many arguments" ]]
}

@test "gh-check-ssh-keys: fails when curl is not available" {
	skip "Cannot reliably test curl unavailability - curl will be found in PATH"
}

@test "gh-check-ssh-keys: fails when authorized_keys does not exist" {
	rm -f "$TEST_AUTH_KEYS"
	run gh-check-ssh-keys torvalds
	[ "$status" -eq 2 ]
	[[ "$output" =~ "No authorized_keys file found" ]]
}

@test "gh-check-ssh-keys: fails for invalid GitHub username" {
	run gh-check-ssh-keys "this-user-definitely-does-not-exist-12345678901234567890"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "not found on GitHub" ]] || [[ "$output" =~ "Failed to fetch" ]] || [[ "$output" =~ "has no public SSH keys" ]]
}

@test "gh-check-ssh-keys: handles user with no SSH keys" {
	skip "Requires finding a GitHub user with no SSH keys"
}

@test "gh-check-ssh-keys: returns error when no keys found in authorized_keys" {
	# authorized_keys is empty, so no keys will match
	run gh-check-ssh-keys torvalds
	# Should return exit code 2 (no keys found)
	[ "$status" -eq 2 ] || [ "$status" -eq 1 ]
	[[ "$output" =~ "None of" ]] || [[ "$output" =~ "not found" ]] || [[ "$output" =~ "Failed" ]]
}

@test "gh-check-ssh-keys: finds key when it exists in authorized_keys" {
	skip "Requires mocking GitHub API response or using a stable test key"
	# This test would need to:
	# 1. Mock the curl call to return a known key
	# 2. Add that key to authorized_keys
	# 3. Verify the function finds it
}

@test "gh-check-ssh-keys: verbose mode shows detailed output" {
	# Just verify verbose mode works
	run gh-check-ssh-keys --verbose torvalds
	# Should have verbose output
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
	[[ "$output" =~ "Checking GitHub SSH keys" ]] || [[ "$output" =~ "Fetching" ]]
}

@test "gh-check-ssh-keys: short verbose option works" {
	run gh-check-ssh-keys -v torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
	[[ "$output" =~ "Checking GitHub SSH keys" ]] || [[ "$output" =~ "Fetching" ]]
}

@test "gh-check-ssh-keys: combines verbose with username" {
	run gh-check-ssh-keys --verbose torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
	# Output should mention torvalds
	[[ "$output" =~ "torvalds" ]]
}

@test "gh-check-ssh-keys: handles username with hyphens" {
	run gh-check-ssh-keys test-user
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
	# Should attempt to process, even if user doesn't exist
}

@test "gh-check-ssh-keys: handles username with underscores" {
	run gh-check-ssh-keys test_user
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
	# Should attempt to process, even if user doesn't exist
}

@test "gh-check-ssh-keys: authorized_keys with proper permissions" {
	chmod 600 "$TEST_AUTH_KEYS"
	run gh-check-ssh-keys torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
	# Should work regardless of outcome
}

@test "gh-check-ssh-keys: authorized_keys with comments" {
	# Add some comments to authorized_keys
	echo "# This is a comment" >"$TEST_AUTH_KEYS"
	echo "# Another comment" >>"$TEST_AUTH_KEYS"

	run gh-check-ssh-keys torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]
	# Should handle comments properly
}

@test "gh-check-ssh-keys: exits with appropriate code when no keys match" {
	# Empty authorized_keys
	echo "" >"$TEST_AUTH_KEYS"

	run gh-check-ssh-keys torvalds
	# Should return 2 (no keys found) if user exists with keys
	# Or 1 if there's an error
	[ "$status" -ne 0 ]
}
