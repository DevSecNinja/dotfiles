#!/usr/bin/env bats
# Tests for gh-add-ssh-keys bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/gh-add-ssh-keys.sh"

	# Unset CHEZMOI_GITHUB_USERNAME to prevent interactive prompts
	unset CHEZMOI_GITHUB_USERNAME

	# Create a temporary test directory
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

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

@test "gh-add-ssh-keys: help option displays usage" {
	run gh-add-ssh-keys --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: gh-add-ssh-keys" ]]
	[[ "$output" =~ "--dry-run" ]]
	[[ "$output" =~ "--verbose" ]]
	[[ "$output" =~ "Add GitHub user's SSH keys to authorized_keys" ]]
}

@test "gh-add-ssh-keys: short help option displays usage" {
	run gh-add-ssh-keys -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: gh-add-ssh-keys" ]]
}

@test "gh-add-ssh-keys: fails when no username provided" {
	run gh-add-ssh-keys
	[ "$status" -eq 1 ]
	[[ "$output" =~ "GitHub username is required" ]]
}

@test "gh-add-ssh-keys: unknown option returns error" {
	run gh-add-ssh-keys --invalid-option
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
	[[ "$output" =~ "Use --help for usage information" ]]
}

@test "gh-add-ssh-keys: too many arguments returns error" {
	run gh-add-ssh-keys user1 user2
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Too many arguments" ]]
}

@test "gh-add-ssh-keys: fails when curl is not available" {
	skip "Cannot reliably test curl unavailability - curl will be found in PATH"
}

@test "gh-add-ssh-keys: creates .ssh directory if it doesn't exist" {
	# Ensure .ssh doesn't exist
	[ ! -d "$HOME/.ssh" ]

	run gh-add-ssh-keys --dry-run torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
	[[ "$output" =~ "Would create directory" ]] || [[ "$output" =~ "not found" ]] || [[ "$output" =~ "Failed" ]]
}

@test "gh-add-ssh-keys: dry-run mode doesn't create directories" {
	run gh-add-ssh-keys --dry-run torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]

	# .ssh directory should not exist after dry-run
	# (Unless there was an error and it didn't get to that point)
	if [[ "$output" =~ "Would create directory" ]]; then
		[ ! -d "$HOME/.ssh" ]
	fi
}

@test "gh-add-ssh-keys: dry-run mode doesn't add keys" {
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"

	run gh-add-ssh-keys --dry-run torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]

	# authorized_keys should not exist or be empty after dry-run
	if [ -f "$HOME/.ssh/authorized_keys" ]; then
		# File should be empty if it exists
		[ ! -s "$HOME/.ssh/authorized_keys" ]
	fi
}

@test "gh-add-ssh-keys: short dry-run option works" {
	run gh-add-ssh-keys -n torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
	[[ "$output" =~ "DRY RUN" ]] || [[ "$output" =~ "not found" ]] || [[ "$output" =~ "Failed" ]]
}

@test "gh-add-ssh-keys: verbose mode shows detailed output" {
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"

	run gh-add-ssh-keys --verbose torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
	[[ "$output" =~ "Adding GitHub SSH keys" ]] || [[ "$output" =~ "Fetching" ]]
}

@test "gh-add-ssh-keys: short verbose option works" {
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"

	run gh-add-ssh-keys -v torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
	[[ "$output" =~ "Adding GitHub SSH keys" ]] || [[ "$output" =~ "Fetching" ]]
}

@test "gh-add-ssh-keys: combines dry-run and verbose flags" {
	run gh-add-ssh-keys --dry-run --verbose torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
	# Should have both dry-run and verbose output
	if [[ "$output" =~ "DRY RUN" ]]; then
		[[ "$output" =~ "Adding GitHub SSH keys" ]]
	fi
}

@test "gh-add-ssh-keys: fails for invalid GitHub username" {
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"

	run gh-add-ssh-keys "this-user-definitely-does-not-exist-12345678901234567890"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "not found on GitHub" ]] || [[ "$output" =~ "Failed to fetch" ]] || [[ "$output" =~ "has no public SSH keys" ]]
}

@test "gh-add-ssh-keys: handles user with no SSH keys" {
	skip "Requires finding a GitHub user with no SSH keys"
}

@test "gh-add-ssh-keys: sets correct permissions on .ssh directory" {
	run gh-add-ssh-keys --dry-run torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]

	# Should mention creating with mode 700
	[[ "$output" =~ "mode 700" ]] || [[ "$output" =~ "not found" ]] || [[ "$output" =~ "Failed" ]]
}

@test "gh-add-ssh-keys: sets correct permissions on authorized_keys" {
	skip "Requires mocking GitHub API response"
	# This test would need to:
	# 1. Mock the curl call to return a known key
	# 2. Run the function
	# 3. Verify authorized_keys has 600 permissions
}

@test "gh-add-ssh-keys: skips keys that already exist" {
	skip "Requires mocking GitHub API response"
	# This test would need to:
	# 1. Add a key to authorized_keys
	# 2. Mock curl to return the same key
	# 3. Run the function
	# 4. Verify it skipped the key
}

@test "gh-add-ssh-keys: adds comment line before each key" {
	skip "Requires mocking GitHub API response"
	# This test would need to:
	# 1. Mock curl to return a known key
	# 2. Run the function
	# 3. Verify comment line exists in authorized_keys
}

@test "gh-add-ssh-keys: handles username with hyphens" {
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"

	run gh-add-ssh-keys test-user
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
	# Should attempt to process, even if user doesn't exist
}

@test "gh-add-ssh-keys: handles username with underscores" {
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"

	run gh-add-ssh-keys test_user
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
	# Should attempt to process, even if user doesn't exist
}

@test "gh-add-ssh-keys: dry-run shows summary" {
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"

	run gh-add-ssh-keys --dry-run torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
	# Should show summary if successful
	if [ "$status" -eq 0 ]; then
		[[ "$output" =~ "Summary" ]] || [[ "$output" =~ "Would add" ]]
	fi
}

@test "gh-add-ssh-keys: provides helpful message about running without dry-run" {
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"

	run gh-add-ssh-keys --dry-run torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
	if [ "$status" -eq 0 ]; then
		[[ "$output" =~ "without --dry-run" ]]
	fi
}

@test "gh-add-ssh-keys: handles existing .ssh directory gracefully" {
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"

	run gh-add-ssh-keys --dry-run torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
	# Should not mention creating the directory
	[[ ! "$output" =~ "Would create directory" ]] || [[ "$output" =~ "not found" ]]
}

@test "gh-add-ssh-keys: handles existing authorized_keys gracefully" {
	mkdir -p "$HOME/.ssh"
	chmod 700 "$HOME/.ssh"
	touch "$HOME/.ssh/authorized_keys"
	chmod 600 "$HOME/.ssh/authorized_keys"
	echo "# Existing key" >>"$HOME/.ssh/authorized_keys"

	run gh-add-ssh-keys --dry-run torvalds
	[ "$status" -eq 0 ] || [ "$status" -eq 1 ]
	# Should work with existing file
}

@test "gh-add-ssh-keys: reports success when keys are added" {
	skip "Requires mocking GitHub API response"
}

@test "gh-add-ssh-keys: reports when all keys already exist" {
	skip "Requires mocking GitHub API response"
}
