#!/usr/bin/env bats
# Tests for Fish shell configuration validation

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
}

@test "validate-fish-config: fish command is available or can be installed" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed (requires manual installation for test)"
	fi
	
	run fish --version
	[ "$status" -eq 0 ]
}

@test "validate-fish-config: can find fish config files in repository" {
	cd "$REPO_ROOT"
	run bash -c "find home -name '*.fish' -type f | head -1"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

@test "validate-fish-config: main fish config has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	
	local config_file="$REPO_ROOT/home/dot_config/fish/config.fish"
	if [ ! -f "$config_file" ]; then
		skip "Fish config not found"
	fi
	
	run fish -n "$config_file"
	[ "$status" -eq 0 ]
}

@test "validate-fish-config: aliases.fish has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	
	local aliases_file="$REPO_ROOT/home/dot_config/fish/conf.d/aliases.fish"
	if [ ! -f "$aliases_file" ]; then
		skip "Fish aliases not found"
	fi
	
	run fish -n "$aliases_file"
	[ "$status" -eq 0 ]
}

@test "validate-fish-config: all .fish files have valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	
	cd "$REPO_ROOT"
	
	# Find and validate all Fish files
	local found_fish_files=false
	local error_count=0
	
	while IFS= read -r fish_file; do
		if [ -n "$fish_file" ] && [ -f "$fish_file" ]; then
			found_fish_files=true
			if ! fish -n "$fish_file" >/dev/null 2>&1; then
				echo "Syntax error in: $fish_file"
				error_count=$((error_count + 1))
			fi
		fi
	done < <(find home -name "*.fish" -type f 2>/dev/null || true)
	
	if [ "$found_fish_files" = false ]; then
		skip "No Fish files found"
	fi
	
	[ "$error_count" -eq 0 ]
}

@test "validate-fish-config: fish_greeting function exists" {
	local greeting_file="$REPO_ROOT/home/dot_config/fish/functions/fish_greeting.fish"
	[ -f "$greeting_file" ]
}

@test "validate-fish-config: fish config directory structure is correct" {
	[ -d "$REPO_ROOT/home/dot_config/fish" ]
	[ -d "$REPO_ROOT/home/dot_config/fish/conf.d" ]
	[ -d "$REPO_ROOT/home/dot_config/fish/functions" ]
}
