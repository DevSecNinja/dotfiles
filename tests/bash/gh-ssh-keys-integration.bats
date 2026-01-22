#!/usr/bin/env bats
# Integration tests for GitHub SSH key management functions
# These tests simulate real-world scenarios with mock GitHub API responses

# Setup function runs before each test
setup() {
	# Load both functions
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/gh-check-ssh-keys.sh"
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/gh-add-ssh-keys.sh"

	# Create a temporary test directory
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

	# Override HOME for testing
	ORIGINAL_HOME="$HOME"
	export ORIGINAL_HOME
	export HOME="$TEST_DIR"

	# Create test SSH keys that look realistic
	TEST_KEY_1="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDTestKey1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa user1@github"
	TEST_KEY_2="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey2bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb user2@github"
	TEST_KEY_3="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDTestKey3cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc user3@github"

	export TEST_KEY_1 TEST_KEY_2 TEST_KEY_3

	# Create a mock curl function for testing
	# This will be called instead of the real curl
	curl() {
		local url="$2"
		# Extract username from URL
		local username
		username=$(echo "$url" | sed 's|https://api.github.com/users/\([^/]*\)/keys|\1|')

		case "$username" in
		"testuser-single")
			# User with one SSH key
			echo '[{"id":1,"key":"'"$TEST_KEY_1"'"}]'
			return 0
			;;
		"testuser-multiple")
			# User with multiple SSH keys
			echo '[{"id":1,"key":"'"$TEST_KEY_1"'"},{"id":2,"key":"'"$TEST_KEY_2"'"},{"id":3,"key":"'"$TEST_KEY_3"'"}]'
			return 0
			;;
		"testuser-nokeys")
			# User with no SSH keys
			echo '[]'
			return 0
			;;
		"testuser-invalid")
			# User not found
			return 22
			;;
		*)
			# Unknown user - return error
			return 1
			;;
		esac
	}
	export -f curl
}

# Teardown function runs after each test
teardown() {
	# Restore original HOME
	export HOME="$ORIGINAL_HOME"

	# Clean up test directory
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi

	# Unset mock curl
	unset -f curl 2>/dev/null || true
}

# Test 1: Add single key to empty authorized_keys
@test "integration: add single key to empty authorized_keys" {
	run gh-add-ssh-keys testuser-single
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Successfully added 1 key(s)" ]]

	# Verify file was created with correct permissions
	[ -f "$HOME/.ssh/authorized_keys" ]
	local perms
	perms=$(stat -c '%a' "$HOME/.ssh/authorized_keys")
	[ "$perms" = "600" ]

	# Verify key was added with comment
	grep -q "# GitHub user: testuser-single" "$HOME/.ssh/authorized_keys"
	grep -q "TestKey1" "$HOME/.ssh/authorized_keys"
}

# Test 2: Add multiple keys to empty authorized_keys
@test "integration: add multiple keys to empty authorized_keys" {
	run gh-add-ssh-keys --verbose testuser-multiple
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Successfully added 3 key(s)" ]]
	[[ "$output" =~ "Found 3 SSH key(s)" ]]

	# Verify all three keys were added
	grep -q "TestKey1" "$HOME/.ssh/authorized_keys"
	grep -q "TestKey2" "$HOME/.ssh/authorized_keys"
	grep -q "TestKey3" "$HOME/.ssh/authorized_keys"

	# Verify comments were added for each key
	grep -q "# GitHub user: testuser-multiple (key #1)" "$HOME/.ssh/authorized_keys"
	grep -q "# GitHub user: testuser-multiple (key #2)" "$HOME/.ssh/authorized_keys"
	grep -q "# GitHub user: testuser-multiple (key #3)" "$HOME/.ssh/authorized_keys"
}

# Test 3: Check when no keys exist in authorized_keys
@test "integration: check returns error when no keys exist in authorized_keys" {
	# Add some unrelated keys first
	mkdir -p "$HOME/.ssh"
	echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDifferentkey other@host" >"$HOME/.ssh/authorized_keys"
	chmod 600 "$HOME/.ssh/authorized_keys"

	run gh-check-ssh-keys testuser-single
	[ "$status" -eq 2 ]
	[[ "$output" =~ "None of the 1 key(s)" ]]
}

# Test 4: Check when key exists in authorized_keys
@test "integration: check returns success when key exists in authorized_keys" {
	# First add the key
	gh-add-ssh-keys testuser-single >/dev/null

	# Now check if it exists
	run gh-check-ssh-keys testuser-single
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Found 1 of 1 key(s)" ]]
}

# Test 5: Add keys when some already exist
@test "integration: add keys when one already exists" {
	# Manually add one key first
	mkdir -p "$HOME/.ssh"
	{
		echo "# Existing key"
		echo "$TEST_KEY_1"
	} >"$HOME/.ssh/authorized_keys"
	chmod 600 "$HOME/.ssh/authorized_keys"

	# Try to add all three keys (one already exists)
	run gh-add-ssh-keys --verbose testuser-multiple
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Successfully added 2 key(s)" ]]
	[[ "$output" =~ "Skipped 1 key(s)" ]]
	[[ "$output" =~ "already exists, skipping" ]]

	# Verify only the two new keys were added (not the duplicate)
	local key1_count
	key1_count=$(grep -c "TestKey1" "$HOME/.ssh/authorized_keys")
	[ "$key1_count" -eq 1 ]

	# Verify the other two keys were added
	grep -q "TestKey2" "$HOME/.ssh/authorized_keys"
	grep -q "TestKey3" "$HOME/.ssh/authorized_keys"
}

# Test 6: Check when some keys exist
@test "integration: check reports partial matches correctly" {
	# Add only key 1 and key 2
	mkdir -p "$HOME/.ssh"
	{
		echo "# GitHub user: testuser-multiple (key #1)"
		echo "$TEST_KEY_1"
		echo "# GitHub user: testuser-multiple (key #2)"
		echo "$TEST_KEY_2"
	} >"$HOME/.ssh/authorized_keys"
	chmod 600 "$HOME/.ssh/authorized_keys"

	# Check for user with three keys (only 2 should be found)
	run gh-check-ssh-keys --verbose testuser-multiple
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Found 2 of 3 key(s)" ]]
	[[ "$output" =~ "is trusted" ]]
	[[ "$output" =~ "is NOT trusted" ]]
}

# Test 7: Add all keys when all already exist
@test "integration: add when all keys already exist" {
	# First add all keys
	gh-add-ssh-keys testuser-multiple >/dev/null

	# Try to add again
	run gh-add-ssh-keys testuser-multiple
	[ "$status" -eq 0 ]
	[[ "$output" =~ "All 3 key(s) from 'testuser-multiple' already exist" ]]

	# Verify no duplicates were created
	local key1_count
	key1_count=$(grep -c "TestKey1" "$HOME/.ssh/authorized_keys")
	[ "$key1_count" -eq 1 ]
}

# Test 8: Dry-run mode doesn't modify files
@test "integration: dry-run mode shows what would be added without changes" {
	# Add one key first
	mkdir -p "$HOME/.ssh"
	echo "$TEST_KEY_1" >"$HOME/.ssh/authorized_keys"
	chmod 600 "$HOME/.ssh/authorized_keys"

	# Dry-run to add all three keys
	run gh-add-ssh-keys --dry-run testuser-multiple
	[ "$status" -eq 0 ]
	[[ "$output" =~ "DRY RUN" ]]
	[[ "$output" =~ "Would add: 2 key(s)" ]]
	[[ "$output" =~ "Would skip: 1 key(s)" ]]

	# Verify file wasn't modified (still only has 1 key)
	local line_count
	line_count=$(wc -l <"$HOME/.ssh/authorized_keys")
	[ "$line_count" -eq 1 ]
}

# Test 9: Handles user with no SSH keys
@test "integration: handles user with no SSH keys gracefully" {
	run gh-add-ssh-keys testuser-nokeys
	[ "$status" -eq 1 ]
	[[ "$output" =~ "has no public SSH keys on GitHub" ]]

	# gh-check-ssh-keys returns exit code 1 for API errors (no keys on GitHub)
	# or 2 for no authorized_keys file
	run gh-check-ssh-keys testuser-nokeys
	[ "$status" -eq 1 ] || [ "$status" -eq 2 ]
	[[ "$output" =~ "has no public SSH keys on GitHub" ]] || [[ "$output" =~ "No authorized_keys file found" ]]
}

# Test 10: Handles invalid user
@test "integration: handles invalid user gracefully" {
	run gh-add-ssh-keys testuser-invalid
	[ "$status" -eq 1 ]
	[[ "$output" =~ "not found on GitHub" ]]

	# gh-check-ssh-keys returns exit code 1 for API errors (user not found)
	# or 2 for no authorized_keys file
	run gh-check-ssh-keys testuser-invalid
	[ "$status" -eq 1 ] || [ "$status" -eq 2 ]
	[[ "$output" =~ "not found on GitHub" ]] || [[ "$output" =~ "No authorized_keys file found" ]]
}

# Test 11: Preserves existing authorized_keys content
@test "integration: preserves existing authorized_keys content when adding keys" {
	# Create authorized_keys with existing content
	mkdir -p "$HOME/.ssh"
	{
		echo "# Existing user keys"
		echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDexistingkey existing@host"
		echo ""
		echo "# Another existing key"
		echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExistingKey2 another@host"
	} >"$HOME/.ssh/authorized_keys"
	chmod 600 "$HOME/.ssh/authorized_keys"

	# Add GitHub keys
	gh-add-ssh-keys testuser-single >/dev/null

	# Verify existing content is preserved
	grep -q "Dexistingkey" "$HOME/.ssh/authorized_keys"
	grep -q "ExistingKey2" "$HOME/.ssh/authorized_keys"

	# Verify new key was added
	grep -q "TestKey1" "$HOME/.ssh/authorized_keys"
}

# Test 12: Directory and file permissions are correct
@test "integration: creates .ssh directory with correct permissions" {
	# Ensure .ssh doesn't exist
	[ ! -d "$HOME/.ssh" ]

	# Add keys
	gh-add-ssh-keys testuser-single >/dev/null

	# Verify .ssh directory has correct permissions (700)
	[ -d "$HOME/.ssh" ]
	local dir_perms
	dir_perms=$(stat -c '%a' "$HOME/.ssh")
	[ "$dir_perms" = "700" ]

	# Verify authorized_keys has correct permissions (600)
	local file_perms
	file_perms=$(stat -c '%a' "$HOME/.ssh/authorized_keys")
	[ "$file_perms" = "600" ]
}

# Test 13: Check all keys trusted
@test "integration: check reports all keys trusted when all exist" {
	# Add all keys
	gh-add-ssh-keys testuser-multiple >/dev/null

	# Check with verbose mode
	run gh-check-ssh-keys --verbose testuser-multiple
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Found 3 of 3 key(s)" ]]

	# Count how many times "is trusted" appears (should be 3)
	local trusted_count
	trusted_count=$(echo "$output" | grep -c "is trusted")
	[ "$trusted_count" -eq 3 ]
}

# Test 14: Multiple users' keys can coexist
@test "integration: keys from multiple GitHub users can coexist" {
	# Add keys from first user
	gh-add-ssh-keys testuser-single >/dev/null

	# Add keys from second user
	gh-add-ssh-keys testuser-multiple >/dev/null

	# Verify both users' keys exist
	grep -q "# GitHub user: testuser-single" "$HOME/.ssh/authorized_keys"
	grep -q "# GitHub user: testuser-multiple" "$HOME/.ssh/authorized_keys"

	# Check both users
	run gh-check-ssh-keys testuser-single
	[ "$status" -eq 0 ]

	run gh-check-ssh-keys testuser-multiple
	[ "$status" -eq 0 ]
}

# Test 15: Verbose mode provides detailed output
@test "integration: verbose mode shows detailed progress" {
	run gh-add-ssh-keys --verbose testuser-multiple
	[ "$status" -eq 0 ]

	# Verify verbose output elements
	[[ "$output" =~ "Adding GitHub SSH keys" ]]
	[[ "$output" =~ "SSH directory:" ]]
	[[ "$output" =~ "Authorized keys file:" ]]
	[[ "$output" =~ "Fetching SSH keys from GitHub API" ]]
	[[ "$output" =~ "Found 3 SSH key(s)" ]]
	[[ "$output" =~ "Adding key #1" ]]
	[[ "$output" =~ "Adding key #2" ]]
	[[ "$output" =~ "Adding key #3" ]]
	[[ "$output" =~ "Set permissions" ]]
	[[ "$output" =~ "Summary:" ]]
}
