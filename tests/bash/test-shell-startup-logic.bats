#!/usr/bin/env bats
# Tests for shell startup directory logic across all shells

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
}

@test "test-shell-startup-logic: bash config contains VS Code check" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.bash"

	if [ ! -f "$config_file" ]; then
		skip "Bash config not found"
	fi

	run grep -q 'TERM_PROGRAM.*vscode' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: bash config contains projects path check" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.bash"

	if [ ! -f "$config_file" ]; then
		skip "Bash config not found"
	fi

	run grep -q 'projects' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: bash config checks directory existence before changing" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.bash"

	if [ ! -f "$config_file" ]; then
		skip "Bash config not found"
	fi

	# Should check if directory exists before cd
	run grep -q '\-d.*projects' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: bash config uses case-insensitive check" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.bash"

	if [ ! -f "$config_file" ]; then
		skip "Bash config not found"
	fi

	# Should use case-insensitive comparison (either parameter expansion or regex)
	run bash -c "grep -q ',,\|[Pp][Rr][Oo][Jj][Ee][Cc][Tt][Ss]' '$config_file'"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: zsh config contains VS Code check" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.zsh"

	if [ ! -f "$config_file" ]; then
		skip "Zsh config not found"
	fi

	run grep -q 'TERM_PROGRAM.*vscode' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: zsh config contains projects path check" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.zsh"

	if [ ! -f "$config_file" ]; then
		skip "Zsh config not found"
	fi

	run grep -q 'projects' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: zsh config checks directory existence before changing" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.zsh"

	if [ ! -f "$config_file" ]; then
		skip "Zsh config not found"
	fi

	# Should check if directory exists before cd
	run grep -q '\-d.*projects' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: zsh config uses case-insensitive check" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.zsh"

	if [ ! -f "$config_file" ]; then
		skip "Zsh config not found"
	fi

	# Should use case-insensitive comparison (either parameter expansion or regex)
	run bash -c "grep -q ':l\|[Pp][Rr][Oo][Jj][Ee][Cc][Tt][Ss]' '$config_file'"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: fish config contains VS Code check" {
	local config_file="$REPO_ROOT/home/dot_config/fish/config.fish"

	if [ ! -f "$config_file" ]; then
		skip "Fish config not found"
	fi

	run grep -q 'TERM_PROGRAM.*vscode' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: fish config contains projects path check" {
	local config_file="$REPO_ROOT/home/dot_config/fish/config.fish"

	if [ ! -f "$config_file" ]; then
		skip "Fish config not found"
	fi

	run grep -q 'projects' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: fish config checks directory existence before changing" {
	local config_file="$REPO_ROOT/home/dot_config/fish/config.fish"

	if [ ! -f "$config_file" ]; then
		skip "Fish config not found"
	fi

	# Should check if directory exists before cd
	run grep -q 'test -d' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: fish config uses case-insensitive check" {
	local config_file="$REPO_ROOT/home/dot_config/fish/config.fish"

	if [ ! -f "$config_file" ]; then
		skip "Fish config not found"
	fi

	# Should use case-insensitive string match
	run grep -q 'string match.*-qi' "$config_file"
	[ "$status" -eq 0 ]
}
