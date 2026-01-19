#!/usr/bin/env bats
# Tests for Chezmoi configuration validation

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	
	# Ensure PATH includes ~/.local/bin for chezmoi
	export PATH="${HOME}/.local/bin:${PATH}"
}

@test "validate-chezmoi: chezmoi command is available" {
	# Check if chezmoi is available or can be installed
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed (requires manual installation for test)"
	fi
	
	run chezmoi --version
	[ "$status" -eq 0 ]
}

@test "validate-chezmoi: can read chezmoi data from repository" {
	# Check if chezmoi is available
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi
	
	cd "$REPO_ROOT/home"
	run chezmoi data --source=.
	[ "$status" -eq 0 ]
	[[ "$output" != "" ]]
}

@test "validate-chezmoi: chezmoi configuration is valid" {
	# Check if chezmoi is available
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi
	
	cd "$REPO_ROOT/home"
	run chezmoi data --source=.
	[ "$status" -eq 0 ]
	
	# Check for expected fields in output
	[[ "$output" =~ "chezmoi" ]]
}

@test "validate-chezmoi: .chezmoi.yaml.tmpl exists" {
	[ -f "$REPO_ROOT/home/.chezmoi.yaml.tmpl" ]
}

@test "validate-chezmoi: .chezmoiignore exists" {
	[ -f "$REPO_ROOT/home/.chezmoiignore" ]
}
