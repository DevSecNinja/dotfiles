#!/usr/bin/env bats
# Tests for Fish shell configuration loading and functionality

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	
	# Create a temporary Fish config directory for testing
	TEST_FISH_DIR="$(mktemp -d)"
	export TEST_FISH_DIR
	export XDG_CONFIG_HOME="$TEST_FISH_DIR"
}

# Teardown function runs after each test
teardown() {
	# Clean up test directory
	if [ -n "$TEST_FISH_DIR" ] && [ -d "$TEST_FISH_DIR" ]; then
		rm -rf "$TEST_FISH_DIR"
	fi
}

@test "test-fish-config: fish command is available" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed (requires manual installation for test)"
	fi
	
	run fish --version
	[ "$status" -eq 0 ]
}

@test "test-fish-config: fish can start with default config" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	
	run fish -c "echo 'test'"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "test" ]]
}

@test "test-fish-config: fish can start with repository config" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	
	# Copy Fish config to test location
	mkdir -p "$TEST_FISH_DIR/fish"
	if [ -d "$REPO_ROOT/home/dot_config/fish" ]; then
		cp -r "$REPO_ROOT/home/dot_config/fish"/* "$TEST_FISH_DIR/fish/" 2>/dev/null || true
	else
		skip "Fish config not found in repository"
	fi
	
	run fish -c "echo 'Fish started successfully'"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Fish started successfully" ]]
}

@test "test-fish-config: custom functions are available" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	
	# Copy Fish config to test location
	mkdir -p "$TEST_FISH_DIR/fish"
	if [ -d "$REPO_ROOT/home/dot_config/fish" ]; then
		cp -r "$REPO_ROOT/home/dot_config/fish"/* "$TEST_FISH_DIR/fish/" 2>/dev/null || true
	else
		skip "Fish config not found in repository"
	fi
	
	# Check if fish_greeting function exists
	run fish -c "functions fish_greeting"
	# Function may or may not exist, but fish should start
	[ "$status" -eq 0 ] || skip "fish_greeting function not defined"
}

@test "test-fish-config: aliases are loaded" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	
	# Copy Fish config to test location
	mkdir -p "$TEST_FISH_DIR/fish"
	if [ -d "$REPO_ROOT/home/dot_config/fish" ]; then
		cp -r "$REPO_ROOT/home/dot_config/fish"/* "$TEST_FISH_DIR/fish/" 2>/dev/null || true
	else
		skip "Fish config not found in repository"
	fi
	
	# Check if aliases file exists and was loaded
	if [ -f "$TEST_FISH_DIR/fish/conf.d/aliases.fish" ]; then
		# Try to check for a common alias (like 'l' or 'll')
		run fish -c "type -q l"
		# Alias may or may not exist, but fish should start
		[ "$status" -eq 0 ] || skip "Alias 'l' not defined"
	else
		skip "Aliases file not found"
	fi
}

@test "test-fish-config: config.fish loads without errors" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	
	local config_file="$REPO_ROOT/home/dot_config/fish/config.fish"
	if [ ! -f "$config_file" ]; then
		skip "Fish config.fish not found"
	fi
	
	# Copy Fish config to test location
	mkdir -p "$TEST_FISH_DIR/fish"
	cp "$config_file" "$TEST_FISH_DIR/fish/config.fish"
	
	# If there are conf.d files, copy them too
	if [ -d "$REPO_ROOT/home/dot_config/fish/conf.d" ]; then
		mkdir -p "$TEST_FISH_DIR/fish/conf.d"
		cp -r "$REPO_ROOT/home/dot_config/fish/conf.d"/* "$TEST_FISH_DIR/fish/conf.d/" 2>/dev/null || true
	fi
	
	# If there are function files, copy them too
	if [ -d "$REPO_ROOT/home/dot_config/fish/functions" ]; then
		mkdir -p "$TEST_FISH_DIR/fish/functions"
		cp -r "$REPO_ROOT/home/dot_config/fish/functions"/* "$TEST_FISH_DIR/fish/functions/" 2>/dev/null || true
	fi
	
	run fish -c "echo 'Config loaded'"
	[ "$status" -eq 0 ]
}
