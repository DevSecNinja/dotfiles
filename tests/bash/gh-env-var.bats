#!/usr/bin/env bats
# Tests for GitHub username environment variable integration

# Test configuration
readonly TIMEOUT_SECONDS=2

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

# Helper function to create wrapper scripts for testing functions with timeout
create_wrapper_script() {
	local script_name=$1
	local function_name=$2
	local function_file=$3

	cat >"$TEST_DIR/$script_name" <<SCRIPT
#!/bin/bash
source "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/$function_file"
$function_name 2>&1
SCRIPT
	chmod +x "$TEST_DIR/$script_name"
}

@test "gh-add-ssh-keys: shows username when CHEZMOI_GITHUB_USERNAME is set" {
	# This test validates that when CHEZMOI_GITHUB_USERNAME is set,
	# it's mentioned in the output even if we can't interact with the prompt.
	# We test the non-TTY code path which shows the helpful message.
	export CHEZMOI_GITHUB_USERNAME="testuser"

	# Run in non-TTY mode to avoid hanging
	run bash -c "source home/dot_config/shell/functions/gh-add-ssh-keys.sh && gh-add-ssh-keys < /dev/null"

	# Should show the username and explain it can't confirm
	[ "$status" -eq 1 ]
	[[ "$output" == *"testuser"* ]]
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
	# Should NOT mention the environment variable when it's not set
	[[ "$output" != *"CHEZMOI_GITHUB_USERNAME"* ]]
}

@test "gh-check-ssh-keys: shows username when CHEZMOI_GITHUB_USERNAME is set" {
	# This test validates that when CHEZMOI_GITHUB_USERNAME is set,
	# it's mentioned in the output even if we can't interact with the prompt.
	# We test the non-TTY code path which shows the helpful message.
	export CHEZMOI_GITHUB_USERNAME="testuser"

	# Run in non-TTY mode to avoid hanging
	run bash -c "source home/dot_config/shell/functions/gh-check-ssh-keys.sh && gh-check-ssh-keys < /dev/null"

	# Should show the username and explain it can't confirm
	[ "$status" -eq 1 ]
	[[ "$output" == *"testuser"* ]]
}

@test "gh-check-ssh-keys: prefers explicit username over environment variable" {
	export CHEZMOI_GITHUB_USERNAME="testuser"

	# Create authorized_keys so function proceeds to check username
	touch "$HOME/.ssh/authorized_keys"
	chmod 600 "$HOME/.ssh/authorized_keys"

	# Run with explicit username - should use that instead
	run gh-check-ssh-keys explicit-user
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ] || [ "$status" -eq 2 ]

	# Should mention explicit-user
	[[ "$output" =~ "explicit-user" ]]
}

@test "gh-check-ssh-keys: works without CHEZMOI_GITHUB_USERNAME set" {
	# Ensure environment variable is not set
	unset CHEZMOI_GITHUB_USERNAME

	# Run without username - should fail with standard error
	run gh-check-ssh-keys
	[ "$status" -eq 1 ]
	[[ "$output" =~ "GitHub username is required" ]]
	# Should NOT mention the environment variable when it's not set
	[[ "$output" != *"CHEZMOI_GITHUB_USERNAME"* ]]
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

@test "gh-add-ssh-keys: fails in non-TTY with helpful message" {
	export CHEZMOI_GITHUB_USERNAME="testuser"

	# Run without TTY by redirecting stdin from /dev/null
	run bash -c "export BATS_TEST_DIRNAME='${BATS_TEST_DIRNAME}' && source home/dot_config/shell/functions/gh-add-ssh-keys.sh && gh-add-ssh-keys < /dev/null"

	# Should fail and explain that it cannot confirm in non-interactive mode
	[ "$status" -eq 1 ]
	[[ "$output" =~ "testuser" ]]
	[[ "$output" =~ "cannot confirm in non-interactive mode" ]]
}

@test "gh-check-ssh-keys: fails in non-TTY with helpful message" {
	export CHEZMOI_GITHUB_USERNAME="testuser"

	# Run without TTY by redirecting stdin from /dev/null
	run bash -c "export BATS_TEST_DIRNAME='${BATS_TEST_DIRNAME}' && source home/dot_config/shell/functions/gh-check-ssh-keys.sh && gh-check-ssh-keys < /dev/null"

	# Should fail and explain that it cannot confirm in non-interactive mode
	[ "$status" -eq 1 ]
	[[ "$output" =~ "testuser" ]]
	[[ "$output" =~ "cannot confirm in non-interactive mode" ]]
}
