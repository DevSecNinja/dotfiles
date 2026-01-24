#!/usr/bin/env bats
# Tests for bash shell invocation behavior
# Validates that bash can be launched explicitly without auto-switching to fish

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
}

@test "test-bash-from-fish: bash_profile checks SHLVL before exec" {
	local bash_profile="$REPO_ROOT/home/dot_bash_profile"

	if [ ! -f "$bash_profile" ]; then
		skip "bash_profile not found"
	fi

	# Check that the file contains SHLVL check
	run grep -q 'SHLVL' "$bash_profile"
	[ "$status" -eq 0 ]
}

@test "test-bash-from-fish: bash_profile only execs fish when SHLVL is 1" {
	local bash_profile="$REPO_ROOT/home/dot_bash_profile"

	if [ ! -f "$bash_profile" ]; then
		skip "bash_profile not found"
	fi

	# Check that the line with exec \$SHELL also has SHLVL -eq 1 check
	run bash -c "grep 'exec.*\$SHELL' '$bash_profile' | grep -q 'SHLVL.*-eq 1'"
	[ "$status" -eq 0 ]
}

@test "test-bash-from-fish: bash_profile allows nested bash shells" {
	if ! command -v bash >/dev/null 2>&1; then
		skip "Bash not installed"
	fi

	local bash_profile="$REPO_ROOT/home/dot_bash_profile"

	if [ ! -f "$bash_profile" ]; then
		skip "bash_profile not found"
	fi

	# Simulate a nested bash shell (SHLVL > 1)
	# The bash_profile should NOT exec to fish in this case
	export SHLVL=2

	# Source the bash_profile and check if we're still in bash
	output=$(bash --noprofile --norc -c "
		export SHLVL=2
		source '$bash_profile'
		echo \$BASH_VERSION
	" 2>&1)

	# Should output bash version (meaning we stayed in bash)
	[[ "$output" =~ [0-9]+\.[0-9]+ ]] || {
		echo "ERROR: Expected bash version, got: $output"
		return 1
	}
}

@test "test-bash-from-fish: bash_profile switches to fish on login (SHLVL=1)" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed (this test requires fish)"
	fi

	local bash_profile="$REPO_ROOT/home/dot_bash_profile"

	if [ ! -f "$bash_profile" ]; then
		skip "bash_profile not found"
	fi

	# When SHLVL=1 (login shell), bash_profile should contain logic to switch to fish
	# Check for SHLVL=1 condition followed by exec
	run bash -c "grep 'SHLVL' '$bash_profile' | grep -q '\-eq 1'"
	[ "$status" -eq 0 ]

	# Also check that exec exists
	run grep -q 'exec' "$bash_profile"
	[ "$status" -eq 0 ]
}

@test "test-bash-from-fish: bash_profile has comment explaining nested shell behavior" {
	local bash_profile="$REPO_ROOT/home/dot_bash_profile"

	if [ ! -f "$bash_profile" ]; then
		skip "bash_profile not found"
	fi

	# Check that there's a comment explaining the nested shell behavior
	run grep -i "nested" "$bash_profile"
	[ "$status" -eq 0 ]
}

@test "test-bash-from-fish: bash_profile checks parent process" {
	local bash_profile="$REPO_ROOT/home/dot_bash_profile"

	if [ ! -f "$bash_profile" ]; then
		skip "bash_profile not found"
	fi

	# Check that there's a function to check if parent is fish
	run grep -q "_parent_is_fish" "$bash_profile"
	[ "$status" -eq 0 ]

	# Check that the function checks /proc (Linux) or ps (macOS)
	run bash -c "grep -A 10 '_parent_is_fish' '$bash_profile' | grep -q 'proc\|ps.*PPID'"
	[ "$status" -eq 0 ]
}

@test "test-bash-from-fish: bash from fish with parent check works" {
	if ! command -v bash >/dev/null 2>&1; then
		skip "Bash not installed"
	fi

	local bash_profile="$REPO_ROOT/home/dot_bash_profile"

	if [ ! -f "$bash_profile" ]; then
		skip "bash_profile not found"
	fi

	# Simulate bash invoked from fish (parent is bash in this test)
	# The bash_profile should NOT exec to fish even if SHLVL=1 and IN_FISH_SHELL not set
	# because the parent process check will detect we're from bash (not from systemd/init)
	output=$(bash --noprofile --norc -c "
		export SHLVL=1
		unset IN_FISH_SHELL
		source '$bash_profile'
		echo \$BASH_VERSION
	" 2>&1)

	# Should output bash version (meaning we stayed in bash due to parent check)
	[[ "$output" =~ [0-9]+\.[0-9]+ ]] || {
		echo "ERROR: Expected bash version, got: $output"
		echo "Parent check should prevent exec to fish when parent is bash"
		return 1
	}
}
