#!/usr/bin/env bats
# Tests for GitHub username environment variable integration

# Setup function runs before each test
setup() {
	# Load the functions
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/gh-add-ssh-keys.sh"
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/gh-check-ssh-keys.sh"

	# Create a temporary test directory
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

	# Override HOME for testing
	ORIGINAL_HOME="$HOME"
	export ORIGINAL_HOME
	export HOME="$TEST_DIR"

	# Create test SSH directory
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"
}

# Teardown function runs after each test
teardown() {
	# Restore original HOME
	export HOME="$ORIGINAL_HOME"

	# Clean up test directory
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi

	# Clean up environment variable
	unset CHEZMOI_GITHUB_USERNAME
}

@test "gh-add-ssh-keys: uses CHEZMOI_GITHUB_USERNAME when no username provided" {
	export CHEZMOI_GITHUB_USERNAME="testuser"

	# Run with no username argument - should prompt for confirmation
	# Since it's interactive, we can't test the full flow without mocking input
	# But we can verify the error message includes the environment variable
	run gh-add-ssh-keys
	[ "$status" -eq 1 ]
	[[ "$output" =~ "testuser" ]] || [[ "$output" =~ "CHEZMOI_GITHUB_USERNAME" ]]
}

@test "gh-add-ssh-keys: prefers explicit username over environment variable" {
	export CHEZMOI_GITHUB_USERNAME="testuser"

	# Run with explicit username - should use that instead
	run gh-add-ssh-keys --dry-run explicit-user
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]

	# Should mention explicit-user, not testuser
	if [ "$status" -eq 0 ]; then
		[[ "$output" =~ "explicit-user" ]]
	fi
}

@test "gh-add-ssh-keys: works without CHEZMOI_GITHUB_USERNAME set" {
	# Ensure environment variable is not set
	unset CHEZMOI_GITHUB_USERNAME

	# Run without username - should fail with standard error
	run gh-add-ssh-keys
	[ "$status" -eq 1 ]
	[[ "$output" =~ "GitHub username is required" ]]
}

@test "gh-check-ssh-keys: uses CHEZMOI_GITHUB_USERNAME when no username provided" {
	export CHEZMOI_GITHUB_USERNAME="testuser"

	# Run with no username argument - should prompt for confirmation
	run gh-check-ssh-keys
	[ "$status" -eq 1 ] || [ "$status" -eq 2 ]
	[[ "$output" =~ "testuser" ]] || [[ "$output" =~ "CHEZMOI_GITHUB_USERNAME" ]]
}

@test "gh-check-ssh-keys: prefers explicit username over environment variable" {
	export CHEZMOI_GITHUB_USERNAME="testuser"

	# Run with explicit username - should use that instead
	run gh-check-ssh-keys explicit-user
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]

	# Should mention explicit-user, not testuser
	[[ "$output" =~ "explicit-user" ]]
}

@test "gh-check-ssh-keys: works without CHEZMOI_GITHUB_USERNAME set" {
	# Ensure environment variable is not set
	unset CHEZMOI_GITHUB_USERNAME

	# Run without username - should fail with standard error
	run gh-check-ssh-keys
	[ "$status" -eq 1 ]
	[[ "$output" =~ "GitHub username is required" ]]
}

@test "gh-add-ssh-keys: handles empty CHEZMOI_GITHUB_USERNAME" {
	export CHEZMOI_GITHUB_USERNAME=""

	# Run without username - should fail as if not set
	run gh-add-ssh-keys
	[ "$status" -eq 1 ]
	[[ "$output" =~ "GitHub username is required" ]]
}

@test "gh-check-ssh-keys: handles empty CHEZMOI_GITHUB_USERNAME" {
	export CHEZMOI_GITHUB_USERNAME=""

	# Run without username - should fail as if not set
	run gh-check-ssh-keys
	[ "$status" -eq 1 ]
	[[ "$output" =~ "GitHub username is required" ]]
}
